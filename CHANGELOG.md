# Changelog

## Addressable 2.10.0 (unreleased) <a name="v2.10.0">
- release tags are only created and published from `main`: `rake git:tag:create`
  refuses any other branch, uncommitted changes, a `main` that doesn't match
  `origin/main` and an existing tag, and the Release workflow refuses a tag on
  a commit that isn't on `main`
- fixes `Addressable::URI#route_from` and `#route_to` giving routes that don't
  resolve to the target: e.g. from `http://example.com/a/b?x=1` to
  `http://example.com/a/` the route was empty, which resolves to the base, and
  is now `./`; this also happened when only the base had a query (#623) or a
  fragment, when the target's path had empty segments, as in `/a//b`, and when
  the target had an empty path or no authority
- `Addressable::URI#route_from` and `#route_to` no longer add a `../` that
  climbs above the root: e.g. from `http://example.com/a` to
  `http://example.com/` the route is now `./`, not `../`
- `Addressable::Template#hash` is now the same for equal templates, so
  templates with the same pattern find each other as `Hash` keys and are
  merged by `uniq` and `Set`; before, every template had its own hash (#604)
- fixes `Addressable::URI#userinfo=` splitting the user from the password at
  the last colon instead of the first, as `Addressable::URI.parse` and
  `#authority=` do: e.g. `alice:one:two` gave the user `alice:one` and the
  password `one:two`, repeating `one` in `#to_s`, and `alice` gave no user at
  all; an empty string now gives an empty user rather than none, as parsing
  `http://@example.com` does (#606)
- `Addressable::URI#query_values` now reads `+` as a space in names as well as
  values, as form encoding does: e.g. `http://example.com/?a+b=c` gives
  `{"a b" => "c"}`, not `{"a+b" => "c"}`; `%2B` is still a plus; it also
  reads `+` as a space for `HTTP` and `HTTPS` in uppercase, not only
  lowercase; other schemes, such as `mailto`, still keep `+` as is (#607)
- fixes `Addressable::URI.normalized_encode` decoding pct-encoded delimiters
  that change how the URI is read: e.g. `/a%2Fb` gave `/a/b`, `?a=1%262`
  gave `?a=1&2`, and `?a=1%2B2` gave `?a=1+2`, which reads as a space; it
  now keeps the same delimiters encoded as `#normalize`: `/` in the path;
  `&`, `;` and `+` in the query; and `#` in the fragment; other reserved
  characters are still decoded, as before (#589)
- fixes `Addressable::URI#normalize`, `#normalized_query` and
  `.normalized_encode` decoding `%3D` in a query name: e.g. `?a%3Db=1` gave
  `?a=b=1`, so `#query_values` changed from `{"a=b" => "1"}` to
  `{"a" => "b=1"}`; a `=` and a combining mark after it are also no longer
  composed by Unicode normalization, which lost the `=` (#589)
- fixes `Addressable::URI#normalize` decoding a triplet in a query twice:
  e.g. `%252B` gave `%2B`, which reads as a plus sign rather than as `%2B`;
  `%25` now stays encoded, and a bare `%` is encoded before decoding; and a
  query with invalid UTF-8, such as `?q=%2B%FF`, no longer has its `%2B`
  encoded again as `%252B` (#589)
- fixes `Addressable::URI#normalize` and `#normalized_path` encoding the
  first colon in a relative path's first segment as `%2F`, an encoded slash:
  e.g. a URI given the path `acct:bob@example.com` normalized to
  `acct%2Fbob@example.com`; every colon in that segment is now encoded as
  `%3A`, so it normalizes to `acct%3Abob@example.com`
- fixes `Addressable::URI#normalize` raising `InvalidURIError` when removing
  a leading `./` or `../` left a colon in the first segment of a relative
  path: e.g. `../folder:2/readme.md` now normalizes to
  `folder%3A2/readme.md` (#550)
- `Addressable::URI#normalize` and `.normalized_encode` now keep `%3A`
  encoded in the first segment of a relative path, rather than raising
  `InvalidURIError` because the decoded colon would read as a scheme: e.g.
  `a%3Ab/c%3Ad` normalizes to `a%3Ab/c:d` (#589)
- the pure-Ruby `Addressable::IDNA.to_ascii` and `.to_unicode` now keep
  trailing empty labels, as the `idn-ruby` backend does: e.g.
  `to_ascii("bücher.example.")` gives `xn--bcher-kva.example.`, not
  `xn--bcher-kva.example`; so with the pure-Ruby backend,
  `http://bücher.example../` now normalizes to
  `http://xn--bcher-kva.example../`, not `http://xn--bcher-kva.example/`,
  and `#display_uri` keeps the dots too; `#normalize` still drops a single
  trailing dot (#609)
- `Addressable::URI#origin=` now keeps an IPv6 or IPvFuture host in brackets
  whole: e.g. `http://[::1]:8080` gives the host `[::1]` and the port 8080;
  it now raises `InvalidURIError` for a string that isn't a serialized
  origin (a scheme, a host and an optional port), such as
  `http://user@example.com` or `http://example.com/a`, which have userinfo
  and a path (#616)
- `Addressable::URI#port=` and `Addressable::URI.new` now raise
  `InvalidURIError` for a port with a line break, which they took as the
  digits on one of its lines: e.g. `"8080\nx"` was taken as 8080 and
  `":\n8080"` as no port; `#origin=` now raises for a port that isn't only
  digits, including a pct-encoded one, before changing the URI
- `Addressable::Template#partial_expand` now keeps the separators of an
  expression with several variables: e.g. `{a,b}` with both given becomes
  `1,2`, not `12`, and `{#a,b}` becomes `#1,2`, not `#1#2`; variables that
  aren't given stay together in one expression, so `{?a,b,c}` with `b` set
  to `nil` becomes `{?a,c}`, not `{?a}{&c}`, which expanded to `&c=3` with
  no `?`, and `{a,b,c}` becomes `{a,c}`, not `{a}{c}`; a `{#a,b}`
  expression with only `b` set to `2` becomes `#{+a}2`, not `{#a}#2`, so
  the `#` appears once; for a `{a,b}`, `{+a,b}` or `{#a,b}` expression with
  only some of its variables given, the result matches `#expand` if the
  missing variables end up undefined, but has one comma too few for each
  that's defined, since RFC 6570 has no expression for a comma that depends
  on a later variable
- removes `Addressable::URI::RULE_2A`, `RULE_2B_2C`, `RULE_2D` and
  `RULE_PREFIXED_PARENT`, deprecated in 2.9.1; `.normalize_path` hasn't used
  them since then
- `Addressable::URI#freeze` now freezes the strings the URI holds, so a
  frozen URI can't be changed through the strings its getters return:
  before, `uri.host << "x"` on a frozen URI changed its host while `#to_s`
  and `#hash` kept the old values; `#to_s` and `#to_str` of a frozen URI
  still return a mutable string, now a new copy each time, so changing it
  doesn't change the URI; a string passed to `.new` or a setter
  is copied rather than frozen, so the caller's string stays mutable;
  `#clone` of a frozen URI is frozen the same way and `#dup` still gives
  mutable strings; on Ruby 3.0+, `#clone(freeze: true)` of an unfrozen URI
  no longer raises `FrozenError` from its getters; and before Ruby 3.0,
  `#userinfo` no longer returns a frozen string for a URI that isn't frozen
- `Addressable::URI`'s component setters, `.new` and `#merge` now reject
  `false` exactly as they reject `true`, with the same `TypeError` or
  `InvalidURIError`: before, most setters treated `false` as `nil` and
  cleared the component, `.new` ignored it, and `#scheme=` stored it, so
  `uri.scheme = false` turned `http://example.com/` into
  `false://example.com/`; only `nil` now means no component
- a setter on `Addressable::URI` that raises now leaves the URI as it was:
  e.g. `uri.host = nil` on `http://example.com` raised `InvalidURIError` but
  still cleared the host, leaving `uri.to_s` as `http:`; every setter now
  puts back all components when it raises, and so does
  `#defer_validation` when its block or the validation at its end raises,
  so a group of assignments in one `#defer_validation` block takes effect
  together or not at all
- `Addressable::Template#expand` and `#partial_expand` now take values
  from more than a `Hash`: an object with `each_pair`, such as a `Struct`;
  any object that responds to `[]`, such as a lambda, which is called once
  per variable with its name; or a block given in place of the mapping,
  e.g. `template.partial_expand { |name| values.fetch(name) }`; lookups
  follow the `Hash#fetch` convention, so raising `KeyError` means the
  variable is missing, and `#partial_expand` keeps its expression, while
  returning `nil` means it's undefined, and both methods expand it to
  nothing, just as for a `Hash`; an object that responds to `key?` reports
  missing variables with `key?` instead; any other mapping now raises
  `TypeError` instead of `NoMethodError` (#512, #133)
- `Addressable::Template#expand` and `#partial_expand` now treat an empty
  list or associative array, and one with only `nil` members, as
  undefined, and leave out `nil` members, as RFC 6570 says: e.g. `{?list}`
  with `[]` expands to nothing, not `?list=`, and `{/list*}` with
  `["a", nil, "b"]` expands to `/a/b`, not `/a//b` (#611)
- `Addressable::Template#expand` and `#partial_expand` now keep
  pct-encoded triplets in reserved (`{+var}`) and fragment (`{#var}`)
  expansion, as RFC 6570 says: e.g. `{+id}` with `admin%2F` expands to
  `admin%2F`, not `admin%252F`; a `%` that doesn't start a triplet is still
  encoded as `%25`, and a prefix modifier counts a triplet as one character;
  `#extract` still decodes each value once, so it gives `admin/` for that
  expansion, and expanding `admin/` gives `admin/`, a different URI
- `Addressable::Template#expand` and `#partial_expand` now raise
  `Addressable::Template::InvalidTemplateError`, naming the expression and
  its position, for a template that doesn't match the RFC 6570 grammar, as
  RFC 6570 says the error should be indicated: e.g. an unclosed `{/id*`, a
  stray `}`, `{with space}`, `{x..y}` or `{var:0}`, which were kept in the
  result as text; an operator RFC 6570 reserves (`=`, `,`, `!`, `@`, `|`)
  raises `InvalidTemplateOperatorError`, now a subclass of
  `InvalidTemplateError`, where before `{!var}` expanded like `{var}`;
  `.new`, `#match` and `#extract` still accept such templates
- `Addressable::Template#expand` and `#partial_expand` now raise
  `InvalidTemplateValueError` for a prefix modifier on a list or associative
  array, which RFC 6570 says doesn't apply to them: before, `{list:2}` with
  `["red", "green"]` gave `re,gr`, and `{keys:1}` ignored the prefix
- `Addressable::Template#expand` now encodes every `#` after the one that
  starts the fragment as `%23`, since RFC 3986 doesn't allow `#` in a
  fragment: e.g. `x{#var}` with `a#b` expands to `x#a%23b`, not `x#a#b`, and
  `x#a#{var}` to `x#a%23...`; `#match` and `#extract` accept such a `#` either
  as written or encoded; `#partial_expand` returns a template, so it doesn't
  encode a `#` it fills in; `#expand` encodes it when it produces the URI
- `Addressable::Template#expand` and `#partial_expand` now append `=` for a
  list with one empty member in `;` expansion, as RFC 6570 section 3.2.7
  does for any value that isn't empty: e.g. `{;a}` with `[""]` expands to
  `;a=`, not `;a`; an empty string still expands to `;a`
- `Addressable::Template#expand` and `#partial_expand` now leave out the
  `=` for an empty member of an exploded list or associative array in `;`
  expansion, as RFC 6570 says: e.g. `{;a*}` with `["", "y"]` expands to
  `;a;a=y`, not `;a=;a=y`, and with `{"k" => ""}` to `;k`, not `;k=`
- `Addressable::Template#extract` and `#match` now give an exploded list in
  `;`, `?` or `&` expansion as a list: e.g. `{?a*}` on `?a=x&a=y` gives
  `["x", "y"]`, not `{"a" => "y"}`; pairs that all repeat the variable's
  name, as written, are a list, even a single pair (`?a=x` gives `["x"]`, not
  `{"a" => "x"}`), and other pairs are still an associative array; each
  value also keeps everything after its first `=`, so `?a=x=y` gives
  `["x=y"]`, not `{"a" => "x"}`; a processor's `restore` method gets the
  list
- `Addressable::Template#expand` and `#partial_expand` now transcode a
  value in another character encoding to UTF-8 before pct-encoding it, as
  RFC 6570 section 3.2.1 says: e.g. `M\xE9thode` in ISO-8859-1 expands to
  `M%C3%A9thode`; before, its bytes were read as UTF-8, which raised
  `ArgumentError` for most such values; binary and US-ASCII values are read
  as UTF-8 as before
- fixes `Addressable::Template#expand` and `#partial_expand` raising
  `ArgumentError` for a value that isn't valid UTF-8; its bytes are now
  pct-encoded as they are, as `CGI.escape` does, so `"M\xE9thode".b`
  expands to `M%E9thode`, and a value `#extract` gives from `%A4` expands to
  `%A4` again
- fixes `Addressable::Template#match` and `#extract` raising `ArgumentError`
  for a URI that isn't valid UTF-8, such as `"/caf\xFF".b`; they now return
  `nil`, as for any other string that isn't a valid URI
- fixes `Addressable::Template#variables`, `#keys`, `#variable_defaults`,
  `#match`, `#extract`, `#to_regexp` and `#freeze` raising `RegexpError` for
  a variable name that starts with a digit, such as `{42}`, which RFC 6570
  allows; `#to_regexp` names that variable's group with a leading `.`, or
  `__42__` on Ruby 2.3 and earlier, which only allow a letter or `_` as the
  first character of a group name; there, a name that starts with a
  pct-encoded triplet, such as `{%41}`, gets a group like `__%41__` too
- `Addressable::Template#match` and `#extract` now accept non-ASCII text
  in a URI either as written or pct-encoded as UTF-8: e.g. `/{var}` extracts
  `café` from both `/caf%C3%A9` and `/café`, which didn't match before; a
  non-ASCII literal in the template matches either form too, whichever form
  the template uses
- `Addressable::Template#expand` now pct-encodes non-ASCII literal
  characters, as RFC 6570 says: e.g. `café/{var}` expands to
  `caf%C3%A9/value`, not `café/value`; pct-encoded triplets and reserved
  characters in literals are kept; `#match` and `#extract` accept such a
  literal either as written or encoded; `#partial_expand` leaves literals as
  written
- `Addressable::Template#match` and `#extract` now match text in braces that
  isn't an expression as written: e.g. `x{a.*}/{var}` no longer matches
  `x{aZZZ}/value`, and `x{a(}/{var}` no longer raises `RegexpError`
- fixes `Addressable::Template#variables`, `#variable_defaults` and
  `Addressable::Template::MatchData#values` returning the cached array or
  hash: e.g. clearing the array from `#variables` emptied the variables of
  that template, even a frozen one, for every later call; each call now
  returns a copy (#619)
- `Addressable::Template` now only reads a prefix modifier from 1 to 9999
  with no leading zero, as RFC 6570 says; other lengths, such as `{var:0}`,
  `{var:05}` and `{var:10000}`, are malformed expressions, so `#expand` and
  `#partial_expand` raise `InvalidTemplateError` where `{var:10000}` used to
  expand to the whole value, and `#match` reads them as literal text; a
  length too large for a machine integer no longer raises `RangeError` (#618)
- adds an IDNA backend using libidn2 through `ffi`, which follows IDNA2008
  and UTS #46: e.g. `faß.de` converts to `xn--fa-hia.de` rather than
  `fass.de`; it isn't used by default, and can be selected with
  `require "addressable/idna/libidn2"` and
  `Addressable::IDNA.backend = Addressable::IDNA::Libidn2`; `ffi` is now a
  dependency (#496)
- IDNA backends are now the modules `Addressable::IDNA::Libidn1`,
  `Addressable::IDNA::Pure` and `Addressable::IDNA::Libidn2`, and
  `Addressable::IDNA.backend` selects which one `Addressable::IDNA.to_ascii`
  and `.to_unicode` use; their other methods and constants, such as
  `punycode_encode`, are no longer on `Addressable::IDNA`; requiring
  `addressable/idna/native` still selects libidn1, with a deprecation
  warning (#496)
- adds `Addressable::IDNA.strict_mode`, `false` by default: when `true`, a
  hostname label that can't be converted raises `Addressable::IDNA::Error`
  from `Addressable::IDNA`, and `Addressable::URI::InvalidURIError` with the
  IDNA error as its `cause` from `Addressable::URI`, rather than being kept
  unchanged; which labels are rejected depends on the backend: libidn2
  rejects the most (#496)
- `Addressable::IDNA::PunycodeBadInput`, `PunycodeBigOutput` and
  `PunycodeOverflow` now inherit from the new `Addressable::IDNA::Error`
  rather than `StandardError` (#496)
- the pure-Ruby `Addressable::IDNA.to_ascii` no longer raises
  `PunycodeBigOutput` for a label too long to encode, nor
  `Addressable::URI#normalized_host` for such a host; the label is kept
  unchanged, as with libidn, unless `Addressable::IDNA.strict_mode` is on
  (#496)
- the libidn1 `Addressable::IDNA.to_ascii` no longer raises
  `IDN::Idna::IdnaError` for a label libidn can't convert, nor
  `Addressable::URI#normalized_host` for such a host: e.g. `bücher.\u{E000}.de`
  gives `xn--bcher-kva.\u{E000}.de`; the label is kept unchanged and the
  others are still converted, unless `Addressable::IDNA.strict_mode` is on
  (#496)

## Addressable 2.9.2 <a name="v2.9.2">
- fixes `Addressable::URI` returning stale values after a component was
  changed: e.g. after `host=`, `#site`, `#normalized_site`,
  `#normalized_authority` and `#normalize` could still use the old host, and
  after `scheme=`, `#normalized_port` could keep a port that's the new
  scheme's default (#613)
- fixes `Addressable::URI#normalized_query` reusing the result of an earlier
  call with different flags: e.g. after `normalized_query(:sorted)`,
  `normalized_query` and `#normalize` gave a sorted query, and after
  `normalized_query`, `normalized_query(:sorted)` gave an unsorted one (#608)
- fixes `Addressable::Template#expand` and `#partial_expand` changing the
  arrays given as values: e.g. `[1, :a]` became `["1", "a"]`; a frozen array
  raised `FrozenError`, and an object that responds to `to_ary`
  raised `TypeError` (#605)
- fixes `Addressable::URI#clone` sharing component strings with the original:
  e.g. appending to the clone's `#host` also changed the original's host, but
  not its cached normalized values; `#dup` already made a separate copy (#617)
- fixes the pure-Ruby `Addressable::IDNA.to_unicode` raising `ZeroDivisionError`
  on some malformed labels, e.g. `xn--rp3=`, which also made
  `Addressable::URI#display_uri` raise, because the Punycode decoder
  treated punctuation as digits; such labels are now returned unchanged (#614)
- speeds up the pure-Ruby `Addressable::IDNA.to_unicode`, which became up to
  25 times slower in 2.9.1 on long labels with many non-ASCII characters;
  Punycode encoding no longer takes quadratic time (#645)
- fixes the "character class has duplicated range" warnings that 2.9.1 gave
  when `Addressable::IDNA` was loaded with warnings enabled
- fixes the "instance variable @validation_deferred not initialized" warning
  that 2.9.1 gave for every new `Addressable::URI` on Ruby before 3.0 with
  warnings enabled, and a "shadowing outer local variable" warning from
  `Addressable::Template` on Ruby 2.4 and 2.5

## Addressable 2.9.1 <a name="v2.9.1">
- fixes denial of service in `Addressable::URI.normalize_path`, which took
  quadratic time on paths with many dot segments; `URI#normalize`, `#join`,
  `#==` and `#===` were affected (GHSA-qq38-m9mg-xjj5)
- fixes `Addressable::URI.normalize_path` keeping segments that a `..` should
  have removed after a `..` above the root, e.g.
  `/../../public/x/../../secret` normalized to `/public/x/secret` instead of
  `/secret` (GHSA-8gmh-2hhj-2hv9)
- fixes `Addressable::URI.normalize_path` treating a raw line feed as a
  segment boundary, e.g. joining `..\n/secret` onto `/public/` gave
  `/\n/secret`
- deprecates `Addressable::URI::RULE_2A`, `RULE_2B_2C`, `RULE_2D` and
  `RULE_PREFIXED_PARENT`, which are no longer used; they will be removed in
  2.10.0
- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which still backtracked exponentially in 2.9.0 for exploded `/`, `.`, `;`,
  `?` and `&` expressions (e.g. `{/path*}`) on regex engines without match
  memoization, such as JRuby, TruffleRuby and MRI before 3.2; match results
  are unchanged (GHSA-j82w-28jv-3pmj)
- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which backtracked polynomially or exponentially on the same regex engines
  for expressions with several variables (e.g. `{/owner,repo,ref}`, or
  `{+a,b,c}` with many variables), for `;` expressions, and for adjacent
  expressions (e.g. `{+a}{+b}{+c}` or `{+a}{b}`); match results are unchanged
  (GHSA-9f42-57jx-vpp3)
- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which backtracked polynomially for expressions with several exploded
  variables (e.g. `{+a*,b*}`), including on MRI 3.2; match results are
  unchanged (GHSA-4w5q-wg7v-w6gp)
- fixes `Addressable::IDNA.to_unicode` in the pure-Ruby backend decoding
  Punycode labels that aren't valid A-labels: labels that decode to only
  ASCII characters (e.g. `xn--google-` decoded to `google`) and labels that
  don't convert back to themselves; such a label is now returned unchanged,
  as with libidn, so `Addressable::URI#display_uri` no longer shows a host
  that differs from `#normalized_host` (GHSA-9crm-g4mf-wc5j)
- fixes `Addressable::IDNA.to_unicode` decoding Punycode labels with
  characters that change how a host displays without being visible
  themselves, such as bidi overrides and isolates (e.g. U+202E and U+2066),
  zero width characters and control characters; such a label is now
  returned unchanged, so `Addressable::URI#display_uri` no longer shows
  them. The pure-Ruby backend also no longer decodes labels with other
  characters that nameprep prohibits, as with libidn (GHSA-539f-xcgw-2gjg)
- fixes `Addressable::URI#route_from` and `#route_to` raising
  `InvalidURIError` when the route's first segment contains a colon
  (e.g. `/a:b` from `/a`); the route is now `./a:b` ([#625])
- fixes `Addressable::IDNA.to_unicode` raising in the pure-Ruby backend for
  Punycode labels that are too long, overflow the decoder, or decode past
  U+10FFFF; the label is now returned unchanged, as with libidn, so
  `Addressable::URI#display_uri` no longer raises for such hosts ([#620])
- fixes `Addressable::URI#display_uri` raising `InvalidURIError` for URIs
  without a host, such as `abc` or `mailto:user@example.com`; relative URIs
  are also no longer displayed with an empty authority (e.g. `/path/to` was
  displayed as `///path/to`) ([#610])
- fixes `Addressable::Template#match` and `#extract` raising
  `Addressable::URI::InvalidURIError` for a string that isn't a valid URI;
  they now return `nil`, as for any other URI that doesn't match ([#621])
- fixes `Addressable::URI#origin=` raising `InvalidURIError` for an origin
  with an empty port (e.g. `http://example.com:`), which is the same as no
  port ([#627])

[#610]: https://github.com/sporkmonger/addressable/pull/610
[#620]: https://github.com/sporkmonger/addressable/pull/620
[#621]: https://github.com/sporkmonger/addressable/pull/621
[#625]: https://github.com/sporkmonger/addressable/pull/625
[#627]: https://github.com/sporkmonger/addressable/pull/627

## Addressable 2.9.0 <a name="v2.9.0">
- fixes ReDoS vulnerability in Addressable::Template#match (fixes incomplete
  remediation in 2.8.10)

## Addressable 2.8.10 <a name="v2.8.10">
- fixes ReDoS vulnerability in Addressable::Template#match

## Addressable 2.8.9 <a name="v2.8.9">
- Reduce gem size by excluding test files ([#569])
- No need for bundler as development dependency ([#571], [5fc1d93](https://github.com/sporkmonger/addressable/commit/5fc1d93))
- idna/pure: stop building the useless `COMPOSITION_TABLE` (removes the `Addressable::IDNA::COMPOSITION_TABLE` constant) ([#564])

[#569]: https://github.com/sporkmonger/addressable/pull/569
[#571]: https://github.com/sporkmonger/addressable/pull/571
[#564]: https://github.com/sporkmonger/addressable/pull/564

## Addressable 2.8.8 <a name="v2.8.8">
- Replace the `unicode.data` blob by a ruby constant ([#561])
- Allow `public_suffix` 7 ([#558])

[#561]: https://github.com/sporkmonger/addressable/pull/561
[#558]: https://github.com/sporkmonger/addressable/pull/558

## Addressable 2.8.7 <a name="v2.8.7">
- Allow `public_suffix` 6 ([#535])

[#535]: https://github.com/sporkmonger/addressable/pull/535

## Addressable 2.8.6 <a name="v2.8.6">
- Memoize regexps for common character classes ([#524])

[#524]: https://github.com/sporkmonger/addressable/pull/524

## Addressable 2.8.5 <a name="v2.8.5">
- Fix thread safety issue with encoding tables ([#515])
- Define URI::NONE as a module to avoid serialization issues ([#509])
- Fix YAML serialization ([#508])

[#508]: https://github.com/sporkmonger/addressable/pull/508
[#509]: https://github.com/sporkmonger/addressable/pull/509
[#515]: https://github.com/sporkmonger/addressable/pull/515

## Addressable 2.8.4 <a name="v2.8.4">
- Restore `Addressable::IDNA.unicode_normalize_kc` as a deprecated method ([#504])

[#504]: https://github.com/sporkmonger/addressable/pull/504

## Addressable 2.8.3 <a name="v2.8.3">
- Fix template expand level 2 hash support for non-string objects ([#499], [#498])

[#499]: https://github.com/sporkmonger/addressable/pull/499
[#498]: https://github.com/sporkmonger/addressable/pull/498

## Addressable 2.8.2 <a name="v2.8.2">
- Improve cache hits and JIT friendliness ([#486](https://github.com/sporkmonger/addressable/pull/486))
- Improve code style and test coverage ([#482](https://github.com/sporkmonger/addressable/pull/482))
- Ensure reset of deferred validation ([#481](https://github.com/sporkmonger/addressable/pull/481))
- Resolve normalization differences between `IDNA::Native` and `IDNA::Pure` ([#408](https://github.com/sporkmonger/addressable/issues/408), [#492])
- Remove redundant colon in `Addressable::URI::CharacterClasses::AUTHORITY` regex ([#438](https://github.com/sporkmonger/addressable/pull/438)) (accidentally reverted by [#449] merge but [added back](https://github.com/sporkmonger/addressable/pull/492#discussion_r1105125280) in [#492])

[#492]: https://github.com/sporkmonger/addressable/pull/492

## Addressable 2.8.1 <a name="v2.8.1">
- refactor `Addressable::URI.normalize_path` to address linter offenses ([#430](https://github.com/sporkmonger/addressable/pull/430))
- update gemspec to reflect supported Ruby versions ([#466], [#464], [#463])
- compatibility w/ public_suffix 5.x ([#466], [#465], [#460])
- fixes "invalid byte sequence in UTF-8" exception when unencoding URLs containing non UTF-8 characters ([#459](https://github.com/sporkmonger/addressable/pull/459))
- `Ractor` compatibility ([#449])
- use the whole string instead of a single line for template match ([#431](https://github.com/sporkmonger/addressable/pull/431))
- force UTF-8 encoding only if needed ([#341](https://github.com/sporkmonger/addressable/pull/341))

[#449]: https://github.com/sporkmonger/addressable/pull/449
[#460]: https://github.com/sporkmonger/addressable/pull/460
[#463]: https://github.com/sporkmonger/addressable/pull/463
[#464]: https://github.com/sporkmonger/addressable/pull/464
[#465]: https://github.com/sporkmonger/addressable/pull/465
[#466]: https://github.com/sporkmonger/addressable/pull/466

## Addressable 2.8.0 <a name="v2.8.0">
- fixes ReDoS vulnerability in Addressable::Template#match
- no longer replaces `+` with spaces in queries for non-http(s) schemes
- fixed encoding ipv6 literals
- the `:compacted` flag for `normalized_query` now dedupes parameters
- fix broken `escape_component` alias
- dropping support for Ruby 2.0 and 2.1
- adding Ruby 3.0 compatibility for development tasks
- drop support for `rack-mount` and remove Addressable::Template#generate
- performance improvements
- switch CI/CD to GitHub Actions

## Addressable 2.7.0 <a name="v2.7.0">
- added `:compacted` flag to `normalized_query`
- `heuristic_parse` handles `mailto:` more intuitively
- dropped explicit support for JRuby 9.0.5.0
- compatibility w/ public_suffix 4.x
- performance improvements

## Addressable 2.6.0 <a name="v2.6.0">
- added `tld=` method to allow assignment to the public suffix
- most `heuristic_parse` patterns are now case-insensitive
- `heuristic_parse` handles more `file://` URI variations
- fixes bug in `heuristic_parse` when uri starts with digit
- fixes bug in `request_uri=` with query strings
- fixes template issues with `nil` and `?` operator
- `frozen_string_literal` pragmas added
- minor performance improvements in regexps
- fixes to eliminate warnings

## Addressable 2.5.2 <a name="v2.5.2">
- better support for frozen string literals
- fixed bug w/ uppercase characters in scheme
- IDNA errors w/ emoji URLs
- compatibility w/ public_suffix 3.x

## Addressable 2.5.1 <a name="v2.5.1">
- allow unicode normalization to be disabled for URI Template expansion
- removed duplicate test

## Addressable 2.5.0 <a name="v2.5.0">
- dropping support for Ruby 1.9
- adding support for Ruby 2.4 preview
- add support for public suffixes and tld; first runtime dependency
- hostname escaping should match RFC; underscores in hostnames no longer escaped
- paths beginning with // and missing an authority are now considered invalid
- validation now also takes place after setting a path
- handle backslashes in authority more like a browser for `heuristic_parse`
- unescaped backslashes in host now raise an `InvalidURIError`
- `merge!`, `join!`, `omit!` and `normalize!` don't disable deferred validation
- `heuristic_parse` now trims whitespace before parsing
- host parts longer than 63 bytes will be ignored and not passed to libidn
- normalized values always encoded as UTF-8

## Addressable 2.4.0 <a name="v2.4.0">
- support for 1.8.x dropped
- double quotes in a host now raises an error
- newlines in host will no longer get unescaped during normalization
- stricter handling of bogus scheme values
- stricter handling of encoded port values
- calling `require 'addressable'` will now load both the URI and Template files
- assigning to the `hostname` component with an `IPAddr` object is now supported
- assigning to the `origin` component is now supported
- fixed minor bug where an exception would be thrown for a missing ACE suffix
- better partial expansion of URI templates

## Addressable 2.3.8 <a name="v2.3.8">
- fix warnings
- update dependency gems
- support for 1.8.x officially deprecated

## Addressable 2.3.7 <a name="v2.3.7">
- fix scenario in which invalid URIs don't get an exception until inspected
- handle hostnames with two adjacent periods correctly
- upgrade of RSpec

## Addressable 2.3.6 <a name="v2.3.6">
- normalization drops empty query string
- better handling in template extract for missing values
- template modifier for `'?'` now treated as optional
- fixed issue where character class parameters were modified
- templates can now be tested for equality
- added `:sorted` option to normalization of query strings
- fixed issue with normalization of hosts given in `'example.com.'` form

## Addressable 2.3.5 <a name="v2.3.5">
- added Addressable::URI#empty? method
- Addressable::URI#hostname methods now strip square brackets from IPv6 hosts
- compatibility with Net::HTTP in Ruby 2.0.0
- Addressable::URI#route_from should always give relative URIs

## Addressable 2.3.4 <a name="v2.3.4">
- fixed issue with encoding altering its inputs
- query string normalization now leaves ';' characters alone
- FakeFS is detected before attempting to load unicode tables
- additional testing to ensure frozen objects don't cause problems

## Addressable 2.3.3 <a name="v2.3.3">
- fixed issue with converting common primitives during template expansion
- fixed port encoding issue
- removed a few warnings
- normalize should now ignore %2B in query strings
- the IDNA logic should now be handled by libidn in Ruby 1.9
- no template match should now result in nil instead of an empty MatchData
- added license information to gemspec

## Addressable 2.3.2 <a name="v2.3.2">
- added Addressable::URI#default_port method
- fixed issue with Marshalling Unicode data on Windows
- improved heuristic parsing to better handle IPv4 addresses

## Addressable 2.3.1 <a name="v2.3.1">
- fixed missing unicode data file

## Addressable 2.3.0 <a name="v2.3.0">
- updated Addressable::Template to use RFC 6570, level 4
- fixed compatibility problems with some versions of Ruby
- moved unicode tables into a data file for performance reasons
- removing support for multiple query value notations

## Addressable 2.2.8 <a name="v2.2.8">
- fixed issues with dot segment removal code
- form encoding can now handle multiple values per key
- updated development environment

## Addressable 2.2.7 <a name="v2.2.7">
- fixed issues related to Addressable::URI#query_values=
- the Addressable::URI.parse method is now polymorphic

## Addressable 2.2.6 <a name="v2.2.6">
- changed the way ambiguous paths are handled
- fixed bug with frozen URIs
- https supported in heuristic parsing

## Addressable 2.2.5 <a name="v2.2.5">
- 'parsing' a pre-parsed URI object is now a dup operation
- introduced conditional support for libidn
- fixed normalization issue on ampersands in query strings
- added additional tests around handling of query strings

## Addressable 2.2.4 <a name="v2.2.4">
- added origin support from draft-ietf-websec-origin-00
- resolved issue with attempting to navigate below root
- fixed bug with string splitting in query strings

## Addressable 2.2.3 <a name="v2.2.3">
- added :flat_array notation for query strings

## Addressable 2.2.2 <a name="v2.2.2">
- fixed issue with percent escaping of '+' character in query strings

## Addressable 2.2.1 <a name="v2.2.1">
- added support for application/x-www-form-urlencoded.

## Addressable 2.2.0 <a name="v2.2.0">
- added site methods
- improved documentation

## Addressable 2.1.2 <a name="v2.1.2">
- added HTTP request URI methods
- better handling of Windows file paths
- validation_deferred boolean replaced with defer_validation block
- normalization of percent-encoded paths should now be correct
- fixed issue with constructing URIs with relative paths
- fixed warnings

## Addressable 2.1.1 <a name="v2.1.1">
- more type checking changes
- fixed issue with unicode normalization
- added method to find template defaults
- symbolic keys are now allowed in template mappings
- numeric values and symbolic values are now allowed in template mappings

## Addressable 2.1.0 <a name="v2.1.0x">
- refactored URI template support out into its own class
- removed extract method due to being useless and unreliable
- removed Addressable::URI.expand_template
- removed Addressable::URI#extract_mapping
- added partial template expansion
- fixed minor bugs in the parse and heuristic_parse methods
- fixed incompatibility with Ruby 1.9.1
- fixed bottleneck in Addressable::URI#hash and Addressable::URI#to_s
- fixed unicode normalization exception
- updated query_values methods to better handle subscript notation
- worked around issue with freezing URIs
- improved specs

## Addressable 2.0.2 <a name="v2.0.2">
- fixed issue with URI template expansion
- fixed issue with percent escaping characters 0-15

## Addressable 2.0.1 <a name="v2.0.1">
- fixed issue with query string assignment
- fixed issue with improperly encoded components

## Addressable 2.0.0 <a name="v2.0.0">
- the initialize method now takes an options hash as its only parameter
- added query_values method to URI class
- completely replaced IDNA implementation with pure Ruby
- renamed Addressable::ADDRESSABLE_VERSION to Addressable::VERSION
- completely reworked the Rakefile
- changed the behavior of the port method significantly
- Addressable::URI.encode_segment, Addressable::URI.unencode_segment renamed
- documentation is now in YARD format
- more rigorous type checking
- to_str method implemented, implicit conversion to Strings now allowed
- Addressable::URI#omit method added, Addressable::URI#merge method replaced
- updated URI Template code to match v 03 of the draft spec
- added a bunch of new specifications

## Addressable 1.0.4 <a name="v1.0.4">
- switched to using RSpec's pending system for specs that rely on IDN
- fixed issue with creating URIs with paths that are not prefixed with '/'

## Addressable 1.0.3 <a name="v1.0.3">
- implemented a hash method

## Addressable 1.0.2 <a name="v1.0.2">
- fixed minor bug with the extract_mapping method

## Addressable 1.0.1 <a name="v1.0.1">
- fixed minor bug with the extract_mapping method

## Addressable 1.0.0 <a name="v1.0.0">
- heuristic parse method added
- parsing is slightly more strict
- replaced to_h with to_hash
- fixed routing methods
- improved specifications
- improved heckle rake task
- no surviving heckle mutations

## Addressable 0.1.2 <a name="v0.1.2">
- improved normalization
- fixed bug in joining algorithm
- updated specifications

## Addressable 0.1.1 <a name="v0.1.1">
- updated documentation
- added URI Template variable extraction

## Addressable 0.1.0 <a name="v0.1.0">
- initial release
- implementation based on RFC 3986, 3987
- support for IRIs via libidn
- support for the URI Template draft spec
