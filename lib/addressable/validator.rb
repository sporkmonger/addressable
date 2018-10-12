# frozen_string_literal: true

module Addressable
  ##
  # Ensures that the URI is valid.
  module Validator
    METHODS_POOL = %w[
      scheme user password userinfo host authority
      origin port path fragment
    ].freeze

    METHODS_POOL.each do |m|
      define_method "#{m}=".to_sym do |*args|
        super(*args)
        validate
      end
    end

    private

    def validate
      return if @validation_deferred

      if !scheme.nil? && ip_based? &&
         (host.nil? || host.empty?) &&
         (path.nil? || path.empty?)
        raise URI::InvalidURIError,
              "Absolute URI missing hierarchical segment: '#{self}'"
      end

      if host.nil?
        if !port.nil? || !user.nil? || !password.nil?
          raise URI::InvalidURIError, "Hostname not supplied: '#{self}'"
        end
      end

      if !path.nil? && !path.empty?
        if path[0..0] != URI::SLASH && !authority.nil?
          raise URI::InvalidURIError,
                "Cannot have a relative path with an authority set: '#{self}'"
        end

        if path[0..1] == URI::SLASH + URI::SLASH && authority.nil?
          raise URI::InvalidURIError,
                "Cannot have a path with two leading slashes without an authority set: '#{self}'"
        end
      end

      unreserved = URI::CharacterClasses::UNRESERVED
      sub_delims = URI::CharacterClasses::SUB_DELIMS

      if !host.nil? && (host =~ %r/[<>{}\/\\\?\#\@"[[:space:]]]/ ||
          (!host[/^\[(.*)\]$/, 1].nil? && host[/^\[(.*)\]$/, 1] !~
              Regexp.new("^[#{unreserved}#{sub_delims}:]*$")))

        raise URI::InvalidURIError, "Invalid character in host: '#{host}'"
      end

      nil
    end
  end
end
