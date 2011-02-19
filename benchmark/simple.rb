require 'benchmark'

$: << '../lib' << 'lib'
require 'addressable/uri'

n = 5000
Benchmark.bm do |x|
  x.report do
    n.times do
      u = Addressable::URI.parse('http://google.com/stuff/../?with_lots=of&params=asdff#!stuff')
      u.normalize
    end
  end
end
