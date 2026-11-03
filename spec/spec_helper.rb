# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require 'belt'
require 'belt-policies'
require_relative 'support/fake_models'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random

  config.before do
    FakePolicyVersion.reset!
    FakePolicyAcceptance.reset!
    Belt::Policies.reset_configuration!
    Belt::Policies.configure do |c|
      c.version_model = FakePolicyVersion
      c.acceptance_model = FakePolicyAcceptance
    end
  end
end
