# frozen_string_literal: true

module Addressable
  ##
  # Ensures that the URI is valid.
  module Validator
    VALIDATE_METHODS = %w[
      scheme user password userinfo host authority
      origin port path fragment
    ].freeze

    VALIDATE_METHODS.each do |m|
      define_method "#{m}=".to_sym do |*args|
        super(*args)
        validate
      end
    end

    private

    def validate
      return if @validation_deferred

      if missing_hierarchical_segment?
        error_msg = "Absolute URI missing hierarchical segment: '#{self}'"
        raise URI::InvalidURIError, error_msg
      end

      if hostname_not_supplied?
        raise URI::InvalidURIError, "Hostname not supplied: '#{self}'"
      end

      if path_presence
        if relative_path? && !authority.nil?
          error_msg = "Cannot have a relative path"
          error_msg += " with an authority set: '#{self}'"
          raise URI::InvalidURIError, error_msg
        end

        if path_with_two_leading_slashes? && authority.nil?
          error_msg = "Cannot have a path with two leading slashes"
          error_msg += " without an authority set: '#{self}'"
          raise URI::InvalidURIError, error_msg
        end
      end

      if !host.nil? && invalid_host_character?
        raise URI::InvalidURIError, "Invalid character in host: '#{host}'"
      end

      nil
    end

    def missing_hierarchical_segment?
      !scheme.nil? && ip_based? && host.to_s.empty? && path.to_s.empty?
    end

    def hostname_not_supplied?
      host.nil? && (!port.nil? || !user.nil? || !password.nil?)
    end

    def path_presence
      !path.nil? && !path.empty?
    end

    def relative_path?
      !path.start_with?(URI::SLASH)
    end

    def path_with_two_leading_slashes?
      path.start_with?(URI::DOUBLE_SLASH)
    end

    def invalid_host_character?
      (host =~ %r/[<>{}\/\\\?\#\@"[[:space:]]]/ || unescaped_backslashes?)
    end

    def unescaped_backslashes?
      return unless unescaped_backslashes_exist?

      unescaped_backslashes !~ unreserved_sub_delims_regexp
    end

    def unescaped_backslashes
      host[/^\[(.*)\]$/, 1]
    end

    def unescaped_backslashes_exist?
      !unescaped_backslashes.nil?
    end

    def unreserved_sub_delims_regexp
      @unreserved_sub_delims_regexp ||= begin
        unreserved = URI::CharacterClasses::UNRESERVED
        sub_delimiters = URI::CharacterClasses::SUB_DELIMS
        Regexp.new("^[#{unreserved}#{sub_delimiters}:]*$")
      end
    end
  end
end
