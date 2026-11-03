# frozen_string_literal: true

module Belt
  module Policies
    # Who is asking and from where, read off the API Gateway event, for the
    # acceptance record. Works with REST (v1) and HTTP API (v2) events.
    module RequestDetails
      private

      def policies_user_id
        current_user_id
      end

      def policies_user_email
        claims = event.dig('requestContext', 'authorizer', 'claims') ||
                 event.dig('requestContext', 'authorizer', 'jwt', 'claims') || {}
        claims['email']
      end

      def policies_ip_address
        event.dig('requestContext', 'identity', 'sourceIp') || event.dig('requestContext', 'http', 'sourceIp')
      end

      def policies_user_agent
        headers = event['headers'] || {}
        _, value = headers.find { |name, _| name.to_s.casecmp('user-agent').zero? }
        value || event.dig('requestContext', 'identity',
                           'userAgent') || event.dig('requestContext', 'http', 'userAgent')
      end
    end
  end
end
