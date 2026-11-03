# frozen_string_literal: true

require 'date'
require 'erb'
require 'fileutils'
require_relative '../policies'

module Belt
  module Generators
    # `belt generate policy <kind>` — outline one policy as a draft in
    # policies/<slug>.md. Installs belt-policies first if it isn't yet.
    class PolicyGenerator
      TEMPLATE = File.expand_path('../policies/templates/policies/policy.md.erb', __dir__)

      def self.description
        'Outline a policy (terms-of-service, privacy-policy, …) as a draft in policies/'
      end

      def self.run(args)
        return print_help if args.include?('--help') || args.include?('-h') || args.empty?

        new(args).generate
      end

      def self.destroy(args)
        new(args).destroy
      end

      def self.print_help
        kinds = Belt::Policies::Catalog.all.map { |k| format('  %-28<slug>s %<title>s', slug: k.slug, title: k.title) }
        puts <<~HELP
          Outline a policy as a draft in policies/<slug>.md.

          #{Belt::Policies::NOT_LEGAL_ADVICE}

          Usage: belt generate policy KIND_OR_SLUG [options]

          Options:
            --title TITLE        Title for a policy that isn't a known kind
            --no-acceptance      People don't have to agree to it (published only)
            --force              Overwrite an existing file

          Known kinds (aliases work too, e.g. tos, privacy, cookies, aup, dpa):
          #{kinds.join("\n")}

          Any other slug gets a blank outline:
            belt g policy beta-program-terms --title "Beta Program Terms"

          Examples:
            belt g policy terms-of-service
            belt g policy privacy
            belt d policy cookie-policy
        HELP
      end

      def initialize(args)
        name = args.find { |a| !a.start_with?('--') && !option_value?(args, a) }
        @kind = Belt::Policies::Catalog.find(name)
        @slug = @kind&.slug || Belt::Policies::Catalog.normalize(name)
        @title = option(args, '--title') || @kind&.title || @slug.split('-').map(&:capitalize).join(' ')
        # Unknown slugs default to needing acceptance; --no-acceptance overrides.
        @requires_acceptance = !args.include?('--no-acceptance') && @kind&.requires_acceptance != false
        @summary = @kind&.summary || "TODO: One or two sentences on what this #{@title} covers."
        @sections = @kind&.sections || { 'TODO: First section' => 'What this section covers.' }
        @version = Date.today.strftime('%F')
        @force = args.include?('--force')
        @quiet = args.include?('--quiet') # when `belt g policies --with` calls us
      end

      def generate
        abort 'Usage: belt generate policy KIND_OR_SLUG (see belt g policy --help)' if @slug.empty?
        PoliciesGenerator.run([]) unless File.exist?('lambda/models/policy_version.rb')

        dest = "policies/#{@slug}.md"
        if File.exist?(dest) && !@force
          puts "  skip    #{dest} (already exists, use --force to overwrite)"
          return
        end

        FileUtils.mkdir_p('policies')
        File.write(dest, ERB.new(File.read(TEMPLATE), trim_mode: '-').result(binding))
        puts "  create  #{dest} (draft)"
        return if @quiet

        puts <<~NEXT

          #{Belt::Policies::NOT_LEGAL_ADVICE}

          #{dest} is an outline. Replace every TODO with your real text, then:
            belt policies publish #{@slug}
        NEXT
      end

      def destroy
        dest = "policies/#{@slug}.md"
        return puts("  skip    #{dest} (not found)") unless File.exist?(dest)

        File.delete(dest)
        puts "  remove  #{dest}"
        puts '  Published versions stay in policy_versions, along with who accepted them.'
      end

      private

      def option(args, name)
        index = args.index(name)
        return args[index + 1] if index

        args.find { |a| a.start_with?("#{name}=") }&.split('=', 2)&.last
      end

      def option_value?(args, arg)
        index = args.index(arg)
        index&.positive? && args[index - 1] == '--title'
      end
    end
  end
end

require_relative 'policies_generator'
