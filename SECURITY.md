# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's private
vulnerability reporting:

https://github.com/sporkmonger/addressable/security/advisories/new

Don't open a public issue or pull request for a security problem.

## Include a proposed fix

Because of the recent high volume of security reports, please include a
proposed fix with each report. A good fix includes:

- the proposed fix
- basic test coverage for the fix
- adversarial tests that simulate the exploit
- whenever possible, property-based tests that identify one or more
  invariants on the previously vulnerable code
- a changelog entry that identifies the security risk being mitigated with
  a link to the advisory

Please provide any fixes as a pull request in the advisory's temporary
private fork rather than embedding them as a patch file in the report.

## Put everything in the report

Write and make any updates to the details of the issue in the report
itself rather than in later comments on the advisory. Comments aren't
easily accessible through the API, so follow-up comments can be easy to
miss when interacting with a report programmatically. It's okay to use
comments to talk about changes you've made to the report.
