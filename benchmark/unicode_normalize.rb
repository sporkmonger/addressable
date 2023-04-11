# /usr/bin/env ruby
# frozen_string_literal: true.

require "benchmark"
require_relative "../lib/addressable/idna/pure.rb"
require "idn"

value = "ﬁﾯリ宠퐱卄.com"
expected = "fiᆵリ宠퐱卄.com"
N = 100_000

fail "ruby does not match" unless expected == value.unicode_normalize(:nfkc)
fail "libidn does not match" unless expected == IDN::Stringprep.nfkc_normalize(value)
fail "addressable does not match" unless expected == Addressable::IDNA.unicode_normalize_kc(value)

Benchmark.bmbm do |x|
  x.report("pure") { N.times { Addressable::IDNA.unicode_normalize_kc(value) } }
  x.report("libidn") { N.times { IDN::Stringprep.nfkc_normalize(value) } }
  x.report("ruby") { N.times { value.unicode_normalize(:nfkc) } }
end

# February 14th 2023, before replacing the legacy pure normalize code:

# > ruby benchmark/unicode_normalize.rb
# Rehearsal ------------------------------------------
# pure     1.335230   0.000315   1.335545 (  1.335657)
# libidn   0.058568   0.000000   0.058568 (  0.058570)
# ruby     0.326008   0.000014   0.326022 (  0.326026)
# --------------------------------- total: 1.720135sec

#              user     system      total        real
# pure     1.325948   0.000000   1.325948 (  1.326054)
# libidn   0.058067   0.000000   0.058067 (  0.058069)
# ruby     0.325062   0.000000   0.325062 (  0.325115)
