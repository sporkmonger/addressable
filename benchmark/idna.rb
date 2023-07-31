# /usr/bin/env ruby
# frozen_string_literal: true.

require "benchmark"
require "addressable/idna/libidn2"
require "addressable/idna/libidn1"
require "addressable/idna/pure"

value = "fiᆵリ宠퐱卄.com"
expected = "xn--fi-w1k207vk59a3qk9w9r.com"
N = 100_000

fail "pure ruby does not match" unless expected == Addressable::IDNA::Pure.to_ascii(value)
fail "libidn does not match" unless expected == Addressable::IDNA::Libidn1.to_ascii(value)
fail "addressable does not match" unless expected == Addressable::IDNA::Libidn2.to_ascii(value)

Benchmark.bmbm do |x|
  x.report("pure") { N.times {
    Addressable::IDNA::Pure.to_unicode(Addressable::IDNA::Pure.to_ascii(value))
  } }

  x.report("libidn") { N.times {
    Addressable::IDNA::Libidn1.to_unicode(Addressable::IDNA::Libidn1.to_ascii(value))
  } }

  x.report("libidn2") { N.times {
    Addressable::IDNA::Libidn2.to_unicode(Addressable::IDNA::Libidn2.to_ascii(value))
  } }
end

# > ruby benchmark/idna.rb
# Rehearsal -------------------------------------------
# pure      5.914630   0.000000   5.914630 (  5.915326)
# libidn    0.518971   0.003672   0.522643 (  0.522676)
# libidn2   0.763936   0.000000   0.763936 (  0.763983)
# ---------------------------------- total: 7.201209sec

#               user     system      total        real
# pure      6.042877   0.000000   6.042877 (  6.043252)
# libidn    0.521668   0.000000   0.521668 (  0.521704)
# libidn2   0.764782   0.000000   0.764782 (  0.764863)
