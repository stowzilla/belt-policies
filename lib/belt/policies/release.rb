# frozen_string_literal: true

require 'date'
require 'erb'
require 'fileutils'

module Belt
  module Policies
    # `belt policies publish <slug>`: give a policy file a new version, clear
    # draft, record the hash of its text, and write the data migration that
    # copies it into policy_versions on the next `belt deploy`.
    #
    # Nothing touches DynamoDB here; the migration does that, once per
    # environment.
    class Release
      TEMPLATE = File.expand_path('templates/migrations/publish_policies.rb.erb', __dir__)
      MIGRATIONS_DIR = File.join('db', 'migrate')
      PLACEHOLDER = /\bTODO\b|NOT LEGAL ADVICE\. belt-policies wrote this outline/

      Result = Struct.new(:document, :migration_path, keyword_init: true)

      def initialize(slug:, policies_dir:, root: Dir.pwd, version: nil, minor: false, force: false, today: Date.today)
        @slug = Catalog.normalize(slug)
        @policies_dir = policies_dir
        @root = root
        @version = version&.to_s
        @minor = minor
        @force = force
        @today = today
      end

      def call
        path = Document.path_for(@policies_dir, @slug)
        unless File.exist?(path)
          raise Error,
                "No policy at #{relative(path)}. Create one with `belt g policy #{@slug}`."
        end

        doc = Document.load(path)
        check_unchanged!(doc)
        check_placeholders!(doc)
        version = next_version(doc)

        effective_date = @version ? doc.effective_date : @today.strftime('%F')
        File.write(path, doc.with_front_matter(
                           'version' => version, 'effective_date' => effective_date,
                           'requires_reacceptance' => !@minor, 'draft' => nil, 'published_sha256' => doc.sha256
                         ))
        Result.new(document: Document.load(path), migration_path: write_migration(version))
      end

      private

      def check_unchanged!(doc)
        return if @version || doc.draft? || doc.published_sha256 != doc.sha256

        raise Error, "#{@slug} #{doc.version} is already published and its text hasn't changed. " \
                     'Edit it first, or pass --version to force a new version.'
      end

      def check_placeholders!(doc)
        return if @force || !doc.body.match?(PLACEHOLDER)

        raise Error, "#{relative(doc.path)} still has TODO placeholders or the generated outline note. " \
                     'Replace them with your real text (pass --force to publish anyway).'
      end

      # Today's date, or today.2, .3 … when today's is already taken by a
      # different published text.
      def next_version(doc)
        return @version if @version

        base = @today.strftime('%F')
        return base unless taken?(doc, base)

        (2..).each do |n|
          candidate = "#{base}.#{n}"
          return candidate unless taken?(doc, candidate)
        end
      end

      # A version is taken once `belt policies publish` has given it to some
      # text (draft cleared, hash recorded).
      def taken?(doc, version)
        doc.version == version && !doc.draft? && !doc.published_sha256.nil?
      end

      def write_migration(version)
        dir = File.join(@root, MIGRATIONS_DIR)
        FileUtils.mkdir_p(dir)
        name = migration_name(version)
        existing = Dir.glob(File.join(dir, "*_#{name}.rb")).first
        return existing if existing

        path = File.join(dir, "#{next_timestamp(dir)}_#{name}.rb")
        @class_name = name.split('_').map(&:capitalize).join
        File.write(path, ERB.new(File.read(TEMPLATE), trim_mode: '-').result(binding))
        path
      end

      def migration_name(version)
        "publish_#{@slug.tr('-', '_')}_#{version.gsub(/[^0-9a-z]+/i, '_').downcase}"
      end

      # Migrations are keyed by timestamp, so never reuse one — two policies
      # published in the same second get consecutive seconds.
      def next_timestamp(dir)
        now = Time.now.utc.strftime('%Y%m%d%H%M%S').to_i
        latest = Dir.glob(File.join(dir, '*.rb')).filter_map { |f| File.basename(f)[/\A(\d{14})_/, 1]&.to_i }.max
        [now, latest.to_i + 1].max.to_s
      end

      def relative(path)
        path.delete_prefix("#{@root}/")
      end
    end
  end
end
