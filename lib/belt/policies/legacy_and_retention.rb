# frozen_string_literal: true

module Belt
  module Policies
    # Belt::Policies.import_acceptance! and .expire_deleted!: bringing in
    # acceptances recorded before the app used this gem, and deleting the
    # rows of deleted accounts once the retention period has passed.
    module LegacyAndRetention
      # Record an acceptance made before the app used this gem, keeping its
      # original date. The version doesn't have to be published: legacy rows
      # carry no content_sha256 unless you pass one. Running it again for the
      # same user, subject, and policy@version records nothing, so a data
      # migration can be re-run. Returns the new row, or nil.
      #
      #   Belt::Policies.import_acceptance!(
      #     user_id: 'user-1', policy: 'terms-of-service', version: '2025-06-01',
      #     accepted_at: '2025-07-14T09:30:00Z', metadata: { 'source' => 'terms_acceptances' }
      #   )
      def import_acceptance!(user_id:, policy:, version:, accepted_at:, via: 'import', email: nil, ip_address: nil,
                             user_agent: nil, subject_id: nil, metadata: nil, content_sha256: nil)
        raise ArgumentError, 'user_id is required' if user_id.to_s.empty?
        raise ArgumentError, 'policy and version are required' if policy.to_s.empty? || version.to_s.empty?

        accepted_at = Time.iso8601(accepted_at) if accepted_at.is_a?(String)
        subject_id = presence(subject_id)
        id = version_id(policy, version)
        return nil if acceptances_about(user_id, subject_id).any? { |a| version_id(a.policy, a.version) == id }

        configuration.acceptance_class.record!(
          {
            user_id: user_id, policy: policy.to_s, version: version.to_s, policy_version_id: id,
            content_sha256: presence(content_sha256), email: presence(email),
            accepted_at: accepted_at.utc.iso8601, accepted_via: via.to_s, ip_address: presence(ip_address),
            user_agent: presence(user_agent), subject_id: subject_id, metadata: normalize_metadata(metadata)
          }.compact
        )
      end

      # Delete acceptance rows whose account was deleted before the cutoff:
      # older_than: is seconds (3 * 365 * 86_400, or 3.years) or a Time. Reads
      # the table a page at a time, so a daily sweep can call it. Returns the
      # number of rows deleted.
      #
      #   Belt::Policies.expire_deleted!(older_than: 3 * 365 * 86_400)
      def expire_deleted!(older_than:, now: Time.now.utc)
        cutoff = older_than.is_a?(Time) ? older_than : now - older_than.to_i
        model = configuration.acceptance_class
        count = 0
        model.deleted_before(cutoff.utc.iso8601) do |rows|
          rows.each do |row|
            model.expire!(row)
            count += 1
          end
        end
        count
      end
    end
  end
end
