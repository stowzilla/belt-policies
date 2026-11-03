# frozen_string_literal: true

module Belt
  module Policies
    # Mixed into the app's PolicyVersion model (lambda/models/policy_version.rb).
    #
    # One row per published version of a policy, keyed "<policy>@<version>".
    # Rows are written by Belt::Policies.publish! and never edited: the
    # content is the exact text people agreed to.
    module VersionRecord
      ATTRIBUTES = %i[policy version title effective_date published_at
                      requires_acceptance requires_reacceptance content content_sha256].freeze

      def self.included(base)
        base.attr_accessor(*ATTRIBUTES)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def find_version(id)
          find(id)
        rescue ActiveItem::RecordNotFound
          nil
        end

        # Every version of every policy. The table holds a few rows per policy.
        def all_versions
          all.to_a
        end

        def create_version!(attributes)
          create!(attributes)
        end
      end

      # What the API shows when listing policies (no content).
      def summary
        {
          policy: policy, version: version, title: title, effective_date: effective_date,
          published_at: published_at, requires_acceptance: requires_acceptance == true,
          requires_reacceptance: requires_reacceptance != false, content_sha256: content_sha256
        }
      end
    end
  end
end
