
require 'faraday'
require 'faraday_middleware'
require 'json'

module Moco
  class OnlineCompiler
    API_ENDPOINT = 'http://developer.mbed.org/api/v2/tasks/compiler/'
    attr_reader :options, :faraday
    def initialize(options, logger)
      @options = options
      @faraday = Faraday.new(url: API_ENDPOINT) do |faraday|
        faraday.request :url_encoded
        faraday.response :logger, logger
        faraday.basic_auth options.username, options.password
        faraday.adapter Faraday.default_adapter
        faraday.response :json, content_type: /\bjson$/
      end
    end

    def download(path)
      data = @task_complete_data
      params = {
        repomode: 'True',
        program: data['program'],
        binary: data['binary'],
        task_id: task_id
      }
      res = faraday.get('bin/', params)

      path = path.join(data['binary'])
      path.open('w') {|f|
        f.puts res.body
      }

      {
        path: path,
        size: res.body.size
      }
    end

    def task_id
      @compile_result['result']['data']['task_id']
    end

    def finished?
      @task_complete_data && @task_complete_data['task_complete']
    end

    def compile_messages
      if @task_complete_data
        @task_complete_data['new_messages'] || []
      else
        []
      end
    end

    def compile_error?
      !!compile_messages.detect {|m| m['severity'] && m['severity'] == 'error' }
    end

    def task_check
      res = faraday.get("output/#{task_id}")
      raise ApiError.new('response code is not 200', res) if res.body['code'] != 200
      data = res.body['result']['data']
      @task_complete_data = data
      raise CompileError.new if compile_error?
    end

    def compile
      payload = {
        platform: options.platform,
        repo: options.repository,
        clean: options.clean,
        extra_symbols: options.extra_symbols
      }
      payload.each_key {|key| payload.delete(key) unless payload[key] }
      if options.replace_files && options.replace_files.size > 0
        files = []
        options.replace_files.map do |file|
          if file.file?
            files << { file.to_s => file.read }
          else
            files << { file.to_s => '' }
          end
        end
        payload['replace'] = files.to_json
      end
      res = faraday.post('start/', payload)
      @compile_result = res.body
      raise ApiError.new('response code is not 200', res) if @compile_result['code'] != 200
    end
  end
end
