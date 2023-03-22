# /usr/bin/env ruby
# frozen_string_literal: true.

require "benchmark"

value = "fiᆵリ宠퐱卄.com"
expected = "xn--fi-w1k207vk59a3qk9w9r.com"
N = 100_000

Benchmark.bmbm do |x|
  x.report("pure") {
    load "lib/addressable/idna/pure.rb"
    fail "pure ruby does not match" unless expected == Addressable::IDNA.to_ascii(value)
    N.times { Addressable::IDNA.to_unicode(Addressable::IDNA.to_ascii(value)) }
    Addressable.send(:remove_const, :IDNA)
  }

  x.report("libidn") {
    load "lib/addressable/idna/native.rb"
    fail "libidn does not match" unless expected == Addressable::IDNA.to_ascii(value)
    N.times { Addressable::IDNA.to_unicode(Addressable::IDNA.to_ascii(value)) }
    Addressable.send(:remove_const, :IDNA)
  }

  x.report("libidn2") {
    load "lib/addressable/idna/native2.rb"
    fail "addressable does not match" unless expected == Addressable::IDNA.to_ascii(value)
    N.times { Addressable::IDNA.to_unicode(Addressable::IDNA.to_ascii(value)) }
    Addressable.send(:remove_const, :IDNA)
  }
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

puts "\nMemory leak test for libidn2 (memory should stabilize quickly):"
load "lib/addressable/idna/native2.rb"
GC.disable # Only run GC when manually called
10.times do
  N.times { Addressable::IDNA.to_unicode(Addressable::IDNA.to_ascii(value)) }
  GC.start # Run a major GC
  pid, size = `ps ax -o pid,rss | grep -E "^[[:space:]]*#{$$}"`.strip.split.map(&:to_i)
  puts " Memory: #{size/1024}MB" # show process memory
end

# Memory leak test for libidn2 (memory should stabilize quickly):
#  Memory: 117MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB
#  Memory: 121MB