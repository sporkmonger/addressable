begin
  require 'coveralls'
  Coveralls.wear!
rescue LoadError
  warn "warning: coveralls gem not found; skipping Coveralls"
end
