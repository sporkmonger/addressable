require 'benchmark'

$: << '../lib' << 'lib'
require 'addressable/uri'

n = 30000
Benchmark.bm do |x|
  x.report do
    n.times do
      u = Addressable::URI.parse('http://google.com/stuff/../?with_lots=of&params=asdff#!stuff')
      u.normalize
    end
  end
end

# Total: 1026 samples
#      203  19.8%  19.8%      328  32.0% Addressable::URI#normalized_path
#      177  17.3%  37.0%      177  17.3% garbage_collector
#      155  15.1%  52.1%      221  21.5% Addressable::URI#initialize
#       52   5.1%  57.2%       52   5.1% Addressable::URI.encode_component
#       46   4.5%  61.7%      142  13.8% Addressable::URI.normalize_component
#       39   3.8%  65.5%       41   4.0% Addressable::URI.normalize_path
#       38   3.7%  69.2%      128  12.5% Addressable::URI.parse
#       36   3.5%  72.7%       58   5.7% Addressable::URI#normalized_scheme
#       35   3.4%  76.1%       53   5.2% Addressable::URI#normalized_fragment
#       34   3.3%  79.4%       34   3.3% Addressable::IDNA.unicode_normalize_kc
#       34   3.3%  82.7%       56   5.5% Addressable::URI#normalized_query
#       27   2.6%  85.4%      689  67.2% Addressable::URI#normalize
