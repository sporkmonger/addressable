require "addressable/template"

shared_examples_for 'expands' do |tests|
  tests.each do |template, expansion|
    exp = expansion.is_a?(Array) ? expansion.first : expansion
    it "#{template} to #{exp}" do
      tmpl = Addressable::Template.new(template).expand(subject)
      if expansion.is_a?(Array)
        expansion.any?{|i| i == tmpl.to_str}.should be_true
      else
        tmpl.to_str.should == expansion
      end
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
      'X{#hello}' => 'X#Hello%20World!'
    }
  end
end

describe "Level 3" do
  subject{
    {
      :var => "value",
      :hello => "Hello World!",
      :empty => "",
      :path => "/foo/bar",
      :x => "1024",
      :y => "768"
    }
  }
  context "Operator nil (multiple vars):" do
    it_behaves_like 'expands', {
      'map?{x,y}' => 'map?1024,768',
      '{x,hello,y}' => '1024,Hello%20World%21,768'
    }
  end
  context "Operator + (multiple vars):" do
    it_behaves_like 'expands', {
      '{+x,hello,y}' => '1024,Hello%20World!,768',
      '{+path,x}/here' => '/foo/bar,1024/here'
    }
  end
  context "Operator # (multiple vars):" do
    it_behaves_like 'expands', {
      '{#x,hello,y}' => '#1024,Hello%20World!,768',
      '{#path,x}/here' => '#/foo/bar,1024/here'
    }
  end
  context "Operator ." do
    it_behaves_like 'expands', {
      'X{.var}' => 'X.value',
      'X{.x,y}' => 'X.1024.768'
    }
  end
  context "Operator /" do
    it_behaves_like 'expands', {
      '{/var}' => '/value',
      '{/var,x}/here' => '/value/1024/here'
    }
  end
  context "Operator ;" do
    it_behaves_like 'expands', {
      '{;x,y}' => ';x=1024;y=768',
      '{;x,y,empty}' => ';x=1024;y=768;empty'
    }
  end
  context "Operator ?" do
    it_behaves_like 'expands', {
      '{?x,y}' => '?x=1024&y=768',
      '{?x,y,empty}' => '?x=1024&y=768&empty='
    }
  end
  context "Operator &" do
    it_behaves_like 'expands', {
      '?fixed=yes{&x}' => '?fixed=yes&x=1024',
      '{&x,y,empty}' => '&x=1024&y=768&empty='
    }
  end
end

