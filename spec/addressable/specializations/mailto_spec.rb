# coding: utf-8
# Copyright (C) 2006-2011 Bob Aman
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


require "addressable/uri"

describe Addressable::URI, "when parsed from " +
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

# Section 2 of RFC 6068
describe Addressable::URI, "when parsed from " +
    "'mailto:?to=addr1@an.example,addr2@an.example'" do
  before do
    @uri = Addressable::URI.parse(
      "mailto:?to=addr1@an.example,addr2@an.example"
    )
  end

  it "should use the 'mailto' scheme" do
    @uri.scheme.should == "mailto"
  end

  it "should not be considered to be ip-based" do
    @uri.should_not be_ip_based
  end

  it "should not have an inferred_port" do
    @uri.inferred_port.should == nil
  end

  it "should have a path of ''" do
    @uri.path.should == ""
  end

  it "should not have a request URI" do
    @uri.request_uri.should == nil
  end

  it "should have the To: field value parameterized" do
    @uri.query_values(Hash)["to"].should == (
      "addr1@an.example,addr2@an.example"
    )
  end

  it "should not be considered to be in normal form" do
    @uri.normalize.should_not be_eql(@uri)
  end

  it "should have a 'null' origin" do
    @uri.origin.should == 'null'
  end
end
