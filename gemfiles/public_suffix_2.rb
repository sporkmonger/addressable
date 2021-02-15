# frozen_string_literal: true

# Assumes this gemfile is used from the project root
eval File.read("Gemfile") # rubocop:disable Security/Eval

gem "public_suffix", ">= 2.0.2", "~> 2.0"
