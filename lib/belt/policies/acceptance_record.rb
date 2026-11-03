# frozen_string_literal: true

module Belt
  module Policies
    # Mixed into the app's PolicyAcceptance model
    # (lambda/models/policy_acceptance.rb).
    #
    # One row each time a user agreed to a version of a policy: who, which
    # version (and the hash of its text), when, how, and from where. Rows are
    # the record and are never changed, except that account_deleted_at is
    # stamped when the account goes, so a retention job can expire them.
    module AcceptanceRecord
      ATTRIBUTES = %i[user_id email policy version policy_version_id content_sha256
                      accepted_at accepted_via ip_address user_agent account_deleted_at].freeze

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
      end

      def summary
        {
          policy: policy, version: version, accepted_at: accepted_at, accepted_via: accepted_via
        }
      end
    end
  end
end
