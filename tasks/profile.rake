# frozen_string_literal: true

namespace :profile do
  task :idna_selection do
    require "addressable/idna"
    if ENV["IDNA_MODE"] == "pure"
      require "addressable/idna/pure"
      Addressable::IDNA.backend = Addressable::IDNA::Pure
    elsif ENV["IDNA_MODE"] == "libidn2"
      require "addressable/idna/libidn2"
      Addressable::IDNA.backend = Addressable::IDNA::Libidn2
    end
  end

  desc "Profile Template match memory allocations"
  task :template_match_memory => :idna_selection do
    require "memory_profiler"
    require "addressable/template"

    start_at = Time.now.to_f
    template = Addressable::Template.new("http://example.com/{?one,two,three}")
    report = MemoryProfiler.report do
      30_000.times do
        template.match(
          "http://example.com/?one=one&two=floo&three=me"
        )
      end
    end
    end_at = Time.now.to_f
    print_options = { scale_bytes: true, normalize_paths: true }
    puts "\n\n"

    if ENV["CI"]
      report.pretty_print(print_options)
    else
      t_allocated = report.scale_bytes(report.total_allocated_memsize)
      t_retained  = report.scale_bytes(report.total_retained_memsize)

      puts "Total allocated: #{t_allocated} (#{report.total_allocated} objects)"
      puts "Total retained:  #{t_retained} (#{report.total_retained} objects)"
      puts "Took #{end_at - start_at} seconds"

      FileUtils.mkdir_p("tmp")
      report.pretty_print(to_file: "tmp/memprof.txt", **print_options)
    end
  end

  desc "Profile URI parse memory allocations"
  task :memory => :idna_selection do
    require "memory_profiler"
    require "addressable/uri"

    start_at = Time.now.to_f
    report = MemoryProfiler.report do
      30_000.times do
        Addressable::URI.parse(
          "http://fiᆵリ宠퐱卄.com/stuff/../?with_lots=of&params=asdff#!stuff"
        ).normalize
      end
    end
    end_at = Time.now.to_f
    print_options = { scale_bytes: true, normalize_paths: true }

    if ENV["CI"]
      report.pretty_print(**print_options)
    else
      t_allocated = report.scale_bytes(report.total_allocated_memsize)
      t_retained  = report.scale_bytes(report.total_retained_memsize)

      puts "Total allocated: #{t_allocated} (#{report.total_allocated} objects)"
      puts "Total retained:  #{t_retained} (#{report.total_retained} objects)"
      puts "Took #{(end_at - start_at).round(1)} seconds"
      puts "IDNA backend: #{Addressable::IDNA.backend.name}"

      FileUtils.mkdir_p("tmp")
      report.pretty_print(to_file: "tmp/memprof.txt", **print_options)
    end
  end

  desc "Test for IDNA backend memory leaks"
  task :idna_memory_leak => :idna_selection do
    value = "fiᆵリ宠퐱卄.com"
    puts "\nMemory leak test for IDNA backend: #{Addressable::IDNA.backend.name}"
    start_at = Time.now.to_f
    GC.disable # Only run GC when manually called
    samples = []
    10.times do
      50_000.times {
        Addressable::IDNA.to_unicode(Addressable::IDNA.to_ascii(value))
      }
      GC.start # Run a major GC
      _, size = `ps ax -o pid,rss | grep -E "^[[:space:]]*#{$$}"`.strip.split.map(&:to_i)
      samples << size/1024
      puts " Memory: #{size/1024}MB" # show process memory
    end
    end_at = Time.now.to_f
    samples.shift # remove first sample which is often unstable in pure ruby
    percent = (samples.last - samples.first) * 100 / samples.first

    puts "Took #{(end_at - start_at).round(1)} seconds"
    puts "Memory rose from #{samples.first}MB to #{samples.last}MB"
    if percent > 10
      puts "Potential MEMORY LEAK detected (#{percent}% increase)"
      exit 1
    else
      puts "Looks fine (#{percent}% increase)"
    end
  end
end
