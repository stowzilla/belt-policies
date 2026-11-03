# frozen_string_literal: true

require_relative 'lib/belt/policies/version'

Gem::Specification.new do |spec|
  spec.name          = 'belt-policies'
  spec.version       = Belt::Policies::VERSION
  spec.authors       = ['Stowzilla']
  spec.email         = ['andy@stowzilla.com', 'adam@stowzilla.com']

  spec.summary       = 'Versioned policies (terms, privacy, …) and acceptance records for Belt applications'
  spec.description   = 'Belt plugin that scaffolds policy documents (Terms of Service, Privacy Policy, and more), ' \
                       'publishes each version to DynamoDB, and records which user accepted which version, when, ' \
                       'and from where. Generates outlines only; it is not legal advice.'
  spec.homepage      = 'https://github.com/stowzilla/belt-policies'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md', 'AGENTS.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'activeitem', '>= 0.0.13'
  spec.add_dependency 'belt', '>= 0.6.4'
end
