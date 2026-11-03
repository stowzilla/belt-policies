# frozen_string_literal: true

module Belt
  module Policies
    # A before_action that stops signed-in users who still have to agree to
    # a current policy. The front end gets a 403 with the pending list and
    # can show them, then POST /policies/accept.
    #
    #   class ApplicationController < BeltController::Base
    #     include Belt::Policies::RequireAcceptance
    #     before_action :require_current_policies!
    #   end
    #
    # The routes it guards need `tables: %i[policy_versions policy_acceptances]`
    # (read access is enough) so the Lambda can check.
    module RequireAcceptance
      include RequestDetails

      private

      def require_current_policies!
        return if policies_user_id.to_s.empty?
        # The policies routes themselves stay open, or nobody could accept.
        return if is_a?(Belt::Policies::Controller)

        pending = Belt::Policies.pending_for(policies_user_id)
        return if pending.empty?

        error_response('Please review and accept the current policies', 403,
                       { code: 'policies_pending', pending: pending.map(&:summary) })
      end
    end
  end
end
