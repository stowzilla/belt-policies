# frozen_string_literal: true

RSpec.describe Belt::Policies::Document do
  def doc(source, slug: 'terms-of-service')
    described_class.new("/app/policies/#{slug}.md", source)
  end

  let(:source) do
    <<~MD
      ---
      title: Terms of Service
      version: 2026-11-02
      requires_acceptance: true
      ---
      # Terms

      Be nice.
    MD
  end

  it 'reads the front matter and keeps the body separate' do
    terms = doc(source)
    expect(terms.slug).to eq('terms-of-service')
    expect(terms.title).to eq('Terms of Service')
    expect(terms.version).to eq('2026-11-02') # a YAML date comes back as the same string
    expect(terms.effective_date).to eq('2026-11-02')
    expect(terms.body).to eq("# Terms\n\nBe nice.\n")
    expect(terms.id).to eq('terms-of-service@2026-11-02')
  end

  it 'hashes only the body, so front matter edits do not change it' do
    expect(doc(source).sha256).to eq(doc(source.sub('title: Terms of Service', 'title: Terms')).sha256)
    expect(doc(source).sha256).not_to eq(doc(source.sub('Be nice.', 'Be kind.')).sha256)
  end

  it 'defaults to requiring acceptance and re-acceptance, and to not being a draft' do
    terms = doc("---\nversion: '1'\n---\nx\n")
    expect(terms.requires_acceptance?).to be(true)
    expect(terms.requires_reacceptance?).to be(true)
    expect(terms.draft?).to be(false)
  end

  it 'flags text edited after it was published' do
    published = doc(source)
    stamped = doc(published.with_front_matter('published_sha256' => published.sha256))
    expect(stamped.edited_since_published?).to be(false)

    edited = doc(stamped.with_front_matter({}).sub('Be nice.', 'Be kinder.'))
    expect(edited.edited_since_published?).to be(true)
  end

  it 'rewrites front matter keeping the body, and removes keys set to nil' do
    draft = doc(source.sub("requires_acceptance: true\n", "requires_acceptance: true\ndraft: true\n"))
    rewritten = doc(draft.with_front_matter('draft' => nil, 'version' => '2026-12-01'))
    expect(rewritten.draft?).to be(false)
    expect(rewritten.version).to eq('2026-12-01')
    expect(rewritten.body).to eq(draft.body)
  end

  it 'rejects files without front matter, without a version, or with a bad slug' do
    expect { doc("# no front matter\n") }.to raise_error(Belt::Policies::InvalidDocument, /front matter/)
    expect { doc("---\ntitle: x\n---\nbody\n") }.to raise_error(Belt::Policies::InvalidDocument, /version/)
    expect { doc(source, slug: 'Terms_Of_Service') }.to raise_error(Belt::Policies::InvalidDocument, /slug/)
  end

  it 'lists every policy file in a directory except the README' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'README.md'), '# Policies')
      File.write(File.join(dir, 'privacy-policy.md'), source)
      File.write(File.join(dir, 'terms-of-service.md'), source)
      expect(described_class.all(dir).map(&:slug)).to eq(%w[privacy-policy terms-of-service])
    end
  end
end
