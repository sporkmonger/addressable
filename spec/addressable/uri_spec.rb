# coding:utf-8
#--
# Addressable, Copyright (c) 2006-2007 Bob Aman
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../../lib'))
$:.uniq!

require "addressable/uri"

if !"".respond_to?("force_encoding")
  class String
    def force_encoding(encoding)
      # Do nothing, just make sure this gets called.
    end
  end

  class Encoding
    UTF_8 = Encoding.new
    ASCII_8BIT = Encoding.new
  end
end

class ExampleProcessor
  def self.validate(name, value)
    return !!(value =~ /^[\w ]+$/) if name == "query"
    return true
  end

  def self.transform(name, value)
    return value.gsub(/ /, "+") if name == "query"
    return value
  end

  def self.restore(name, value)
    return value.gsub(/\+/, " ") if name == "query"
    return value.tr("A-Za-z", "N-ZA-Mn-za-m") if name == "rot13"
    return value
  end

  def self.match(name)
    return ".*?" if name == "first"
    return ".*"
  end
end

class SlashlessProcessor
  def self.match(name)
    return "[^/\\n]*"
  end
end

class NoOpProcessor
  def self.transform(name, value)
    value
  end
end

describe Addressable::URI, "when created with a non-numeric port number" do
  it "should raise an error" do
    (lambda do
      Addressable::URI.new(:port => "bogus")
    end).should raise_error(Addressable::URI::InvalidURIError)
  end
end

describe Addressable::URI, "when created with a scheme but no hierarchical " +
    "segment" do
  it "should raise an error" do
    (lambda do
      Addressable::URI.parse("http:")
    end).should raise_error(Addressable::URI::InvalidURIError)
  end
end

describe Addressable::URI, "when created from nil components" do
  before do
    @uri = Addressable::URI.new
  end

  it "should have an empty path" do
    @uri.path.should == ""
  end

  it "should be an empty uri" do
    @uri.to_s.should == ""
  end
end

describe Addressable::URI, "when created from string components" do
  before do
    @uri = Addressable::URI.new(
      :scheme => "http", :host => "example.com"
    )
  end

  it "should be equal to the equivalent parsed URI" do
    @uri.should == Addressable::URI.parse("http://example.com")
  end

  it "should raise an error if invalid components omitted" do
    (lambda do
      @uri.omit(:bogus)
    end).should raise_error(ArgumentError)
    (lambda do
      @uri.omit(:scheme, :bogus, :path)
    end).should raise_error(ArgumentError)
  end
end

describe Addressable::URI, "when created with a nil host but " +
    "non-nil authority components" do
  it "should raise an error" do
    (lambda do
      Addressable::URI.new(:user => "user", :password => "pass", :port => 80)
    end).should raise_error(Addressable::URI::InvalidURIError)
  end
end

describe Addressable::URI, "when created with both an authority and a user" do
  it "should raise an error" do
    (lambda do
      Addressable::URI.new(:user => "user", :authority => "user@example.com:80")
    end).should raise_error(ArgumentError)
  end
end

describe Addressable::URI, "when created with an authority and no port" do
  before do
    @uri = Addressable::URI.new(:authority => "user@example.com")
  end

  it "should not infer a port" do
    @uri.port.should == nil
    @uri.inferred_port.should == nil
  end
end

describe Addressable::URI, "when created with both a userinfo and a user" do
  it "should raise an error" do
    (lambda do
      Addressable::URI.new(:user => "user", :userinfo => "user:pass")
    end).should raise_error(ArgumentError)
  end
end

describe Addressable::URI, "when created with a path that hasn't been " +
    "prefixed with a '/' but a host specified" do
  it "should prefix a '/' to the path" do
    Addressable::URI.new(
      :scheme => "http", :host => "example.com", :path => "path"
    ).should == Addressable::URI.parse("http://example.com/path")
  end
end

describe Addressable::URI, "when created with a path that hasn't been " +
    "prefixed with a '/' but no host specified" do
  it "should prefix a '/' to the path" do
    Addressable::URI.new(
      :scheme => "http", :path => "path"
    ).should == Addressable::URI.parse("http:path")
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'ftp://ftp.is.co.za/rfc/rfc1808.txt'" do
  before do
    @uri = Addressable::URI.parse("ftp://ftp.is.co.za/rfc/rfc1808.txt")
  end

  it "should use the 'ftp' scheme" do
    @uri.scheme.should == "ftp"
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have a host of 'ftp.is.co.za'" do
    @uri.host.should == "ftp.is.co.za"
  end

  it "should have a path of '/rfc/rfc1808.txt'" do
    @uri.path.should == "/rfc/rfc1808.txt"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'http://www.ietf.org/rfc/rfc2396.txt'" do
  before do
    @uri = Addressable::URI.parse("http://www.ietf.org/rfc/rfc2396.txt")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have a host of 'www.ietf.org'" do
    @uri.host.should == "www.ietf.org"
  end

  it "should have a path of '/rfc/rfc2396.txt'" do
    @uri.path.should == "/rfc/rfc2396.txt"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end

  it "should correctly omit components" do
    @uri.omit(:scheme).to_s.should == "//www.ietf.org/rfc/rfc2396.txt"
    @uri.omit(:path).to_s.should == "http://www.ietf.org"
  end

  it "should correctly omit components destructively" do
    @uri.omit!(:scheme)
    @uri.to_s.should == "//www.ietf.org/rfc/rfc2396.txt"
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, "when parsed from " +
    "'ldap://[2001:db8::7]/c=GB?objectClass?one'" do
  before do
    @uri = Addressable::URI.parse("ldap://[2001:db8::7]/c=GB?objectClass?one")
  end

  it "should use the 'ldap' scheme" do
    @uri.scheme.should == "ldap"
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have a host of '[2001:db8::7]'" do
    @uri.host.should == "[2001:db8::7]"
  end

  it "should have a path of '/c=GB'" do
    @uri.path.should == "/c=GB"
  end

  it "should have a query of 'objectClass?one'" do
    @uri.query.should == "objectClass?one"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end

  it "should correctly omit components" do
    @uri.omit(:scheme, :authority).to_s.should == "/c=GB?objectClass?one"
    @uri.omit(:path).to_s.should == "ldap://[2001:db8::7]?objectClass?one"
  end

  it "should correctly omit components destructively" do
    @uri.omit!(:scheme, :authority)
    @uri.to_s.should == "/c=GB?objectClass?one"
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'mailto:John.Doe@example.com'" do
  before do
    @uri = Addressable::URI.parse("mailto:John.Doe@example.com")
  end

  it "should use the 'mailto' scheme" do
    @uri.scheme.should == "mailto"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of 'John.Doe@example.com'" do
    @uri.path.should == "John.Doe@example.com"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'news:comp.infosystems.www.servers.unix'" do
  before do
    @uri = Addressable::URI.parse("news:comp.infosystems.www.servers.unix")
  end

  it "should use the 'news' scheme" do
    @uri.scheme.should == "news"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of 'comp.infosystems.www.servers.unix'" do
    @uri.path.should == "comp.infosystems.www.servers.unix"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, "when parsed from " +
    "'tel:+1-816-555-1212'" do
  before do
    @uri = Addressable::URI.parse("tel:+1-816-555-1212")
  end

  it "should use the 'tel' scheme" do
    @uri.scheme.should == "tel"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of '+1-816-555-1212'" do
    @uri.path.should == "+1-816-555-1212"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'telnet://192.0.2.16:80/'" do
  before do
    @uri = Addressable::URI.parse("telnet://192.0.2.16:80/")
  end

  it "should use the 'telnet' scheme" do
    @uri.scheme.should == "telnet"
  end

  it "should have a host of '192.0.2.16'" do
    @uri.host.should == "192.0.2.16"
  end

  it "should have a port of '80'" do
    @uri.port.should == 80
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have a path of '/'" do
    @uri.path.should == "/"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

