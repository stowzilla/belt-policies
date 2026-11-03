# frozen_string_literal: true

require_relative '../policies'
require_relative '../policies/release'

module Belt
  module Commands
    # `belt policies …` — work with the policy files in policies/.
    class PoliciesCommand
      def self.description
        'List, outline, and publish policies (belt-policies)'
      end

      def self.run(args)
        new.run(args.dup)
      end

      def run(args)
        case args.shift
        when 'list', 'ls', nil then list
        when 'kinds' then kinds
        when 'publish' then publish(args)
        when 'help', '--help', '-h' then help
        else
          warn "Unknown command. Run `belt policies help`.\n"
          exit 1
        end
      end

      private

      def dir
        Belt::Policies.configuration.policies_dir
      end

      def list
        docs = Belt::Policies::Document.all(dir)
        if docs.empty?
          return puts("No policies in #{relative(dir)}/. Outline one with `belt g policy terms-of-service`.")
        end

        puts 'POLICY                         VERSION        ACCEPT     STATE'
        docs.each do |doc|
          puts format('%-30<slug>s %-14<version>s %-10<accept>s %<state>s',
                      slug: doc.slug, version: doc.version, accept: doc.requires_acceptance? ? 'required' : '-',
                      state: state(doc))
        end
      rescue Belt::Policies::InvalidDocument => e
        abort "Error: #{e.message}"
      end

      def state(doc)
        return 'draft' if doc.draft?
        return 'edited since published — run `belt policies publish`' if doc.edited_since_published?
        return 'ready (no publish migration yet — run `belt policies publish`)' if doc.published_sha256.nil?

        'published'
      end

      def kinds
        Belt::Policies::Catalog.all.each do |kind|
          accept = kind.requires_acceptance ? 'acceptance required' : ''
          puts format('%-28<slug>s %-48<title>s %<accept>s', slug: kind.slug, title: kind.title, accept: accept)
          puts "#{' ' * 29}aliases: #{kind.aliases.join(', ')}"
        end
        puts "\nAny other slug works too: belt g policy my-policy --title \"My Policy\""
      end

      def publish(args)
        slugs = args.reject { |a| a.start_with?('--') || option_value?(args, a) }
        abort 'Usage: belt policies publish SLUG [SLUG …] [--minor] [--version V] [--force]' if slugs.empty?

        slugs.each do |slug|
          result = Belt::Policies::Release.new(
            slug: slug, policies_dir: dir, root: Dir.pwd,
            version: option(args, '--version'), minor: args.include?('--minor'), force: args.include?('--force')
          ).call
          doc = result.document
          puts "  update  #{relative(doc.path)} (version #{doc.version}" \
               "#{', no re-acceptance' unless doc.requires_reacceptance?})"
          puts "  create  #{relative(result.migration_path)}"
        end
        puts "\nRun `belt deploy <env>` (or `belt db:migrate <env>`) to publish."
      rescue Belt::Policies::Error => e
        abort "Error: #{e.message}"
      end

      def help
        puts <<~HELP
          Usage: belt policies COMMAND

          #{Belt::Policies::NOT_LEGAL_ADVICE}

          Commands:
            list                   Policies in policies/ with version and state
            kinds                  Policies `belt g policy` can outline
            publish SLUG [...]     Give it a new version (today's date), clear draft, and
                                   write the db/migrate file that publishes it on deploy
              --minor              Don't ask people who accepted an earlier version again
              --version V          Use V instead of today's date
              --force              Publish even with TODO placeholders left

          Related:
            belt g policies        Install (models, tables, routes, controller)
            belt g policy KIND     Outline a policy as a draft
        HELP
      end

      def option(args, name)
        index = args.index(name)
        return args[index + 1] if index

        args.find { |a| a.start_with?("#{name}=") }&.split('=', 2)&.last
      end

      def option_value?(args, arg)
        index = args.index(arg)
        index&.positive? && args[index - 1] == '--version'
      end

      def relative(path)
        path.delete_prefix("#{Dir.pwd}/")
      end
    end
  end
end
