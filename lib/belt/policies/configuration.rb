# frozen_string_literal: true

module Belt
  module Policies
    class Configuration
      # Where the policy markdown lives. Defaults to <app root>/policies.
      attr_writer :policies_dir
      # The app's models (generated into lambda/models by `belt g policies`).
      # A class or a constant name; names resolve lazily so the models can load
      # after this gem.
      attr_accessor :version_model, :acceptance_model
      # Seconds a Lambda keeps the current versions in memory before reading
      # policy_versions again. 0 reads every time.
      attr_accessor :cache_ttl

      def initialize
        @policies_dir = nil
        @version_model = 'PolicyVersion'
        @acceptance_model = 'PolicyAcceptance'
        @cache_ttl = 60
      end

      def policies_dir
        @policies_dir || File.join(app_root, 'policies')
      end

      def version_class
        resolve(version_model)
      end

      def acceptance_class
        resolve(acceptance_model)
      end

      private

      def resolve(model)
        model.is_a?(String) ? Object.const_get(model) : model
      end

      def app_root
        root = Belt.root if Belt.respond_to?(:root)
        root || Dir.pwd
      end
    end
  end
end
