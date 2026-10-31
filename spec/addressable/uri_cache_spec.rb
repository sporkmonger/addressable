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

require "addressable/uri"

module URICacheSpec
  COMPONENTS = %i[scheme user password host port path query fragment].freeze

  # Every getter that's computed from other components, most of them cached.
  GETTERS = %i[
    normalized_scheme normalized_user normalized_password userinfo
    normalized_userinfo normalized_host authority normalized_authority
    normalized_port inferred_port site normalized_site normalized_path
    normalized_query normalized_fragment request_uri origin to_s hash
  ].freeze

  def self.getters(uri)
    values = GETTERS.map do |getter|
      [getter, (uri.public_send(getter) rescue $!.class)]
    end
    Hash[values].merge(normalize: (uri.normalize.to_s rescue $!.class))
  end

  # A URI with the same components that has never cached anything.
  def self.fresh(uri)
    Addressable::URI.new(Hash[COMPONENTS.map { |c| [c, uri.public_send(c)] }])
  end

  STARTS = [
    "http://one.example/p?b=2&a=1#f",
    "HTTPS://U:P@Two.Example:443/a/../b",
    "ftp://f.example:21/",
    "/rel?q",
    "mailto:x@y"
  ].freeze

  CHANGES = {
    scheme: [nil, "http", "HTTPS", "ftp", "ssh+svn", "mailto"],
    user: [nil, "", "Al%69ce", " bob ", "u:x"],
    password: [nil, "", "S%65cret", " pw "],
    host: [nil, "", "one.example", "TWO.Example.", "bücher.example",
      "[::1]", "xn--bcher-kva.example"],
    port: [nil, 80, 443, 8080, "21", ""],
    path: ["", "/", "/a/./b/../c", "x:y", "/%7Efoo", "rel/path"],
    query: [nil, "", "b=2&a=1", "x=%41"],
    fragment: [nil, "", "Frag%41"],
    userinfo: [nil, "a:b", "solo", "Al%69ce:S%65cret"],
    authority: [nil, "h.example", "U@H.EXAMPLE:80", "a:b@one.example:8080",
      "[::1]:443"],
    site: [nil, "http://Site.Example", "https://u@s.example:443",
      "//no-scheme.example"],
    origin: [nil, "http://O.example", "https://o.example:8443"],
    hostname: ["one.example", "::1", "Host.Example"],
    query_values: [{ "z" => "1", "a" => "2" }, nil],
    normalize!: [nil],
    join!: ["../x", "?q=1", "//other.example/", "#frag",
      "HTTP://J.example:80/"],
    merge!: [{ host: "m.example" }, { scheme: "https" }, { port: 8443 },
      { path: "/m" }, { user: "mu" }],
    omit!: [:scheme, :user, :port, :query, :host, :authority]
  }.freeze

  def self.change(uri, name, value)
    case name
    when :normalize! then uri.normalize!
    when :join!, :merge!, :omit! then uri.public_send(name, value)
    else uri.public_send(:"#{name}=", value)
    end
  end
end

