# Deprecated, for backward compatibility only
require "addressable/idna/libidn1"
Addressable::IDNA.backend = Addressable::IDNA::Libidn1
warn "NOTE: loading 'addressable/idna/native' is deprecated; use 'addressable/idna/libidn1' instead and set `Addressable::IDNA.backend = Addressable::IDNA::Libidn1` to force libidn1."