# Section 1.1.2 of RFC 3986
describe Addressable::URI, " when parsed from " +
    "'urn:oasis:names:specification:docbook:dtd:xml:4.1.2'" do
  before do
    @uri = Addressable::URI.parse(
      "urn:oasis:names:specification:docbook:dtd:xml:4.1.2")
  end

  it "should use the 'urn' scheme" do
    @uri.scheme.should == "urn"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of " +
      "'oasis:names:specification:docbook:dtd:xml:4.1.2'" do
    @uri.path.should == "oasis:names:specification:docbook:dtd:xml:4.1.2"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com'" do
  before do
    @uri = Addressable::URI.parse("http://example.com")
  end

  it "when inspected, should have the correct URI" do
    @uri.inspect.should include("http://example.com")
  end

  it "when inspected, should have the correct class name" do
    @uri.inspect.should include("Addressable::URI")
  end

  it "when inspected, should have the correct object id" do
    @uri.inspect.should include("%#0x" % @uri.object_id)
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should be considered ip-based" do
    @uri.should be_ip_based
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should not have a specified port" do
    @uri.port.should == nil
  end

  it "should have an empty path" do
    @uri.path.should == ""
  end

  it "should have no query string" do
    @uri.query.should == nil
    @uri.query_values.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should not be considered relative" do
    @uri.should_not be_relative
  end

  it "should not be exactly equal to 42" do
    @uri.eql?(42).should == false
  end

  it "should not be equal to 42" do
    (@uri == 42).should == false
  end

  it "should not be roughly equal to 42" do
    (@uri === 42).should == false
  end

  it "should be exactly equal to http://example.com" do
    @uri.eql?(Addressable::URI.parse("http://example.com")).should == true
  end

  it "should be roughly equal to http://example.com/" do
    (@uri === Addressable::URI.parse("http://example.com/")).should == true
  end

  it "should be roughly equal to the string 'http://example.com/'" do
    (@uri === "http://example.com/").should == true
  end

  it "should not be roughly equal to the string " +
      "'http://example.com:bogus/'" do
    (lambda do
      (@uri === "http://example.com:bogus/").should == false
    end).should_not raise_error
  end

  it "should result in itself when joined with itself" do
    @uri.join(@uri).to_s.should == "http://example.com"
    @uri.join!(@uri).to_s.should == "http://example.com"
  end

  # Section 6.2.3 of RFC 3986
  it "should be equivalent to http://example.com/" do
    @uri.should == Addressable::URI.parse("http://example.com/")
  end

  # Section 6.2.3 of RFC 3986
  it "should be equivalent to http://example.com:/" do
    @uri.should == Addressable::URI.parse("http://example.com:/")
  end

  # Section 6.2.3 of RFC 3986
  it "should be equivalent to http://example.com:80/" do
    @uri.should == Addressable::URI.parse("http://example.com:80/")
  end

  # Section 6.2.2.1 of RFC 3986
  it "should be equivalent to http://EXAMPLE.COM/" do
    @uri.should == Addressable::URI.parse("http://EXAMPLE.COM/")
  end

  it "should have a route of '/path/' to 'http://example.com/path/'" do
    @uri.route_to("http://example.com/path/").should ==
      Addressable::URI.parse("/path/")
  end

  it "should have a route of '/' from 'http://example.com/path/'" do
    @uri.route_from("http://example.com/path/").should ==
      Addressable::URI.parse("/")
  end

  it "should have a route of '#' to 'http://example.com/'" do
    @uri.route_to("http://example.com/").should ==
      Addressable::URI.parse("#")
  end

  it "should have a route of 'http://elsewhere.com/' to " +
      "'http://elsewhere.com/'" do
    @uri.route_to("http://elsewhere.com/").should ==
      Addressable::URI.parse("http://elsewhere.com/")
  end

  it "when joined with 'relative/path' should be " +
      "'http://example.com/relative/path'" do
    @uri.join('relative/path').should ==
      Addressable::URI.parse("http://example.com/relative/path")
  end

  it "when joined with a bogus object a TypeError should be raised" do
    (lambda do
      @uri.join(42)
    end).should raise_error(TypeError)
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password.should == nil
    @uri.to_s.should == "http://newuser@example.com"
  end

  it "should have the correct username after assignment" do
    @uri.user = "user@123!"
    @uri.user.should == "user@123!"
    @uri.normalized_user.should == "user%40123%21"
    @uri.password.should == nil
    @uri.normalize.to_s.should == "http://user%40123%21@example.com/"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.user.should == ""
    @uri.to_s.should == "http://:newpass@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "secret@123!"
    @uri.password.should == "secret@123!"
    @uri.normalized_password.should == "secret%40123%21"
    @uri.user.should == ""
    @uri.normalize.to_s.should == "http://:secret%40123%21@example.com/"
  end

  it "should have the correct user/pass after repeated assignment" do
    @uri.user = nil
    @uri.user.should == nil
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    # Username cannot be nil if the password is set
    @uri.user.should == ""
    @uri.to_s.should == "http://:newpass@example.com"
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password = nil
    @uri.password.should == nil
    @uri.to_s.should == "http://newuser@example.com"
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password = ""
    @uri.password.should == ""
    @uri.to_s.should == "http://newuser:@example.com"
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.user = nil
    # Username cannot be nil if the password is set
    @uri.user.should == ""
    @uri.to_s.should == "http://:newpass@example.com"
  end

  it "should have the correct user/pass after userinfo assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.userinfo = nil
    @uri.userinfo.should == nil
    @uri.user.should == nil
    @uri.password.should == nil
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => nil,
      :password => nil,
      :host => "example.com",
      :port => nil,
      :path => "",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://example.com" do
    @uri.should == Addressable::URI.parse("http://example.com")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to HTTP://example.com/" do
    @uri.should == Addressable::URI.parse("HTTP://example.com/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://example.com:/" do
    @uri.should == Addressable::URI.parse("http://example.com:/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://example.com:80/" do
    @uri.should == Addressable::URI.parse("http://example.com:80/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://Example.com/" do
    @uri.should == Addressable::URI.parse("http://Example.com/")
  end

  it "should have the correct username after assignment" do
    @uri.user = nil
    @uri.user.should == nil
    @uri.password.should == nil
    @uri.to_s.should == "http://example.com/"
  end

  it "should have the correct password after assignment" do
    @uri.password = nil
    @uri.password.should == nil
    @uri.user.should == nil
    @uri.to_s.should == "http://example.com/"
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => nil,
      :password => nil,
      :host => "example.com",
      :port => nil,
      :path => "/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end

  it "should have the same hash as its duplicate" do
    @uri.hash.should == @uri.dup.hash
  end

  it "should have a different hash from its equivalent String value" do
    @uri.hash.should_not == @uri.to_s.hash
  end

  it "should have the same hash as an equivalent URI" do
    @uri.hash.should == Addressable::URI.parse("http://example.com:80/").hash
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://@example.com/'" do
  before do
    @uri = Addressable::URI.parse("http://@example.com/")
  end

  it "should be equivalent to http://example.com" do
    @uri.should == Addressable::URI.parse("http://example.com")
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => "",
      :password => nil,
      :host => "example.com",
      :port => nil,
      :path => "/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com./'" do
  before do
    @uri = Addressable::URI.parse("http://example.com./")
  end

  it "should be equivalent to http://example.com" do
    @uri.should == Addressable::URI.parse("http://example.com")
  end

  it "should not be considered to be in normal form" do
    @uri.normalize.should_not be_eql(@uri)
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://:@example.com/'" do
  before do
    @uri = Addressable::URI.parse("http://:@example.com/")
  end

  it "should be equivalent to http://example.com" do
    @uri.should == Addressable::URI.parse("http://example.com")
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => "",
      :password => "",
      :host => "example.com",
      :port => nil,
      :path => "/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/~smith/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/~smith/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://example.com/%7Esmith/" do
    @uri.should == Addressable::URI.parse("http://example.com/%7Esmith/")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to http://example.com/%7esmith/" do
    @uri.should == Addressable::URI.parse("http://example.com/%7esmith/")
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/%C3%87'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/%C3%87")
  end

  # Based on http://intertwingly.net/blog/2004/07/31/URI-Equivalence
  it "should be equivalent to 'http://example.com/C%CC%A7'" do
    @uri.should == Addressable::URI.parse("http://example.com/C%CC%A7")
  end

  it "should not change if encoded with the normalizing algorithm" do
    Addressable::URI.normalized_encode(@uri).to_s.should ==
      "http://example.com/%C3%87"
    Addressable::URI.normalized_encode(@uri, Addressable::URI).to_s.should ===
      "http://example.com/%C3%87"
  end

  it "should raise an error if encoding with an unexpected return type" do
    (lambda do
      Addressable::URI.normalized_encode(@uri, Integer)
    end).should raise_error(TypeError)
  end

  it "if percent encoded should be 'http://example.com/C%25CC%25A7'" do
    Addressable::URI.encode(@uri).to_s.should ==
      "http://example.com/%25C3%2587"
  end

  it "if percent encoded should be 'http://example.com/C%25CC%25A7'" do
    Addressable::URI.encode(@uri, Addressable::URI).should ==
      Addressable::URI.parse("http://example.com/%25C3%2587")
  end

  it "should raise an error if encoding with an unexpected return type" do
    (lambda do
      Addressable::URI.encode(@uri, Integer)
    end).should raise_error(TypeError)
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?q=string'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?q=string")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/'" do
    @uri.path.should == "/"
  end

  it "should have a query string of 'q=string'" do
    @uri.query.should == "q=string"
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should not be considered relative" do
    @uri.should_not be_relative
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com:80/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com:80/")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com:80'" do
    @uri.authority.should == "example.com:80"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.port.should == 80
  end

  it "should have a path of '/'" do
    @uri.path.should == "/"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should not be considered relative" do
    @uri.should_not be_relative
  end

  it "should be exactly equal to http://example.com:80/" do
    @uri.eql?(Addressable::URI.parse("http://example.com:80/")).should == true
  end

  it "should be roughly equal to http://example.com/" do
    (@uri === Addressable::URI.parse("http://example.com/")).should == true
  end

  it "should be roughly equal to the string 'http://example.com/'" do
    (@uri === "http://example.com/").should == true
  end

  it "should not be roughly equal to the string " +
      "'http://example.com:bogus/'" do
    (lambda do
      (@uri === "http://example.com:bogus/").should == false
    end).should_not raise_error
  end

  it "should result in itself when joined with itself" do
    @uri.join(@uri).to_s.should == "http://example.com:80/"
    @uri.join!(@uri).to_s.should == "http://example.com:80/"
  end

  # Section 6.2.3 of RFC 3986
  it "should be equal to http://example.com/" do
    @uri.should == Addressable::URI.parse("http://example.com/")
  end

  # Section 6.2.3 of RFC 3986
  it "should be equal to http://example.com:/" do
    @uri.should == Addressable::URI.parse("http://example.com:/")
  end

  # Section 6.2.3 of RFC 3986
  it "should be equal to http://example.com:80/" do
    @uri.should == Addressable::URI.parse("http://example.com:80/")
  end

  # Section 6.2.2.1 of RFC 3986
  it "should be equal to http://EXAMPLE.COM/" do
    @uri.should == Addressable::URI.parse("http://EXAMPLE.COM/")
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => nil,
      :password => nil,
      :host => "example.com",
      :port => 80,
      :path => "/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com:8080/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com:8080/")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com:8080'" do
    @uri.authority.should == "example.com:8080"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 8080" do
    @uri.port.should == 8080
  end

  it "should have a path of '/'" do
    @uri.path.should == "/"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should not be considered relative" do
    @uri.should_not be_relative
  end

  it "should be exactly equal to http://example.com:8080/" do
    @uri.eql?(Addressable::URI.parse(
      "http://example.com:8080/")).should == true
  end

  it "should have a route of 'http://example.com:8080/' from " +
      "'http://example.com/path/to/'" do
    @uri.route_from("http://example.com/path/to/").should ==
      Addressable::URI.parse("http://example.com:8080/")
  end

  it "should have a route of 'http://example.com:8080/' from " +
      "'http://example.com:80/path/to/'" do
    @uri.route_from("http://example.com:80/path/to/").should ==
      Addressable::URI.parse("http://example.com:8080/")
  end

  it "should have a route of '/' from " +
      "'http://example.com:8080/path/to/'" do
    @uri.route_from("http://example.com:8080/path/to/").should ==
      Addressable::URI.parse("/")
  end

  it "should have a route of 'http://example.com:8080/' from " +
      "'http://user:pass@example.com/path/to/'" do
    @uri.route_from("http://user:pass@example.com/path/to/").should ==
      Addressable::URI.parse("http://example.com:8080/")
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => nil,
      :password => nil,
      :host => "example.com",
      :port => 8080,
      :path => "/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com:%38%30/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com:%38%30/")
  end

  it "should have the correct port" do
    @uri.port.should == 80
  end

  it "should not be considered to be in normal form" do
    @uri.normalize.should_not be_eql(@uri)
  end

  it "should normalize to 'http://example.com/'" do
    @uri.normalize.should === "http://example.com/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/path/to/resource/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/path/to/resource/")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/path/to/resource/'" do
    @uri.path.should == "/path/to/resource/"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should not be considered relative" do
    @uri.should_not be_relative
  end

  it "should be exactly equal to http://example.com:8080/" do
    @uri.eql?(Addressable::URI.parse(
      "http://example.com/path/to/resource/")).should == true
  end

  it "should have a route of 'resource/' from " +
      "'http://example.com/path/to/'" do
    @uri.route_from("http://example.com/path/to/").should ==
      Addressable::URI.parse("resource/")
  end

  it "should have a route of 'resource/' from " +
      "'http://example.com:80/path/to/'" do
    @uri.route_from("http://example.com:80/path/to/").should ==
      Addressable::URI.parse("resource/")
  end

  it "should have a route of 'http://example.com/path/to/' from " +
      "'http://example.com:8080/path/to/'" do
    @uri.route_from("http://example.com:8080/path/to/").should ==
      Addressable::URI.parse("http://example.com/path/to/resource/")
  end

  it "should have a route of 'http://example.com/path/to/' from " +
      "'http://user:pass@example.com/path/to/'" do
    @uri.route_from("http://user:pass@example.com/path/to/").should ==
      Addressable::URI.parse("http://example.com/path/to/resource/")
  end

  it "should have a route of '/path/to/resource/' from " +
      "'http://example.com/to/resource/'" do
    @uri.route_from("http://example.com/to/resource/").should ==
      Addressable::URI.parse("/path/to/resource/")
  end

  it "should correctly convert to a hash" do
    @uri.to_hash.should == {
      :scheme => "http",
      :user => nil,
      :password => nil,
      :host => "example.com",
      :port => nil,
      :path => "/path/to/resource/",
      :query => nil,
      :fragment => nil
    }
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, "when parsed from " +
    "'relative/path/to/resource'" do
  before do
    @uri = Addressable::URI.parse("relative/path/to/resource")
  end

  it "should not have a scheme" do
    @uri.scheme.should == nil
  end

  it "should not be considered ip-based" do
    @uri.should_not be_ip_based
  end

  it "should not have an authority segment" do
    @uri.authority.should == nil
  end

  it "should not have a host" do
    @uri.host.should == nil
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should not have a port" do
    @uri.port.should == nil
  end

  it "should have a path of 'relative/path/to/resource'" do
    @uri.path.should == "relative/path/to/resource"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should not be considered absolute" do
    @uri.should_not be_absolute
  end

  it "should be considered relative" do
    @uri.should be_relative
  end

  it "should raise an error if routing is attempted" do
    (lambda do
      @uri.route_to("http://example.com/")
    end).should raise_error(ArgumentError, /relative\/path\/to\/resource/)
    (lambda do
      @uri.route_from("http://example.com/")
    end).should raise_error(ArgumentError, /relative\/path\/to\/resource/)
  end

  it "when joined with 'another/relative/path' should be " +
      "'relative/path/to/another/relative/path'" do
    @uri.join('another/relative/path').should ==
      Addressable::URI.parse("relative/path/to/another/relative/path")
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, "when parsed from " +
    "'relative_path_with_no_slashes'" do
  before do
    @uri = Addressable::URI.parse("relative_path_with_no_slashes")
  end

  it "should not have a scheme" do
    @uri.scheme.should == nil
  end

  it "should not be considered ip-based" do
    @uri.should_not be_ip_based
  end

  it "should not have an authority segment" do
    @uri.authority.should == nil
  end

  it "should not have a host" do
    @uri.host.should == nil
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should not have a port" do
    @uri.port.should == nil
  end

  it "should have a path of 'relative_path_with_no_slashes'" do
    @uri.path.should == "relative_path_with_no_slashes"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should not be considered absolute" do
    @uri.should_not be_absolute
  end

  it "should be considered relative" do
    @uri.should be_relative
  end

  it "when joined with 'another_relative_path' should be " +
      "'another_relative_path'" do
    @uri.join('another_relative_path').should ==
      Addressable::URI.parse("another_relative_path")
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/file.txt'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/file.txt")
  end

  it "should have a scheme of 'http'" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/file.txt'" do
    @uri.path.should == "/file.txt"
  end

  it "should have a basename of 'file.txt'" do
    @uri.basename.should == "file.txt"
  end

  it "should have an extname of '.txt'" do
    @uri.extname.should == ".txt"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/file.txt;parameter'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/file.txt;parameter")
  end

  it "should have a scheme of 'http'" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/file.txt;parameter'" do
    @uri.path.should == "/file.txt;parameter"
  end

  it "should have a basename of 'file.txt'" do
    @uri.basename.should == "file.txt"
  end

  it "should have an extname of '.txt'" do
    @uri.extname.should == ".txt"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/file.txt;x=y'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/file.txt;x=y")
  end

  it "should have a scheme of 'http'" do
    @uri.scheme.should == "http"
  end

  it "should have a scheme of 'http'" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'example.com'" do
    @uri.authority.should == "example.com"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have no username" do
    @uri.user.should == nil
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/file.txt;x=y'" do
    @uri.path.should == "/file.txt;x=y"
  end

  it "should have an extname of '.txt'" do
    @uri.extname.should == ".txt"
  end

  it "should have no query string" do
    @uri.query.should == nil
  end

  it "should have no fragment" do
    @uri.fragment.should == nil
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'svn+ssh://developername@rubyforge.org/var/svn/project'" do
  before do
    @uri = Addressable::URI.parse(
      "svn+ssh://developername@rubyforge.org/var/svn/project"
    )
  end

  it "should have a scheme of 'svn+ssh'" do
    @uri.scheme.should == "svn+ssh"
  end

  it "should be considered to be ip-based" do
    @uri.should be_ip_based
  end

  it "should have a path of '/var/svn/project'" do
    @uri.path.should == "/var/svn/project"
  end

  it "should have a username of 'developername'" do
    @uri.user.should == "developername"
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'ssh+svn://developername@rubyforge.org/var/svn/project'" do
  before do
    @uri = Addressable::URI.parse(
      "ssh+svn://developername@rubyforge.org/var/svn/project"
    )
  end

  it "should have a scheme of 'ssh+svn'" do
    @uri.scheme.should == "ssh+svn"
  end

  it "should have a normalized scheme of 'svn+ssh'" do
    @uri.normalized_scheme.should == "svn+ssh"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of '/var/svn/project'" do
    @uri.path.should == "/var/svn/project"
  end

  it "should have a username of 'developername'" do
    @uri.user.should == "developername"
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should not be considered to be in normal form" do
    @uri.normalize.should_not be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'mailto:user@example.com'" do
  before do
    @uri = Addressable::URI.parse("mailto:user@example.com")
  end

  it "should have a scheme of 'mailto'" do
    @uri.scheme.should == "mailto"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of 'user@example.com'" do
    @uri.path.should == "user@example.com"
  end

  it "should have no user" do
    @uri.user.should == nil
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'tag:example.com,2006-08-18:/path/to/something'" do
  before do
    @uri = Addressable::URI.parse(
      "tag:example.com,2006-08-18:/path/to/something")
  end

  it "should have a scheme of 'tag'" do
    @uri.scheme.should == "tag"
  end

  it "should be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should have a path of " +
      "'example.com,2006-08-18:/path/to/something'" do
    @uri.path.should == "example.com,2006-08-18:/path/to/something"
  end

  it "should have no user" do
    @uri.user.should == nil
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/x;y/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/x;y/")
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?x=1&y=2'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?x=1&y=2")
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'view-source:http://example.com/'" do
  before do
    @uri = Addressable::URI.parse("view-source:http://example.com/")
  end

  it "should have a scheme of 'view-source'" do
    @uri.scheme.should == "view-source"
  end

  it "should have a path of 'http://example.com/'" do
    @uri.path.should == "http://example.com/"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://user:pass@example.com/path/to/resource?query=x#fragment'" do
  before do
    @uri = Addressable::URI.parse(
      "http://user:pass@example.com/path/to/resource?query=x#fragment")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have an authority segment of 'user:pass@example.com'" do
    @uri.authority.should == "user:pass@example.com"
  end

  it "should have a username of 'user'" do
    @uri.user.should == "user"
  end

  it "should have a password of 'pass'" do
    @uri.password.should == "pass"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/path/to/resource'" do
    @uri.path.should == "/path/to/resource"
  end

  it "should have a query string of 'query=x'" do
    @uri.query.should == "query=x"
  end

  it "should have a fragment of 'fragment'" do
    @uri.fragment.should == "fragment"
  end

  it "should be considered to be in normal form" do
    @uri.normalize.should be_eql(@uri)
  end

  it "should have a route of '/path/' to " +
      "'http://user:pass@example.com/path/'" do
    @uri.route_to("http://user:pass@example.com/path/").should ==
      Addressable::URI.parse("/path/")
  end

  it "should have a route of '/path/to/resource?query=x#fragment' " +
      "from 'http://user:pass@example.com/path/'" do
    @uri.route_from("http://user:pass@example.com/path/").should ==
      Addressable::URI.parse("to/resource?query=x#fragment")
  end

  it "should have a route of '?query=x#fragment' " +
      "from 'http://user:pass@example.com/path/to/resource'" do
    @uri.route_from("http://user:pass@example.com/path/to/resource").should ==
      Addressable::URI.parse("?query=x#fragment")
  end

  it "should have a route of '#fragment' " +
      "from 'http://user:pass@example.com/path/to/resource?query=x'" do
    @uri.route_from(
      "http://user:pass@example.com/path/to/resource?query=x").should ==
        Addressable::URI.parse("#fragment")
  end

  it "should have a route of '#fragment' from " +
      "'http://user:pass@example.com/path/to/resource?query=x#fragment'" do
    @uri.route_from(
      "http://user:pass@example.com/path/to/resource?query=x#fragment"
    ).should == Addressable::URI.parse("#fragment")
  end

  it "should have a route of 'http://elsewhere.com/' to " +
      "'http://elsewhere.com/'" do
    @uri.route_to("http://elsewhere.com/").should ==
      Addressable::URI.parse("http://elsewhere.com/")
  end

  it "should have a route of " +
      "'http://user:pass@example.com/path/to/resource?query=x#fragment' " +
      "from 'http://example.com/path/to/'" do
    @uri.route_from("http://elsewhere.com/path/to/").should ==
      Addressable::URI.parse(
        "http://user:pass@example.com/path/to/resource?query=x#fragment")
  end

  it "should have the correct scheme after assignment" do
    @uri.scheme = "ftp"
    @uri.scheme.should == "ftp"
    @uri.to_s.should ==
      "ftp://user:pass@example.com/path/to/resource?query=x#fragment"
    @uri.scheme = "bogus!"
    @uri.scheme.should == "bogus!"
    @uri.normalized_scheme.should == "bogus%21"
    @uri.normalize.to_s.should ==
      "bogus%21://user:pass@example.com/path/to/resource?query=x#fragment"
  end

  it "should have the correct authority segment after assignment" do
    @uri.authority = "newuser:newpass@example.com:80"
    @uri.authority.should == "newuser:newpass@example.com:80"
    @uri.user.should == "newuser"
    @uri.password.should == "newpass"
    @uri.userinfo.should == "newuser:newpass"
    @uri.normalized_userinfo.should == "newuser:newpass"
    @uri.host.should == "example.com"
    @uri.port.should == 80
    @uri.inferred_port.should == 80
    @uri.to_s.should ==
      "http://newuser:newpass@example.com:80" +
      "/path/to/resource?query=x#fragment"
  end

  it "should have the correct userinfo segment after assignment" do
    @uri.userinfo = "newuser:newpass"
    @uri.userinfo.should == "newuser:newpass"
    @uri.authority.should == "newuser:newpass@example.com"
    @uri.user.should == "newuser"
    @uri.password.should == "newpass"
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should ==
      "http://newuser:newpass@example.com" +
      "/path/to/resource?query=x#fragment"
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.authority.should == "newuser:pass@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.authority.should == "user:newpass@example.com"
  end

  it "should have the correct host after assignment" do
    @uri.host = "newexample.com"
    @uri.host.should == "newexample.com"
    @uri.authority.should == "user:pass@newexample.com"
  end

  it "should have the correct port after assignment" do
    @uri.port = 8080
    @uri.port.should == 8080
    @uri.authority.should == "user:pass@example.com:8080"
  end

  it "should have the correct path after assignment" do
    @uri.path = "/newpath/to/resource"
    @uri.path.should == "/newpath/to/resource"
    @uri.to_s.should ==
      "http://user:pass@example.com/newpath/to/resource?query=x#fragment"
  end

  it "should have the correct path after nil assignment" do
    @uri.path = nil
    @uri.path.should == ""
    @uri.to_s.should ==
      "http://user:pass@example.com?query=x#fragment"
  end

  it "should have the correct query string after assignment" do
    @uri.query = "newquery=x"
    @uri.query.should == "newquery=x"
    @uri.to_s.should ==
      "http://user:pass@example.com/path/to/resource?newquery=x#fragment"
    @uri.query = nil
    @uri.query.should == nil
    @uri.to_s.should ==
      "http://user:pass@example.com/path/to/resource#fragment"
  end

  it "should have the correct query string after hash assignment" do
    @uri.query_values = {"?uestion mark"=>"=sign", "hello"=>"günther"}
    @uri.query.split("&").should include("%3Fuestion%20mark=%3Dsign")
    @uri.query.split("&").should include("hello=g%C3%BCnther")
    @uri.query_values.should == {"?uestion mark"=>"=sign", "hello"=>"günther"}
  end

  it "should have the correct query string after flag hash assignment" do
    @uri.query_values = {'flag?1' => true, 'fl=ag2' => true, 'flag3' => true}
    @uri.query.split("&").should include("flag%3F1")
    @uri.query.split("&").should include("fl%3Dag2")
    @uri.query.split("&").should include("flag3")
    @uri.query_values.should == {
      'flag?1' => true, 'fl=ag2' => true, 'flag3' => true
    }
  end

  it "should have the correct fragment after assignment" do
    @uri.fragment = "newfragment"
    @uri.fragment.should == "newfragment"
    @uri.to_s.should ==
      "http://user:pass@example.com/path/to/resource?query=x#newfragment"

    @uri.fragment = nil
    @uri.fragment.should == nil
    @uri.to_s.should ==
      "http://user:pass@example.com/path/to/resource?query=x"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:fragment => "newfragment").to_s.should ==
      "http://user:pass@example.com/path/to/resource?query=x#newfragment"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:fragment => nil).to_s.should ==
      "http://user:pass@example.com/path/to/resource?query=x"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:userinfo => "newuser:newpass").to_s.should ==
      "http://newuser:newpass@example.com/path/to/resource?query=x#fragment"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:userinfo => nil).to_s.should ==
      "http://example.com/path/to/resource?query=x#fragment"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:path => "newpath").to_s.should ==
      "http://user:pass@example.com/newpath?query=x#fragment"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:port => "42", :path => "newpath", :query => "").to_s.should ==
      "http://user:pass@example.com:42/newpath?#fragment"
  end

  it "should have the correct values after a merge" do
    @uri.merge(:authority => "foo:bar@baz:42").to_s.should ==
      "http://foo:bar@baz:42/path/to/resource?query=x#fragment"
    @uri.to_s.should ==
      "http://user:pass@example.com/path/to/resource?query=x#fragment"
  end

  it "should have the correct values after a destructive merge" do
    @uri.merge!(:authority => "foo:bar@baz:42")
    @uri.to_s.should ==
      "http://foo:bar@baz:42/path/to/resource?query=x#fragment"
  end

  it "should fail to merge with bogus values" do
    (lambda do
      @uri.merge(:port => "bogus")
    end).should raise_error(Addressable::URI::InvalidURIError)
  end

  it "should fail to merge with bogus parameters" do
    (lambda do
      @uri.merge(42)
    end).should raise_error(TypeError)
  end

  it "should fail to merge with bogus parameters" do
    (lambda do
      @uri.merge("http://example.com/")
    end).should raise_error(TypeError)
  end

  it "should fail to merge with both authority and subcomponents" do
    (lambda do
      @uri.merge(:authority => "foo:bar@baz:42", :port => "42")
    end).should raise_error(ArgumentError)
  end

  it "should fail to merge with both userinfo and subcomponents" do
    (lambda do
      @uri.merge(:userinfo => "foo:bar", :user => "foo")
    end).should raise_error(ArgumentError)
  end

  it "should be identical to its duplicate" do
    @uri.should == @uri.dup
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://user@example.com'" do
  before do
    @uri = Addressable::URI.parse("http://user@example.com")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have a username of 'user'" do
    @uri.user.should == "user"
  end

  it "should have no password" do
    @uri.password.should == nil
  end

  it "should have a userinfo of 'user'" do
    @uri.userinfo.should == "user"
  end

  it "should have a normalized userinfo of 'user'" do
    @uri.normalized_userinfo.should == "user"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password.should == nil
    @uri.to_s.should == "http://newuser@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.to_s.should == "http://user:newpass@example.com"
  end

  it "should have the correct userinfo segment after assignment" do
    @uri.userinfo = "newuser:newpass"
    @uri.userinfo.should == "newuser:newpass"
    @uri.user.should == "newuser"
    @uri.password.should == "newpass"
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://newuser:newpass@example.com"
  end

  it "should have the correct userinfo segment after nil assignment" do
    @uri.userinfo = nil
    @uri.userinfo.should == nil
    @uri.user.should == nil
    @uri.password.should == nil
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://example.com"
  end

  it "should have the correct authority segment after assignment" do
    @uri.authority = "newuser@example.com"
    @uri.authority.should == "newuser@example.com"
    @uri.user.should == "newuser"
    @uri.password.should == nil
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://newuser@example.com"
  end

  it "should raise an error after nil assignment of authority segment" do
    (lambda do
      # This would create an invalid URI
      @uri.authority = nil
    end).should raise_error
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://user:@example.com'" do
  before do
    @uri = Addressable::URI.parse("http://user:@example.com")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have a username of 'user'" do
    @uri.user.should == "user"
  end

  it "should have a password of ''" do
    @uri.password.should == ""
  end

  it "should have a normalized userinfo of 'user:'" do
    @uri.normalized_userinfo.should == "user:"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password.should == ""
    @uri.to_s.should == "http://newuser:@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.to_s.should == "http://user:newpass@example.com"
  end

  it "should have the correct authority segment after assignment" do
    @uri.authority = "newuser:@example.com"
    @uri.authority.should == "newuser:@example.com"
    @uri.user.should == "newuser"
    @uri.password.should == ""
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://newuser:@example.com"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://:pass@example.com'" do
  before do
    @uri = Addressable::URI.parse("http://:pass@example.com")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have a username of ''" do
    @uri.user.should == ""
  end

  it "should have a password of 'pass'" do
    @uri.password.should == "pass"
  end

  it "should have a userinfo of ':pass'" do
    @uri.userinfo.should == ":pass"
  end

  it "should have a normalized userinfo of ':pass'" do
    @uri.normalized_userinfo.should == ":pass"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password.should == "pass"
    @uri.to_s.should == "http://newuser:pass@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.user.should == ""
    @uri.to_s.should == "http://:newpass@example.com"
  end

  it "should have the correct authority segment after assignment" do
    @uri.authority = ":newpass@example.com"
    @uri.authority.should == ":newpass@example.com"
    @uri.user.should == ""
    @uri.password.should == "newpass"
    @uri.host.should == "example.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://:newpass@example.com"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://:@example.com'" do
  before do
    @uri = Addressable::URI.parse("http://:@example.com")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have a username of ''" do
    @uri.user.should == ""
  end

  it "should have a password of ''" do
    @uri.password.should == ""
  end

  it "should have a normalized userinfo of nil" do
    @uri.normalized_userinfo.should == nil
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have the correct username after assignment" do
    @uri.user = "newuser"
    @uri.user.should == "newuser"
    @uri.password.should == ""
    @uri.to_s.should == "http://newuser:@example.com"
  end

  it "should have the correct password after assignment" do
    @uri.password = "newpass"
    @uri.password.should == "newpass"
    @uri.user.should == ""
    @uri.to_s.should == "http://:newpass@example.com"
  end

  it "should have the correct authority segment after assignment" do
    @uri.authority = ":@newexample.com"
    @uri.authority.should == ":@newexample.com"
    @uri.user.should == ""
    @uri.password.should == ""
    @uri.host.should == "newexample.com"
    @uri.port.should == nil
    @uri.inferred_port.should == 80
    @uri.to_s.should == "http://:@newexample.com"
  end
