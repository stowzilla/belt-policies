# frozen_string_literal: true

# In-memory stand-ins for the app's PolicyVersion / PolicyAcceptance models.
# They implement the class methods VersionRecord / AcceptanceRecord give the
# real ActiveItem models, so the gem's logic runs without DynamoDB.
class FakeRecord
  def self.reset!
    @rows = []
  end

  def self.rows
    @rows ||= []
  end

  def initialize(attributes = {})
    attributes.each { |key, value| public_send("#{key}=", value) }
  end

  def update(attributes) # rubocop:disable Naming/PredicateMethod -- mirrors ActiveItem#update
    attributes.each { |key, value| public_send("#{key}=", value) }
    true
  end
end

class FakePolicyVersion < FakeRecord
  attr_accessor :id, :policy, :version, :title, :effective_date, :published_at,
                :requires_acceptance, :requires_reacceptance, :content, :content_sha256

  include Belt::Policies::VersionRecord

  def self.find_version(id)
    rows.find { |row| row.id == id }
  end

  def self.all_versions
    rows.dup
  end

  def self.create_version!(attributes)
    new(attributes).tap { |row| rows << row }
  end

  # Publish a version straight into the fake table.
  def self.publish(policy, version, published_at: '2026-11-01T00:00:00Z', **attributes)
    create_version!({
      id: "#{policy}@#{version}", policy: policy, version: version, title: policy.tr('-', ' ').capitalize,
      effective_date: version, published_at: published_at, requires_acceptance: true,
      requires_reacceptance: true, content: "# #{policy} #{version}\n", content_sha256: "sha-#{policy}-#{version}"
    }.merge(attributes))
  end
end

class FakePolicyAcceptance < FakeRecord
  attr_accessor :id, :user_id, :email, :policy, :version, :policy_version_id, :content_sha256,
                :accepted_at, :accepted_via, :ip_address, :user_agent, :subject_id, :metadata, :account_deleted_at

  include Belt::Policies::AcceptanceRecord

  def self.for_user(user_id)
    rows.select { |row| row.user_id == user_id }.sort_by { |row| row.accepted_at.to_s }.reverse
  end

  def self.record!(attributes)
    new(attributes.merge(id: "acc-#{rows.size + 1}")).tap { |row| rows << row }
  end

  # Pages of two, so specs exercise more than one page.
  def self.deleted_before(cutoff, &)
    rows.select { |row| row.account_deleted_at && row.account_deleted_at < cutoff }.each_slice(2, &)
  end

  def self.expire!(row)
    rows.delete(row)
  end
end
