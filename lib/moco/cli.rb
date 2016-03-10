
require "thor"
require "pathname"
require "shellwords"
require "logger"
require "stringio"
require "uri"

module Moco
  class CLI < Thor
    TARGET_FILE_EXT = %w(.c .cpp .h .cxx .hpp .hxx .bld)
    DEFAULT_REPOS = 'https://developer.mbed.org/users/hotchpotch/code/moco/'
    WAIT_CHECK_TIMES = 50

    attr_accessor :compile_options
    default_command :compile

    method_option :delete_password, type: :boolean
    method_option :replace_files, type: :array, aliases: "-f"
    method_option :repository, type: :string, aliases: "-r"
    method_option :username, type: :string, aliases: "-u"
    method_option :platform, type: :string, aliases: "-b"
    method_option :password, type: :string, aliases: "-p"
    method_option :debug, type: :boolean
    method_option :output_dir, type: :string, aliases: "-d"
    desc 'compile', "compile by mbed online compiler"

    def compile
      @compile_options = ::Thor::CoreExt::HashWithIndifferentAccess.new options
      begin
        sio = StringIO.new
        logger = Logger.new(sio)

        load_rc(ENV['HOME'])
        load_rc(Dir.pwd)

        set_repository
        set_username
        del_password if @compile_options.delete_password

        set_password
        set_output_dir
        set_replace_files

        check_required_options

        compiler = OnlineCompiler.new(compile_options.merge({
          repository: @repository,
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
      rescue ApiError => e
        say "[FAILED] mbed compile API error. #{e.message}", :red
        say "- may unknown/mistype platform: #{compile_options.platform}"
        sio.rewind
        say sio.read
        exit 1
      rescue AuthError => e
        say "[FAILED] mbed compile Auth error. #{e.message}", :red
        sio.rewind
        say sio.read
        exit 1
      rescue CompileOptionError => e
        say "[FAILED] #{e.message}", :red
        help 'compile'
        exit 1
      rescue StandardError => e
        sio.rewind
        say sio.read
        raise e
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
        files = []
        if hg_command_exist?
          'hg status 2> /dev/null && hg status -umar'.each_line do |line|
            file = line.split(' ')[1..-1].join(' ')
            files << file if TARGET_FILE_EXT.include? File.extname(file)
          end
        end

        if @compile_options.replace_files
          files.concat @compile_options.replace_files
        end

        @replace_files = []
        files.sort.uniq.each do |file|
          @replace_files << Pathname.new(file)
        end

        unless @replace_files.empty?
          d "replace_files: #{@replace_files.join(', ')}"
        end
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
        case compile_options.password
        when Proc
          @password = compile_options.password.call(@username)
        when String
          @password = compile_options.password
        else
          @password = nil
        end
      end

      def keyring
        if keyring_command_exist?
          Proc.new {|username|
            username ||= 'mbed-user'
            unless password = get_password_by_username(username)
              system("keyring", "set", "mbed-moco", username)
              if $?.success?
                password = get_password_by_username(username)
              end
            end
            password
          }
        else
          raise MocoError.new <<-EOF
Can't find keyring command.
You should install keyring.
- https://pypi.python.org/pypi/keyring
          EOF
        end
      end

      def get_password_by_username(username)
        pass = `keyring get mbed-moco #{Shellwords.escape username}`
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

      def hg_command_exist?
        begin
          !!`hg -h`
        rescue Errno::ENOENT => e
          return false
        end
      end

      def quiet_error_cmd(str)
        begin
          orig_error = $stderr
          $stderr = StringIO.new
          res = `#{str}`
          require 'pry'

          binding.pry
          ''
        ensure
          $stderr = orig_error
        end
      end

      def set_repository
        if compile_options.repository
          @repository = compile_options.repository
        elsif hg_command_exist?
          @repository = `hg config paths.default`.chomp
          unless @repository.empty?
            d "set repository '#{@repository}' by `hg config paths.default`"
          end
        end

        if @repository.nil? || @repository.empty?
          d "repository is empty. set default repository: #{DEFAULT_REPOS}"
          @repository = DEFAULT_REPOS
        end
      end

      def set_username
        if compile_options.username
          @username = compile_options.username
        else
          if @repository
            @username = URI.parse(@repository).user
            d "set username by repository URL" if @username
          end
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
          options = ::Thor::CoreExt::HashWithIndifferentAccess.new
          instance_eval path.read, path.to_s, 0
          @compile_options = options.merge(@compile_options)
          d "compile options(after load_rc):", @compile_options
        else
          d "mocorc not found: #{path}"
        end
      end

      def d(*msg)
        if options.debug?
          say "VERBOSE: " + msg.join(" "), :yellow
        end
      end
    end
  end
end