describe "Level 4" do
  subject{
    {
      :var => "value",
      :hello => "Hello World!",
      :path => "/foo/bar",
      :semi => ";",
      :list => %w(red green blue),
      :keys => {"semi" => ';', "dot" => '.', "comma" => ','}
    }
  }
  context "Expansion with value modifiers" do
    it_behaves_like 'expands', {
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{list}' => 'red,green,blue',
      '{list*}' => 'red,green,blue',
      '{keys}' => [
        'semi,%3B,dot,.,comma,%2C',
        'dot,.,semi,%3B,comma,%2C',
        'comma,%2C,semi,%3B,dot,.',
        'semi,%3B,comma,%2C,dot,.',
        'dot,.,comma,%2C,semi,%3B',
        'comma,%2C,dot,.,semi,%3B'
      ],
      '{keys*}' => [
        'semi=%3B,dot=.,comma=%2C',
        'dot=.,semi=%3B,comma=%2C',
        'comma=%2C,semi=%3B,dot=.',
        'semi=%3B,comma=%2C,dot=.',
        'dot=.,comma=%2C,semi=%3B',
        'comma=%2C,dot=.,semi=%3B'
      ]
    }
  end
  context "Operator + with value modifiers" do
    it_behaves_like 'expands', {
      '{+path:6}/here' => '/foo/b/here',
      '{+list}' => 'red,green,blue',
      '{+list*}' => 'red,green,blue',
      '{+keys}' => [
        'semi,;,dot,.,comma,,',
        'dot,.,semi,;,comma,,',
        'comma,,,semi,;,dot,.',
        'semi,;,comma,,,dot,.',
        'dot,.,comma,,,semi,;',
        'comma,,,dot,.,semi,;'
      ],
      '{+keys*}' => [
        'semi=;,dot=.,comma=,',
        'dot=.,semi=;,comma=,',
        'comma=,,semi=;,dot=.',
        'semi=;,comma=,,dot=.',
        'dot=.,comma=,,semi=;',
        'comma=,,dot=.,semi=;'
      ]
    }
  end
  context "Operator # with value modifiers" do
    it_behaves_like 'expands', {
      '{#path:6}/here' => '#/foo/b/here',
      '{#list}' => '#red,green,blue',
      '{#list*}' => '#red,green,blue',
      '{#keys}' => [
        '#semi,;,dot,.,comma,,',
        '#dot,.,semi,;,comma,,',
        '#comma,,,semi,;,dot,.',
        '#semi,;,comma,,,dot,.',
        '#dot,.,comma,,,semi,;',
        '#comma,,,dot,.,semi,;'
      ],
      '{#keys*}' => [
        '#semi=;,dot=.,comma=,',
        '#dot=.,semi=;,comma=,',
        '#comma=,,semi=;,dot=.',
        '#semi=;,comma=,,dot=.',
        '#dot=.,comma=,,semi=;',
        '#comma=,,dot=.,semi=;'
      ]
    }
  end
  context "Operator . with value modifiers" do
    it_behaves_like 'expands', {
      'X{.var:3}' => 'X.val',
      'X{.list}' => 'X.red,green,blue',
      'X{.list*}' => 'X.red.green.blue',
      'X{.keys}' => [
        'X.semi,%3B,dot,.,comma,%2C',
        'X.dot,.,semi,%3B,comma,%2C',
        'X.comma,%2C,semi,%3B,dot,.',
        'X.semi,%3B,comma,%2C,dot,.',
        'X.dot,.,comma,%2C,semi,%3B',
        'X.comma,%2C,dot,.,semi,%3B'
      ],
      'X{.keys*}' => [
        'X.semi=%3B.dot=..comma=%2C',
        'X.dot=..semi=%3B.comma=%2C',
        'X.comma=%2C.semi=%3B.dot=.',
        'X.semi=%3B.comma=%2C.dot=.',
        'X.dot=..comma=%2C.semi=%3B',
        'X.comma=%2C.dot=..semi=%3B'
      ]
    }
  end
  context "Operator / with value modifiers" do
    it_behaves_like 'expands', {
      '{/var:1,var}' => '/v/value',
      '{/list}' => '/red,green,blue',
      '{/list*}' => '/red/green/blue',
      '{/list*,path:4}' => '/red/green/blue/%2Ffoo',
      '{/keys}' => [
        '/semi,%3B,dot,.,comma,%2C',
        '/dot,.,semi,%3B,comma,%2C',
        '/comma,%2C,semi,%3B,dot,.',
        '/semi,%3B,comma,%2C,dot,.',
        '/dot,.,comma,%2C,semi,%3B',
        '/comma,%2C,dot,.,semi,%3B'
      ],
      '{/keys*}' => [
        '/semi=%3B/dot=./comma=%2C',
        '/dot=./semi=%3B/comma=%2C',
        '/comma=%2C/semi=%3B/dot=.',
        '/semi=%3B/comma=%2C/dot=.',
        '/dot=./comma=%2C/semi=%3B',
        '/comma=%2C/dot=./semi=%3B'
      ]
    }
  end
  context "Operator ; with value modifiers" do
    it_behaves_like 'expands', {
      '{;hello:5}' => ';hello=Hello',
      '{;list}' => ';list=red,green,blue',
      '{;list*}' => ';list=red;list=green;list=blue',
      '{;keys}' => [
        ';keys=semi,%3B,dot,.,comma,%2C',
        ';keys=dot,.,semi,%3B,comma,%2C',
        ';keys=comma,%2C,semi,%3B,dot,.',
        ';keys=semi,%3B,comma,%2C,dot,.',
        ';keys=dot,.,comma,%2C,semi,%3B',
        ';keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{;keys*}' => [
        ';semi=%3B;dot=.;comma=%2C',
        ';dot=.;semi=%3B;comma=%2C',
        ';comma=%2C;semi=%3B;dot=.',
        ';semi=%3B;comma=%2C;dot=.',
        ';dot=.;comma=%2C;semi=%3B',
        ';comma=%2C;dot=.;semi=%3B'
      ]
    }
  end
  context "Operator ? with value modifiers" do
    it_behaves_like 'expands', {
      '{?var:3}' => '?var=val',
      '{?list}' => '?list=red,green,blue',
      '{?list*}' => '?list=red&list=green&list=blue',
      '{?keys}' => [
        '?keys=semi,%3B,dot,.,comma,%2C',
        '?keys=dot,.,semi,%3B,comma,%2C',
        '?keys=comma,%2C,semi,%3B,dot,.',
        '?keys=semi,%3B,comma,%2C,dot,.',
        '?keys=dot,.,comma,%2C,semi,%3B',
        '?keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{?keys*}' => [
        '?semi=%3B&dot=.&comma=%2C',
        '?dot=.&semi=%3B&comma=%2C',
        '?comma=%2C&semi=%3B&dot=.',
        '?semi=%3B&comma=%2C&dot=.',
        '?dot=.&comma=%2C&semi=%3B',
        '?comma=%2C&dot=.&semi=%3B'
      ]
    }
  end
  context "Operator & with value modifiers" do
    it_behaves_like 'expands', {
      '{&var:3}' => '&var=val',
      '{&list}' => '&list=red,green,blue',
      '{&list*}' => '&list=red&list=green&list=blue',
      '{&keys}' => [
        '&keys=semi,%3B,dot,.,comma,%2C',
        '&keys=dot,.,semi,%3B,comma,%2C',
        '&keys=comma,%2C,semi,%3B,dot,.',
        '&keys=semi,%3B,comma,%2C,dot,.',
        '&keys=dot,.,comma,%2C,semi,%3B',
        '&keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{&keys*}' => [
        '&semi=%3B&dot=.&comma=%2C',
        '&dot=.&semi=%3B&comma=%2C',
        '&comma=%2C&semi=%3B&dot=.',
        '&semi=%3B&comma=%2C&dot=.',
        '&dot=.&comma=%2C&semi=%3B',
        '&comma=%2C&dot=.&semi=%3B'
      ]
    }
  end
end
describe "Modifiers" do
  subject{
    {
      :var => "value",
      :semi => ";",
      :year => %w(1965 2000 2012),
      :dom => %w(example com)
    }
  }
  context "length" do
    it_behaves_like 'expands', {
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{var}' => 'value',
      '{semi}' => '%3B',
      '{semi:2}' => '%3B'
    }
  end
  context "explode" do
    it_behaves_like 'expands', {
      'find{?year*}' => 'find?year=1965&year=2000&year=2012',
      'www{.dom*}' => 'www.example.com',
    }
  end
end
describe "Expansion" do
  subject{
    {
      :count => ["one", "two", "three"],
      :dom => ["example", "com"],
      :dub   => "me/too",
      :hello => "Hello World!",
      :half  => "50%",
      :var   => "value",
      :who   => "fred",
      :base  => "http://example.com/home/",
      :path  => "/foo/bar",
      :list  => ["red", "green", "blue"],
      :keys  => {"semi" => ";","dot" => ".","comma" => ","},
      :v     => "6",
      :x     => "1024",
      :y     => "768",
      :empty => "",
      :empty_keys  => {},
      :undef => nil
    }
  }
  context "concatenation" do
    it_behaves_like 'expands', {
      '{count}' => 'one,two,three',
      '{count*}' => 'one,two,three',
      '{/count}' => '/one,two,three',
      '{/count*}' => '/one/two/three',
      '{;count}' => ';count=one,two,three',
      '{;count*}' => ';count=one;count=two;count=three',
      '{?count}' => '?count=one,two,three',
      '{?count*}' => '?count=one&count=two&count=three',
      '{&count*}' => '&count=one&count=two&count=three'
    }
  end
  context "simple expansion" do
    it_behaves_like 'expands', {
      '{var}' => 'value',
      '{hello}' => 'Hello%20World%21',
      '{half}' => '50%25',
      'O{empty}X' => 'OX',
      'O{undef}X' => 'OX',
      '{x,y}' => '1024,768',
      '{x,hello,y}' => '1024,Hello%20World%21,768',
      '?{x,empty}' => '?1024,',
      '?{x,undef}' => '?1024',
      '?{undef,y}' => '?768',
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{list}' => 'red,green,blue',
      '{list*}' => 'red,green,blue',
      '{keys}' => [
        'semi,%3B,dot,.,comma,%2C',
        'dot,.,semi,%3B,comma,%2C',
        'comma,%2C,semi,%3B,dot,.',
        'semi,%3B,comma,%2C,dot,.',
        'dot,.,comma,%2C,semi,%3B',
        'comma,%2C,dot,.,semi,%3B'
      ],
      '{keys*}' => [
        'semi=%3B,dot=.,comma=%2C',
        'dot=.,semi=%3B,comma=%2C',
        'comma=%2C,semi=%3B,dot=.',
        'semi=%3B,comma=%2C,dot=.',
        'dot=.,comma=%2C,semi=%3B',
        'comma=%2C,dot=.,semi=%3B'
      ]
    }
  end
  context "reserved expansion (+)" do
    it_behaves_like 'expands', {
      '{+var}' => 'value',
      '{+hello}' => 'Hello%20World!',
      '{+half}' => '50%25',
      '{base}index' => 'http%3A%2F%2Fexample.com%2Fhome%2Findex',
      '{+base}index' => 'http://example.com/home/index',
      'O{+empty}X' => 'OX',
      'O{+undef}X' => 'OX',
      '{+path}/here' => '/foo/bar/here',
      'here?ref={+path}' => 'here?ref=/foo/bar',
      'up{+path}{var}/here' => 'up/foo/barvalue/here',
      '{+x,hello,y}' => '1024,Hello%20World!,768',
      '{+path,x}/here' => '/foo/bar,1024/here',
      '{+path:6}/here' => '/foo/b/here',
      '{+list}' => 'red,green,blue',
      '{+list*}' => 'red,green,blue',
      '{+keys}' => [
        'semi,;,dot,.,comma,,',
        'dot,.,semi,;,comma,,',
        'comma,,,semi,;,dot,.',
        'semi,;,comma,,,dot,.',
        'dot,.,comma,,,semi,;',
        'comma,,,dot,.,semi,;'
      ],
      '{+keys*}' => [
        'semi=;,dot=.,comma=,',
        'dot=.,semi=;,comma=,',
        'comma=,,semi=;,dot=.',
        'semi=;,comma=,,dot=.',
        'dot=.,comma=,,semi=;',
        'comma=,,dot=.,semi=;'
      ]
    }
  end
  context "fragment expansion (#)" do
    it_behaves_like 'expands', {
      '{#var}' => '#value',
      '{#hello}' => '#Hello%20World!',
      '{#half}' => '#50%25',
      'foo{#empty}' => 'foo#',
      'foo{#undef}' => 'foo',
      '{#x,hello,y}' => '#1024,Hello%20World!,768',
      '{#path,x}/here' => '#/foo/bar,1024/here',
      '{#path:6}/here' => '#/foo/b/here',
      '{#list}' => '#red,green,blue',
      '{#list*}' => '#red,green,blue',
      '{#keys}' => [
        '#semi,;,dot,.,comma,,',
        '#dot,.,semi,;,comma,,',
        '#comma,,,semi,;,dot,.',
        '#semi,;,comma,,,dot,.',
        '#dot,.,comma,,,semi,;',
        '#comma,,,dot,.,semi,;'
      ],
      '{#keys*}' => [
        '#semi=;,dot=.,comma=,',
        '#dot=.,semi=;,comma=,',
        '#comma=,,semi=;,dot=.',
        '#semi=;,comma=,,dot=.',
        '#dot=.,comma=,,semi=;',
        '#comma=,,dot=.,semi=;'
      ]
    }
  end
  context "label expansion (.)" do
    it_behaves_like 'expands', {
      '{.who}' => '.fred',
      '{.who,who}' => '.fred.fred',
      '{.half,who}' => '.50%25.fred',
      'www{.dom*}' => 'www.example.com',
      'X{.var}' => 'X.value',
      'X{.empty}' => 'X.',
      'X{.undef}' => 'X',
      'X{.var:3}' => 'X.val',
      'X{.list}' => 'X.red,green,blue',
      'X{.list*}' => 'X.red.green.blue',
      'X{.keys}' => [
        'X.semi,%3B,dot,.,comma,%2C',
        'X.dot,.,semi,%3B,comma,%2C',
        'X.comma,%2C,semi,%3B,dot,.',
        'X.semi,%3B,comma,%2C,dot,.',
        'X.dot,.,comma,%2C,semi,%3B',
        'X.comma,%2C,dot,.,semi,%3B'
      ],
      'X{.keys*}' => [
        'X.semi=%3B.dot=..comma=%2C',
        'X.dot=..semi=%3B.comma=%2C',
        'X.comma=%2C.semi=%3B.dot=.',
        'X.semi=%3B.comma=%2C.dot=.',
        'X.dot=..comma=%2C.semi=%3B',
        'X.comma=%2C.dot=..semi=%3B'
      ],
      'X{.empty_keys}' => 'X',
      'X{.empty_keys*}' => 'X'
    }
  end
  context "path expansion (/)" do
    it_behaves_like 'expands', {
      '{/who}' => '/fred',
      '{/who,who}' => '/fred/fred',
      '{/half,who}' => '/50%25/fred',
      '{/who,dub}' => '/fred/me%2Ftoo',
      '{/var}' => '/value',
      '{/var,empty}' => '/value/',
      '{/var,undef}' => '/value',
      '{/var,x}/here' => '/value/1024/here',
      '{/var:1,var}' => '/v/value',
      '{/list}' => '/red,green,blue',
      '{/list*}' => '/red/green/blue',
      '{/list*,path:4}' => '/red/green/blue/%2Ffoo',
      '{/keys}' => [
        '/semi,%3B,dot,.,comma,%2C',
        '/dot,.,semi,%3B,comma,%2C',
        '/comma,%2C,semi,%3B,dot,.',
        '/semi,%3B,comma,%2C,dot,.',
        '/dot,.,comma,%2C,semi,%3B',
        '/comma,%2C,dot,.,semi,%3B'
      ],
      '{/keys*}' => [
        '/semi=%3B/dot=./comma=%2C',
        '/dot=./semi=%3B/comma=%2C',
        '/comma=%2C/semi=%3B/dot=.',
        '/semi=%3B/comma=%2C/dot=.',
        '/dot=./comma=%2C/semi=%3B',
        '/comma=%2C/dot=./semi=%3B'
      ]
    }
  end
  context "path-style expansion (;)" do
    it_behaves_like 'expands', {
      '{;who}' => ';who=fred',
      '{;half}' => ';half=50%25',
      '{;empty}' => ';empty',
      '{;v,empty,who}' => ';v=6;empty;who=fred',
      '{;v,bar,who}' => ';v=6;who=fred',
      '{;x,y}' => ';x=1024;y=768',
      '{;x,y,empty}' => ';x=1024;y=768;empty',
      '{;x,y,undef}' => ';x=1024;y=768',
      '{;hello:5}' => ';hello=Hello',
      '{;list}' => ';list=red,green,blue',
      '{;list*}' => ';list=red;list=green;list=blue',
      '{;keys}' => [
        ';keys=semi,%3B,dot,.,comma,%2C',
        ';keys=dot,.,semi,%3B,comma,%2C',
        ';keys=comma,%2C,semi,%3B,dot,.',
        ';keys=semi,%3B,comma,%2C,dot,.',
        ';keys=dot,.,comma,%2C,semi,%3B',
        ';keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{;keys*}' => [
        ';semi=%3B;dot=.;comma=%2C',
        ';dot=.;semi=%3B;comma=%2C',
        ';comma=%2C;semi=%3B;dot=.',
        ';semi=%3B;comma=%2C;dot=.',
        ';dot=.;comma=%2C;semi=%3B',
        ';comma=%2C;dot=.;semi=%3B'
      ]
    }
  end
  context "form query expansion (?)" do
    it_behaves_like 'expands', {
      '{?who}' => '?who=fred',
      '{?half}' => '?half=50%25',
      '{?x,y}' => '?x=1024&y=768',
      '{?x,y,empty}' => '?x=1024&y=768&empty=',
      '{?x,y,undef}' => '?x=1024&y=768',
      '{?var:3}' => '?var=val',
      '{?list}' => '?list=red,green,blue',
      '{?list*}' => '?list=red&list=green&list=blue',
      '{?keys}' => [
        '?keys=semi,%3B,dot,.,comma,%2C',
        '?keys=dot,.,semi,%3B,comma,%2C',
        '?keys=comma,%2C,semi,%3B,dot,.',
        '?keys=semi,%3B,comma,%2C,dot,.',
        '?keys=dot,.,comma,%2C,semi,%3B',
        '?keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{?keys*}' => [
        '?semi=%3B&dot=.&comma=%2C',
        '?dot=.&semi=%3B&comma=%2C',
        '?comma=%2C&semi=%3B&dot=.',
        '?semi=%3B&comma=%2C&dot=.',
        '?dot=.&comma=%2C&semi=%3B',
        '?comma=%2C&dot=.&semi=%3B'
      ]
    }
  end
  context "form query expansion (&)" do
    it_behaves_like 'expands', {
      '{&who}' => '&who=fred',
      '{&half}' => '&half=50%25',
      '?fixed=yes{&x}' => '?fixed=yes&x=1024',
      '{&x,y,empty}' => '&x=1024&y=768&empty=',
      '{&x,y,undef}' => '&x=1024&y=768',
      '{&var:3}' => '&var=val',
      '{&list}' => '&list=red,green,blue',
      '{&list*}' => '&list=red&list=green&list=blue',
      '{&keys}' => [
        '&keys=semi,%3B,dot,.,comma,%2C',
        '&keys=dot,.,semi,%3B,comma,%2C',
        '&keys=comma,%2C,semi,%3B,dot,.',
        '&keys=semi,%3B,comma,%2C,dot,.',
        '&keys=dot,.,comma,%2C,semi,%3B',
        '&keys=comma,%2C,dot,.,semi,%3B'
      ],
      '{&keys*}' => [
        '&semi=%3B&dot=.&comma=%2C',
        '&dot=.&semi=%3B&comma=%2C',
        '&comma=%2C&semi=%3B&dot=.',
        '&semi=%3B&comma=%2C&dot=.',
        '&dot=.&comma=%2C&semi=%3B',
        '&comma=%2C&dot=.&semi=%3B'
      ]
    }
  end
end

class ExampleTwoProcessor
  def self.restore(name, value)
    return value.gsub(/-/, " ") if name == "query"
    return value
  end

  def self.match(name)
    return ".*?" if name == "first"
    return ".*"
  end
  def self.validate(name, value)
    return !!(value =~ /^[\w ]+$/) if name == "query"
    return true
  end

  def self.transform(name, value)
    return value.gsub(/ /, "+") if name == "query"
    return value
  end
end


describe Addressable::Template do
  describe "Matching" do
    let(:uri){
      Addressable::URI.parse(
        "http://example.com/search/an-example-search-query/"
      )
    }
    let(:uri2){
      Addressable::URI.parse("http://example.com/a/b/c/")
    }
    let(:uri3){
      Addressable::URI.parse("http://example.com/;a=1;b=2;c=3;first=foo")
    }
    let(:uri4){
      Addressable::URI.parse("http://example.com/?a=1&b=2&c=3&first=foo")
    }
    context "first uri with ExampleTwoProcessor" do
      subject{
        match = Addressable::Template.new(
          "http://example.com/search/{query}/"
        ).match(uri, ExampleTwoProcessor)
      }
      its(:variables){ should == ["query"]}
      its(:captures){ should == ["an example search query"]}
    end

    context "second uri with ExampleTwoProcessor" do
      subject{
        match = Addressable::Template.new(
          "http://example.com/{first}/{+second}/"
        ).match(uri2, ExampleTwoProcessor)
      }
      its(:variables){ should == ["first", "second"]}
      its(:captures){ should == ["a", "b/c"] }
    end
    context "second uri" do
      subject{
        match = Addressable::Template.new(
          "http://example.com/{first}{/second*}/"
        ).match(uri2)
      }
      its(:variables){ should == ["first", "second"]}
      its(:captures){ should == ["a", ["b","c"]] }
    end
    context "third uri" do
      subject{
        match = Addressable::Template.new(
          "http://example.com/{;hash*,first}"
        ).match(uri3)
      }
      its(:variables){ should == ["hash", "first"]}
      its(:captures){ should == [
        {"a" => "1", "b" => "2", "c" => "3", "first" => "foo"}, nil] }
    end
    context "fourth uri" do
      subject{
        match = Addressable::Template.new(
          "http://example.com/{?hash*,first}"
        ).match(uri4)
      }
      its(:variables){ should == ["hash", "first"]}
      its(:captures){ should == [
        {"a" => "1", "b" => "2", "c" => "3", "first"=> "foo"}, nil] }
    end
  end
  describe "extract" do
    let(:template) {
      Addressable::Template.new(
        "http://{host}{/segments*}/{?one,two,bogus}{#fragment}"
      )
    }
    let(:uri){ "http://example.com/a/b/c/?one=1&two=2#foo" }
    it "should be able to extract" do
      template.extract(uri).should == {
        "host" => "example.com",
        "segments" => %w(a b c),
        "one" => "1",
        "bogus" => nil,
        "two" => "2",
        "fragment" => "foo"
      }
    end
  end
  describe "Partial expand" do
    context "partial_expand with two simple values" do
      subject{
        Addressable::Template.new("http://example.com/{one}/{two}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1").pattern.should ==
          "http://example.com/1/{two}/"
      end
    end
    context "partial_expand query with missing param in middle" do
      subject{
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1", "three" => "3").pattern.should ==
          "http://example.com/?one=1{&two}&three=3/"
      end
    end
    context "partial_expand with query string" do
      subject{
        Addressable::Template.new("http://example.com/{?two,one}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1").pattern.should ==
          "http://example.com/{?two}&one=1/"
      end
    end
    context "partial_expand with path operator" do
      subject{
        Addressable::Template.new("http://example.com{/one,two}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1").pattern.should ==
          "http://example.com/1{/two}/"
      end
    end
  end
  describe "Expand" do
    context "expand with a processor" do
      subject{
        Addressable::Template.new("http://example.com/search/{query}/")
      }
      it "processes spaces" do
        subject.expand({"query" => "an example search query"},
                      ExampleTwoProcessor).to_str.should ==
          "http://example.com/search/an+example+search+query/"
      end
      it "validates" do
        lambda{
          subject.expand({"query" => "Bogus!"},
                      ExampleTwoProcessor).to_str
        }.should raise_error(Addressable::Template::InvalidTemplateValueError)
      end
    end
    context "partial_expand query with missing param in middle" do
      subject{
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1", "three" => "3").pattern.should ==
          "http://example.com/?one=1{&two}&three=3/"
      end
    end
    context "partial_expand with query string" do
      subject{
        Addressable::Template.new("http://example.com/{?two,one}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1").pattern.should ==
          "http://example.com/{?two}&one=1/"
      end
    end
    context "partial_expand with path operator" do
      subject{
        Addressable::Template.new("http://example.com{/one,two}/")
      }
      it "builds a new pattern" do
        subject.partial_expand("one" => "1").pattern.should ==
          "http://example.com/1{/two}/"
      end
    end
  end
  context "Matching with operators" do
    describe "Level 1:" do
      subject { Addressable::Template.new("foo{foo}/{bar}baz") }
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
      subject { Addressable::Template.new("foo{+foo}{#bar}baz") }
      it "can match" do
        data = subject.match("foo/test/banana#bazbaz")
        data.mapping["foo"].should == "/test/banana"
        data.mapping["bar"].should == "baz"
      end
      it "lists vars" do
        subject.variables.should == ["foo", "bar"]
      end
    end

    describe "Level 3:" do
      context "no operator" do
        subject { Addressable::Template.new("foo{foo,bar}baz") }
        it "can match" do
          data = subject.match("foofoo,barbaz")
          data.mapping["foo"].should == "foo"
          data.mapping["bar"].should == "bar"
        end
        it "lists vars" do
          subject.variables.should == ["foo", "bar"]
        end
      end
      context "+ operator" do
        subject { Addressable::Template.new("foo{+foo,bar}baz") }
        it "can match" do
          data = subject.match("foofoo/bar,barbaz")
          data.mapping["bar"].should == "foo/bar,bar"
          data.mapping["foo"].should == ""
        end
        it "lists vars" do
          subject.variables.should == ["foo", "bar"]
        end
      end
      context ". operator" do
        subject { Addressable::Template.new("foo{.foo,bar}baz") }
        it "can match" do
          data = subject.match("foo.foo.barbaz")
          data.mapping["foo"].should == "foo"
          data.mapping["bar"].should == "bar"
        end
        it "lists vars" do
          subject.variables.should == ["foo", "bar"]
        end
      end
      context "/ operator" do
        subject { Addressable::Template.new("foo{/foo,bar}baz") }
        it "can match" do
          data = subject.match("foo/foo/barbaz")
          data.mapping["foo"].should == "foo"
          data.mapping["bar"].should == "bar"
        end
        it "lists vars" do
          subject.variables.should == ["foo", "bar"]
        end
      end
      context "; operator" do
        subject { Addressable::Template.new("foo{;foo,bar,baz}baz") }
        it "can match" do
          data = subject.match("foo;foo=bar%20baz;bar=foo;bazbaz")
          data.mapping["foo"].should == "bar baz"
          data.mapping["bar"].should == "foo"
          data.mapping["baz"].should == ""
        end
        it "lists vars" do
          subject.variables.should == %w(foo bar baz)
        end
      end
      context "? operator" do
        context "test" do
          subject { Addressable::Template.new("foo{?foo,bar}baz") }
          it "can match" do
            data = subject.match("foo?foo=bar%20baz&bar=foobaz")
            data.mapping["foo"].should == "bar baz"
            data.mapping["bar"].should == "foo"
          end
          it "lists vars" do
            subject.variables.should == %w(foo bar)
          end
        end
        context "issue #71" do
          subject { Addressable::Template.new("http://cyberscore.dev/api/users{?username}") }
          it "can match" do
            data = subject.match("http://cyberscore.dev/api/users?username=foobaz")
            data.mapping["username"].should == "foobaz"
          end
          it "lists vars" do
            subject.variables.should == %w(username)
            subject.keys.should == %w(username)
          end
        end
      end
      context "& operator" do
        subject { Addressable::Template.new("foo{&foo,bar}baz") }
        it "can match" do
          data = subject.match("foo&foo=bar%20baz&bar=foobaz")
          data.mapping["foo"].should == "bar baz"
          data.mapping["bar"].should == "foo"
        end
        it "lists vars" do
          subject.variables.should == %w(foo bar)
        end
      end
    end
  end

  context "support regexes:" do
    context "EXPRESSION" do
      subject { Addressable::Template::EXPRESSION }
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
      subject { Addressable::Template::VARNAME }
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
      subject { Addressable::Template::VARIABLE_LIST }
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
      subject { Addressable::Template::VARSPEC }
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
