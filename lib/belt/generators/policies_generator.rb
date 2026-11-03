# frozen_string_literal: true

require 'erb'
require 'fileutils'
require_relative '../policies'

module Belt
  module Generators
    # `belt generate policies` — install policy versions + acceptance records
    # into a Belt app: two models (so `belt setup tables` creates the
    # DynamoDB tables), a controller, routes, and policies/README.md.
    class PoliciesGenerator
      TEMPLATE_DIR = File.expand_path('../policies/templates', __dir__)
      MODELS = %w[policy_version policy_acceptance].freeze
      ROUTES_FILE = 'config/routes.rb'
      ROUTES_MARKER = 'belt-policies'

      def self.description
        'Install versioned policies (terms, privacy, …) and acceptance records'
      end

      def self.run(args)
        return print_help if args.include?('--help') || args.include?('-h')

        new(args).generate
      end

      def self.destroy(args)
        new(args).destroy
      end

      def self.print_help
        puts <<~HELP
          Install versioned policies and acceptance records into your Belt app.

          #{Belt::Policies::NOT_LEGAL_ADVICE}

          Usage: belt generate policies [options]

          Options:
            --gateway NAME     Gateway to add the routes to (default: the first in config/routes.rb)
            --auth NAME        Authorizer for status/accept (default: cognito)
            --with LIST        Also outline these policies, e.g. --with terms-of-service,privacy-policy
            --skip-routes      Don't touch config/routes.rb
            --force            Overwrite existing files

          What gets created:
            lambda/models/policy_version.rb                 PolicyVersion → policy_versions table
            lambda/models/policy_acceptance.rb              PolicyAcceptance → policy_acceptances table
            lambda/controllers/<gateway>/policies_controller.rb
            infrastructure/modules/app/dynamodb.tf          Both tables (via belt setup tables)
            config/routes.rb                                GET /policies, GET /policies/{slug},
                                                            GET /policies/status, POST /policies/accept
            policies/README.md                              How the files and versions work

          Then:
            belt g policy terms-of-service                  Outline a policy (see `belt policies kinds`)
            belt policies publish terms-of-service          When the text is final
            belt deploy dev

          Examples:
            belt g policies
            belt g policies --with terms,privacy
            belt d policies
        HELP
      end

      def initialize(args)
        @force = args.include?('--force')
        @skip_routes = args.include?('--skip-routes')
        @gateway = option(args, '--gateway') || detect_gateway || 'api'
        @auth = option(args, '--auth') || 'cognito'
        @with = option(args, '--with').to_s.split(',').map(&:strip).reject(&:empty?)
        @controller_module = "#{camelize(@gateway)}Controllers"
      end

      def generate
        MODELS.each { |model| write("models/#{model}.rb.erb", "lambda/models/#{model}.rb") }
        write('controllers/policies_controller.rb.erb', controller_path)
        write('policies/README.md.erb', 'policies/README.md')
        inject_routes unless @skip_routes
        sync_tables
        @with.each { |kind| PolicyGenerator.run([kind, '--quiet']) }
        print_success
      end

      def destroy
        (MODELS.map { |m| "lambda/models/#{m}.rb" } + [controller_path]).each { |path| remove(path) }
        remove_routes
        sync_tables
        puts <<~DONE

          ✓ belt-policies removed. policies/*.md and db/migrate files were kept.
            The next `belt deploy` deletes the policy_versions and policy_acceptances
            tables (and the acceptance records in them) unless deletion protection is on.
        DONE
      end

      private

      def controller_path
        "lambda/controllers/#{@gateway}/policies_controller.rb"
      end

      def write(template, dest)
        if File.exist?(dest) && !@force
          puts "  skip    #{dest} (already exists, use --force to overwrite)"
          return
        end

        FileUtils.mkdir_p(File.dirname(dest))
        File.write(dest, ERB.new(File.read(File.join(TEMPLATE_DIR, template)), trim_mode: '-').result(binding))
        puts "  create  #{dest}"
      end

      def remove(path)
        return unless File.exist?(path)

        File.delete(path)
        puts "  remove  #{path}"
      end

      def routes_block
        auth = "auth: :#{@auth}, "
        <<~RUBY.gsub(/^/, '    ')
          # Policies (#{ROUTES_MARKER}): current versions are public; status and
          # accepting need a signed-in user. See policies/README.md.
          get 'policies', to: 'policies#index', tables: [:policy_versions]
          get 'policies/status', to: 'policies#status', #{auth}tables: %i[policy_versions policy_acceptances]
          post 'policies/accept', to: 'policies#accept', #{auth}tables: %i[policy_versions policy_acceptances]
          get 'policies/:slug', to: 'policies#show', tables: [:policy_versions]
          # end #{ROUTES_MARKER}
        RUBY
      end

      def inject_routes
        unless File.exist?(ROUTES_FILE)
          puts "  skip    #{ROUTES_FILE} (not found — add the routes from policies/README.md yourself)"
          return
        end

        content = File.read(ROUTES_FILE)
        return puts("  skip    #{ROUTES_FILE} (policy routes already there)") if content.include?(ROUTES_MARKER)

        updated = insert_into_gateway(content)
        unless updated
          puts "  skip    #{ROUTES_FILE} (no `gateway :#{@gateway} do` block — add the routes yourself)"
          return
        end

        File.write(ROUTES_FILE, updated)
        puts "  update  #{ROUTES_FILE} (policy routes in gateway :#{@gateway})"
      end

      # Insert the routes before the `end` that closes `gateway :<name> do`.
      def insert_into_gateway(content)
        lines = content.lines
        start = lines.index { |l| l.match?(/^\s*gateway\s+:#{Regexp.escape(@gateway)}\b.*\bdo\b/) }
        return nil unless start

        indent = lines[start][/^\s*/]
        finish = ((start + 1)...lines.size).find { |i| lines[i].match?(/^#{indent}end\b/) }
        return nil unless finish

        lines.insert(finish, "\n#{routes_block}")
        lines.join
      end

      def remove_routes
        return unless File.exist?(ROUTES_FILE)

        content = File.read(ROUTES_FILE)
        pattern = /\n?^\s*# Policies \(#{ROUTES_MARKER}\).*?# end #{ROUTES_MARKER}\n/m
        return unless content.match?(pattern)

        File.write(ROUTES_FILE, content.sub(pattern, ''))
        puts "  update  #{ROUTES_FILE} (removed policy routes)"
      end

      def sync_tables
        return unless defined?(Belt::CLI::TablesCommand)

        Belt::CLI::TablesCommand.sync_all_environments
      end

      def detect_gateway
        return nil unless File.exist?(ROUTES_FILE)

        File.read(ROUTES_FILE)[/^\s*gateway\s+:(\w+)/, 1]
      end

      def option(args, name)
        index = args.index(name)
        return args[index + 1] if index

        args.find { |a| a.start_with?("#{name}=") }&.split('=', 2)&.last
      end

      def camelize(word)
        word.to_s.split('_').map(&:capitalize).join
      end

      def print_success
        puts <<~DONE

          ✓ belt-policies installed.

          #{Belt::Policies::NOT_LEGAL_ADVICE}

          Next:
            belt g policy terms-of-service       # outline a policy (`belt policies kinds` lists them)
            # replace every TODO in policies/<slug>.md with your real text, then:
            belt policies publish terms-of-service
            belt deploy dev

          In your app:
            GET  /policies/status   → { pending: [...] } for the signed-in user
            POST /policies/accept   { "policies": [{ "policy": "terms-of-service", "version": "…" }], "via": "signup" }

          To block signed-in users until they accept, in ApplicationController:
            include Belt::Policies::RequireAcceptance
            before_action :require_current_policies!
        DONE
      end
    end
  end
end

require_relative 'policy_generator'