describe Addressable::URI, "after a component changes" do
  let(:uri) { Addressable::URI.parse("https://one.example") }

  it "uses the new host for every value built from the host" do
    uri.normalize
    uri.site
    uri.normalized_site
    uri.normalized_authority
    uri.host = "two.example"
    expect(uri.site).to eq("https://two.example")
    expect(uri.normalized_site).to eq("https://two.example")
    expect(uri.normalized_authority).to eq("two.example")
    expect(uri.normalize.to_s).to eq("https://two.example/")
  end

  it "uses the new port for the site" do
    uri.normalized_site
    uri.port = 8443
    expect(uri.site).to eq("https://one.example:8443")
    expect(uri.normalized_site).to eq("https://one.example:8443")
  end

  it "drops a port that the new scheme has as its default" do
    uri = Addressable::URI.parse("http://a.example:443")
    expect(uri.normalized_port).to eq(443)
    uri.scheme = "https"
    expect(uri.normalized_port).to be_nil
    expect(uri.normalize.to_s).to eq("https://a.example/")
  end

  it "uses the new scheme for an empty path" do
    uri = Addressable::URI.parse("//a.example")
    expect(uri.normalized_path).to eq("")
    uri.scheme = "http"
    expect(uri.normalized_path).to eq("/")
  end

  it "uses the new scheme for empty userinfo" do
    uri = Addressable::URI.parse("ftp://:@a.example")
    expect(uri.normalized_authority).to eq(":@a.example")
    uri.scheme = "http"
    expect(uri.normalized_userinfo).to be_nil
    expect(uri.normalized_authority).to eq("a.example")
  end

  it "uses the new user for an empty password" do
    uri = Addressable::URI.parse("http://:@a.example")
    expect(uri.normalized_password).to be_nil
    uri.user = "u"
    expect(uri.normalized_password).to eq("")
  end

  it "uses the new password for an empty user" do
    uri = Addressable::URI.parse("http://:@a.example")
    expect(uri.normalized_user).to be_nil
    uri.password = "p"
    expect(uri.normalized_user).to eq("")
  end

  it "uses the joined URI for the site" do
    uri.normalized_site
    uri.join!("//two.example/")
    expect(uri.site).to eq("https://two.example")
    expect(uri.normalized_site).to eq("https://two.example")
  end

  it "uses the merged URI for the site" do
    uri.site
    uri.merge!(host: "two.example")
    expect(uri.site).to eq("https://two.example")
  end

  it "gives every value a fresh URI gives, after any changes" do
    random = Random.new(613)
    stale = []
    300.times do
      uri = Addressable::URI.parse(
        URICacheSpec::STARTS[random.rand(URICacheSpec::STARTS.size)]
      )
      changes = []
      8.times do
        URICacheSpec.getters(uri) if random.rand < 0.7
        name = URICacheSpec::CHANGES.keys[
          random.rand(URICacheSpec::CHANGES.size)
        ]
        values = URICacheSpec::CHANGES[name]
        value = values[random.rand(values.size)]
        changes << [name, value]
        begin
          URICacheSpec.change(uri, name, value)
          fresh = URICacheSpec.fresh(uri)
        rescue Addressable::URI::InvalidURIError
          next
        end
        # A setter that raises keeps the changes it made before raising, so
        # the URI can hold components that a new URI would adjust (such as a
        # path without a leading slash next to a host). Only compare URIs
        # with the same components.
        next unless URICacheSpec::COMPONENTS.all? do |component|
          uri.public_send(component) == fresh.public_send(component)
        end
        expected = URICacheSpec.getters(fresh)
        URICacheSpec.getters(uri).each do |getter, actual|
          next if actual == expected[getter]
          stale << [changes.dup, getter, actual, expected[getter]]
        end
      end
    end
    expect(stale.first(5)).to eq([])
  end
end

describe Addressable::URI, "when normalizing the query with flags" do
  let(:uri) { Addressable::URI.parse("http://example.com/?b=2&a=1&a=1") }

  it "sorts after a call without flags" do
    expect(uri.normalized_query).to eq("b=2&a=1&a=1")
    expect(uri.normalized_query(:sorted)).to eq("a=1&a=1&b=2")
  end

  it "doesn't sort a later call without flags" do
    expect(uri.normalized_query(:sorted)).to eq("a=1&a=1&b=2")
    expect(uri.normalized_query).to eq("b=2&a=1&a=1")
    expect(uri.normalize.to_s).to eq("http://example.com/?b=2&a=1&a=1")
  end

  it "applies only the flags given in each call" do
    expect(uri.normalized_query(:compacted)).to eq("b=2&a=1")
    expect(uri.normalized_query(:sorted)).to eq("a=1&a=1&b=2")
    expect(uri.normalized_query(:sorted, :compacted)).to eq("a=1&b=2")
  end

  it "applies flags to a frozen URI" do
    uri.freeze
    expect(uri.normalized_query(:sorted, :compacted)).to eq("a=1&b=2")
    expect(uri.normalized_query).to eq("b=2&a=1&a=1")
  end

  it "uses a new query" do
    uri.normalized_query(:sorted)
    uri.query = "d=4&c=3"
    expect(uri.normalized_query).to eq("d=4&c=3")
    expect(uri.normalized_query(:sorted)).to eq("c=3&d=4")
  end

  it "keeps caching the query normalized without flags" do
    expect(uri.normalized_query).to equal(uri.normalized_query)
  end

  it "gives every result a fresh URI gives, after any calls" do
    flag_sets = [[], [:sorted], [:compacted], [:sorted, :compacted]]
    queries = [nil, "", "b=2&a=1", "a&&c&a", "a=1&a=1&b", "x=%41&y=%7e"]
    random = Random.new(608)
    wrong = []
    300.times do
      uri = Addressable::URI.new(
        host: "example.com", query: queries[random.rand(queries.size)]
      )
      calls = []
      8.times do
        case random.rand(8)
        when 0
          next if uri.frozen?
          query = queries[random.rand(queries.size)]
          uri.query = query
          calls << [:query=, query]
        when 1
          uri.freeze
          calls << :freeze
        else
          flags = flag_sets[random.rand(flag_sets.size)]
          calls << flags
          fresh = Addressable::URI.new(host: "example.com", query: uri.query)
          result = uri.normalized_query(*flags)
          expected = fresh.normalized_query(*flags)
          wrong << [calls.dup, result, expected] if result != expected
        end
      end
    end
    expect(wrong.first(5)).to eq([])
  end
end
