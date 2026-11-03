# frozen_string_literal: true

RSpec.describe Belt::Policies::Catalog do
  it 'finds kinds by slug, alias, or a loosely typed name' do
    expect(described_class.find('terms-of-service').title).to eq('Terms of Service')
    expect(described_class.find('tos').slug).to eq('terms-of-service')
    expect(described_class.find('Privacy').slug).to eq('privacy-policy')
    expect(described_class.find('terms_of_service').slug).to eq('terms-of-service')
    expect(described_class.find('cookies').requires_acceptance).to be(false)
    expect(described_class.find('beta-terms')).to be_nil
  end

  it 'has unique slugs and aliases' do
    names = described_class.all.flat_map { |kind| [kind.slug, *kind.aliases] }
    expect(names).to eq(names.uniq)
  end

  it 'gives every kind sections with a prompt' do
    described_class.all.each do |kind|
      expect(kind.sections).not_to be_empty
      expect(kind.sections.values).to all(be_a(String).and(satisfy { |s| !s.empty? }))
    end
  end
end
