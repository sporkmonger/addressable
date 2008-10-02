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

require 'addressable/idna'

describe Addressable::IDNA, "when converting from unicode to ASCII" do
  it "should convert 'www.詹姆斯.com' correctly" do
    Addressable::IDNA.to_ascii(
      "www.詹姆斯.com"
    ).should == "www.xn--8ws00zhy3a.com"
  end

  it "should convert 'www.Iñtërnâtiônàlizætiøn.com' correctly" do
    Addressable::IDNA.to_ascii(
      "www.I\303\261t\303\253rn\303\242ti\303\264" +
      "n\303\240liz\303\246ti\303\270n.com"
    ).should == "www.xn--itrntinliztin-vdb0a5exd8ewcye.com"
  end

  it "should convert 'www.Iñtërnâtiônàlizætiøn.com' correctly" do
    Addressable::IDNA.to_ascii(
      "www.In\314\203te\314\210rna\314\202tio\314\202n" +
      "a\314\200liz\303\246ti\303\270n.com"
    ).should == "www.xn--itrntinliztin-vdb0a5exd8ewcye.com"
  end
end

describe Addressable::IDNA, "when converting from ASCII to unicode" do
  it "should convert 'www.詹姆斯.com' correctly" do
    Addressable::IDNA.to_unicode(
      "www.xn--8ws00zhy3a.com"
    ).should == "www.詹姆斯.com"
  end

  it "should convert 'www.iñtërnâtiônàlizætiøn.com' correctly" do
    Addressable::IDNA.to_unicode(
      "www.xn--itrntinliztin-vdb0a5exd8ewcye.com"
    ).should == "www.iñtërnâtiônàlizætiøn.com"
  end
end
