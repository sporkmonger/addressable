# frozen_string_literal: true

namespace :profile do
  desc "Profile memory allocations"
  task :memory do
    require "memory_profiler"
    require "addressable/uri"
    if ENV["IDNA_MODE"] == "pure"
      Addressable.send(:remove_const, :IDNA)
      load "addressable/idna/pure.rb"
    end

    report = MemoryProfiler.report do
      30_000.times do
        Addressable::URI.parse(
          "http://google.com/stuff/../?with_lots=of&params=asdff#!stuff"
        ).normalize
      end
    end
    print_options = { scale_bytes: true, normalize_paths: true }
    puts "\n\n"

    if ENV["CI"]
      report.pretty_print(print_options)
    else
      t_allocated = report.scale_bytes(report.total_allocated_memsize)
      t_retained  = report.scale_bytes(report.total_retained_memsize)

      puts "Total allocated: #{t_allocated} (#{report.total_allocated} objects)"
      puts "Total retained:  #{t_retained} (#{report.total_retained} objects)"

      FileUtils.mkdir_p("tmp")
      report.pretty_print(to_file: "tmp/memprof.txt", **print_options)
    end
  end
end
