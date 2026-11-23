# Changelog

## Addressable 2.10.0 <a name="v2.10.0">

### Breaking changes

- Ruby 3.2 and earlier and JRuby 9.4 are no longer supported, and loading Addressable on them gives a deprecation warning when deprecation warnings are turned on, as with `-W:deprecated` ([#706])
- `Addressable::URI::RULE_2A`, `RULE_2B_2C`, `RULE_2D` and `RULE_PREFIXED_PARENT`, deprecated in 2.9.1, are removed ([#669])
- `Addressable::URI` setters, `.new` and `#merge` raise for `false` instead of treating it as `nil` ([#667])
- `Addressable::URI#port=` and `.new` raise `InvalidURIError` for a port with a line break, such as `"8080\nx"` ([#663])
- `Addressable::URI` setters, `.new` and `.parse` raise `InvalidURIError` for a port above 65535 in a URI whose scheme has a default port, such as `http://example.com:70000/`, and for a port above the largest integer Ruby stores without a bignum, 2**62 - 1 on 64-bit platforms, in any URI ([#711])
- `Addressable::URI#origin=` raises `InvalidURIError` for a string with a path, query or fragment, which it dropped, and for one with userinfo that has a colon, from which it took the host: `https://user:pass@example.com` raises instead of setting the host to `user` ([#616], [GHSA-cwmp-x65r-27fv])
- `Addressable::URI.parse`, `.new` and the host setters raise `InvalidURIError` for brackets in a host that don't enclose an IPv6 address or IPvFuture literal, such as `http://[127.0.0.1]/` or `http://example[.]com/`, which they accepted ([GHSA-c7j3-jq7p-v3pr])
- `Addressable::URI#host=`, `#authority=`, `.new` and `.parse` raise `InvalidURIError` for a colon in a host outside the brackets of an IP literal, such as `example.com:8080` or `http://a:b:80/`, which they accepted ([GHSA-w5p3-7836-69vh])
- `Addressable::URI#user=`, `#password=`, `#userinfo=`, `#authority=`, `.new` and `.parse` raise `InvalidURIError` for `/`, `?`, `#`, `[`, `]` or `\` in the user or password, or `:` in the user, which they accepted: `uri.password = "#secret"` raises, and a password with these characters has to be pct-encoded first ([GHSA-qrq6-rcpx-pmm6])
- The strings a frozen `Addressable::URI` holds are frozen, so changing one, as in `uri.host << "x"`, raises `FrozenError` ([#668])
- `Addressable::Template#expand`, `#partial_expand`, `#match`, `#extract` and `#to_regexp` raise `InvalidTemplateError` for a template that doesn't match the RFC 6570 grammar, which expansion kept as text and matching read as literal text ([#660], [#693], [#697])
- `Addressable::Template` reads a prefix modifier outside 1 to 9999 or with a leading zero, such as `{var:0}`, `{var:05}` or `{var:10000}`, as malformed: `#expand`, `#partial_expand`, `#match`, `#extract` and `#to_regexp` raise `InvalidTemplateError` where they used to expand or match it, and `#variables` ignores the expression ([#618], [#693], [#697])
- `Addressable::Template` reads the operators RFC 6570 reserves, `=`, `,`, `!`, `@` and `|`, as malformed: `#expand`, `#partial_expand`, `#match`, `#extract` and `#to_regexp` raise `InvalidTemplateOperatorError` where expansion used to treat `{!var}` like `{var}`, and `#variables` ignores the expression ([#660], [#693], [#697])
- `Addressable::Template#expand` and `#partial_expand` raise `InvalidTemplateValueError` for a prefix modifier on a list or associative array ([#660])
- With the native backend, `Addressable::IDNA.punycode_encode` and `.punycode_decode` raise `IDN::Punycode::PunycodeError` for a string with a NUL, where they converted only the text before it: `punycode_encode("a\u0000b")` gave `"a-"` ([GHSA-mrrj-5mhw-rcf2])
- The pure-Ruby `Addressable::IDNA.to_ascii` raises `Addressable::IDNA::InvalidLabel` for a label that breaks the bidi rule of RFC 3454, such as `exampleא`, where it returned an A-label, as `idn-ruby` raises `IDN::Idna::IdnaError`; `Addressable::URI#normalize` keeps such a host pct-encoded: `http://example%D7%90.test/` gives itself, not `http://xn--example-c5i.test/` ([GHSA-fccw-gx6q-mh6c])
- `Addressable::Template#match` and `#extract` only read a pair in a `;`, `?` or `&` expression as the pair of a variable that isn't exploded when the name is one of the expression's variables, and only as many times as the expression has the name, and otherwise don't match: `{?q}` on `?admin=true` gives `nil`, not `{"q" => nil, "admin" => "true"}` ([GHSA-q5vw-6v74-fg2g])
- A processor's `match` pattern for a `;`, `?` or `&` variable that isn't exploded matches only the variable's value, as documented, so `Addressable::Template#match` and `#extract` no longer match a pattern that includes the name, such as `page=\d+` ([GHSA-q5vw-6v74-fg2g])
- The pure-Ruby `Addressable::IDNA.to_ascii` raises `Addressable::IDNA::InvalidLabel` for a label made only of characters nameprep maps to nothing, such as U+200B ZERO WIDTH SPACE in `"\u200B.example"`, where it returned an A-label, as `idn-ruby` raises `IDN::Idna::IdnaError` ([#703], [#714])

### Changed output

- `Addressable::URI#normalize`, `#==`, `#===`, `.normalized_encode`, the pure-Ruby `Addressable::IDNA.to_ascii` and `Addressable::Template#expand`, `#match` and `#extract` leave a run of more than 30 combining marks as it is instead of normalizing it, so they take linear time on any Ruby: `e` followed by 31 U+0301 keeps the `e` and all 31 marks, not `é` and 30 ([GHSA-v6hg-69pc-4f3f])
- `Addressable::URI.heuristic_parse("localhost:3000")` gives `http://localhost:3000`, not `localhost:3000` with a `localhost` scheme ([#691])
- `Addressable::URI#route_from` and `#route_to` give `./`, not `../`, for a route that would climb above the root ([#648])
- `Addressable::URI#query_values` reads `+` as a space in query names too, and for uppercase `HTTP` and `HTTPS`: `?a+b=c` gives `{"a b" => "c"}`, not `{"a+b" => "c"}` ([#607])
- `Addressable::URI#request_uri` percent-encodes control characters and spaces: `/a b?q=1` gives `/a%20b?q=1`, not `/a b?q=1` ([GHSA-qg8x-qm93-fw27])
- `Addressable::URI#normalize` and `.normalized_encode` keep U+037E GREEK QUESTION MARK pct-encoded instead of turning it into a `;` delimiter: `/a%CD%BEb` gives `/a%CD%BEb`, not `/a;b` ([#712])
- `Addressable::URI#normalize` keeps U+037E GREEK QUESTION MARK in a query: `?a=%CD%BE` gives `?a=%CD%BE`, not `?a=%3B` ([#712])
- `Addressable::Template#expand` treats an empty list or associative array as undefined and leaves out `nil` members: `{?list}` with `[]` gives nothing, not `?list=` ([#611])
- `Addressable::Template#expand` keeps pct-encoded triplets in reserved and fragment expansion: `{+id}` with `admin%2F` gives `admin%2F`, not `admin%252F` ([#656])
- `Addressable::Template#expand` gives `;a=`, not `;a`, for `{;a}` with `[""]` ([#689])
- `Addressable::Template#expand` gives `;a;a=y`, not `;a=;a=y`, for `{;a*}` with `["", "y"]` ([#688])
- `Addressable::Template#expand` pct-encodes non-ASCII literals: `café/{var}` gives `caf%C3%A9/value`, not `café/value` ([#676])
- `Addressable::Template#match` and `#extract` read a label value that contains `.` when the expression is set off by delimiters: `/f{.ext}` on `/f.tar.gz` gives `{"ext" => "tar.gz"}`, not `nil`, so code that tries several templates may pick a different one ([#692])
- `Addressable::Template#match` and `#extract` keep the empty members of an exploded value: `{/segments*}` on `/a/b/` gives `{"segments" => ["a", "b", ""]}`, not `{"segments" => ["a", "b"]}`, and on `/` gives `{"segments" => [""]}`, not `{"segments" => []}` ([#700])
- `Addressable::Template#match` and `#extract` give a variable that's repeated in an expression its first value: `{+v1,v2,v1}` on `a,b,c` gives `{"v1" => "a", "v2" => "b"}`, not `{"v1" => "", "v2" => "a"}` ([GHSA-xj9m-f88p-5j38])
- `Addressable::Template#match` and `#extract` give a value that more than one variable of a `/`, `.`, `+`, `#` or default expression could take to the first of them, leaving a later variable undefined when nothing is left for it: `{/a,b*}` on `/x/y/z` gives `{"a" => "x", "b" => ["y", "z"]}`, not `{"a" => "", "b" => ["x", "y", "z"]}` ([#715])
- The pure-Ruby `Addressable::IDNA.to_ascii` and `.to_unicode` keep trailing empty labels, as `idn-ruby` does: `bücher.example.` gives `xn--bcher-kva.example.`, not `xn--bcher-kva.example` ([#609])
- The pure-Ruby `Addressable::IDNA.to_ascii` treats U+3002 and U+FF61 as label separators, as `idn-ruby` does: `bücher。example` gives `xn--bcher-kva.example`, not `xn--bcherexample-dlb0569n` ([GHSA-x378-rg7m-2c49])
- `Addressable::IDNA.to_unicode` and `Addressable::URI#display_uri` leave an A-label as it is when it decodes to ASCII other than letters, digits and hyphens, or starts or ends with a hyphen: `xn--mn,chen-n2a` gives `xn--mn,chen-n2a`, not `mün,chen` ([#716])

### `Addressable::URI`

- Fix `#normalize`, `#normalized_host`, `#origin` and `#==` turning a pct-encoded or fullwidth colon in the host into the port delimiter: `http://example.com%3A8080/` normalizes to itself, not `http://example.com:8080/` ([GHSA-w5p3-7836-69vh])
- Fix `#normalize` and `#normalized_host` decoding a host twice: `http://127%252E0%252E0%252E1/` normalizes to `http://127%252e0%252e0%252e1/`, not `http://127.0.0.1/` ([GHSA-w5p3-7836-69vh])
- Lowercase the letters that decoding a host gives in `#normalize`, `#normalized_host`, `#origin` and `#==`: `http://%49NTERNAL.example/` normalizes to `http://internal.example/`, not `http://Internal.example/` ([GHSA-w5p3-7836-69vh])
- Fix `#normalize`, `#normalized_host` and `#origin` treating a dot before a pct-encoded line break in the host as a trailing dot: `http://localhost.%0A/` normalizes to itself, not `http://localhost./` ([GHSA-w5p3-7836-69vh])
- Fix `#route_from` and `#route_to` giving routes that don't resolve to the target ([#623], [#648])
- Fix `#userinfo=` splitting the user from the password at the last colon instead of the first ([#606])
- Fix `.normalized_encode` decoding pct-encoded delimiters, such as `%2F` in the path and `%26` in the query ([#589])
- Fix `#normalize` decoding `%3D` in a query name ([#589])
- Fix `#normalize` decoding a triplet in a query twice, such as `%252B` to `%2B` ([#589])
- Encode a colon in a relative path's first segment as `%3A` instead of `%2F` ([#675])
- Fix `#normalize` raising `InvalidURIError` for a colon left in a relative path's first segment ([#550], [#589])
- Keep an IPv6 host in brackets whole in `#origin=` ([#616])
- Leave a URI unchanged when a setter or `#defer_validation` raises ([#666])
- Fix `#normalized_host`, `#normalize`, `#display_uri` and `#freeze` raising `ArgumentError` for a host whose pct-encoded bytes aren't valid UTF-8; they stay pct-encoded: `http://a%a9b/` normalizes to `http://a%A9b/` ([#701])
- Fix `#normalized_host`, `#normalize`, `#display_uri` and `#===` raising the IDNA backend's error for a host it can't convert to a domain name; the host stays pct-encoded: with `idn-ruby`, `http://a%EF%BF%BD.example/` normalizes to itself instead of raising `IDN::Idna::IdnaError` ([#714])
- Fix `#display_uri` showing a different name for a host whose A-label has a pct-encoded character: `http://xn--mn%3Fchen-n2a.example/` displays as itself, not as `http://mn%ã3Fchen.example/` ([#716])
- Fix `#normalize` decoding a pct-encoded bracket in a registered name: `http://a%5Db.example/` gives `http://a%5Db.example/`, not `http://a]b.example/` ([GHSA-c7j3-jq7p-v3pr])
- Speed up `.unencode` on TruffleRuby for a long run of pct-encoded bytes that aren't ASCII ([#720])

### `Addressable::Template`

- Give equal templates the same `#hash` ([#604])
- Keep the separators of an expression with several variables in `#partial_expand` ([#670], [#690])
- Take values from any object with `each_pair` or `[]`, or from a block, in `#expand` and `#partial_expand` ([#512], [#133])
- Encode a `#` after the one that starts the fragment as `%23` ([#679])
- Transcode values to UTF-8, and handle text that isn't valid UTF-8 instead of raising `ArgumentError` ([#686])
- Allow variable names that start with a digit, such as `{42}` ([#684])
- Match non-ASCII text in a URI either as written or pct-encoded ([#680])
- Return copies from `#variables`, `#variable_defaults` and `MatchData#values` ([#619])
- Split an exploded value of the default, `+` and `#` operators into its members in `#match` and `#extract`: `{a*,b}` on `x,y,z` gives `{"a" => ["x", "y", "z"], "b" => nil}`, not `{"a" => ["x,y,"], "b" => "z"}` ([#700], [#715])
- Build the regexp for a template in linear time when it has non-ASCII literal text or a long run of expressions with no literal text between them ([GHSA-h78h-gj97-g737])
- Match a URI in linear time on Rubies that don't memoize regexps (MRI before 3.3, JRuby, TruffleRuby), except for some templates that combine an exploded variable, or several variables in one expression, with other expressions, and where a processor gives a variable its own pattern ([GHSA-grhv-8jgq-r74x], [GHSA-jrfq-gw62-2f3j], [GHSA-xfg6-27c4-wr4r], [GHSA-xj9m-f88p-5j38])
- Fix `#match` and `#extract` giving a `nil` key for an empty member of an exploded `?` or `&` variable: `{?a*,b,c*}` on `?&==` gives `{"a" => nil, "b" => nil, "c" => {"" => "="}}`, not `{"a" => nil, "b" => nil, nil => "", "c" => {nil => ""}}` ([GHSA-xfg6-27c4-wr4r])
- Keep everything after the first `=` of each pair in an exploded `;`, `?` or `&` value in `#match` and `#extract`: `{?a*}` on `?k=x=y` gives `{"a" => {"k" => "x=y"}}`, not `{"a" => {"k" => "x"}}` ([#687])
- Give a pair with the name of a variable that isn't exploded to that variable in `#match` and `#extract`, wherever it is in a `;`, `?` or `&` expression: `{?q,list*}` on `?page=1&q=cat` gives `{"q" => "cat", "list" => {"page" => "1"}}`, not `{"q" => nil, "page" => "1", "list" => {"q" => "cat"}}` ([GHSA-q5vw-6v74-fg2g])

### `Addressable::IDNA`

- Fix `.to_ascii` and `.to_unicode` in the native backend dropping the rest of a label after a NUL, so `http://internal.example%00x/` no longer normalizes to `http://internal.example/` ([GHSA-mrrj-5mhw-rcf2])
- Fix `.to_unicode` decoding a label to one with a label separator, such as `xn--victimexample-882l` to `victim。example` ([GHSA-x378-rg7m-2c49])
- Fix the pure-Ruby `.to_unicode` decoding a label that breaks the bidi rule of RFC 3454, such as `xn--example-c5i` to `exampleא`, which `idn-ruby` leaves unchanged ([GHSA-fccw-gx6q-mh6c])
- Remove the characters nameprep maps to nothing, such as a zero width joiner, in the pure-Ruby `.to_ascii`, as `idn-ruby` does ([#703])
- Fix the native `.to_ascii` and `.to_unicode` crashing the process for a string that isn't tagged as UTF-8 and has bytes that aren't valid UTF-8, such as `"caf\xE9.example".b`; they raise `ArgumentError`, as they do for a UTF-8 string ([#710])

[#133]: https://github.com/sporkmonger/addressable/pull/133
[#512]: https://github.com/sporkmonger/addressable/pull/512
[#550]: https://github.com/sporkmonger/addressable/pull/550
[#589]: https://github.com/sporkmonger/addressable/pull/589
[#604]: https://github.com/sporkmonger/addressable/pull/604
[#606]: https://github.com/sporkmonger/addressable/pull/606
[#607]: https://github.com/sporkmonger/addressable/pull/607
[#609]: https://github.com/sporkmonger/addressable/pull/609
[#611]: https://github.com/sporkmonger/addressable/pull/611
[#616]: https://github.com/sporkmonger/addressable/pull/616
[#618]: https://github.com/sporkmonger/addressable/pull/618
[#619]: https://github.com/sporkmonger/addressable/pull/619
[#623]: https://github.com/sporkmonger/addressable/pull/623
[#648]: https://github.com/sporkmonger/addressable/pull/648
[#656]: https://github.com/sporkmonger/addressable/pull/656
[#660]: https://github.com/sporkmonger/addressable/pull/660
[#663]: https://github.com/sporkmonger/addressable/pull/663
[#666]: https://github.com/sporkmonger/addressable/pull/666
[#667]: https://github.com/sporkmonger/addressable/pull/667
[#668]: https://github.com/sporkmonger/addressable/pull/668
[#669]: https://github.com/sporkmonger/addressable/pull/669
[#670]: https://github.com/sporkmonger/addressable/pull/670
[#675]: https://github.com/sporkmonger/addressable/pull/675
[#676]: https://github.com/sporkmonger/addressable/pull/676
[#679]: https://github.com/sporkmonger/addressable/pull/679
[#680]: https://github.com/sporkmonger/addressable/pull/680
[#684]: https://github.com/sporkmonger/addressable/pull/684
[#686]: https://github.com/sporkmonger/addressable/pull/686
[#687]: https://github.com/sporkmonger/addressable/pull/687
[#688]: https://github.com/sporkmonger/addressable/pull/688
[#689]: https://github.com/sporkmonger/addressable/pull/689
[#690]: https://github.com/sporkmonger/addressable/pull/690
[#691]: https://github.com/sporkmonger/addressable/pull/691
[#692]: https://github.com/sporkmonger/addressable/pull/692
[#693]: https://github.com/sporkmonger/addressable/pull/693
[#697]: https://github.com/sporkmonger/addressable/pull/697
[#700]: https://github.com/sporkmonger/addressable/pull/700
[#701]: https://github.com/sporkmonger/addressable/pull/701
[#703]: https://github.com/sporkmonger/addressable/pull/703
[#706]: https://github.com/sporkmonger/addressable/pull/706
[#710]: https://github.com/sporkmonger/addressable/pull/710
[#711]: https://github.com/sporkmonger/addressable/pull/711
[#712]: https://github.com/sporkmonger/addressable/pull/712
[#714]: https://github.com/sporkmonger/addressable/pull/714
[#715]: https://github.com/sporkmonger/addressable/pull/715
[#716]: https://github.com/sporkmonger/addressable/pull/716
[#720]: https://github.com/sporkmonger/addressable/pull/720
[GHSA-c7j3-jq7p-v3pr]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-c7j3-jq7p-v3pr
[GHSA-cwmp-x65r-27fv]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-cwmp-x65r-27fv
[GHSA-fccw-gx6q-mh6c]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-fccw-gx6q-mh6c
[GHSA-grhv-8jgq-r74x]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-grhv-8jgq-r74x
[GHSA-h78h-gj97-g737]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-h78h-gj97-g737
[GHSA-jrfq-gw62-2f3j]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-jrfq-gw62-2f3j
[GHSA-mrrj-5mhw-rcf2]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-mrrj-5mhw-rcf2
[GHSA-q5vw-6v74-fg2g]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-q5vw-6v74-fg2g
[GHSA-qg8x-qm93-fw27]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-qg8x-qm93-fw27
[GHSA-qrq6-rcpx-pmm6]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-qrq6-rcpx-pmm6
[GHSA-v6hg-69pc-4f3f]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-v6hg-69pc-4f3f
[GHSA-w5p3-7836-69vh]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-w5p3-7836-69vh
[GHSA-x378-rg7m-2c49]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-x378-rg7m-2c49
[GHSA-xfg6-27c4-wr4r]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-xfg6-27c4-wr4r
[GHSA-xj9m-f88p-5j38]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-xj9m-f88p-5j38

## Addressable 2.9.2 <a name="v2.9.2">

### `Addressable::URI`

- fixes `Addressable::URI` returning stale values after a component was
  changed: e.g. after `host=`, `#site`, `#normalized_site`,
  `#normalized_authority` and `#normalize` could still use the old host, and
  after `scheme=`, `#normalized_port` could keep a port that's the new
  scheme's default ([#613])
- fixes `Addressable::URI#normalized_query` reusing the result of an earlier
  call with different flags: e.g. after `normalized_query(:sorted)`,
  `normalized_query` and `#normalize` gave a sorted query, and after
  `normalized_query`, `normalized_query(:sorted)` gave an unsorted one ([#608])
- fixes `Addressable::URI#clone` sharing component strings with the original:
  e.g. appending to the clone's `#host` also changed the original's host, but
  not its cached normalized values; `#dup` already made a separate copy ([#617])
- fixes the "instance variable @validation_deferred not initialized" warning
  that 2.9.1 gave for every new `Addressable::URI` on Ruby before 3.0 with
  warnings enabled, and a "shadowing outer local variable" warning from
  `Addressable::Template` on Ruby 2.4 and 2.5 ([#637])

### `Addressable::Template`

- fixes `Addressable::Template#expand` and `#partial_expand` changing the
  arrays given as values: e.g. `[1, :a]` became `["1", "a"]`; a frozen array
  raised `FrozenError`, and an object that responds to `to_ary`
  raised `TypeError` ([#605])

### `Addressable::IDNA`

- fixes the pure-Ruby `Addressable::IDNA.to_unicode` raising `ZeroDivisionError`
  on some malformed labels, e.g. `xn--rp3=`, which also made
  `Addressable::URI#display_uri` raise, because the Punycode decoder
  treated punctuation as digits; such labels are now returned unchanged ([#614])
- speeds up the pure-Ruby `Addressable::IDNA.to_unicode`, which became up to
  25 times slower in 2.9.1 on long labels with many non-ASCII characters;
  Punycode encoding no longer takes quadratic time ([#645])
- fixes the "character class has duplicated range" warnings that 2.9.1 gave
  when `Addressable::IDNA` was loaded with warnings enabled ([#636])

[#605]: https://github.com/sporkmonger/addressable/pull/605
[#608]: https://github.com/sporkmonger/addressable/pull/608
[#613]: https://github.com/sporkmonger/addressable/pull/613
[#614]: https://github.com/sporkmonger/addressable/pull/614
[#617]: https://github.com/sporkmonger/addressable/pull/617
[#636]: https://github.com/sporkmonger/addressable/pull/636
[#637]: https://github.com/sporkmonger/addressable/pull/637
[#645]: https://github.com/sporkmonger/addressable/pull/645

## Addressable 2.9.1 <a name="v2.9.1">

### `Addressable::URI`

- fixes denial of service in `Addressable::URI.normalize_path`, which took
  quadratic time on paths with many dot segments; `URI#normalize`, `#join`,
  `#==` and `#===` were affected ([GHSA-qq38-m9mg-xjj5])
- fixes `Addressable::URI.normalize_path` keeping segments that a `..` should
  have removed after a `..` above the root, e.g.
  `/../../public/x/../../secret` normalized to `/public/x/secret` instead of
  `/secret` ([GHSA-8gmh-2hhj-2hv9])
- fixes `Addressable::URI.normalize_path` treating a raw line feed as a
  segment boundary, e.g. joining `..\n/secret` onto `/public/` gave
  `/\n/secret`
- deprecates `Addressable::URI::RULE_2A`, `RULE_2B_2C`, `RULE_2D` and
  `RULE_PREFIXED_PARENT`, which are no longer used; they will be removed in
  2.10.0
- fixes `Addressable::URI#route_from` and `#route_to` raising
  `InvalidURIError` when the route's first segment contains a colon
  (e.g. `/a:b` from `/a`); the route is now `./a:b` ([#625])
- fixes `Addressable::URI#display_uri` raising `InvalidURIError` for URIs
  without a host, such as `abc` or `mailto:user@example.com`; relative URIs
  are also no longer displayed with an empty authority (e.g. `/path/to` was
  displayed as `///path/to`) ([#610])
- fixes `Addressable::URI#origin=` raising `InvalidURIError` for an origin
  with an empty port (e.g. `http://example.com:`), which is the same as no
  port ([#627])

### `Addressable::Template`

- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which still backtracked exponentially in 2.9.0 for exploded `/`, `.`, `;`,
  `?` and `&` expressions (e.g. `{/path*}`) on regex engines without match
  memoization, such as JRuby, TruffleRuby and MRI before 3.2; match results
  are unchanged ([GHSA-j82w-28jv-3pmj])
- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which backtracked polynomially or exponentially on the same regex engines
  for expressions with several variables (e.g. `{/owner,repo,ref}`, or
  `{+a,b,c}` with many variables), for `;` expressions, and for adjacent
  expressions (e.g. `{+a}{+b}{+c}` or `{+a}{b}`); match results are unchanged
  ([GHSA-9f42-57jx-vpp3])
- fixes denial of service in `Addressable::Template#match` and `#extract`,
  which backtracked polynomially for expressions with several exploded
  variables (e.g. `{+a*,b*}`), including on MRI 3.2; match results are
  unchanged ([GHSA-4w5q-wg7v-w6gp])
- fixes `Addressable::Template#match` and `#extract` raising
  `Addressable::URI::InvalidURIError` for a string that isn't a valid URI;
  they now return `nil`, as for any other URI that doesn't match ([#621])

### `Addressable::IDNA`

- fixes `Addressable::IDNA.to_unicode` in the pure-Ruby backend decoding
  Punycode labels that aren't valid A-labels: labels that decode to only
  ASCII characters (e.g. `xn--google-` decoded to `google`) and labels that
  don't convert back to themselves; such a label is now returned unchanged,
  as with libidn, so `Addressable::URI#display_uri` no longer shows a host
  that differs from `#normalized_host` ([GHSA-9crm-g4mf-wc5j])
- fixes `Addressable::IDNA.to_unicode` decoding Punycode labels with
  characters that change how a host displays without being visible
  themselves, such as bidi overrides and isolates (e.g. U+202E and U+2066),
  zero width characters and control characters; such a label is now
  returned unchanged, so `Addressable::URI#display_uri` no longer shows
  them. The pure-Ruby backend also no longer decodes labels with other
  characters that nameprep prohibits, as with libidn ([GHSA-539f-xcgw-2gjg])
- fixes `Addressable::IDNA.to_unicode` raising in the pure-Ruby backend for
  Punycode labels that are too long, overflow the decoder, or decode past
  U+10FFFF; the label is now returned unchanged, as with libidn, so
  `Addressable::URI#display_uri` no longer raises for such hosts ([#620])

[#610]: https://github.com/sporkmonger/addressable/pull/610
[#620]: https://github.com/sporkmonger/addressable/pull/620
[#621]: https://github.com/sporkmonger/addressable/pull/621
[#625]: https://github.com/sporkmonger/addressable/pull/625
[#627]: https://github.com/sporkmonger/addressable/pull/627
[GHSA-4w5q-wg7v-w6gp]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-4w5q-wg7v-w6gp
[GHSA-8gmh-2hhj-2hv9]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-8gmh-2hhj-2hv9
[GHSA-9crm-g4mf-wc5j]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-9crm-g4mf-wc5j
[GHSA-9f42-57jx-vpp3]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-9f42-57jx-vpp3
[GHSA-qq38-m9mg-xjj5]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-qq38-m9mg-xjj5
[GHSA-j82w-28jv-3pmj]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-j82w-28jv-3pmj
[GHSA-539f-xcgw-2gjg]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-539f-xcgw-2gjg

## Addressable 2.9.0 <a name="v2.9.0">
- fixes ReDoS vulnerability in Addressable::Template#match (fixes incomplete
  remediation in 2.8.10)

## Addressable 2.8.10 <a name="v2.8.10">
- fixes ReDoS vulnerability in Addressable::Template#match

## Addressable 2.8.9 <a name="v2.8.9">
- Reduce gem size by excluding test files ([#569])
- No need for bundler as development dependency ([#571], [5fc1d93](https://github.com/sporkmonger/addressable/commit/5fc1d93))
- idna/pure: stop building the useless `COMPOSITION_TABLE` (removes the `Addressable::IDNA::COMPOSITION_TABLE` constant) ([#564])

[#564]: https://github.com/sporkmonger/addressable/pull/564
[#569]: https://github.com/sporkmonger/addressable/pull/569
[#571]: https://github.com/sporkmonger/addressable/pull/571

## Addressable 2.8.8 <a name="v2.8.8">
- Replace the `unicode.data` blob by a ruby constant ([#561])
- Allow `public_suffix` 7 ([#558])

[#558]: https://github.com/sporkmonger/addressable/pull/558
[#561]: https://github.com/sporkmonger/addressable/pull/561

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

[#498]: https://github.com/sporkmonger/addressable/pull/498
[#499]: https://github.com/sporkmonger/addressable/pull/499

## Addressable 2.8.2 <a name="v2.8.2">
- Improve cache hits and JIT friendliness ([#486](https://github.com/sporkmonger/addressable/pull/486))
- Improve code style and test coverage ([#482](https://github.com/sporkmonger/addressable/pull/482))
- Ensure reset of deferred validation ([#481](https://github.com/sporkmonger/addressable/pull/481))
- Resolve normalization differences between `IDNA::Native` and `IDNA::Pure` ([#408](https://github.com/sporkmonger/addressable/issues/408), [#492])
- Remove redundant colon in `Addressable::URI::CharacterClasses::AUTHORITY` regex ([#438](https://github.com/sporkmonger/addressable/pull/438)) (accidentally reverted by [#449] merge but [added back](https://github.com/sporkmonger/addressable/pull/492#discussion_r1105125280) in [#492])

[#449]: https://github.com/sporkmonger/addressable/pull/449
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
