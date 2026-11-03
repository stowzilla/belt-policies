# frozen_string_literal: true

require 'date'
require 'digest'
require 'yaml'

module Belt
  module Policies
    # One policy file in the app's policies/ directory: YAML front matter
    # (title, version, …) followed by the markdown people read.
    #
    #   ---
    #   title: Terms of Service
    #   version: 2026-11-02
    #   effective_date: 2026-11-02
    #   requires_acceptance: true
    #   requires_reacceptance: true
    #   draft: true
    #   ---
    #   # Terms of Service
    #   …
    #
    # The slug is the file name (policies/terms-of-service.md → terms-of-service).
    class Document
      FRONT_MATTER = /\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)/m
      SLUG = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

      attr_reader :path, :slug, :front_matter, :body

      def self.all(dir)
        Dir.glob(File.join(dir, '*.md')).filter_map do |path|
          next if File.basename(path).casecmp('README.md').zero?

          load(path)
        end
      end

      def self.load(path)
        new(path, File.read(path))
      end

      def self.path_for(dir, slug)
        File.join(dir, "#{slug}.md")
      end

      def initialize(path, source)
        @path = path
        @slug = File.basename(path, '.md')
        raise InvalidDocument, "#{path}: file name must be a lowercase-hyphenated slug" unless @slug.match?(SLUG)

        match = source.match(FRONT_MATTER)
        raise InvalidDocument, "#{path}: missing YAML front matter (--- … ---)" unless match

        @front_matter = parse_front_matter(match[1])
        @body = source[match.end(0)..].to_s
        raise InvalidDocument, "#{path}: front matter needs a version" if version.empty?
      end

      def title
        (front_matter['title'] || slug.tr('-', ' ').capitalize).to_s
      end

      def version
        front_matter['version'].to_s
      end

      def effective_date
        (front_matter['effective_date'] || version).to_s
      end

      # Whether people have to agree to it (terms) or it's only published
      # (a cookie policy, an accessibility statement).
      def requires_acceptance?
        front_matter.fetch('requires_acceptance', true) == true
      end

      # When false, people who agreed to an earlier version don't have to agree
      # again — for a typo fix, not for a material change.
      def requires_reacceptance?
        front_matter.fetch('requires_reacceptance', true) == true
      end

      # Drafts are never published. Generated outlines start as drafts.
      def draft?
        front_matter['draft'] == true
      end

      def id
        Policies.version_id(slug, version)
      end

      def sha256
        Digest::SHA256.hexdigest(body)
      end

      # The body hash recorded when `belt policies publish` last ran. Differs
      # from #sha256 once the text is edited without publishing a new version.
      def published_sha256
        front_matter['published_sha256']&.to_s
      end

      def edited_since_published?
        !published_sha256.nil? && published_sha256 != sha256
      end

      # Attributes for the PolicyVersion row this document publishes.
      def version_attributes(published_at:)
        {
          id: id, policy: slug, version: version, title: title,
          effective_date: effective_date, published_at: published_at,
          requires_acceptance: requires_acceptance?, requires_reacceptance: requires_reacceptance?,
          content: body, content_sha256: sha256
        }
      end

      # The file's source with front matter keys changed (nil removes a key).
      # Key order is kept; new keys go at the end.
      def with_front_matter(changes)
        data = front_matter.merge(changes.transform_keys(&:to_s)).compact
        "#{YAML.dump(data)}---\n#{body}" # YAML.dump opens with "---\n"
      end

      private

      def parse_front_matter(yaml)
        data = YAML.safe_load(yaml, permitted_classes: [Date, Time]) || {}
        raise InvalidDocument, "#{path}: front matter must be a YAML mapping" unless data.is_a?(Hash)

        data.transform_keys(&:to_s).transform_values { |v| v.is_a?(Date) || v.is_a?(Time) ? v.strftime('%F') : v }
      rescue Psych::SyntaxError => e
        raise InvalidDocument, "#{path}: front matter is not valid YAML (#{e.message})"
      end
    end
  end
end
