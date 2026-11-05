# frozen_string_literal: true

module Belt
  module Policies
    # The actions behind the routes `belt g policies` adds. Include it in a
    # controller (the generator writes lambda/controllers/<gateway>/policies_controller.rb)
    # and override any action there.
    #
    #   GET  /policies           current version of every policy (public)
    #   GET  /policies/:slug     one policy's text; ?version= for an older one (public)
    #   GET  /policies/status    what the signed-in user has and hasn't agreed to;
    #                            ?subject_id= for acceptances about a subject
    #   POST /policies/accept    { "policies": ["terms-of-service", …] or
    #                              [{ "policy": "terms-of-service", "version": "2026-11-02" }],
    #                              "via": "signup", "subject_id": "child-abc123", "metadata": { … } }
    #
    # The signed-in user comes from #current_user_id; override
    # #policies_user_id (and #policies_user_email) to use something else.
    # Override #policies_may_accept?(subject_id) to refuse an acceptance:
    # a token that may not agree to anything, or a subject the user doesn't
    # own.
    module Controller
      include RequestDetails

      def index
        success_response(policies: Belt::Policies.current.values.sort_by(&:policy).map(&:summary))
      end

      def show
        slug = params[:slug].to_s
        version = if params[:version].to_s.empty?
                    Belt::Policies.current_version(slug)
                  else
                    Belt::Policies.find_version(
                      slug, params[:version]
                    )
                  end
        return error_response('Policy not found', 404) unless version

        current = Belt::Policies.current_version(slug)
        success_response(policy: version.summary.merge(content: version.content,
                                                       current: current&.version == version.version))
      end

      def status
        return error_response('Authentication required', 401) if policies_user_id.to_s.empty?

        success_response(Belt::Policies.status_for(policies_user_id, subject_id: presence(params[:subject_id])))
      end

      def accept
        return error_response('Authentication required', 401) if policies_user_id.to_s.empty?

        subject_id = presence(body['subject_id'])
        unless policies_may_accept?(subject_id)
          return error_response('Not allowed to accept policies', 403, { code: 'acceptance_not_allowed' })
        end

        Belt::Policies.accept!(
          user_id: policies_user_id, email: policies_user_email,
          policies: requested_policies, via: (body['via'] || 'web').to_s,
          ip_address: policies_ip_address, user_agent: policies_user_agent,
          subject_id: subject_id, metadata: body['metadata']
        )
        success_response(Belt::Policies.status_for(policies_user_id, subject_id: subject_id))
      rescue Belt::Policies::StaleVersion => e
        error_response('This policy changed since it was shown. Show the current version and ask again.', 409,
                       { code: 'stale_policy_version', policy: e.policy, version: e.version,
                         current_version: e.current_version })
      rescue Belt::Policies::UnknownPolicy => e
        error_response(e.message, 422, { code: 'unknown_policy', policy: e.policy })
      rescue ArgumentError => e
        error_response(e.message, 422)
      end

      private

      # Whether the signed-in user may record an acceptance (about
      # subject_id, when given). Everyone may, unless the app says otherwise.
      def policies_may_accept?(_subject_id)
        true
      end

      def presence(value)
        value.to_s.empty? ? nil : value.to_s
      end

      # "policies": [...] or a single "policy" (+ "version").
      def requested_policies
        return body['policies'] if body['policies'].is_a?(Array)
        return [{ 'policy' => body['policy'], 'version' => body['version'] }.compact] if body['policy']

        []
      end
    end
  end
end
