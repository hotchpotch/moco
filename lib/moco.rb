require "moco/version"
require "thor"
require "pathname"
require 'shellwords'

require 'pry' # XXX

module Moco
  class CLI < Thor
    class CompileOptionError < StandardError; end
    attr_accessor :compile_options
    default_command :compile

    method_option :debug, type: :boolean
    method_option :repos, type: :string, aliases: "-r"
    method_option :username, type: :string, aliases: "-u"
    method_option :password, type: :string, aliases: "-p"
    method_option :verbose, type: :boolean, aliases: "-v"
    method_option :output_dir, type: :string, aliases: "-d"
    desc 'compile', "compile by mbed online compiler"
    def compile
      @compile_options = ::Thor::CoreExt::HashWithIndifferentAccess.new options
      begin
        load_rc(ENV['HOME'])
        load_rc(Dir.pwd)

        set_repos
        set_username
        set_password
        set_output_dir

        # validate!

        say "hello", :blue
        puts 'compile!'
      rescue CompileOptionError => e
        say e.message, :red
      end
    end

    no_commands do
      #def validate!
      #  err = false
      #  p compile_options
      #  %w(username output_dir).each do |key|
      #    unless compile_options[key]
      #      say "option `#{key}` is required. should set args or ~/.mocorc or ./.mocorc", :red
      #      err = true
      #    end
      #  end

      #  exit 1 if err
      #end
      #
      def set_password
        @password = nil
        if compile_options.password
          @password = compile_options.password
        else
          if keyring_command_exist?
            unless @password = get_password_by_username
              system("keyring", "set", "mbed-moco", @username)
              if $?.success?
                @password = get_password_by_username
              end
            end
          end
        end

        unless @password
          raise CompileOptionError.new "option `password` is required. should set args or ~/.mocorc or ./.mocorc or install `keyring` command."
        end
      end

      def get_password_by_username
        pass = `keyring get mbed-moco #{Shellwords.escape @username}`
        if $?.success?
          pass.chomp
        else
          nil
        end
      end

      def keyring_command_exist?
        begin
          !!`keyring -h`
        rescue Errno::ENOENT => e
          return false
        end
      end

      def set_repos
        if compile_options.repos
          @repos = compile_options.repos
        else
          @repos = `hg config paths.default`.chomp
          d "set repos '#{@repos}' by `hg config paths.default`"
        end
        if @repos.nil? || @repos.empty?
          raise CompileOptionError.new "mercurial repository not found."
        end
      end

      def set_username
        if compile_options.username
          @username = compile_options.username
        else
          @username = URI.new(@repos).user
          d "set username by repository URL" if @username
        end

        if @username.nil?
          raise CompileOptionError.new "option `username` is required. should set args or ~/.mocorc or ./.mocorc"
        end
      end

      def set_output_dir
        unless compile_options.output_dir
          raise CompileOptionError.new "option `output_dir` is required. should set args or ~/.mocorc or ./.mocorc"
        end

        @output_dir = Pathname.new(compile_options.output_dir)

        unless @output_dir.directory?
          raise CompileOptionError.new "output_dir `#{compile_options.output_dir}` is not directory."
        end
      end

      def load_rc(dir)
        path = Pathname.new(dir).join('.mocorc')
        if path.file?
          d "mocorc found: #{path}"
          compile_options = @compile_options
          instance_eval path.read, path.to_s, 0
          d "compile options(after load_rc):", @compile_options
        else
          d "mocorc not found: #{path}"
        end
      end

      def d(*msg)
        if options.debug
          say "DEBUG: " + msg.join(" "), :yellow
        end
      end

      def v(*msg)
        if options.debug || options.verbose
          say "VERVOSE: " + msg.join(" "), :orange
        end
      end
    end
  end
end
