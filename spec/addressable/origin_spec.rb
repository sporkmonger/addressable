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

require "uri"
require "addressable/uri"

module OriginSpec
  STRICT_PARSER = URI::RFC3986_Parser.new

  SCHEMES = ["http", "https", "HTTP", "ftp", "ws", "foo"].freeze
  HOSTS = [
    "example.com", "EXAMPLE.org", "a-b.example", "localhost",
    "xn--bcher-kva.example", "%65xample.com", "192.0.2.1",
    "[::1]", "[2001:db8::7]", "[2001:DB8:0:0:8:800:200C:417A]",
    "[v1.fe80::a]"
  ].freeze
  PORTS = [nil, "", "0", "80", "443", "8080", "65535"].freeze
  USERINFOS = [
    nil, "", "u", "u:p", ":p", "u:", "a:b:c", "%40", "evil.example:fake",
    "user@x"
  ].freeze
  PATHS = [nil, "", "/", "/x", "/a:b", "/x/y"].freeze
  QUERIES = [nil, "", "q=1", "a:b"].freeze
  FRAGMENTS = [nil, "", "f", "a:b"].freeze

  def self.valid?(uri)
    STRICT_PARSER.parse(uri)
    true
  rescue URI::InvalidURIError
    false
  end

  def self.pick(random, values)
    values[random.rand(values.size)]
  end

  def self.authority(random, userinfo: true)
    host = pick(random, HOSTS)
    port = pick(random, PORTS)
    info = userinfo ? pick(random, USERINFOS) : nil
    "#{info ? "#{info}@" : ""}#{host}#{port ? ":#{port}" : ""}"
  end

  # Serialized origins (Section 6.2 of RFC 6454): scheme, host and port only.
  def self.origins(count, seed)
    random = Random.new(seed)
    Array.new(count) do
      "#{pick(random, SCHEMES)}://#{authority(random, userinfo: false)}"
    end.select { |origin| valid?(origin) }
  end

  # Absolute URIs with an authority, including userinfo, path, query and
  # fragment, none of which belong in an origin.
  def self.uris(count, seed)
    random = Random.new(seed)
    Array.new(count) do
      uri = "#{pick(random, SCHEMES)}://#{authority(random)}"
      path = pick(random, PATHS)
      query = pick(random, QUERIES)
      fragment = pick(random, FRAGMENTS)
      uri += path if path
      uri += "?#{query}" if query
      uri += "##{fragment}" if fragment
      uri
    end.select { |uri| valid?(uri) && !Addressable::URI.parse(uri).host.empty? }
  end

  # Assigns the origin to a URI with a path, query and fragment of its own,
  # returning the URI, or the error if the assignment raised.
  def self.assign(origin)
    uri = Addressable::URI.parse("http://placeholder.example/p?q=1#f")
    uri.origin = origin
    uri
  rescue Addressable::URI::InvalidURIError => error
    error
  end

  def self.components(uri)
    {
      scheme: uri.normalized_scheme,
      host: uri.normalized_host,
      port: uri.normalized_port
    }
  end
end

describe Addressable::URI, "when assigning an origin" do
  it "generates enough valid inputs to be meaningful" do
    expect(OriginSpec.origins(2_000, 6454).size).to be > 500
    expect(OriginSpec.uris(4_000, 3986).size).to be > 1_000
  end

  it "gives back any serialized origin it is assigned" do
    failures = OriginSpec.origins(2_000, 6454).filter_map do |origin|
      expected = Addressable::URI.parse(origin).origin
      uri = OriginSpec.assign(origin)
      actual = uri.is_a?(Exception) ? uri.inspect : uri.origin
      [origin, expected, actual] unless actual == expected
    end
    expect(failures).to be_empty, lambda {
      "#{failures.size} origins did not round-trip " +
      "(origin, expected, actual):\n" +
      failures.uniq.first(10).map { |failure| "  #{failure.inspect}" }.join("\n")
    }
  end

  it "takes the same scheme, host and port as parse, or raises" do
    failures = OriginSpec.uris(4_000, 3986).filter_map do |input|
      uri = OriginSpec.assign(input)
      next if uri.is_a?(Exception)
      expected = OriginSpec.components(Addressable::URI.parse(input))
      actual = OriginSpec.components(uri)
      next if actual == expected && uri.userinfo.nil?
      [input, expected, actual.merge(userinfo: uri.userinfo)]
    end
    expect(failures).to be_empty, lambda {
      "#{failures.size} assignments disagreed with parse " +
      "(input, parse, origin=):\n" +
      failures.uniq.first(10).map { |failure| "  #{failure.inspect}" }.join("\n")
    }
  end
end
