# Releasing Addressable

1. Update `CHANGELOG.md`
1. Update `lib/addressable/version.rb` with the new version
1. Run `rake gem:gemspec` to update gemspec
1. Create pull request with all that
1. Merge the pull request when CI is green
1. Ensure you have latest changes locally
1. Run`VERSION=x.y.z rake git:tag:create` to create tag in git
1. Push tag to upstream: `git push --tags upstream`
1. Watch GitHub Actions build and push the gem to RubyGems.org
