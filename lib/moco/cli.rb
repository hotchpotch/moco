
require "thor"
require "pathname"
require "shellwords"
require "logger"
require "stringio"

module Moco
  class CLI < Thor
    REPLACE_FILE_EXT = %w(.c .cpp .h .cxx .hpp .hxx)
    WAIT_CHECK_TIMES = 50

    attr_accessor :compile_options
    default_command :compile

    method_option :delete_password, type: :boolean
    method_option :repo, type: :string, aliases: "-r"
    method_option :username, type: :string, aliases: "-u"
    method_option :platform, type: :string, aliases: "-b"
    method_option :password, type: :string, aliases: "-p"
    method_option :verbose, type: :boolean, aliases: "-v"
    method_option :output_dir, type: :string, aliases: "-d"
    desc 'compile', "compile by mbed online compiler"

    def compile
      @compile_options = ::Thor::CoreExt::HashWithIndifferentAccess.new options
      begin
        sio = StringIO.new
        logger = Logger.new(sio)

        load_rc(ENV['HOME'])
        load_rc(Dir.pwd)

        set_repo
        set_username
        del_password if @compile_options.delete_password
        set_password
        set_output_dir
        set_replace_files

        check_required_options

        compiler = OnlineCompiler.new(compile_options.merge({
          repo: @repo,
          username: @username,
          password: @password,
          replace_files: @replace_files
        }), logger)

        compiler.compile

        WAIT_CHECK_TIMES.times do
          compiler.task_check
          render_messages compiler.compile_messages

          break if compiler.finished?

          sleep 2
        end

        say "Online compile successed! download firmare.", :green
        download_info = compiler.download(@output_dir)
        say "-> firmware(#{download_info[:size]} byte): #{download_info[:path]}"

        sio.rewind
        d sio.read

      rescue CompileError => e
        say "[FAILED] mbed online compile failed", :red
        render_messages compiler.compile_messages
        exit 1
      rescue AuthError, ApiError => e
        say "[FAILED] mbed compile #{e.name}. #{e.message}", :red
        sio.rewind
        say sio.read
        exit 1
      rescue CompileOptionError => e
        say "[FAILED] #{e.message}", :red
        help 'compile'
        exit 1
      end
    end

    no_commands do
      def render_messages(messages)
        messages.each do |message|
          d message.inspect
          case message["severity"]
          when "error"
            say error_message_format(message), :red
          when "warning"
            say error_message_format(message), :yellow
          when "verbose"
            if message["type"] == "info"
              m = message["message"] || ''
              case m.split(':')[0]
              when 'Link'
                d m
              else
                say message["message"]
              end
            end
          end
        end
      end

      def error_message_format(message)
        [
          message["file"].sub('/src/', ''),
          message["line"],
          message["col"],
          message["severity"],
          message["message"],
        ].join(":")
      end

      def set_replace_files
        if @compile_options.replace_files
          files = @compile_options.replace_files
        else
          files = []
          `hg status -m`.each_line do |line|
            file = line.split(' ')[1..-1].join(' ')
            files << file if REPLACE_FILE_EXT.include? File.extname(file)
          end
          files.uniq!
        end

        @replace_files = []
        files.each do |file|
          file = Pathname.new(file)
          @replace_files << file if file.file?
        end
        d "replace_files: #{@replace_files.join(', ')}"
      end

      def check_required_options
        %w(platform).each do |key|
          unless @compile_options[key]
            raise CompileOptionError.new "option `#{key}` is required.\nshould set command-line arguments or ~/.mocorc or ./.mocorc"
          end
        end
      end

      def del_password
        say "delete password on keyring"
        if keyring_command_exist?
          system("keyring", "del", "mbed-moco", @username)
        end
      end

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

      def set_repo
        if compile_options.repo
          @repo = compile_options.repo
        else
          @repo = `hg config paths.default`.chomp
          d "set repo '#{@repo}' by `hg config paths.default`"
        end
        if @repo.nil? || @repo.empty?
          raise CompileOptionError.new "mercurial repoitory not found."
        end
      end

      def set_username
        if compile_options.username
          @username = compile_options.username
        else
          @username = URI.new(@repo).user
          d "set username by repoitory URL" if @username
        end

        if @username.nil?
          raise CompileOptionError.new "option `username` is required. should set args or ~/.mocorc or ./.mocorc"
        end
      end

      def set_output_dir
        if compile_options.output_dir
          @output_dir = Pathname.new(compile_options.output_dir)
        else
          @output_dir = Pathname.new(Dir.pwd)
        end

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
        if options.verbose
          say "VERBOSE: " + msg.join(" "), :yellow
        end
      end
    end
  end
end
