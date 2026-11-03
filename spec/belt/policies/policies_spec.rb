# frozen_string_literal: true

RSpec.describe Belt::Policies do
  let(:at) { Time.utc(2026, 11, 2, 12) }

  def accept(user_id = 'user-1', policies = %w[terms-of-service], **options)
    described_class.accept!(user_id: user_id, policies: policies, via: 'signup', at: at, **options)
  end

  # fp:current_policy_version
  describe '.current' do
    it 'is the most recently published version of each policy' do
      FakePolicyVersion.publish('terms-of-service', '2026-01-01', published_at: '2026-01-01T00:00:00Z')
      FakePolicyVersion.publish('terms-of-service', '2026-11-02', published_at: '2026-11-02T00:00:00Z')
      FakePolicyVersion.publish('privacy-policy', '2026-03-01')

      expect(described_class.current.transform_values(&:version))
        .to eq('terms-of-service' => '2026-11-02', 'privacy-policy' => '2026-03-01')
    end

    it 'is cached for cache_ttl seconds, and re-read when the ttl is 0' do
      FakePolicyVersion.publish('terms-of-service', '1')
      described_class.current
      FakePolicyVersion.publish('terms-of-service', '2', published_at: '2027-01-01T00:00:00Z')
      expect(described_class.current_version('terms-of-service').version).to eq('1')

      described_class.configuration.cache_ttl = 0
      expect(described_class.current_version('terms-of-service').version).to eq('2')
    end
  end

  describe '.accept!' do
    before do
      FakePolicyVersion.publish('terms-of-service', '2026-11-02')
      FakePolicyVersion.publish('privacy-policy', '2026-11-02')
    end

    # fp:record_policy_acceptance
    it 'records who agreed to which version, when, how, and from where' do
      accept('user-1', %w[terms-of-service], email: 'a@example.com', ip_address: '203.0.113.7', user_agent: 'Spec/1.0')

      row = FakePolicyAcceptance.rows.last
      expect(row).to have_attributes(
        user_id: 'user-1', email: 'a@example.com', policy: 'terms-of-service', version: '2026-11-02',
        policy_version_id: 'terms-of-service@2026-11-02', content_sha256: 'sha-terms-of-service-2026-11-02',
        accepted_at: '2026-11-02T12:00:00Z', accepted_via: 'signup', ip_address: '203.0.113.7', user_agent: 'Spec/1.0'
      )
    end

    it 'records the version given when it is current' do
      accept('user-1', [{ 'policy' => 'privacy-policy', 'version' => '2026-11-02' }])
      expect(FakePolicyAcceptance.rows.map(&:policy)).to eq(%w[privacy-policy])
    end

    # fp:reject_stale_policy_version
    it 'refuses a version that is no longer current, recording nothing' do
      expect { accept('user-1', [{ policy: 'terms-of-service', version: '2026-01-01' }]) }
        .to raise_error(Belt::Policies::StaleVersion) { |e| expect(e.current_version).to eq('2026-11-02') }
      expect(FakePolicyAcceptance.rows).to be_empty
    end

    it 'refuses a policy that is not published' do
      expect { accept('user-1', %w[made-up]) }.to raise_error(Belt::Policies::UnknownPolicy)
    end

    # fp:record_policy_acceptance
    it 'records nothing new when the same version is accepted again' do
      accept
      expect(accept).to eq([])
      expect(FakePolicyAcceptance.rows.size).to eq(1)
    end

    it 'needs a user and at least one policy' do
      expect do
        described_class.accept!(user_id: '', policies: %w[terms-of-service], via: 'x')
      end.to raise_error(ArgumentError)
      expect { described_class.accept!(user_id: 'u', policies: [], via: 'x') }.to raise_error(ArgumentError)
    end
  end

  # fp:policy_reacceptance
  describe '.status_for / .pending_for' do
    before do
      FakePolicyVersion.publish('terms-of-service', '1', published_at: '2026-01-01T00:00:00Z')
      FakePolicyVersion.publish('privacy-policy', '1')
      FakePolicyVersion.publish('cookie-policy', '1', requires_acceptance: false)
    end

    it 'lists what a new user has to agree to, leaving out published-only policies' do
      expect(described_class.pending_for('user-1').map(&:policy)).to eq(%w[privacy-policy terms-of-service])
      expect(described_class.accepted?('user-1')).to be(false)
    end

    it 'is satisfied once the current versions are accepted' do
      accept('user-1', %w[terms-of-service privacy-policy])

      status = described_class.status_for('user-1')
      expect(status[:pending]).to eq([])
      terms = status[:policies].find { |p| p[:policy] == 'terms-of-service' }
      expect(terms).to include(accepted: true, pending: false, accepted_version: '1',
                               accepted_at: '2026-11-02T12:00:00Z')
      expect(described_class.accepted?('user-1')).to be(true)
    end

    it 'asks again when a new version needs re-acceptance' do
      accept('user-1', %w[terms-of-service privacy-policy])
      FakePolicyVersion.publish('terms-of-service', '2', published_at: '2027-01-01T00:00:00Z')
      described_class.reset_cache!

      expect(described_class.pending_for('user-1').map(&:policy)).to eq(%w[terms-of-service])
      expect(described_class.accepted?('user-1', 'privacy-policy')).to be(true)
      expect(described_class.accepted?('user-1', 'terms-of-service')).to be(false)
    end

    it 'does not ask again for a minor version, but does ask people who never agreed' do
      accept('user-1', %w[terms-of-service privacy-policy])
      FakePolicyVersion.publish('terms-of-service', '1.1', published_at: '2027-01-01T00:00:00Z',
                                                           requires_reacceptance: false)
      described_class.reset_cache!

      expect(described_class.pending_for('user-1')).to be_empty
      expect(described_class.pending_for('user-2').map(&:policy)).to include('terms-of-service')
    end
  end

  describe '.account_deleted!' do
    it 'stamps the rows without removing them' do
      FakePolicyVersion.publish('terms-of-service', '1')
      accept
      described_class.account_deleted!('user-1', at: at)

      expect(FakePolicyAcceptance.rows.map(&:account_deleted_at)).to eq(['2026-11-02T12:00:00Z'])
    end
  end

  describe '.publish!' do
    it 'copies the policy files into policy_versions and clears the cache' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'terms-of-service.md'), "---\nversion: '1'\n---\n# Terms\n")
        described_class.current
        lines = []
        described_class.publish!(dir: dir) { |line| lines << line }

        expect(lines).to eq(['publish  terms-of-service@1'])
        expect(described_class.current_version('terms-of-service').content).to eq("# Terms\n")
      end
    end
  end
end