end

describe Addressable::URI, " when parsed from " +
    "'#example'" do
  before do
    @uri = Addressable::URI.parse("#example")
  end

  it "should be considered relative" do
    @uri.should be_relative
  end

  it "should have a host of nil" do
    @uri.host.should == nil
  end

  it "should have a path of ''" do
    @uri.path.should == ""
  end

  it "should have a query string of nil" do
    @uri.query.should == nil
  end

  it "should have a fragment of 'example'" do
    @uri.fragment.should == "example"
  end
end

describe Addressable::URI, " when parsed from " +
    "the network-path reference '//example.com/'" do
  before do
    @uri = Addressable::URI.parse("//example.com/")
  end

  it "should be considered relative" do
    @uri.should be_relative
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should have a path of '/'" do
    @uri.path.should == "/"
  end

  it "should raise an error if routing is attempted" do
    (lambda do
      @uri.route_to("http://example.com/")
    end).should raise_error(ArgumentError, /\/\/example.com\//)
    (lambda do
      @uri.route_from("http://example.com/")
    end).should raise_error(ArgumentError, /\/\/example.com\//)
  end
end

describe Addressable::URI, " when parsed from " +
    "'feed://http://example.com/'" do
  before do
    @uri = Addressable::URI.parse("feed://http://example.com/")
  end

  it "should have a host of 'http'" do
    @uri.host.should == "http"
  end

  it "should have a path of '//example.com/'" do
    @uri.path.should == "//example.com/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'feed:http://example.com/'" do
  before do
    @uri = Addressable::URI.parse("feed:http://example.com/")
  end

  it "should have a path of 'http://example.com/'" do
    @uri.path.should == "http://example.com/"
  end

  it "should normalize to 'http://example.com/'" do
    @uri.normalize.to_s.should == "http://example.com/"
    @uri.normalize!.to_s.should == "http://example.com/"
  end
end

describe Addressable::URI, "when parsed from " +
    "'example://a/b/c/%7Bfoo%7D'" do
  before do
    @uri = Addressable::URI.parse("example://a/b/c/%7Bfoo%7D")
  end

  # Section 6.2.2 of RFC 3986
  it "should be equivalent to eXAMPLE://a/./b/../b/%63/%7bfoo%7d" do
    @uri.should ==
      Addressable::URI.parse("eXAMPLE://a/./b/../b/%63/%7bfoo%7d")
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/indirect/path/./to/../resource/'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/indirect/path/./to/../resource/")
  end

  it "should use the 'http' scheme" do
    @uri.scheme.should == "http"
  end

  it "should have a host of 'example.com'" do
    @uri.host.should == "example.com"
  end

  it "should use port 80" do
    @uri.inferred_port.should == 80
  end

  it "should have a path of '/indirect/path/./to/../resource/'" do
    @uri.path.should == "/indirect/path/./to/../resource/"
  end

  # Section 6.2.2.3 of RFC 3986
  it "should have a normalized path of '/indirect/path/resource/'" do
    @uri.normalize.path.should == "/indirect/path/resource/"
    @uri.normalize!.path.should == "/indirect/path/resource/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://under_score.example.com/'" do
  it "should not cause an error" do
    (lambda do
      Addressable::URI.parse("http://under_score.example.com/")
    end).should_not raise_error
  end
end

describe Addressable::URI, " when parsed from " +
    "'./this:that'" do
  before do
    @uri = Addressable::URI.parse("./this:that")
  end

  it "should be considered relative" do
    @uri.should be_relative
  end

  it "should have no scheme" do
    @uri.scheme.should == nil
  end
end

describe Addressable::URI, "when parsed from " +
    "'this:that'" do
  before do
    @uri = Addressable::URI.parse("this:that")
  end

  it "should be considered absolute" do
    @uri.should be_absolute
  end

  it "should have a scheme of 'this'" do
    @uri.scheme.should == "this"
  end
end

describe Addressable::URI, " when parsed from '?one=1&two=2&three=3'" do
  before do
    @uri = Addressable::URI.parse("?one=1&two=2&three=3")
  end

  it "should have the correct query values" do
    @uri.query_values.should == {"one" => "1", "two" => "2", "three" => "3"}
  end

  it "should raise an error for invalid query value notations" do
    (lambda do
      @uri.query_values(:notation => :bogus)
    end).should raise_error(ArgumentError)
  end
end

describe Addressable::URI, " when parsed from '?one[two][three]=four'" do
  before do
    @uri = Addressable::URI.parse("?one[two][three]=four")
  end

  it "should have the correct query values" do
    @uri.query_values.should == {"one" => {"two" => {"three" => "four"}}}
  end

  it "should have the correct flat notation query values" do
    @uri.query_values(:notation => :flat).should == {
      "one[two][three]" => "four"
    }
  end
end

describe Addressable::URI, " when parsed from '?one.two.three=four'" do
  before do
    @uri = Addressable::URI.parse("?one.two.three=four")
  end

  it "should have the correct dot notation query values" do
    @uri.query_values(:notation => :dot).should == {
      "one" => {"two" => {"three" => "four"}}
    }
  end

  it "should have the correct flat notation query values" do
    @uri.query_values(:notation => :flat).should == {
      "one.two.three" => "four"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'?one[two][three]=four&one[two][five]=six'" do
  before do
    @uri = Addressable::URI.parse("?one[two][three]=four&one[two][five]=six")
  end

  it "should have the correct dot notation query values" do
    @uri.query_values(:notation => :subscript).should == {
      "one" => {"two" => {"three" => "four", "five" => "six"}}
    }
  end

  it "should have the correct flat notation query values" do
    @uri.query_values(:notation => :flat).should == {
      "one[two][three]" => "four",
      "one[two][five]" => "six"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'?one.two.three=four&one.two.five=six'" do
  before do
    @uri = Addressable::URI.parse("?one.two.three=four&one.two.five=six")
  end

  it "should have the correct dot notation query values" do
    @uri.query_values(:notation => :dot).should == {
      "one" => {"two" => {"three" => "four", "five" => "six"}}
    }
  end

  it "should have the correct flat notation query values" do
    @uri.query_values(:notation => :flat).should == {
      "one.two.three" => "four",
      "one.two.five" => "six"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'?one[two][three][]=four&one[two][three][]=five'" do
  before do
    @uri = Addressable::URI.parse(
      "?one[two][three][]=four&one[two][three][]=five"
    )
  end

  it "should have the correct dot notation query values" do
    @uri.query_values(:notation => :subscript).should == {
      "one" => {"two" => {"three" => ["four", "five"]}}
    }
  end

  it "should raise an error if a key is repeated in the flat notation" do
    (lambda do
      @uri.query_values(:notation => :flat)
    end).should raise_error(ArgumentError)
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://www.詹姆斯.com/'" do
  before do
    @uri = Addressable::URI.parse("http://www.詹姆斯.com/")
  end

  it "should be equivalent to 'http://www.xn--8ws00zhy3a.com/'" do
    @uri.should ==
      Addressable::URI.parse("http://www.xn--8ws00zhy3a.com/")
  end

  it "should not have domain name encoded during normalization" do
    Addressable::URI.normalized_encode(@uri.to_s).should ==
      "http://www.詹姆斯.com/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://www.詹姆斯.com/ some spaces /'" do
  before do
    @uri = Addressable::URI.parse("http://www.詹姆斯.com/ some spaces /")
  end

  it "should be equivalent to " +
      "'http://www.xn--8ws00zhy3a.com/%20some%20spaces%20/'" do
    @uri.should ==
      Addressable::URI.parse(
        "http://www.xn--8ws00zhy3a.com/%20some%20spaces%20/")
  end

  it "should not have domain name encoded during normalization" do
    Addressable::URI.normalized_encode(@uri.to_s).should ==
      "http://www.詹姆斯.com/%20some%20spaces%20/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://www.xn--8ws00zhy3a.com/'" do
  before do
    @uri = Addressable::URI.parse("http://www.xn--8ws00zhy3a.com/")
  end

  it "should be displayed as http://www.詹姆斯.com/" do
    @uri.display_uri.to_s.should == "http://www.詹姆斯.com/"
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://www.詹姆斯.com/atomtests/iri/詹.html'" do
  before do
    @uri = Addressable::URI.parse("http://www.詹姆斯.com/atomtests/iri/詹.html")
  end

  it "should normalize to " +
      "http://www.xn--8ws00zhy3a.com/atomtests/iri/%E8%A9%B9.html" do
    @uri.normalize.to_s.should ==
      "http://www.xn--8ws00zhy3a.com/atomtests/iri/%E8%A9%B9.html"
    @uri.normalize!.to_s.should ==
      "http://www.xn--8ws00zhy3a.com/atomtests/iri/%E8%A9%B9.html"
  end
end

describe Addressable::URI, " when parsed from a percent-encoded IRI" do
  before do
    @uri = Addressable::URI.parse(
      "http://www.%E3%81%BB%E3%82%93%E3%81%A8%E3%81%86%E3%81%AB%E3%81%AA" +
      "%E3%81%8C%E3%81%84%E3%82%8F%E3%81%91%E3%81%AE%E3%82%8F%E3%81%8B%E3" +
      "%82%89%E3%81%AA%E3%81%84%E3%81%A9%E3%82%81%E3%81%84%E3%82%93%E3%82" +
      "%81%E3%81%84%E3%81%AE%E3%82%89%E3%81%B9%E3%82%8B%E3%81%BE%E3%81%A0" +
      "%E3%81%AA%E3%81%8C%E3%81%8F%E3%81%97%E3%81%AA%E3%81%84%E3%81%A8%E3" +
      "%81%9F%E3%82%8A%E3%81%AA%E3%81%84.w3.mag.keio.ac.jp"
    )
  end

  it "should normalize to something sane" do
    @uri.normalize.to_s.should ==
      "http://www.xn--n8jaaaaai5bhf7as8fsfk3jnknefdde3f" +
      "g11amb5gzdb4wi9bya3kc6lra.w3.mag.keio.ac.jp/"
    @uri.normalize!.to_s.should ==
      "http://www.xn--n8jaaaaai5bhf7as8fsfk3jnknefdde3f" +
      "g11amb5gzdb4wi9bya3kc6lra.w3.mag.keio.ac.jp/"
  end
end

describe Addressable::URI, "with a base uri of 'http://a/b/c/d;p?q'" do
  before do
    @uri = Addressable::URI.parse("http://a/b/c/d;p?q")
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g:h' should resolve to g:h" do
    (@uri + "g:h").to_s.should == "g:h"
    Addressable::URI.join(@uri, "g:h").to_s.should == "g:h"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g' should resolve to http://a/b/c/g" do
    (@uri + "g").to_s.should == "http://a/b/c/g"
    Addressable::URI.join(@uri.to_s, "g").to_s.should == "http://a/b/c/g"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with './g' should resolve to http://a/b/c/g" do
    (@uri + "./g").to_s.should == "http://a/b/c/g"
    Addressable::URI.join(@uri.to_s, "./g").to_s.should == "http://a/b/c/g"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g/' should resolve to http://a/b/c/g/" do
    (@uri + "g/").to_s.should == "http://a/b/c/g/"
    Addressable::URI.join(@uri.to_s, "g/").to_s.should == "http://a/b/c/g/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '/g' should resolve to http://a/g" do
    (@uri + "/g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "/g").to_s.should == "http://a/g"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '//g' should resolve to http://g" do
    (@uri + "//g").to_s.should == "http://g"
    Addressable::URI.join(@uri.to_s, "//g").to_s.should == "http://g"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '?y' should resolve to http://a/b/c/d;p?y" do
    (@uri + "?y").to_s.should == "http://a/b/c/d;p?y"
    Addressable::URI.join(@uri.to_s, "?y").to_s.should == "http://a/b/c/d;p?y"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g?y' should resolve to http://a/b/c/g?y" do
    (@uri + "g?y").to_s.should == "http://a/b/c/g?y"
    Addressable::URI.join(@uri.to_s, "g?y").to_s.should == "http://a/b/c/g?y"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '#s' should resolve to http://a/b/c/d;p?q#s" do
    (@uri + "#s").to_s.should == "http://a/b/c/d;p?q#s"
    Addressable::URI.join(@uri.to_s, "#s").to_s.should == "http://a/b/c/d;p?q#s"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g#s' should resolve to http://a/b/c/g#s" do
    (@uri + "g#s").to_s.should == "http://a/b/c/g#s"
    Addressable::URI.join(@uri.to_s, "g#s").to_s.should == "http://a/b/c/g#s"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g?y#s' should resolve to http://a/b/c/g?y#s" do
    (@uri + "g?y#s").to_s.should == "http://a/b/c/g?y#s"
    Addressable::URI.join(
      @uri.to_s, "g?y#s").to_s.should == "http://a/b/c/g?y#s"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with ';x' should resolve to http://a/b/c/;x" do
    (@uri + ";x").to_s.should == "http://a/b/c/;x"
    Addressable::URI.join(@uri.to_s, ";x").to_s.should == "http://a/b/c/;x"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g;x' should resolve to http://a/b/c/g;x" do
    (@uri + "g;x").to_s.should == "http://a/b/c/g;x"
    Addressable::URI.join(@uri.to_s, "g;x").to_s.should == "http://a/b/c/g;x"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with 'g;x?y#s' should resolve to http://a/b/c/g;x?y#s" do
    (@uri + "g;x?y#s").to_s.should == "http://a/b/c/g;x?y#s"
    Addressable::URI.join(
      @uri.to_s, "g;x?y#s").to_s.should == "http://a/b/c/g;x?y#s"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '' should resolve to http://a/b/c/d;p?q" do
    (@uri + "").to_s.should == "http://a/b/c/d;p?q"
    Addressable::URI.join(@uri.to_s, "").to_s.should == "http://a/b/c/d;p?q"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '.' should resolve to http://a/b/c/" do
    (@uri + ".").to_s.should == "http://a/b/c/"
    Addressable::URI.join(@uri.to_s, ".").to_s.should == "http://a/b/c/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with './' should resolve to http://a/b/c/" do
    (@uri + "./").to_s.should == "http://a/b/c/"
    Addressable::URI.join(@uri.to_s, "./").to_s.should == "http://a/b/c/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '..' should resolve to http://a/b/" do
    (@uri + "..").to_s.should == "http://a/b/"
    Addressable::URI.join(@uri.to_s, "..").to_s.should == "http://a/b/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '../' should resolve to http://a/b/" do
    (@uri + "../").to_s.should == "http://a/b/"
    Addressable::URI.join(@uri.to_s, "../").to_s.should == "http://a/b/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '../g' should resolve to http://a/b/g" do
    (@uri + "../g").to_s.should == "http://a/b/g"
    Addressable::URI.join(@uri.to_s, "../g").to_s.should == "http://a/b/g"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '../..' should resolve to http://a/" do
    (@uri + "../..").to_s.should == "http://a/"
    Addressable::URI.join(@uri.to_s, "../..").to_s.should == "http://a/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '../../' should resolve to http://a/" do
    (@uri + "../../").to_s.should == "http://a/"
    Addressable::URI.join(@uri.to_s, "../../").to_s.should == "http://a/"
  end

  # Section 5.4.1 of RFC 3986
  it "when joined with '../../g' should resolve to http://a/g" do
    (@uri + "../../g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "../../g").to_s.should == "http://a/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '../../../g' should resolve to http://a/g" do
    (@uri + "../../../g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "../../../g").to_s.should == "http://a/g"
  end

  it "when joined with '../.././../g' should resolve to http://a/g" do
    (@uri + "../.././../g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "../.././../g").to_s.should == "http://a/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '../../../../g' should resolve to http://a/g" do
    (@uri + "../../../../g").to_s.should == "http://a/g"
    Addressable::URI.join(
      @uri.to_s, "../../../../g").to_s.should == "http://a/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '/./g' should resolve to http://a/g" do
    (@uri + "/./g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "/./g").to_s.should == "http://a/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '/../g' should resolve to http://a/g" do
    (@uri + "/../g").to_s.should == "http://a/g"
    Addressable::URI.join(@uri.to_s, "/../g").to_s.should == "http://a/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g.' should resolve to http://a/b/c/g." do
    (@uri + "g.").to_s.should == "http://a/b/c/g."
    Addressable::URI.join(@uri.to_s, "g.").to_s.should == "http://a/b/c/g."
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '.g' should resolve to http://a/b/c/.g" do
    (@uri + ".g").to_s.should == "http://a/b/c/.g"
    Addressable::URI.join(@uri.to_s, ".g").to_s.should == "http://a/b/c/.g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g..' should resolve to http://a/b/c/g.." do
    (@uri + "g..").to_s.should == "http://a/b/c/g.."
    Addressable::URI.join(@uri.to_s, "g..").to_s.should == "http://a/b/c/g.."
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with '..g' should resolve to http://a/b/c/..g" do
    (@uri + "..g").to_s.should == "http://a/b/c/..g"
    Addressable::URI.join(@uri.to_s, "..g").to_s.should == "http://a/b/c/..g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with './../g' should resolve to http://a/b/g" do
    (@uri + "./../g").to_s.should == "http://a/b/g"
    Addressable::URI.join(@uri.to_s, "./../g").to_s.should == "http://a/b/g"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with './g/.' should resolve to http://a/b/c/g/" do
    (@uri + "./g/.").to_s.should == "http://a/b/c/g/"
    Addressable::URI.join(@uri.to_s, "./g/.").to_s.should == "http://a/b/c/g/"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g/./h' should resolve to http://a/b/c/g/h" do
    (@uri + "g/./h").to_s.should == "http://a/b/c/g/h"
    Addressable::URI.join(@uri.to_s, "g/./h").to_s.should == "http://a/b/c/g/h"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g/../h' should resolve to http://a/b/c/h" do
    (@uri + "g/../h").to_s.should == "http://a/b/c/h"
    Addressable::URI.join(@uri.to_s, "g/../h").to_s.should == "http://a/b/c/h"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g;x=1/./y' " +
      "should resolve to http://a/b/c/g;x=1/y" do
    (@uri + "g;x=1/./y").to_s.should == "http://a/b/c/g;x=1/y"
    Addressable::URI.join(
      @uri.to_s, "g;x=1/./y").to_s.should == "http://a/b/c/g;x=1/y"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g;x=1/../y' should resolve to http://a/b/c/y" do
    (@uri + "g;x=1/../y").to_s.should == "http://a/b/c/y"
    Addressable::URI.join(
      @uri.to_s, "g;x=1/../y").to_s.should == "http://a/b/c/y"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g?y/./x' " +
      "should resolve to http://a/b/c/g?y/./x" do
    (@uri + "g?y/./x").to_s.should == "http://a/b/c/g?y/./x"
    Addressable::URI.join(
      @uri.to_s, "g?y/./x").to_s.should == "http://a/b/c/g?y/./x"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g?y/../x' " +
      "should resolve to http://a/b/c/g?y/../x" do
    (@uri + "g?y/../x").to_s.should == "http://a/b/c/g?y/../x"
    Addressable::URI.join(
      @uri.to_s, "g?y/../x").to_s.should == "http://a/b/c/g?y/../x"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g#s/./x' " +
      "should resolve to http://a/b/c/g#s/./x" do
    (@uri + "g#s/./x").to_s.should == "http://a/b/c/g#s/./x"
    Addressable::URI.join(
      @uri.to_s, "g#s/./x").to_s.should == "http://a/b/c/g#s/./x"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'g#s/../x' " +
      "should resolve to http://a/b/c/g#s/../x" do
    (@uri + "g#s/../x").to_s.should == "http://a/b/c/g#s/../x"
    Addressable::URI.join(
      @uri.to_s, "g#s/../x").to_s.should == "http://a/b/c/g#s/../x"
  end

  # Section 5.4.2 of RFC 3986
  it "when joined with 'http:g' should resolve to http:g" do
    (@uri + "http:g").to_s.should == "http:g"
    Addressable::URI.join(@uri.to_s, "http:g").to_s.should == "http:g"
  end

  # Edge case to be sure
  it "when joined with '//example.com/' should " +
      "resolve to http://example.com/" do
    (@uri + "//example.com/").to_s.should == "http://example.com/"
    Addressable::URI.join(
      @uri.to_s, "//example.com/").to_s.should == "http://example.com/"
  end

  it "when joined with a bogus object a TypeError should be raised" do
    (lambda do
      Addressable::URI.join(@uri, 42)
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, "when extracting from an arbitrary text" do
  before do
    @text = File.open(File.expand_path(
      File.dirname(__FILE__) + "/../data/rfc3986.txt")) { |file| file.read }
  end

  it "should have all obvious URIs extractable from it" do
    @uris = Addressable::URI.extract(@text)
    @uris.should include("http://www.w3.org/People/Berners-Lee/")
    @uris.should include("http://roy.gbiv.com/")
    @uris.should include("http://larry.masinter.net/")
    @uris = Addressable::URI.extract(@text,
      :base => "http://example.com/", :parse => true)
    @uris.should include(
      Addressable::URI.parse("http://www.w3.org/People/Berners-Lee/"))
    @uris.should include(
      Addressable::URI.parse("http://roy.gbiv.com/"))
    @uris.should include(
      Addressable::URI.parse("http://larry.masinter.net/"))
  end
end

describe Addressable::URI, "when extracting from an arbitrary text " +
    "containing invalid URIs" do
  before do
    @text = <<-TEXT
      This is an invalid URI:
        http://example.com:bogus/path/to/something/
      This is a valid URI:
        http://example.com:80/path/to/something/
    TEXT
  end

  it "should ignore invalid URIs when extracting" do
    @uris = Addressable::URI.extract(@text)
    @uris.should include("http://example.com:80/path/to/something/")
    @uris.should_not include("http://example.com:bogus/path/to/something/")
    @uris.size.should == 1
  end
end

describe Addressable::URI, "when converting the path " +
    "'relative/path/to/something'" do
  before do
    @path = 'relative/path/to/something'
  end

  it "should convert to " +
      "\'relative/path/to/something\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "relative/path/to/something"
  end

  it "should join with an absolute file path correctly" do
    @base = Addressable::URI.convert_path("/absolute/path/")
    @uri = Addressable::URI.convert_path(@path)
    (@base + @uri).to_s.should ==
      "file:///absolute/path/relative/path/to/something"
  end
end

describe Addressable::URI, "when converting a bogus path" do
  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.convert_path(42)
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, "when given the root directory" do
  before do
    if RUBY_PLATFORM =~ /mswin/
      @path = "C:\\"
    else
      @path = "/"
    end
  end

  if RUBY_PLATFORM =~ /mswin/
    it "should convert to \'file:///c:/\'" do
      @uri = Addressable::URI.convert_path(@path)
      @uri.to_s.should == "file:///c:/"
    end
  else
    it "should convert to \'file:///\'" do
      @uri = Addressable::URI.convert_path(@path)
      @uri.to_s.should == "file:///"
    end
  end
end

describe Addressable::URI, "when given the path '/home/user/'" do
  before do
    @path = '/home/user/'
  end

  it "should convert to " +
      "\'file:///home/user/\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///home/user/"
  end
end

describe Addressable::URI, " when given the path " +
    "'c:\\windows\\My Documents 100%20\\foo.txt'" do
  before do
    @path = "c:\\windows\\My Documents 100%20\\foo.txt"
  end

  it "should convert to " +
      "\'file:///c:/windows/My%20Documents%20100%20/foo.txt\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///c:/windows/My%20Documents%20100%20/foo.txt"
  end
end

describe Addressable::URI, " when given the path " +
    "'file://c:\\windows\\My Documents 100%20\\foo.txt'" do
  before do
    @path = "file://c:\\windows\\My Documents 100%20\\foo.txt"
  end

  it "should convert to " +
      "\'file:///c:/windows/My%20Documents%20100%20/foo.txt\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///c:/windows/My%20Documents%20100%20/foo.txt"
  end
end

describe Addressable::URI, " when given the path " +
    "'file:c:\\windows\\My Documents 100%20\\foo.txt'" do
  before do
    @path = "file:c:\\windows\\My Documents 100%20\\foo.txt"
  end

  it "should convert to " +
      "\'file:///c:/windows/My%20Documents%20100%20/foo.txt\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///c:/windows/My%20Documents%20100%20/foo.txt"
  end
end

describe Addressable::URI, " when given the path " +
    "'file:/c:\\windows\\My Documents 100%20\\foo.txt'" do
  before do
    @path = "file:/c:\\windows\\My Documents 100%20\\foo.txt"
  end

  it "should convert to " +
      "\'file:///c:/windows/My%20Documents%20100%20/foo.txt\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///c:/windows/My%20Documents%20100%20/foo.txt"
  end
end

describe Addressable::URI, " when given the path " +
    "'file:///c|/windows/My%20Documents%20100%20/foo.txt'" do
  before do
    @path = "file:///c|/windows/My%20Documents%20100%20/foo.txt"
  end

  it "should convert to " +
      "\'file:///c:/windows/My%20Documents%20100%20/foo.txt\'" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "file:///c:/windows/My%20Documents%20100%20/foo.txt"
  end
end

describe Addressable::URI, "when given an http protocol URI" do
  before do
    @path = "http://example.com/"
  end

  it "should not do any conversion at all" do
    @uri = Addressable::URI.convert_path(@path)
    @uri.to_s.should == "http://example.com/"
  end
end

describe Addressable::URI, " when given the template pattern " +
    "'http://example.com/search/{query}/' " +
    "to be processed with the ExampleProcessor" do
  before do
    @pattern = "http://example.com/search/{query}/"
  end

  it "should expand to " +
      "'http://example.com/search/an+example+search+query/' " +
      "with a mapping of {\"query\" => \"an example search query\"} " do
    Addressable::URI.expand_template(
      "http://example.com/search/{query}/",
      {"query" => "an example search query"},
      ExampleProcessor).to_s.should ==
        "http://example.com/search/an+example+search+query/"
  end

  it "should raise an error " +
      "with a mapping of {\"query\" => \"invalid!\"}" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/search/{query}/",
        {"query" => "invalid!"},
        ExampleProcessor).to_s
    end).should raise_error
  end
end

# Section 3.3.1 of the URI Template draft v 01
describe Addressable::URI, " when given the mapping supplied in " +
    "Section 3.3.1 of the URI Template draft v 01" do
  before do
    @mapping = {
      "a" => "fred",
      "b" => "barney",
      "c" => "cheeseburger",
      "d" => "one two three",
      "e" => "20% tricky",
      "f" => "",
      "20" => "this-is-spinal-tap",
      "scheme" => "https",
      "p" => "quote=to+be+or+not+to+be",
      "q" => "hullo#world"
    }
  end

  it "should result in 'http://example.org/page1#fred' " +
      "when used to expand 'http://example.org/page1\#{a}'" do
    Addressable::URI.expand_template(
      "http://example.org/page1\#{a}",
      @mapping
    ).to_s.should == "http://example.org/page1#fred"
  end

  it "should result in 'http://example.org/fred/barney/' " +
      "when used to expand 'http://example.org/{a}/{b}/'" do
    Addressable::URI.expand_template(
      "http://example.org/{a}/{b}/",
      @mapping
    ).to_s.should == "http://example.org/fred/barney/"
  end

  it "should result in 'http://example.org/fredbarney/' " +
      "when used to expand 'http://example.org/{a}{b}/'" do
    Addressable::URI.expand_template(
      "http://example.org/{a}{b}/",
      @mapping
    ).to_s.should == "http://example.org/fredbarney/"
  end

  it "should result in " +
      "'http://example.com/order/cheeseburger/cheeseburger/cheeseburger/' " +
      "when used to expand 'http://example.com/order/{c}/{c}/{c}/'" do
    Addressable::URI.expand_template(
      "http://example.com/order/{c}/{c}/{c}/",
      @mapping
    ).to_s.should ==
        "http://example.com/order/cheeseburger/cheeseburger/cheeseburger/"
  end

  it "should result in 'http://example.org/one%20two%20three' " +
      "when used to expand 'http://example.org/{d}'" do
    Addressable::URI.expand_template(
      "http://example.org/{d}",
      @mapping
    ).to_s.should == "http://example.org/one%20two%20three"
  end

  it "should result in 'http://example.org/20%25%20tricky' " +
      "when used to expand 'http://example.org/{e}'" do
    Addressable::URI.expand_template(
      "http://example.org/{e}",
      @mapping
    ).to_s.should == "http://example.org/20%25%20tricky"
  end

  it "should result in 'http://example.com//' " +
      "when used to expand 'http://example.com/{f}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{f}/",
      @mapping
    ).to_s.should == "http://example.com//"
  end

  it "should result in " +
      "'https://this-is-spinal-tap.example.org?date=&option=fred' " +
      "when used to expand " +
      "'{scheme}://{20}.example.org?date={wilma}&option={a}'" do
    Addressable::URI.expand_template(
      "{scheme}://{20}.example.org?date={wilma}&option={a}",
      @mapping
    ).to_s.should ==
        "https://this-is-spinal-tap.example.org?date=&option=fred"
  end

  # The v 01 draft conflicts with the v 03 draft here.
  # The Addressable implementation uses v 03.
  it "should result in " +
      "'http://example.org?quote%3Dto%2Bbe%2Bor%2Bnot%2Bto%2Bbe' " +
      "when used to expand 'http://example.org?{p}'" do
    Addressable::URI.expand_template(
      "http://example.org?{p}",
      @mapping
    ).to_s.should == "http://example.org?quote%3Dto%2Bbe%2Bor%2Bnot%2Bto%2Bbe"
  end

  # The v 01 draft conflicts with the v 03 draft here.
  # The Addressable implementation uses v 03.
  it "should result in 'http://example.com/hullo%23world' " +
      "when used to expand 'http://example.com/{q}'" do
    Addressable::URI.expand_template(
      "http://example.com/{q}",
      @mapping
    ).to_s.should == "http://example.com/hullo%23world"
  end
end

# Section 4.5 of the URI Template draft v 03
describe Addressable::URI, " when given the mapping supplied in " +
    "Section 4.5 of the URI Template draft v 03" do
  before do
    @mapping = {
      "foo" => "ϓ",
      "bar" => "fred",
      "baz" => "10,20,30",
      "qux" => ["10","20","30"],
      "corge" => [],
      "grault" => "",
      "garply" => "a/b/c",
      "waldo" => "ben & jerrys",
      "fred" => ["fred", "", "wilma"],
      "plugh" => ["ẛ", "ṡ"],
      "1-a_b.c" => "200"
    }
  end

  it "should result in 'http://example.org/?q=fred' " +
      "when used to expand 'http://example.org/?q={bar}'" do
    Addressable::URI.expand_template(
      "http://example.org/?q={bar}",
      @mapping
    ).to_s.should == "http://example.org/?q=fred"
  end

  it "should result in '/' " +
      "when used to expand '/{xyzzy}'" do
    Addressable::URI.expand_template(
      "/{xyzzy}",
      @mapping
    ).to_s.should == "/"
  end

  it "should result in " +
      "'http://example.org/?foo=%CE%8E&bar=fred&baz=10%2C20%2C30' " +
      "when used to expand " +
      "'http://example.org/?{-join|&|foo,bar,xyzzy,baz}'" do
    Addressable::URI.expand_template(
      "http://example.org/?{-join|&|foo,bar,xyzzy,baz}",
      @mapping
    ).to_s.should ==
      "http://example.org/?foo=%CE%8E&bar=fred&baz=10%2C20%2C30"
  end

  it "should result in 'http://example.org/?d=10,20,30' " +
      "when used to expand 'http://example.org/?d={-list|,|qux}'" do
    Addressable::URI.expand_template(
      "http://example.org/?d={-list|,|qux}",
      @mapping
    ).to_s.should == "http://example.org/?d=10,20,30"
  end

  it "should result in 'http://example.org/?d=10&d=20&d=30' " +
      "when used to expand 'http://example.org/?d={-list|&d=|qux}'" do
    Addressable::URI.expand_template(
      "http://example.org/?d={-list|&d=|qux}",
      @mapping
    ).to_s.should == "http://example.org/?d=10&d=20&d=30"
  end

  it "should result in 'http://example.org/fredfred/a%2Fb%2Fc' " +
      "when used to expand 'http://example.org/{bar}{bar}/{garply}'" do
    Addressable::URI.expand_template(
      "http://example.org/{bar}{bar}/{garply}",
      @mapping
    ).to_s.should == "http://example.org/fredfred/a%2Fb%2Fc"
  end

  it "should result in 'http://example.org/fred/fred//wilma' " +
      "when used to expand 'http://example.org/{bar}{-prefix|/|fred}'" do
    Addressable::URI.expand_template(
      "http://example.org/{bar}{-prefix|/|fred}",
      @mapping
    ).to_s.should == "http://example.org/fred/fred//wilma"
  end

  it "should result in ':%E1%B9%A1:%E1%B9%A1:' " +
      "when used to expand '{-neg|:|corge}{-suffix|:|plugh}'" do
    Addressable::URI.expand_template(
      "{-neg|:|corge}{-suffix|:|plugh}",
      @mapping
    ).to_s.should == ":%E1%B9%A1:%E1%B9%A1:"
  end

  it "should result in '../ben%20%26%20jerrys/' " +
      "when used to expand '../{waldo}/'" do
    Addressable::URI.expand_template(
      "../{waldo}/",
      @mapping
    ).to_s.should == "../ben%20%26%20jerrys/"
  end

  it "should result in 'telnet:192.0.2.16:80' " +
      "when used to expand 'telnet:192.0.2.16{-opt|:80|grault}'" do
    Addressable::URI.expand_template(
      "telnet:192.0.2.16{-opt|:80|grault}",
      @mapping
    ).to_s.should == "telnet:192.0.2.16:80"
  end

  it "should result in ':200:' " +
      "when used to expand ':{1-a_b.c}:'" do
    Addressable::URI.expand_template(
      ":{1-a_b.c}:",
      @mapping
    ).to_s.should == ":200:"
  end
end

describe Addressable::URI, "when given a mapping that contains a " +
  "template-var within a value" do
  before do
    @mapping = {
      "a" => "{b}",
      "b" => "barney",
    }
  end

  it "should result in 'http://example.com/%7Bb%7D/barney/' " +
      "when used to expand 'http://example.com/{a}/{b}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{a}/{b}/",
      @mapping).to_s.should == "http://example.com/%7Bb%7D/barney/"
  end

  it "should result in 'http://example.com//%7Bb%7D/' " +
      "when used to expand 'http://example.com/{-opt|foo|foo}/{a}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{-opt|foo|foo}/{a}/",
      @mapping).to_s.should == "http://example.com//%7Bb%7D/"
  end

  it "should result in 'http://example.com//%7Bb%7D/' " +
      "when used to expand 'http://example.com/{-neg|foo|b}/{a}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{-neg|foo|b}/{a}/",
      @mapping).to_s.should == "http://example.com//%7Bb%7D/"
  end

  it "should result in 'http://example.com//barney/%7Bb%7D/' " +
      "when used to expand 'http://example.com/{-prefix|/|b}/{a}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{-prefix|/|b}/{a}/",
      @mapping).to_s.should == "http://example.com//barney/%7Bb%7D/"
  end

  it "should result in 'http://example.com/barney//%7Bb%7D/' " +
      "when used to expand 'http://example.com/{-suffix|/|b}/{a}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{-suffix|/|b}/{a}/",
      @mapping).to_s.should == "http://example.com/barney//%7Bb%7D/"
  end

  it "should result in 'http://example.com/%7Bb%7D/?b=barney&c=42' " +
      "when used to expand 'http://example.com/{a}/?{-join|&|b,c=42}'" do
    Addressable::URI.expand_template(
      "http://example.com/{a}/?{-join|&|b,c=42}",
      @mapping).to_s.should == "http://example.com/%7Bb%7D/?b=barney&c=42"
  end

  it "should result in 'http://example.com/42/?b=barney' " +
      "when used to expand 'http://example.com/{c=42}/?{-join|&|b}'" do
    Addressable::URI.expand_template(
      "http://example.com/{c=42}/?{-join|&|b}",
      @mapping).to_s.should == "http://example.com/42/?b=barney"
  end
end

describe Addressable::URI, "when given a single variable mapping" do
  before do
    @mapping = {
      "foo" => "fred"
    }
  end

  it "should result in 'fred' when used to expand '{foo}'" do
    Addressable::URI.expand_template(
      "{foo}",
      @mapping
    ).to_s.should == "fred"
  end

  it "should result in 'wilma' when used to expand '{bar=wilma}'" do
    Addressable::URI.expand_template(
      "{bar=wilma}",
      @mapping
    ).to_s.should == "wilma"
  end

  it "should result in '' when used to expand '{baz}'" do
    Addressable::URI.expand_template(
      "{baz}",
      @mapping
    ).to_s.should == ""
  end
end

describe Addressable::URI, "when given a simple mapping" do
  before do
    @mapping = {
      "foo" => "fred",
      "bar" => "barney",
      "baz" => ""
    }
  end

  it "should result in 'foo=fred&bar=barney&baz=' when used to expand " +
      "'{-join|&|foo,bar,baz,qux}'" do
    Addressable::URI.expand_template(
      "{-join|&|foo,bar,baz,qux}",
      @mapping
    ).to_s.should == "foo=fred&bar=barney&baz="
  end

  it "should result in 'bar=barney' when used to expand " +
      "'{-join|&|bar}'" do
    Addressable::URI.expand_template(
      "{-join|&|bar}",
      @mapping
    ).to_s.should == "bar=barney"
  end

  it "should result in '' when used to expand " +
      "'{-join|&|qux}'" do
    Addressable::URI.expand_template(
      "{-join|&|qux}",
      @mapping
    ).to_s.should == ""
  end
end

describe Addressable::URI, "when given a mapping containing values " +
    "that are already percent-encoded" do
  before do
    @mapping = {
      "a" => "%7Bb%7D"
    }
  end

  it "should result in 'http://example.com/%257Bb%257D/' " +
      "when used to expand 'http://example.com/{a}/'" do
    Addressable::URI.expand_template(
      "http://example.com/{a}/",
      @mapping).to_s.should == "http://example.com/%257Bb%257D/"
  end
end

describe Addressable::URI, "when given a mapping containing bogus values" do
  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{bogus}/", {
          "bogus" => 42
        }
      )
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, "when given a pattern with bogus operators" do
  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{-bogus|/|a,b,c}/", {
          "a" => "a", "b" => "b", "c" => "c"
        }
      )
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{-prefix|/|a,b,c}/", {
          "a" => "a", "b" => "b", "c" => "c"
        }
      )
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{-suffix|/|a,b,c}/", {
          "a" => "a", "b" => "b", "c" => "c"
        }
      )
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{-join|/|a,b,c}/", {
          "a" => ["a"], "b" => ["b"], "c" => "c"
        }
      )
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      Addressable::URI.expand_template(
        "http://example.com/{-list|/|a,b,c}/", {
          "a" => ["a"], "b" => ["b"], "c" => "c"
        }
      )
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end
end

