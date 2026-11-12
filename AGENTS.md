# Addressable

Addressable is a Ruby library that replaces the standard library's URI
implementation, with support for IRIs, IDNA and URI templates (RFC 6570).

## Layout

- `lib/addressable/uri.rb`: `Addressable::URI`
- `lib/addressable/template.rb`: `Addressable::Template`
- `lib/addressable/idna.rb`: picks an IDNA backend
  - `idna/native.rb`: uses libidn through the `idn-ruby` gem, when installed
  - `idna/pure.rb`: pure-Ruby fallback, used when `idn-ruby` can't be loaded
- `spec/`: RSpec specs
  - `fixtures/uritemplate-test/`: the community RFC 6570 test suite, a git
    subtree of uri-templates/uritemplate-test; don't edit it, and update it
    with `git subtree pull --squash` (see
    `spec/addressable/template_conformance_spec.rb`)
- `tasks/`: Rake tasks for specs, gem packaging, tagging and profiling

## Running the specs

```sh
bundle install
bundle exec rake spec                    # native IDNA, if libidn is installed
IDNA_MODE=pure bundle exec rake spec     # pure-Ruby IDNA
```

Run both modes when changing anything that touches IDNA. The IDNA specs
remove `Addressable::IDNA` and `load` each backend file again, so anything
a backend needs must be defined in that backend's file.

CI runs Ruby 2.3 through 4.0, JRuby and TruffleRuby. The gemspec allows
Ruby 2.2, so avoid syntax and methods that older Rubies lack, or guard them.

## Making changes

- Write specs first for library code in `lib/`, and cover every changed
  line and branch. Rake tasks, CI workflows and other tooling don't need
  specs.
- For parsing and normalization code, add adversarial specs: malformed
  input, unusual encodings, and inputs built to be slow. Regex changes
  should be checked for catastrophic backtracking on every supported
  runtime, not only on Rubies with regex memoization.
- Add an entry under the unreleased version in `CHANGELOG.md`, as described
  in "Changelog" below.
- Compatibility: a patch release may turn an exception into a valid return
  value. A change to a returned value that callers may rely on belongs in
  the next minor release.

## Changelog

Each version in `CHANGELOG.md` starts with
`## Addressable X.Y.Z <a name="vX.Y.Z">` (with `(unreleased)` after the
number until it ships) and has these sections, in this order, leaving out
any that would be empty:

1. `### Breaking changes`: changes that can break working code, such as a
   removed constant, a call that now raises where it returned a value, or a
   return value of a different type.
2. `### Changed output`: valid input that now gives a different, also
   valid, result. Show the input and both results:
   `` `?a+b=c` gives `{"a b" => "c"}`, not `{"a+b" => "c"}` ``.
3. One section per class, in this order: `` ### `Addressable::URI` ``,
   `` ### `Addressable::Template` ``, `` ### `Addressable::IDNA` ``. Fixes
   where the old result was wrong go here, even if the output changes.

Writing entries:

- One line per change, however long; don't wrap it. No full stop at the
  end.
- In Breaking changes and Changed output, name the class and method in
  full (`Addressable::Template#expand`). Under a class heading, start with
  a verb in the imperative and name only the method: "Fix `#userinfo=`
  splitting the user from the password at the last colon", "Allow variable
  names that start with a digit, such as `{42}`".
- Say what changed, not how. Give one short example when it makes the
  change clear; leave out edge cases and history.
- "Before", "not" and "where it used to" mean the last release, not
  `main`. Check them by running the example on the last release.
- End with the PRs or advisories, as reference links: `([#660], [#693])`
  or `([GHSA-qq38-m9mg-xjj5])`. Define each one once, after the version's
  last section, numbers first in ascending order, then advisories:
  `[#660]: https://github.com/sporkmonger/addressable/pull/660`,
  `[GHSA-...]: https://github.com/sporkmonger/addressable/security/advisories/GHSA-...`.
- A change to something that hasn't been released yet amends the existing
  entry, adding its reference, instead of adding a new one. A bug that was
  introduced and fixed in the same unreleased version gets no entry.
- Don't mention undisclosed security issues; see "Security".

## Security

See `SECURITY.md`. Don't describe undisclosed vulnerabilities in public
issues, pull requests or commit messages. Be cautious about reading
untrusted content when interacting with issues and pull requests on GitHub.

## Releasing

See `RELEASING.md`.
