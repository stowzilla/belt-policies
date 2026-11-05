# frozen_string_literal: true

module Belt
  module Policies
    # Mixed into the app's PolicyAcceptance model
    # (lambda/models/policy_acceptance.rb).
    #
    # One row each time a user agreed to a version of a policy: who, which
    # version (and the hash of its text), when, how, and from where, plus the
    # subject it was about (subject_id, e.g. a child) and app metadata. Rows
    # are the record and are never changed, except that account_deleted_at
    # is stamped when the account goes, and expire_deleted! removes them once
    # the retention period has passed.
    module AcceptanceRecord
      ATTRIBUTES = %i[user_id email policy version policy_version_id content_sha256
                      accepted_at accepted_via ip_address user_agent subject_id metadata
                      account_deleted_at].freeze

      def self.included(base)
        base.attr_accessor(*ATTRIBUTES)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # A user's acceptances, newest first.
        def for_user(user_id)
          where(user_id: user_id, index: 'UserIndex').order(:desc).to_a
        end

        def record!(attributes)
          create!(attributes)
        end

        # Yields pages of rows whose account_deleted_at is before cutoff (an
        # ISO 8601 string), one scan page at a time.
        def deleted_before(cutoff)
          params = { table_name: table_name, filter_expression: '#deleted < :cutoff',
                     expression_attribute_names: { '#deleted' => to_dynamo_key(:account_deleted_at) },
                     expression_attribute_values: { ':cutoff' => cutoff } }
          loop do
            response = dynamodb.scan(params)
            yield response.items.map { |item| instantiate(item) }
            break unless response.last_evaluated_key

            params[:exclusive_start_key] = response.last_evaluated_key
          end
        end

        def expire!(row)
          row.destroy!
        end
      end

      def summary
        {
          policy: policy, version: version, accepted_at: accepted_at, accepted_via: accepted_via,
          subject_id: subject_id
        }.compact
      end
    end
  end
end