describe Addressable::URI, "when given a mapping that contains an Array" do
  before do
    @mapping = {"query" => "an example search query".split(" ")}
  end

  it "should result in 'http://example.com/search/an+example+search+query/'" +
      " when used to expand 'http://example.com/search/{-list|+|query}/'" do
    Addressable::URI.expand_template(
      "http://example.com/search/{-list|+|query}/",
      @mapping).to_s.should ==
        "http://example.com/search/an+example+search+query/"
  end

  it "should result in 'http://example.com/search/an+example+search+query/'" +
      " when used to expand 'http://example.com/search/{-list|+|query}/'" +
      " with a NoOpProcessor" do
    Addressable::URI.expand_template(
      "http://example.com/search/{-list|+|query}/",
      @mapping, NoOpProcessor).to_s.should ==
        "http://example.com/search/an+example+search+query/"
  end
end

class SuperString
  def initialize(string)
    @string = string.to_s
  end

  def to_str
    return @string
  end
end

describe Addressable::URI, " when parsing a non-String object" do
  it "should correctly parse anything with a 'to_str' method" do
    Addressable::URI.parse(SuperString.new(42))
  end

  it "should raise a TypeError for objects than cannot be converted" do
    (lambda do
      Addressable::URI.parse(42)
    end).should raise_error(TypeError)
  end

  it "should correctly parse heuristically anything with a 'to_str' method" do
    Addressable::URI.heuristic_parse(SuperString.new(42))
  end

  it "should raise a TypeError for objects than cannot be converted" do
    (lambda do
      Addressable::URI.heuristic_parse(42)
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, "when encoding a multibyte string" do
  it "should result in correct percent encoded sequence" do
    Addressable::URI.encode_component("günther").should == "g%C3%BCnther"
  end

  it "should result in correct percent encoded sequence" do
    Addressable::URI.encode_component(
      "günther", /[^a-zA-Z0-9\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\-\.\_\~]/
    ).should == "g%C3%BCnther"
  end
end

describe Addressable::URI, "when encoding a string with ASCII chars 0-15" do
  it "should result in correct percent encoded sequence" do
    Addressable::URI.encode_component("one\ntwo").should == "one%0Atwo"
  end

  it "should result in correct percent encoded sequence" do
    Addressable::URI.encode_component(
      "one\ntwo", /[^a-zA-Z0-9\:\/\?\#\[\]\@\!\$\&\'\(\)\*\+\,\;\=\-\.\_\~]/
    ).should == "one%0Atwo"
  end
end

describe Addressable::URI, "when unencoding a multibyte string" do
  it "should result in correct percent encoded sequence" do
    Addressable::URI.unencode_component("g%C3%BCnther").should == "günther"
  end

  it "should result in correct percent encoded sequence as a URI" do
    Addressable::URI.unencode(
      "/path?g%C3%BCnther", ::Addressable::URI
    ).should == Addressable::URI.new(
      :path => "/path", :query => "günther"
    )
  end
end

describe Addressable::URI, "when unencoding a bogus object" do
  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.unencode_component(42)
    end).should raise_error(TypeError)
  end

  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.unencode("/path?g%C3%BCnther", Integer)
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, "when encoding a bogus object" do
  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.encode(42)
    end).should raise_error(TypeError)
  end

  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.normalized_encode(42)
    end).should raise_error(TypeError)
  end

  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.encode_component("günther", 42)
    end).should raise_error(TypeError)
  end

  it "should raise a TypeError" do
    (lambda do
      Addressable::URI.encode_component(42)
    end).should raise_error(TypeError)
  end
