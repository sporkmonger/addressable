# frozen_string_literal: true

require "spec_helper"
require "json"
require "addressable/template"

# Runs the community RFC 6570 test suite, uri-templates/uritemplate-test.
# It's kept in spec/fixtures/uritemplate-test as a git subtree; to update it:
#
#   git subtree pull --prefix=spec/fixtures/uritemplate-test --squash \
#     https://github.com/uri-templates/uritemplate-test.git master
describe Addressable::Template, "uri-templates/uritemplate-test" do
  suite = File.expand_path("../fixtures/uritemplate-test", __dir__)
  # Expansion fails with one of these for an invalid template, or for a
  # value that the template can't take, such as a prefix of a list.
  errors = [
    Addressable::Template::InvalidTemplateError,
    Addressable::Template::InvalidTemplateValueError
  ]

  %w(
    spec-examples.json
    spec-examples-by-section.json
    extended-tests.json
    negative-tests.json
  ).each do |file|
    context file do
      groups = JSON.parse(File.read(File.join(suite, file), encoding: "UTF-8"))

      groups.each do |group, tests|
        context group do
          variables = tests.fetch("variables")

          tests.fetch("testcases").each do |pattern, expected|
            if expected == false
              it "fails to expand #{pattern.inspect}" do
                expect {
                  Addressable::Template.new(pattern).expand(variables)
                }.to raise_error { |error|
                  expect(errors.any? { |klass| error.is_a?(klass) }).to be(true)
                }
              end
            else
              # A list holds the expansions that are equally acceptable.
              expansion = Array(expected).first
              it "expands #{pattern.inspect} to #{expansion.inspect}" do
                result = Addressable::Template.new(pattern).expand(variables)
                expect(Array(expected)).to include(result.to_s)
              end
            end
          end
        end
      end
    end
  end
end
