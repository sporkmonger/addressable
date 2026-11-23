# frozen_string_literal: true

#--
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
#++


# Used to prevent the class/module from being loaded more than once
if !defined?(Addressable::VERSION)
  module Addressable
    module VERSION
      MAJOR = 2
      MINOR = 10
      TINY  = 0

      STRING = [MAJOR, MINOR, TINY].join('.')
    end

    ##
    # Warns that Ruby 3.2 and earlier are no longer supported. Addressable
    # still loads on them, but a future version of Addressable will require
    # Ruby 3.3 or later. Like Ruby's own deprecation warnings, it's only
    # shown when deprecation warnings are turned on: with <code>-w</code>,
    # <code>-W:deprecated</code> or <code>Warning[:deprecated] = true</code>
    # (only <code>-w</code> on Ruby 2.6 and earlier).
    #
    # @param [String] ruby_version
    #   The Ruby version to check, as the runtime reports it.
    # @param [String] engine The runtime, such as <code>"jruby"</code>.
    # @param [String] engine_version The runtime's own version.
    #
    # @api private
    def self.warn_if_unsupported_ruby(
      ruby_version = RUBY_VERSION,
      engine = RUBY_ENGINE,
      engine_version =
        (defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : RUBY_VERSION)
    )
      parts = ruby_version.split('.')
      major = parts[0].to_i
      minor = parts[1].to_i
      return if major > 3 || (major == 3 && minor >= 3)
      runtime =
        case engine
        when 'ruby' then "Ruby #{ruby_version}"
        when 'jruby' then "JRuby #{engine_version} (Ruby #{ruby_version})"
        when 'truffleruby'
          "TruffleRuby #{engine_version} (Ruby #{ruby_version})"
        else "#{engine} #{engine_version} (Ruby #{ruby_version})"
        end
      message =
        "Addressable no longer supports #{runtime}. " \
        "A future version of Addressable will require Ruby 3.3 or later."
      if RUBY_VERSION >= '3.0'
        warn(message, category: :deprecated)
      elsif defined?(Warning) && Warning.respond_to?(:[])
        # Ruby 2.7 has the deprecation setting, but warn doesn't take a
        # category.
        warn(message) if Warning[:deprecated]
      elsif $VERBOSE
        warn(message)
      end
    end

    warn_if_unsupported_ruby
  end
end
