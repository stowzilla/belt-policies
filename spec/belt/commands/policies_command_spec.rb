# frozen_string_literal: true

require 'belt/commands/policies_command'

RSpec.describe Belt::Commands::PoliciesCommand do
  around do |example|
    Dir.mktmpdir do |app|
      Dir.chdir(app) do
        Belt::Policies.configuration.policies_dir = File.join(app, 'policies')
        FileUtils.mkdir_p('policies')
        example.run
      end
    end
  end

  def run_command(*args)
    expect { described_class.run(args) }.to output.to_stdout
  end

  it 'lists policies with their state' do
    File.write('policies/terms-of-service.md', "---\nversion: '1'\ndraft: true\n---\n# Terms\n")
    File.write('policies/cookie-policy.md', "---\nversion: '1'\nrequires_acceptance: false\n---\n# Cookies\n")

    expect { described_class.run(%w[list]) }
      .to output(/cookie-policy\s+1\s+-\s+ready.*terms-of-service\s+1\s+required\s+draft/m).to_stdout
  end

  # fp:publish_policy_version
  it 'publishes a policy and writes its migration' do
    File.write('policies/terms-of-service.md', "---\nversion: '1'\ndraft: true\n---\n# Terms\n")
    expect { described_class.run(%w[publish terms-of-service --version 2026-11-02]) }
      .to output(%r{create  db/migrate/\d{14}_publish_terms_of_service_2026_11_02\.rb}).to_stdout

    expect { described_class.run(%w[list]) }.to output(/terms-of-service\s+2026-11-02\s+required\s+published/).to_stdout
  end

  it 'lists the kinds it can outline' do
    expect { described_class.run(%w[kinds]) }.to output(/terms-of-service.*aliases: terms, tos/m).to_stdout
  end
end
