# frozen_string_literal: true

require_relative 'policies/version'
require_relative 'policies/configuration'
require_relative 'policies/document'
require_relative 'policies/catalog'
require_relative 'policies/version_record'
require_relative 'policies/acceptance_record'
require_relative 'policies/publisher'
require_relative 'policies/request_details'
require_relative 'policies/controller'
require_relative 'policies/require_acceptance'

module Belt
  # Versioned policies (Terms of Service, Privacy Policy, …) and the record of
  # who agreed to which version, when, and from where.
  #
  # belt-policies is plumbing, not legal advice. It does not write your
  # policies and cannot tell you what they must say.
  module Policies
    NOT_LEGAL_ADVICE = 'belt-policies is not legal advice. Generated policies are outlines with placeholders, ' \
                       'not finished policies, and nothing in this gem was written or reviewed by a lawyer. ' \
                       'Have a qualified attorney write or review your policies before you rely on them.'

    class Error < StandardError; end
    class InvalidDocument < Error; end

    # The policy isn't published (or doesn't exist).
    class UnknownPolicy < Error
      attr_reader :policy

      def initialize(policy)
        @policy = policy
        super("No published policy named #{policy.inspect}")
      end
    end

    # The caller agreed to a version that is no longer current — the page
    # they read is out of date.
    class StaleVersion < Error
      attr_reader :policy, :version, :current_version

      def initialize(policy, version, current_version)
        @policy = policy
        @version = version
        @current_version = current_version
        super("#{policy} #{version} is not the current version (#{current_version})")
      end
    end

    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
        reset_cache!
      end

      def reset_configuration!
        @configuration = Configuration.new
        reset_cache!
      end

      def version_id(policy, version)
        "#{policy}@#{version}"
      end

      # --- Current versions ---

      # The current (most recently published) version of each policy,
      # { 'terms-of-service' => PolicyVersion, … }. Cached per Lambda for
      # configuration.cache_ttl seconds.
      def current
        ttl = configuration.cache_ttl.to_i
        return @current if @current && ttl.positive? && monotonic - @current_at < ttl

        @current_at = monotonic
        @current = configuration.version_class.all_versions
                                .group_by(&:policy)
                                .transform_values { |versions| versions.max_by { |v| v.published_at.to_s } }
      end

      def current_version(policy)
        current[policy.to_s]
      end

      # A specific published version, or nil.
      def find_version(policy, version)
        configuration.version_class.find_version(version_id(policy, version))
      end

      def reset_cache!
        @current = nil
        @current_at = nil
      end

      # --- Acceptance ---

      # Each policy's standing for this user:
      #   { policies: [{ policy:, version:, title:, requires_acceptance:, accepted:,
      #                  accepted_version:, accepted_at: }, …],
      #     pending: ['terms-of-service', …] }
      def status_for(user_id)
        acceptances = acceptances_for(user_id).group_by(&:policy)
        policies = current.values.sort_by(&:policy).map do |version|
          mine = acceptances.fetch(version.policy, [])
          latest = mine.max_by { |a| a.accepted_at.to_s }
          version.summary.merge(
            accepted: !needs_acceptance?(version, mine) && !mine.empty?,
            pending: needs_acceptance?(version, mine),
            accepted_version: latest&.version,
            accepted_at: latest&.accepted_at
          )
        end
        { policies: policies, pending: policies.select { |p| p[:pending] }.map { |p| p[:policy] } }
      end

      # The current versions this user still has to agree to.
      def pending_for(user_id)
        acceptances = acceptances_for(user_id).group_by(&:policy)
        current.values.sort_by(&:policy).select do |version|
          needs_acceptance?(version, acceptances.fetch(version.policy, []))
        end
      end

      # True when the user has nothing left to agree to (or, given a policy,
      # has agreed to that one's current version).
      def accepted?(user_id, policy = nil)
        pending = pending_for(user_id).map(&:policy)
        policy ? !pending.include?(policy.to_s) : pending.empty?
      end

      # Record that a user agreed to the current version of each policy.
      #
      #   Belt::Policies.accept!(
      #     user_id: current_user_id, email: 'a@example.com',
      #     policies: ['terms-of-service', { 'policy' => 'privacy-policy', 'version' => '2026-11-02' }],
      #     via: 'signup', ip_address: '203.0.113.7', user_agent: 'Mozilla/5.0 …'
      #   )
      #
      # Each entry is a slug or { policy:, version: }. When a version is given
      # it must be the current one (StaleVersion otherwise), so a person is
      # never recorded agreeing to text they didn't see. Agreeing again to a
      # version already accepted records nothing new. Returns the new rows.
      def accept!(user_id:, policies:, via:, email: nil, ip_address: nil, user_agent: nil, at: Time.now.utc)
        raise ArgumentError, 'user_id is required' if user_id.to_s.empty?

        requested = Array(policies).map { |entry| normalize_request(entry) }
        raise ArgumentError, 'name at least one policy to accept' if requested.empty?

        versions = requested.map { |policy, version| resolve_current(policy, version) }
        details = { email: presence(email), accepted_at: at.utc.iso8601, accepted_via: via.to_s,
                    ip_address: presence(ip_address), user_agent: presence(user_agent) }.compact
        record_acceptances(user_id, versions.uniq(&:policy), details)
      end

      # Every time this user agreed to anything, newest first.
      def history_for(user_id)
        acceptances_for(user_id)
      end

      # Stamp a deleted account's acceptance rows so a retention job can
      # expire them later. The rows themselves are not deleted here.
      def account_deleted!(user_id, at: Time.now.utc)
        acceptances_for(user_id).each do |acceptance|
          next if acceptance.account_deleted_at

          acceptance.update(account_deleted_at: at.utc.iso8601)
        end
      end

      # --- Publishing ---

      # Copy every non-draft policies/*.md into policy_versions. Called by the
      # data migrations `belt policies publish` writes, so it runs during
      # `belt deploy`. Yields a progress line per policy.
      def publish!(dir: configuration.policies_dir, &say)
        results = Publisher.new(dir: dir, version_class: configuration.version_class, &say).call
        reset_cache!
        results
      end

      private

      def record_acceptances(user_id, versions, details)
        already = acceptances_for(user_id).to_set { |a| version_id(a.policy, a.version) }
        versions.reject { |v| already.include?(version_id(v.policy, v.version)) }.map do |version|
          configuration.acceptance_class.record!(
            user_id: user_id, policy: version.policy, version: version.version,
            policy_version_id: version_id(version.policy, version.version),
            content_sha256: version.content_sha256, **details
          )
        end
      end

      # Whether this user still has to agree to the current version, given
      # their acceptances of that policy.
      def needs_acceptance?(version, acceptances)
        return false unless version.requires_acceptance == true
        return false if acceptances.any? { |a| a.version == version.version }
        return false if version.requires_reacceptance == false && acceptances.any?

        true
      end

      def acceptances_for(user_id)
        return [] if user_id.to_s.empty?

        configuration.acceptance_class.for_user(user_id)
      end

      def normalize_request(entry)
        case entry
        when Hash
          entry = entry.transform_keys(&:to_s)
          [(entry['policy'] || entry['slug']).to_s, entry['version']&.to_s]
        else
          [entry.to_s, nil]
        end
      end

      def resolve_current(policy, version)
        current_version = current_version(policy)
        raise UnknownPolicy, policy unless current_version
        if version && version != current_version.version
          raise StaleVersion.new(policy, version,
                                 current_version.version)
        end

        current_version
      end

      def presence(value)
        value.to_s.empty? ? nil : value.to_s
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