end

describe Addressable::URI, " when parsed from " +
    "'/'" do
  before do
    @uri = Addressable::URI.parse("/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/'" do
    @uri.extract_mapping("/").should == {}
  end
end

describe Addressable::URI, " when parsed from '/one/'" do
  before do
    @uri = Addressable::URI.parse("/one/")
  end

  it "should not match the pattern '/two/'" do
    @uri.extract_mapping("/two/").should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{number}/'" do
    @uri.extract_mapping("/{number}/").should == {"number" => "one"}
  end
end

describe Addressable::URI, " when parsed from '/one/two/'" do
  before do
    @uri = Addressable::URI.parse("/one/two/")
  end

  it "should not match the pattern '/{number}/' " +
      "with the SlashlessProcessor" do
    @uri.extract_mapping("/{number}/", SlashlessProcessor).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{number}/' without a processor" do
    @uri.extract_mapping("/{number}/").should == {
      "number" => "one/two"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{first}/{second}/' with the SlashlessProcessor" do
    @uri.extract_mapping("/{first}/{second}/", SlashlessProcessor).should == {
      "first" => "one",
      "second" => "two"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/search/an+example+search+query/'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/search/an+example+search+query/")
  end

  it "should have the correct mapping when extracting values using " +
      "the pattern 'http://example.com/search/{query}/' with the " +
      "ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/search/{query}/", ExampleProcessor
    ).should == {
      "query" => "an example search query"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/search/{-list|+|query}/'" do
    @uri.extract_mapping(
      "http://example.com/search/{-list|+|query}/"
    ).should == {
      "query" => ["an", "example", "search", "query"]
    }
  end

  it "should return nil when extracting values using " +
      "a non-matching pattern" do
    @uri.extract_mapping(
      "http://bogus.com/{thingy}/"
    ).should == nil
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/a/b/c/'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/a/b/c/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{second}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{first}/{second}/", ExampleProcessor
    ).should == {
      "first" => "a",
      "second" => "b/c"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{-list|/|second}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/{-list|/|second}/"
    ).should == {
      "first" => "a",
      "second" => ["b", "c"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{-list|/|rot13}/' " +
      "with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{first}/{-list|/|rot13}/",
      ExampleProcessor
    ).should == {
      "first" => "a",
      "rot13" => ["o", "p"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-list|/|rot13}/' " +
      "with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-list|/|rot13}/",
      ExampleProcessor
    ).should == {
      "rot13" => ["n", "o", "p"]
    }
  end

  it "should not map to anything when extracting values " +
      "using the pattern " +
      "'http://example.com/{-list|/|rot13}/'" do
    @uri.extract_mapping("http://example.com/{-join|/|a,b,c}/").should == nil
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?a=one&b=two&c=three'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?a=one&b=two&c=three")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/?{-join|&|a,b,c}'" do
    @uri.extract_mapping(
      "http://example.com/?{-join|&|a,b,c}"
    ).should == {
      "a" => "one",
      "b" => "two",
      "c" => "three"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?rot13=frperg'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?rot13=frperg")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/?{-join|&|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/?{-join|&|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => "secret"
    }
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/one/spacer/two/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/one/spacer/two/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer/{second}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer/{second}/"
    ).should == {
      "first" => "one",
      "second" => "two"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|stuff}/"
    ).should == {
      "stuff" => ["one", "spacer", "two"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/o{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/o{-prefix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer{-prefix|/|stuff}/"
    ).should == {
      "first" => "one",
      "stuff" => ["two"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{-prefix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|rot13}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|rot13}/",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb", ""]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-prefix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-prefix|/|rot13}",
      ExampleProcessor
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}"
    ).should == {
      "stuff" => ["one", "spacer", "two"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|stuff}o'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}o"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/o{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/o{-suffix|/|stuff}"
    ).should == {"stuff"=>["ne", "spacer", "two"]}
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer/{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer/{-suffix|/|stuff}"
    ).should == {
      "first" => "one",
      "stuff" => ["two"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-suffix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-suffix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-suffix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["", "bar", "fcnpre", "gjb"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-suffix|/|rot13}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|rot13}/",
      ExampleProcessor
    ).should == nil
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?email=bob@sporkmonger.com'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/?email=bob@sporkmonger.com"
    )
  end

  it "should not match anything when extracting values " +
      "using the incorrect opt pattern " +
      "'http://example.com/?email={-opt|bogus@bogus.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bogus@bogus.com|test}"
    ).should == nil
  end

  it "should not match anything when extracting values " +
      "using the incorrect neg pattern " +
      "'http://example.com/?email={-neg|bogus@bogus.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bogus@bogus.com|test}"
    ).should == nil
  end

  it "should indicate a match when extracting values " +
      "using the opt pattern " +
      "'http://example.com/?email={-opt|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bob@sporkmonger.com|test}"
    ).should == {}
  end

  it "should indicate a match when extracting values " +
      "using the neg pattern " +
      "'http://example.com/?email={-neg|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bob@sporkmonger.com|test}"
    ).should == {}
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/?email='" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/?email="
    )
  end

  it "should indicate a match when extracting values " +
      "using the opt pattern " +
      "'http://example.com/?email={-opt|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bob@sporkmonger.com|test}"
    ).should == {}
  end

  it "should indicate a match when extracting values " +
      "using the neg pattern " +
      "'http://example.com/?email={-neg|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bob@sporkmonger.com|test}"
    ).should == {}
  end
