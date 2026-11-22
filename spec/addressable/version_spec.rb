# frozen_string_literal: true

# Copyright (C) Bob Aman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.


require "spec_helper"

require "stringio"

require "addressable/version"

describe Addressable, ".warn_if_unsupported_ruby" do
  # Ruby 2.7 and later have a setting for deprecation warnings; earlier
  # Rubies show them only in verbose mode.
  def deprecation_warnings=(enabled)
    if defined?(Warning) && Warning.respond_to?(:[]=)
      Warning[:deprecated] = enabled
    else
      $VERBOSE = enabled
    end
  end

  around do |example|
    saved_deprecated = Warning[:deprecated] if defined?(Warning) && Warning.respond_to?(:[])
    saved_verbose = $VERBOSE
    begin
      example.run
    ensure
      Warning[:deprecated] = saved_deprecated if defined?(Warning) && Warning.respond_to?(:[]=)
      $VERBOSE = saved_verbose
    end
  end

  context "with deprecation warnings turned on" do
    before { self.deprecation_warnings = true }

    ["2.2.10", "2.7.8", "3.0.7", "3.2.11", "3"].each do |version|
      it "warns that Ruby #{version} is no longer supported" do
        expect do
          Addressable.warn_if_unsupported_ruby(version, "ruby", version)
        end.to output(
          "Addressable no longer supports Ruby #{version}. " \
          "A future version of Addressable will require Ruby 3.3 or later.\n"
        ).to_stderr
      end
    end

    ["3.3.0", "3.3.13", "3.4.12", "4.0.9", "10.0.0", "4"].each do |version|
      it "doesn't warn for Ruby #{version}" do
        expect do
          Addressable.warn_if_unsupported_ruby(version, "ruby", version)
        end.not_to output.to_stderr
      end
    end

    it "names JRuby and the Ruby version it reports" do
      expect do
        Addressable.warn_if_unsupported_ruby("3.1.4", "jruby", "9.4.15.0")
      end.to output(
        "Addressable no longer supports JRuby 9.4.15.0 (Ruby 3.1.4). " \
        "A future version of Addressable will require Ruby 3.3 or later.\n"
      ).to_stderr
    end

    it "names TruffleRuby and the Ruby version it reports" do
      expect do
        Addressable.warn_if_unsupported_ruby("3.2.4", "truffleruby", "24.1.0")
      end.to output(
        "Addressable no longer supports TruffleRuby 24.1.0 (Ruby 3.2.4). " \
        "A future version of Addressable will require Ruby 3.3 or later.\n"
      ).to_stderr
    end

    it "names another runtime as it calls itself" do
      expect do
        Addressable.warn_if_unsupported_ruby("3.2.0", "otheruby", "1.0")
      end.to output(
        "Addressable no longer supports otheruby 1.0 (Ruby 3.2.0). " \
        "A future version of Addressable will require Ruby 3.3 or later.\n"
      ).to_stderr
    end

    it "doesn't warn for a supported JRuby" do
      expect do
        Addressable.warn_if_unsupported_ruby("3.4.5", "jruby", "10.0.8.0")
      end.not_to output.to_stderr
    end

    it "checks the running Ruby by default" do
      engine_version =
        defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : RUBY_VERSION
      expected = StringIO.new
      saved_stderr = $stderr
      begin
        $stderr = expected
        Addressable.warn_if_unsupported_ruby(
          RUBY_VERSION, RUBY_ENGINE, engine_version
        )
      ensure
        $stderr = saved_stderr
      end
      expect do
        Addressable.warn_if_unsupported_ruby
      end.to output(expected.string).to_stderr
    end
  end

  context "with deprecation warnings turned off" do
    before { self.deprecation_warnings = false }

    it "doesn't warn for an unsupported Ruby" do
      expect do
        Addressable.warn_if_unsupported_ruby("3.2.11", "ruby", "3.2.11")
      end.not_to output.to_stderr
    end
  end
end
