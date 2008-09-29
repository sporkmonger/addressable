require 'spec/rake/verify_rcov'

namespace :spec do
  Spec::Rake::SpecTask.new(:rcov) do |t|
    t.spec_files = FileList['spec/**/*_spec.rb']
    t.spec_opts = ['--color', '--format', 'specdoc']
    if RUBY_PLATFORM != "java"
      t.rcov = true
    else
      t.rcov = false
    end
    t.rcov_opts = [
      '--exclude', 'spec',
      '--exclude', '1\\.8\\/gems',
      '--exclude', '1\\.9\\/gems'
    ]
  end

  Spec::Rake::SpecTask.new(:normal) do |t|
    t.spec_files = FileList['spec/**/*_spec.rb']
    t.spec_opts = ['--color', '--format', 'specdoc']
    t.rcov = false
  end

  if RUBY_PLATFORM != "java"
    RCov::VerifyTask.new(:verify) do |t|
      t.threshold = 100.0
      t.index_html = 'coverage/index.html'
    end

    task :verify => :rcov
  end

  desc "Generate HTML Specdocs for all specs"
  Spec::Rake::SpecTask.new(:specdoc) do |t|
    specdoc_path = File.expand_path(
      File.join(File.dirname(__FILE__), '../specdoc/'))
    Dir.mkdir(specdoc_path) if !File.exist?(specdoc_path)

    output_file = File.join(specdoc_path, 'index.html')
    t.spec_files = FileList['spec/**/*_spec.rb']
    t.spec_opts = ["--format", "\"html:#{output_file}\"", "--diff"]
    t.fail_on_error = false
  end

  namespace :rcov do
    desc "Browse the code coverage report."
    task :browse => "spec:rcov" do
      Rake.browse("coverage/index.html")
    end
  end
end

if RUBY_PLATFORM != "java"
  desc "Alias to spec:verify"
  task "spec" => "spec:verify"
else
  task "spec" => "spec:normal"
end

task "clobber" => ["spec:clobber_rcov"]

module Rake
  def self.browse(filepath)
    if RUBY_PLATFORM =~ /mswin/
      system(filepath)
    else
      try_browsers = lambda do
        result = true
        if !(`which firefox 2>&1` =~ /no firefox/)
          system("firefox #{filepath}")
        elsif !(`which mozilla 2>&1` =~ /no mozilla/)
          system("mozilla #{filepath}")
        elsif !(`which netscape 2>&1` =~ /no netscape/)
          system("netscape #{filepath}")
        elsif !(`which links 2>&1` =~ /no links/)
          system("links #{filepath}")
        elsif !(`which lynx 2>&1` =~ /no lynx/)
          system("lynx #{filepath}")
        else
          result = false
        end
        result
      end
      opened = false
      if RUBY_PLATFORM =~ /darwin/
        opened = true
        system("open #{filepath}")
      elsif !(`which gnome-open 2>&1` =~ /no gnome-open/)
        success =
          !(`gnome-open #{filepath} 2>&1` =~ /There is no default action/)
        if !success
          opened = try_browsers.call()
        else
          opened = true
        end
      else
        opened = try_browsers.call()
      end
      if !opened
        puts "Don't know how to browse to location."
      end
    end
  end
end