end

describe Addressable::URI, " when parsed from " +
    "'http://example.com/a/b/c/?one=1&two=2#foo'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/a/b/c/?one=1&two=2#foo"
    )
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|one,two}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,two}\#{fragment}"
    ).should == {
      "host" => "example.com",
      "segments" => ["a", "b", "c"],
      "one" => "1",
      "two" => "2",
      "fragment" => "foo"
    }
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|one}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|bogus}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?" +
      "{-join|&|one,bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,bogus}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?" +
      "{-join|&|one,two,bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,two,bogus}\#{fragment}"
    ).should == {
      "host" => "example.com",
      "segments" => ["a", "b", "c"],
      "one" => "1",
      "two" => "2",
      "fragment" => "foo"
    }
  end
end

describe Addressable::URI, "when given a pattern with bogus operators" do
  before do
    @uri = Addressable::URI.parse("http://example.com/a/b/c/")
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-bogus|/|a,b,c}/")
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-prefix|/|a,b,c}/")
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-suffix|/|a,b,c}/")
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-list|/|a,b,c}/")
    end).should raise_error(Addressable::URI::InvalidTemplateOperatorError)
  end
end

describe Addressable::URI, " when given the input " +
    "'/path/to/resource'" do
  before do
    @input = "/path/to/resource"
  end

  it "should heuristically parse to '/path/to/resource'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "/path/to/resource"
  end
