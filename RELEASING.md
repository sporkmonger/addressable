# Releasing Addressable

1. Update `CHANGELOG.md`
1. Update `lib/addressable/version.rb` with the new version
1. Run `rake gem:gemspec` to update gemspec
1. Run `rake gem:install` to sanity check your work
1. Create pull request with all that
1. Merge the pull request when CI is green
1. Ensure you have latest changes locally
1. Run `VERSION=x.y.z rake git:tag:create` to create tag in git
1. Push only the new tag: `git push origin addressable-x.y.z`
1. Watch GitHub Actions build and push the gem to RubyGems.org

## What the tag push does

Pushing a tag named `addressable-x.y.z` starts the Release workflow
(`.github/workflows/release.yml`) on `sporkmonger/addressable`:

1. It runs the full CI workflow (`.github/workflows/test.yml`) against the
   tagged commit. If any required job fails, nothing is published.
1. It checks that the tag's version matches the version in
   `addressable.gemspec`.
1. It builds and installs the gem, then pushes it to RubyGems.org using
   trusted publishing, so no API key is needed locally.

The workflow only publishes from `sporkmonger/addressable`. A tag pushed to
a fork, including a security advisory fork, doesn't publish anything.

## GitHub Releases

GitHub Releases are not currently in use. The tag and `CHANGELOG.md` are
the release record, and nothing needs to be created on the Releases page.

## Security releases

Fixes for security advisories are developed in GitHub's private advisory
forks, which don't run CI.

1. Merge each advisory's pull request into `main`. The fix is public once
   it's merged, so do the remaining steps without delay.
1. Wait for CI to pass on `main`.
1. Release as above.
1. Once the gem is available on RubyGems.org, publish the advisories.
