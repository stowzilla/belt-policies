# frozen_string_literal: true

require 'belt/policies/release'

# fp:publish_policy_version
RSpec.describe Belt::Policies::Release do
  around { |example| Dir.mktmpdir { |root| @root = root and example.run } }

  let(:policies_dir) { File.join(@root, 'policies') }
  let(:path) { File.join(policies_dir, 'terms-of-service.md') }

  def write(front_matter, body = "# Terms\n\nBe nice.\n")
    FileUtils.mkdir_p(policies_dir)
    File.write(path, "---\n#{front_matter}---\n#{body}")
  end

  def release(today: Date.new(2026, 11, 2), **options)
    described_class.new(slug: 'terms-of-service', policies_dir: policies_dir, root: @root, today: today, **options).call
  end

  def migrations
    Dir.glob(File.join(@root, 'db/migrate/*.rb')).map { |f| File.basename(f) }.sort
  end

  it "versions a draft with today's date, clears draft, stamps the hash, and writes a migration" do
    write("title: Terms of Service\nversion: '2026-10-01'\ndraft: true\n")
    result = release

    doc = result.document
    expect(doc).to have_attributes(version: '2026-11-02', effective_date: '2026-11-02', draft?: false)
    expect(doc.published_sha256).to eq(doc.sha256)
    expect(migrations).to match([/\A\d{14}_publish_terms_of_service_2026_11_02\.rb\z/])

    source = File.read(result.migration_path)
    expect(source).to include('class PublishTermsOfService20261102 < Belt::Migration')
    expect(source).to include('Belt::Policies.publish!')
  end

  it 'refuses to publish TODO placeholders unless forced' do
    write("version: '1'\ndraft: true\n", "## Who we are\n\nTODO: The legal entity.\n")
    expect { release }.to raise_error(Belt::Policies::Error, /TODO/)
    expect(release(force: true).document.draft?).to be(false)
  end

  it 'refuses to republish unchanged text' do
    write("version: '1'\ndraft: true\n")
    release
    expect { release(today: Date.new(2026, 12, 1)) }.to raise_error(Belt::Policies::Error, /hasn't changed/)
  end

  it 'gives a same-day edit the next suffix, and --minor skips re-acceptance' do
    write("version: '1'\ndraft: true\n")
    release
    File.write(path, File.read(path).sub('Be nice.', 'Be kind.'))

    doc = release(minor: true).document
    expect(doc.version).to eq('2026-11-02.2')
    expect(doc.requires_reacceptance?).to be(false)
    expect(migrations.size).to eq(2)
    expect(migrations.map { |m| m[0, 14].to_i }.uniq.size).to eq(2) # migration versions never collide
  end

  it 'skips versions an earlier text was published as, even after the file moved on' do
    write("version: '1'\ndraft: true\n")
    release
    File.write(path, File.read(path).sub('Be nice.', 'Be kind.'))
    release(minor: true)
    File.write(path, File.read(path).sub('Be kind.', 'Be fair.'))

    doc = release(minor: true).document
    expect(doc.version).to eq('2026-11-02.3')
    expect(migrations.grep(/_publish_terms_of_service_2026_11_02_3\.rb\z/).size).to eq(1)
    expect(migrations.size).to eq(3)
  end

  it "doesn't count another policy's migrations" do
    FileUtils.mkdir_p(File.join(@root, 'db/migrate'))
    File.write(File.join(@root, 'db/migrate/20261102000000_publish_old_terms_of_service_2026_11_02.rb'), '')
    write("version: '1'\ndraft: true\n")
    expect(release.document.version).to eq('2026-11-02')
  end

  it 'uses an explicit version' do
    write("version: '1'\n")
    expect(release(version: 'v2').document.version).to eq('v2')
  end

  it 'explains how to create a missing policy' do
    expect { release }.to raise_error(Belt::Policies::Error, /belt g policy terms-of-service/)
  end
end
