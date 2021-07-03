# frozen_string_literal: true

module Addressable
  ##
  # Ensures that the URI is valid.
  module Validator
    private

    def validate
      return if @validation_deferred

      check_hierarchical_segment
      check_hostname_supplied
      check_path_presence
      check_invalid_host_characters

      nil
    end

    def check_hierarchical_segment
      return unless missing_hierarchical_segment?

      error_msg = "Absolute URI missing hierarchical segment: '#{self}'"
      raise URI::InvalidURIError, error_msg
    end

    def check_path_presence
      return unless path_presence?

      check_relative_path
      check_path_with_two_leading_slashes
    end

    def check_relative_path
      return unless relative_path?

      error_msg = "Cannot have a relative path"
      error_msg += " with an authority set: '#{self}'"
      raise URI::InvalidURIError, error_msg
    end

    def check_path_with_two_leading_slashes
      return unless path_with_two_leading_slashes?

      error_msg = "Cannot have a path with two leading slashes"
      error_msg += " without an authority set: '#{self}'"
      raise URI::InvalidURIError, error_msg
    end

    def check_invalid_host_characters
      return if host.nil?
      return unless invalid_host_character?

      raise URI::InvalidURIError, "Invalid character in host: '#{host}'"
    end

    def check_hostname_supplied
      return unless hostname_not_supplied?

      raise URI::InvalidURIError, "Hostname not supplied: '#{self}'"
    end

    def missing_hierarchical_segment?
      !scheme.nil? && ip_based? && host.to_s.empty? && path.to_s.empty?
    end

    def hostname_not_supplied?
      host.nil? && (!port.nil? || !user.nil? || !password.nil?)
    end

    def path_presence?
      !path.nil? && !path.empty?
    end

    def relative_path?
      !path.start_with?(URI::SLASH) && !authority.nil?
    end

    def path_with_two_leading_slashes?
      path.start_with?(URI::DOUBLE_SLASH) && authority.nil?
    end

    def invalid_host_character?
      host =~ %r/[<>{}\/\\\?\#\@"[[:space:]]]/ || unescaped_backslashes?
    end

    def unescaped_backslashes?
      return false unless unescaped_backslashes_exist?

      unescaped_backslashes !~ URI::UNRESERVED_SUB_DELIMITERS_REGEXP
    end

    def unescaped_backslashes
      host[/^\[(.*)\]$/, 1]
    end

    def unescaped_backslashes_exist?
      !unescaped_backslashes.nil?
    end
  end
end