end

describe Addressable::URI, " when given the input " +
    "'relative/path/to/resource'" do
  before do
    @input = "relative/path/to/resource"
  end

  it "should heuristically parse to 'relative/path/to/resource'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "relative/path/to/resource"
  end
end

describe Addressable::URI, " when given the input " +
    "'example.com'" do
  before do
    @input = "example.com"
  end

  it "should heuristically parse to 'http://example.com'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "http://example.com"
  end
end

describe Addressable::URI, " when given the input " +
    "'example.com' and a scheme hint of 'ftp'" do
  before do
    @input = "example.com"
    @hints = {:scheme => 'ftp'}
  end

  it "should heuristically parse to 'http://example.com'" do
    @uri = Addressable::URI.heuristic_parse(@input, @hints)
    @uri.to_s.should == "ftp://example.com"
  end
end

describe Addressable::URI, " when given the input " +
    "'example.com:21' and a scheme hint of 'ftp'" do
  before do
    @input = "example.com:21"
    @hints = {:scheme => 'ftp'}
  end

  it "should heuristically parse to 'http://example.com:21'" do
    @uri = Addressable::URI.heuristic_parse(@input, @hints)
    @uri.to_s.should == "ftp://example.com:21"
  end
end

describe Addressable::URI, " when given the input " +
    "'example.com/path/to/resource'" do
  before do
    @input = "example.com/path/to/resource"
  end

  it "should heuristically parse to 'http://example.com/path/to/resource'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "http://example.com/path/to/resource"
  end
end

describe Addressable::URI, " when given the input " +
    "'http:///example.com'" do
  before do
    @input = "http:///example.com"
  end

  it "should heuristically parse to 'http://example.com'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "http://example.com"
  end
end

describe Addressable::URI, " when given the input " +
    "'feed:///example.com'" do
  before do
    @input = "feed:///example.com"
  end

  it "should heuristically parse to 'feed://example.com'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "feed://example.com"
  end
end

describe Addressable::URI, " when given the input " +
    "'file://path/to/resource/'" do
  before do
    @input = "file://path/to/resource/"
  end

  it "should heuristically parse to 'file:///path/to/resource/'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "file:///path/to/resource/"
  end
end

describe Addressable::URI, " when given the input " +
    "'feed://http://example.com'" do
  before do
    @input = "feed://http://example.com"
  end

  it "should heuristically parse to 'feed:http://example.com'" do
    @uri = Addressable::URI.heuristic_parse(@input)
    @uri.to_s.should == "feed:http://example.com"
  end
end
