# frozen_string_literal: true

# fp:published_text_immutable
RSpec.describe Belt::Policies::Publisher do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  def write(slug, front_matter, body = "# #{slug}\n")
    File.write(File.join(@dir, "#{slug}.md"), "---\n#{front_matter}---\n#{body}")
  end

  def publish
    lines = []
    results = described_class.new(dir: @dir, version_class: FakePolicyVersion,
                                  now: -> { Time.utc(2026, 11, 2) }) { |line| lines << line }.call
    [results, lines]
  end

  it 'publishes each version once, with its text and hash' do
    write('terms-of-service', "title: Terms\nversion: '2026-11-02'\nrequires_reacceptance: false\n", "Be nice.\n")
    results, = publish

    expect(results.map(&:status)).to eq([:published])
    row = FakePolicyVersion.find_version('terms-of-service@2026-11-02')
    expect(row).to have_attributes(policy: 'terms-of-service', version: '2026-11-02', title: 'Terms',
                                   content: "Be nice.\n", published_at: '2026-11-02T00:00:00Z',
                                   requires_acceptance: true, requires_reacceptance: false)
    expect(row.content_sha256).to eq(Digest::SHA256.hexdigest("Be nice.\n"))

    expect(publish.first.map(&:status)).to eq([:unchanged])
    expect(FakePolicyVersion.rows.size).to eq(1)
  end

  it 'never publishes drafts' do
    write('privacy-policy', "version: '1'\ndraft: true\n")
    results, lines = publish
    expect(results.map(&:status)).to eq([:draft])
    expect(lines.first).to include('draft')
    expect(FakePolicyVersion.rows).to be_empty
  end

  it 'keeps the published text when the file changed without a new version' do
    write('terms-of-service', "version: '1'\n", "Original.\n")
    publish
    write('terms-of-service', "version: '1'\n", "Sneaky edit.\n")
    results, lines = publish

    expect(results.map(&:status)).to eq([:changed])
    expect(lines.first).to include('belt policies publish terms-of-service')
    expect(FakePolicyVersion.find_version('terms-of-service@1').content).to eq("Original.\n")
  end

  it 'does nothing when there is no policies directory' do
    expect(described_class.new(dir: File.join(@dir, 'missing'), version_class: FakePolicyVersion).call).to eq([])
  end
end
