# frozen_string_literal: true

require 'belt/generators/policies_generator'

RSpec.describe Belt::Generators::PoliciesGenerator do
  around do |example|
    Dir.mktmpdir do |app|
      Dir.chdir(app) do
        FileUtils.mkdir_p('config')
        File.write('config/routes.rb', <<~RUBY)
          # frozen_string_literal: true

          Belt.application.routes.draw do
            gateway :api do
              root to: 'welcome#show'
            end
          end
        RUBY
        example.run
      end
    end
  end

  def run_generator(*args)
    expect { described_class.run(args) }.to output.to_stdout
  end

  # fp:install_policies
  it 'installs the models, controller, routes, and README' do
    run_generator

    expect(File.read('lambda/models/policy_version.rb')).to include('class PolicyVersion < ApplicationRecord',
                                                                    'include Belt::Policies::VersionRecord')
    expect(File.read('lambda/models/policy_acceptance.rb')).to include("'UserIndex' => { partition_key: 'userId'")
    expect(File.read('lambda/controllers/api/policies_controller.rb'))
      .to include('module ApiControllers', 'include Belt::Policies::Controller')
    expect(File.read('policies/README.md')).to include('Not legal advice')

    routes = File.read('config/routes.rb')
    expect(routes).to include("get 'policies', to: 'policies#index', tables: [:policy_versions]")
    expect(routes).to include("post 'policies/accept', to: 'policies#accept', auth: :cognito")
    expect(routes.index('# end belt-policies')).to be < routes.rindex("  end\nend")
  end

  # fp:install_policies
  it 'writes models the table generator can read the indexes from' do
    run_generator
    expect(File.read('lambda/models/policy_version.rb'))
      .to match(/^\s*indexes\(\s*\n\s*'PolicyIndex' => \{ partition_key: 'policy', sort_key: 'publishedAt' \}/)
  end

  # fp:install_policies
  it 'does not add the routes twice, and honours --gateway and --auth' do
    File.write('config/routes.rb',
               File.read('config/routes.rb').sub('gateway :api do', "gateway :api do\n  end\n\n  gateway :app do"))
    run_generator('--gateway', 'app', '--auth', 'cognito_users')
    run_generator('--gateway', 'app')

    routes = File.read('config/routes.rb')
    expect(routes.scan('# end belt-policies').size).to eq(1)
    expect(routes).to include('auth: :cognito_users')
    expect(File).to exist('lambda/controllers/app/policies_controller.rb')
  end

  it 'outlines policies passed with --with' do
    run_generator('--with', 'tos,privacy')
    expect(Dir.glob('policies/*.md')).to eq(%w[policies/README.md policies/privacy-policy.md
                                               policies/terms-of-service.md])
  end

  # fp:install_policies
  it 'removes what it installed, keeping the policy files' do
    run_generator('--with', 'tos')
    expect { described_class.destroy([]) }.to output(/removed/).to_stdout

    expect(File).not_to exist('lambda/models/policy_version.rb')
    expect(File).not_to exist('lambda/controllers/api/policies_controller.rb')
    expect(File.read('config/routes.rb')).not_to include('policies')
    expect(File).to exist('policies/terms-of-service.md')
  end
end

RSpec.describe Belt::Generators::PolicyGenerator do
  around { |example| Dir.mktmpdir { |app| Dir.chdir(app) { example.run } } }

  before { FileUtils.mkdir_p('lambda/models') && File.write('lambda/models/policy_version.rb', '') }

  # fp:outline_policy
  it 'outlines a known kind as a draft that cannot be published as is' do
    expect { described_class.run(['privacy']) }.to output(/not legal advice/).to_stdout

    doc = Belt::Policies::Document.load('policies/privacy-policy.md')
    expect(doc).to have_attributes(title: 'Privacy Policy', draft?: true, requires_acceptance?: true)
    expect(doc.version).to eq(Date.today.strftime('%F'))
    expect(doc.body).to include('NOT LEGAL ADVICE', '## What we collect', 'TODO:')
  end

  # fp:outline_policy
  it 'outlines an unknown slug with the given title, and --no-acceptance' do
    expect { described_class.run(['beta-terms', '--title', 'Beta Terms', '--no-acceptance']) }.to output.to_stdout

    doc = Belt::Policies::Document.load('policies/beta-terms.md')
    expect(doc).to have_attributes(title: 'Beta Terms', requires_acceptance?: false)
  end

  # fp:outline_policy
  it 'does not overwrite an existing policy without --force' do
    expect { described_class.run(%w[tos --quiet]) }.to output.to_stdout
    File.write('policies/terms-of-service.md', 'mine')
    expect { described_class.run(%w[tos]) }.to output(/skip/).to_stdout
    expect(File.read('policies/terms-of-service.md')).to eq('mine')
  end

  it 'installs belt-policies first when it is missing' do
    File.delete('lambda/models/policy_version.rb')
    expect { described_class.run(%w[tos]) }.to output(/belt-policies installed/).to_stdout
    expect(File).to exist('lambda/models/policy_acceptance.rb')
  end
end
