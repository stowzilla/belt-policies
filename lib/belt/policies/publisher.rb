# frozen_string_literal: true

require 'time'

module Belt
  module Policies
    # Copies every non-draft policy in policies/*.md into policy_versions.
    #
    # Safe to run any number of times: a version already in the table is left
    # alone. A version whose text changed after it was published is reported,
    # not overwritten — the stored text is what people agreed to. Publish a
    # new version instead (`belt policies publish <slug>`).
    class Publisher
      Result = Struct.new(:slug, :version, :status, keyword_init: true)

      def initialize(dir:, version_class:, now: -> { Time.now.utc }, &say)
        @dir = dir
        @version_class = version_class
        @now = now
        @say = say || ->(_line) {}
      end

      def call
        return [] unless Dir.exist?(@dir)

        Document.all(@dir).map { |doc| publish(doc) }
      end

      private

      def publish(doc)
        return result(doc, :draft, "skip     #{doc.id} (draft)") if doc.draft?

        existing = @version_class.find_version(doc.id)
        return create(doc) unless existing
        return result(doc, :unchanged, "exists   #{doc.id}") if existing.content_sha256 == doc.sha256

        result(doc, :changed, "changed  #{doc.id} — its text differs from the published copy, which is kept. " \
                              "Run `belt policies publish #{doc.slug}` to publish a new version.")
      end

      def create(doc)
        @version_class.create_version!(doc.version_attributes(published_at: @now.call.iso8601))
        result(doc, :published, "publish  #{doc.id}")
      end

      def result(doc, status, line)
        @say.call(line)
        Result.new(slug: doc.slug, version: doc.version, status: status)
      end
    end
  end
end
