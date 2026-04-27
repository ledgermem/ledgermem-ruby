# frozen_string_literal: true

require_relative "lib/ledgermem/version"

Gem::Specification.new do |spec|
  spec.name          = "ledgermem"
  spec.version       = Ledgermem::VERSION
  spec.authors       = ["LedgerMem"]
  spec.email         = ["founders@proofly.dev"]

  spec.summary       = "Official Ruby SDK for the LedgerMem API"
  spec.description   = "Auditable memory for AI agents."
  spec.homepage      = "https://proofly.dev"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["source_code_uri"] = "https://github.com/ledgermem/ledgermem-ruby"
  spec.metadata["changelog_uri"]   = "https://github.com/ledgermem/ledgermem-ruby/releases"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.20"
  spec.add_development_dependency "rake", "~> 13.0"
end
