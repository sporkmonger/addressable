# frozen_string_literal: true

require "open3"

namespace :git do
  namespace :tag do
    desc "List tags from the Git repository"
    task :list do
      tags = `git tag -l`
      tags.gsub!("\r", "")
      tags = tags.split("\n").sort {|a, b| b <=> a }
      puts tags.join("\n")
    end

    desc "Create a new tag in the Git repository"
    task :create do
      changelog = File.open("CHANGELOG.md", "r") { |file| file.read }
      puts "-" * 80
      puts changelog
      puts "-" * 80
      puts

      v = ENV["VERSION"] or abort "Must supply VERSION=x.y.z"
      abort "Versions don't match #{v} vs #{PKG_VERSION}" if v != PKG_VERSION

      git = lambda do |*args|
        output, status = Open3.capture2e("git", *args)
        [output.strip, status.success?]
      end

      status, ok = git.call("status", "--porcelain")
      abort "Couldn't get the status of the working directory." unless ok
      abort "Working directory isn't clean." unless status.empty?

      # Tag only what's on main on GitHub, so a release can't come from an
      # unmerged branch or from local commits.
      branch, ok = git.call("symbolic-ref", "--short", "HEAD")
      unless ok && branch == "main"
        abort "Releases are tagged on main, not " +
          (ok ? "#{branch}." : "a detached HEAD.")
      end
      _, ok = git.call("fetch", "--quiet", "origin", "main")
      abort "Couldn't fetch main from origin." unless ok
      if git.call("rev-parse", "HEAD") != git.call("rev-parse", "origin/main")
        abort "main doesn't match origin/main. Pull or push it first."
      end

      tag = "#{PKG_NAME}-#{PKG_VERSION}"
      msg = "Release #{PKG_NAME}-#{PKG_VERSION}"

      # A released version's tag must never move.
      _, exists = git.call(
        "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}"
      )
      abort "Tag #{tag} already exists." if exists
      remote, ok = git.call(
        "ls-remote", "--tags", "origin", "refs/tags/#{tag}"
      )
      abort "Couldn't list the tags on origin." unless ok
      abort "Tag #{tag} already exists on origin." unless remote.empty?

      puts "Creating git tag '#{tag}'..."
      _, ok = git.call("tag", "-a", "-m", msg, tag)
      abort "Tag creation failed." unless ok
    end
  end
end

task "gem:release" => "git:tag:create"
