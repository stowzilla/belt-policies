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

  describe 'acceptances about a subject' do
    before { FakePolicyVersion.publish('parent-notice', '1') }

    def consent(child, **options)
      accept('parent-1', %w[parent-notice], subject_id: child, **options)
    end

    # fp:record_subject_acceptance
    it 'records a separate acceptance for each subject under the same version' do
      consent('child-a', metadata: { terms_version: '3' })
      consent('child-b')
      expect(consent('child-a')).to eq([])

      expect(FakePolicyAcceptance.rows.map(&:subject_id)).to eq(%w[child-a child-b])
      expect(FakePolicyAcceptance.rows.first.metadata).to eq('terms_version' => '3')
    end

    # fp:record_subject_acceptance
    it 'filters history by subject' do
      accept('parent-1', %w[parent-notice])
      consent('child-a')

      expect(described_class.history_for('parent-1').size).to eq(2)
      expect(described_class.history_for('parent-1', subject_id: 'child-a').map(&:subject_id)).to eq(%w[child-a])
    end

    # fp:subject_policy_status
    it "keeps a subject's status apart from the account's" do
      consent('child-a')

      expect(described_class.pending_for('parent-1').map(&:policy)).to eq(%w[parent-notice])
      expect(described_class.accepted?('parent-1', 'parent-notice', subject_id: 'child-a')).to be(true)
      expect(described_class.accepted?('parent-1', 'parent-notice', subject_id: 'child-b')).to be(false)
      expect(described_class.status_for('parent-1', subject_id: 'child-a')[:pending]).to eq([])
    end

    it 'refuses metadata that is not a hash' do
      expect { consent('child-a', metadata: 'x') }.to raise_error(ArgumentError)
    end
  end

  describe '.import_acceptance!' do
    def import(**options)
      described_class.import_acceptance!(user_id: 'user-1', policy: 'terms-of-service', version: '2025-06-01',
                                         accepted_at: '2025-07-14T09:30:00Z', **options)
    end

    # fp:import_legacy_acceptance
    it 'records an earlier acceptance with its original date and no stored text, once' do
      row = import(metadata: { source: 'terms_acceptances' })
      expect(import).to be_nil

      expect(FakePolicyAcceptance.rows).to eq([row])
      expect(row).to have_attributes(
        policy_version_id: 'terms-of-service@2025-06-01', accepted_at: '2025-07-14T09:30:00Z',
        accepted_via: 'import', content_sha256: nil, metadata: { 'source' => 'terms_acceptances' }
      )
    end

    # fp:import_legacy_acceptance
    it 'counts toward the current version when it was published under the same version' do
      FakePolicyVersion.publish('terms-of-service', '2025-06-01')
      import
      expect(described_class.pending_for('user-1')).to be_empty
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

  # fp:expire_deleted_acceptances
  describe '.expire_deleted!' do
    let(:now) { Time.utc(2029, 11, 2, 12) }
    let(:three_years) { 3 * 365 * 86_400 }

    before { FakePolicyVersion.publish('terms-of-service', '1') }

    it 'deletes rows stamped before the cutoff, page by page, and counts them' do
      %w[old-1 old-2 old-3 recent].each { |user| accept(user) }
      %w[old-1 old-2 old-3].each { |user| described_class.account_deleted!(user, at: Time.utc(2026, 1, 1)) }
      described_class.account_deleted!('recent', at: Time.utc(2029, 1, 1))
      accept('active')

      expect(described_class.expire_deleted!(older_than: three_years, now: now)).to eq(3)
      expect(FakePolicyAcceptance.rows.map(&:user_id)).to contain_exactly('recent', 'active')
    end

    it 'takes a cutoff time' do
      accept
      described_class.account_deleted!('user-1', at: Time.utc(2026, 1, 1))
      expect(described_class.expire_deleted!(older_than: Time.utc(2025, 1, 1))).to eq(0)
      expect(described_class.expire_deleted!(older_than: Time.utc(2027, 1, 1))).to eq(1)
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
