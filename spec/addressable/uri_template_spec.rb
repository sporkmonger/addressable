require "addressable/uri_template"

shared_examples_for 'expands' do |tests|
  tests.each do |template, expansion|
    it "#{template} to #{expansion}" do
      tmpl = Addressable::UriTemplate.new(template).expand(subject)
      tmpl.to_str.should == expansion
    end
  end
end

describe "Level 1:" do
  subject{
    {:var => "value", :hello => "Hello World!"}
  }
  it_behaves_like 'expands', {
    '{var}' => 'value',
    '{hello}' => 'Hello%20World%21'
  }
end

describe "Level 2" do
  subject{
    {
      :var => "value",
      :hello => "Hello World!",
      :path => "/foo/bar"
    }
  }
  context "Operator +:" do
    it_behaves_like 'expands', {
      '{+var}' => 'value',
      '{+hello}' => 'Hello%20World!',
      '{+path}/here' => '/foo/bar/here',
      'here?ref={+path}' => 'here?ref=/foo/bar'
    }
  end
  context "Operator #:" do
    it_behaves_like 'expands', {
      'X{#var}' => 'X#value',
      'X{#hello}' => 'X#Hello%20World!',
    }
  end
end



describe Addressable::UriTemplate do
  describe "Level 1:" do
    subject { Addressable::UriTemplate.new("foo{foo}/{bar}baz") }
    it "can match" do
      data = subject.match("foofoo/bananabaz")
      data.mapping["foo"].should == "foo"
      data.mapping["bar"].should == "banana"
    end
    it "lists vars" do
      subject.variables.should == ["foo", "bar"]
    end
  end

  describe "Level 2:" do
    subject { Addressable::UriTemplate.new("foo{+foo}{#bar}baz") }
    it "can match" do
      data = subject.match("foo/test/banana#bazbaz")
      data.mapping["foo"].should == "/test/banana"
      data.mapping["bar"].should == "baz"
    end
    it "lists vars" do
      subject.variables.should == ["foo", "bar"]
    end
  end

  context "support regexes:" do
    context "EXPRESSION" do
      subject { Addressable::UriTemplate::EXPRESSION }
      it "should be able to match an expression" do
        subject.should match("{foo}")
        subject.should match("{foo,9}")
        subject.should match("{foo.bar,baz}")
        subject.should match("{+foo.bar,baz}")
        subject.should match("{foo,foo%20bar}")
        subject.should match("{#foo:20,baz*}")
        subject.should match("stuff{#foo:20,baz*}things")
      end
      it "should fail on non vars" do
        subject.should_not match("!{foo")
        subject.should_not match("{foo.bar.}")
        subject.should_not match("!{}")
      end
    end
    context "VARNAME" do
      subject { Addressable::UriTemplate::VARNAME }
      it "should be able to match a variable" do
        subject.should match("foo")
        subject.should match("9")
        subject.should match("foo.bar")
        subject.should match("foo_bar")
        subject.should match("foo_bar.baz")
        subject.should match("foo%20bar")
        subject.should match("foo%20bar.baz")
      end
      it "should fail on non vars" do
        subject.should_not match("!foo")
        subject.should_not match("foo.bar.")
        subject.should_not match("foo%2%00bar")
        subject.should_not match("foo_ba%r")
        subject.should_not match("foo_bar*")
        subject.should_not match("foo_bar:20")
      end
    end
    context "VARIABLE_LIST" do
      subject { Addressable::UriTemplate::VARIABLE_LIST }
      it "should be able to match a variable list" do
        subject.should match("foo,bar")
        subject.should match("foo")
        subject.should match("foo,bar*,baz")
        subject.should match("foo.bar,bar_baz*,baz:12")
      end
      it "should fail on non vars" do
        subject.should_not match(",foo,bar*,baz")
        subject.should_not match("foo,*bar,baz")
        subject.should_not match("foo,,bar*,baz")
      end
    end
    context "VARSPEC" do
      subject { Addressable::UriTemplate::VARSPEC }
      it "should be able to match a variable with modifier" do
        subject.should match("9:8")
        subject.should match("foo.bar*")
        subject.should match("foo_bar:12")
        subject.should match("foo_bar.baz*")
        subject.should match("foo%20bar:12")
        subject.should match("foo%20bar.baz*")
      end
      it "should fail on non vars" do
        subject.should_not match("!foo")
        subject.should_not match("*foo")
        subject.should_not match("fo*o")
        subject.should_not match("fo:o")
        subject.should_not match("foo:")
      end
    end
  end
end
