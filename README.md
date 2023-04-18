# Addressable

<dl>
  <dt>Homepage</dt><dd><a href="https://github.com/sporkmonger/addressable">github.com/sporkmonger/addressable</a></dd>
  <dt>Author</dt><dd><a href="mailto:bob@sporkmonger.com">Bob Aman</a></dd>
  <dt>Copyright</dt><dd>Copyright © Bob Aman</dd>
  <dt>License</dt><dd>Apache 2.0</dd>
</dl>

[![Gem Version](https://img.shields.io/gem/dt/addressable.svg)][gem]
[![Build Status](https://github.com/sporkmonger/addressable/workflows/CI/badge.svg)][actions]
[![Test Coverage Status](https://img.shields.io/coveralls/sporkmonger/addressable.svg)][coveralls]
[![Documentation Coverage Status](https://inch-ci.org/github/sporkmonger/addressable.svg?branch=master)][inch]

[gem]: https://rubygems.org/gems/addressable
[actions]: https://github.com/sporkmonger/addressable/actions
[coveralls]: https://coveralls.io/r/sporkmonger/addressable
[inch]: https://inch-ci.org/github/sporkmonger/addressable

# Description

Addressable is an alternative implementation to the URI implementation
that is part of Ruby's standard library. It is flexible, offers heuristic
parsing, and additionally provides extensive support for IRIs and URI templates.

Addressable closely conforms to RFC 3986, RFC 3987, and RFC 6570 (level 4).

# Reference

- {Addressable::URI}
- {Addressable::Template}

# Example usage

```ruby
require "addressable/uri"

uri = Addressable::URI.parse("http://example.com/path/to/resource/")
uri.scheme
#=> "http"
uri.host
#=> "example.com"
uri.path
#=> "/path/to/resource/"

uri = Addressable::URI.parse("http://www.詹姆斯.com/")
uri.normalize
#=> #<Addressable::URI:0xc9a4c8 URI:http://www.xn--8ws00zhy3a.com/>
```


# URI Templates

For more details, see [RFC 6570](https://www.rfc-editor.org/rfc/rfc6570.txt).


```ruby

require "addressable/template"

template = Addressable::Template.new("http://example.com/{?query*}")
template.expand({
  "query" => {
    'foo' => 'bar',
    'color' => 'red'
  }
})
#=> #<Addressable::URI:0xc9d95c URI:http://example.com/?foo=bar&color=red>

template = Addressable::Template.new("http://example.com/{?one,two,three}")
template.partial_expand({"one" => "1", "three" => 3}).pattern
#=> "http://example.com/?one=1{&two}&three=3"

template = Addressable::Template.new(
  "http://{host}{/segments*}/{?one,two,bogus}{#fragment}"
)
uri = Addressable::URI.parse(
  "http://example.com/a/b/c/?one=1&two=2#foo"
)
template.extract(uri)
#=>
# {
#   "host" => "example.com",
#   "segments" => ["a", "b", "c"],
#   "one" => "1",
#   "two" => "2",
#   "fragment" => "foo"
# }
```

# Install

```console
$ gem install addressable
```

# IDNA support (unicode hostnames)

Three IDNA implementations are available, the first one available is used:
- A `libidn1` wrapper (if `libidn` and the `idn` gem are installed), supporting IDNA2003.
- A pure ruby implementation (slower), [almost](https://github.com/sporkmonger/addressable/issues/491) supporting IDNA2008.
- A `libidn2` wrapper (if `libidn2` is installed), supporting IDNA2008+UTS#46.

Note: in the future major version, `libidn2` will become the default.

To install `libidn2`:

```console
$ sudo apt-get install libidn2-dev # Debian/Ubuntu
$ brew install libidn2 # OS X
```

To install `libidn1` and the `idn` gem (also add it to your Gemfile):

```console
$ sudo apt-get install libidn11-dev # Debian/Ubuntu
$ brew install libidn # OS X
$ gem install idn-ruby
```

Optionally you can turn on the strict mode which will raise exceptions in case of invalid hostname during IDNA conversion. The default (`false`) silently ignores them and keeps the hostname unchanged. The strictness will depend on the backend used, libidn2 is stricter than libidn1 for example.
```ruby
Addressable::IDNA.backend.strict_mode = true # default: false
```

Finally if you want to force a different IDNA implementation, you can do so like this (after addressable is required):

```ruby
require "addressable/idna/pure"
Addressable::IDNA.backend = Addressable::IDNA::Pure
require "addressable/idna/libidn2"
Addressable::IDNA.backend = Addressable::IDNA::Libidn2
# Check which implmentation is active:
puts Addressable::IDNA.backend.name
```

# Semantic Versioning

This project uses [Semantic Versioning](https://semver.org/). You can (and should) specify your
dependency using a pessimistic version constraint covering the major and minor
values:

```ruby
spec.add_dependency 'addressable', '~> 2.7'
```

If you need a specific bug fix, you can also specify minimum tiny versions
without preventing updates to the latest minor release:

```ruby
spec.add_dependency 'addressable', '~> 2.3', '>= 2.3.7'
```
