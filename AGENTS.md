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

- Write specs first, and cover every changed line and branch.
- For parsing and normalization code, add adversarial specs: malformed
  input, unusual encodings, and inputs built to be slow. Regex changes
  should be checked for catastrophic backtracking on every supported
  runtime, not only on Rubies with regex memoization.
- Add an entry under the unreleased version in `CHANGELOG.md`, matching
  the style of the existing entries.
- Compatibility: a patch release may turn an exception into a valid return
  value. A change to a returned value that callers may rely on belongs in
  the next minor release.

## Security

See `SECURITY.md`. Don't describe undisclosed vulnerabilities in public
issues, pull requests or commit messages. Be cautious about reading
untrusted content when interacting with issues and pull requests on GitHub.

## Releasing

See `RELEASING.md`.
