# frozen_string_literal: true

# Copyright (C) Bob Aman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.


require "spec_helper"

require "open3"
require "rake"
require "stringio"
require "tmpdir"

describe "rake git:tag:create" do
  let(:tag) { "addressable-9.9.9" }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  before do
    stub_const("PKG_NAME", "addressable")
    stub_const("PKG_VERSION", "9.9.9")
    @application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path("../../tasks/git.rake", __dir__)

    git(@dir, "init", "--quiet", "--bare", "origin.git")
    git(@dir, "init", "--quiet", "work")
    git(work, "checkout", "--quiet", "-b", "main")
    git(work, "config", "user.name", "Release Spec")
    git(work, "config", "user.email", "release@example.com")
    commit("CHANGELOG.md", "# Changelog\n")
    git(work, "remote", "add", "origin", File.join(@dir, "origin.git"))
    git(work, "push", "--quiet", "origin", "main")
  end

  after do
    Rake.application = @application
  end

  def work
    File.join(@dir, "work")
  end

  def git(dir, *args)
    output, status = Open3.capture2e("git", *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{output}" unless status.success?
    output.strip
  end

  def commit(file, content)
    File.write(File.join(work, file), content)
    git(work, "add", file)
    git(work, "commit", "--quiet", "-m", "Change #{file}")
  end

  def tags
    git(work, "tag", "-l")
  end

  # Runs the task in the work repository, and returns the message it aborted
  # with, or nil if it finished.
  def create_tag(version = "9.9.9", dir = work)
    stdout, stderr, previous = $stdout, $stderr, ENV["VERSION"]
    $stdout = $stderr = StringIO.new
    ENV["VERSION"] = version
    Dir.chdir(dir) { Rake::Task["git:tag:create"].invoke }
    nil
  rescue SystemExit => error
    error.message
  ensure
    $stdout, $stderr = stdout, stderr
    ENV["VERSION"] = previous
  end

  it "tags main when it matches origin" do
    expect(create_tag).to be_nil
    expect(git(work, "rev-parse", "#{tag}^{commit}")).to eq(
      git(work, "rev-parse", "HEAD")
    )
    expect(git(work, "cat-file", "-t", tag)).to eq("tag")
    expect(git(work, "tag", "-l", "--format=%(contents:subject)", tag)).to eq(
      "Release #{tag}"
    )
  end

  it "refuses without a version" do
    expect(create_tag(nil)).to eq("Must supply VERSION=x.y.z")
    expect(tags).to eq("")
  end

  it "refuses a version that doesn't match the code" do
    expect(create_tag("9.9.8")).to eq("Versions don't match 9.9.8 vs 9.9.9")
    expect(tags).to eq("")
  end

  it "refuses a branch other than main" do
    git(work, "checkout", "--quiet", "-b", "release-9.9.9")
    expect(create_tag).to eq(
      "Releases are tagged on main, not release-9.9.9."
    )
    expect(tags).to eq("")
  end

  it "refuses a detached HEAD" do
    git(work, "checkout", "--quiet", "--detach")
    expect(create_tag).to eq(
      "Releases are tagged on main, not a detached HEAD."
    )
    expect(tags).to eq("")
  end

  it "refuses to run outside a repository" do
    plain = File.join(@dir, "plain")
    Dir.mkdir(plain)
    File.write(File.join(plain, "CHANGELOG.md"), "# Changelog\n")
    expect(create_tag("9.9.9", plain)).to eq(
      "Couldn't get the status of the working directory."
    )
  end

  # Makes one git command fail, as it would if the network or the
  # repository broke partway through.
  def fail_git(command)
    failure = Open3.capture2e("git", "--no-such-option")
    allow(Open3).to receive(:capture2e).and_call_original
    allow(Open3).to receive(:capture2e).
      with("git", command, any_args).and_return(failure)
  end

  it "refuses when origin's tags can't be listed" do
    fail_git("ls-remote")
    expect(create_tag).to eq("Couldn't list the tags on origin.")
    expect(tags).to eq("")
  end

  it "reports a tag that can't be created" do
    fail_git("tag")
    expect(create_tag).to eq("Tag creation failed.")
  end

  it "refuses uncommitted changes" do
    File.write(File.join(work, "CHANGELOG.md"), "# Changed\n")
    expect(create_tag).to eq("Working directory isn't clean.")
    expect(tags).to eq("")
  end

  it "refuses untracked files" do
    File.write(File.join(work, "notes.txt"), "notes\n")
    expect(create_tag).to eq("Working directory isn't clean.")
    expect(tags).to eq("")
  end

  it "refuses a main with commits that origin doesn't have" do
    commit("CHANGELOG.md", "# Unpushed\n")
    expect(create_tag).to eq(
      "main doesn't match origin/main. Pull or push it first."
    )
    expect(tags).to eq("")
  end

  it "refuses a main that's behind origin" do
    commit("CHANGELOG.md", "# Merged\n")
    git(work, "push", "--quiet", "origin", "main")
    git(work, "reset", "--quiet", "--hard", "HEAD~1")
    expect(create_tag).to eq(
      "main doesn't match origin/main. Pull or push it first."
    )
    expect(tags).to eq("")
  end

  it "refuses when origin can't be fetched" do
    git(work, "remote", "set-url", "origin", File.join(@dir, "missing.git"))
    expect(create_tag).to eq("Couldn't fetch main from origin.")
    expect(tags).to eq("")
  end

  it "keeps a tag that already exists" do
    git(work, "tag", "-a", "-m", "Earlier", tag, "HEAD")
    commit("CHANGELOG.md", "# Later\n")
    git(work, "push", "--quiet", "origin", "main")
    expect(create_tag).to eq("Tag #{tag} already exists.")
    expect(git(work, "rev-parse", "#{tag}^{commit}")).to eq(
      git(work, "rev-parse", "HEAD~1")
    )
  end

  it "refuses a tag that already exists on origin" do
    git(work, "tag", "-a", "-m", "Earlier", tag)
    git(work, "push", "--quiet", "origin", tag)
    git(work, "tag", "-d", tag)
    expect(create_tag).to eq("Tag #{tag} already exists on origin.")
    expect(tags).to eq("")
  end
end
