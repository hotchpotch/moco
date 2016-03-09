
require 'faraday'
require 'faraday_middleware'
require 'json'
require 'pry'

module Moco
  class OnlineCompiler
    API_ENDPOINT = 'http://developer.mbed.org/api/v2/tasks/compiler/'
    attr_reader :compile_messages, :options, :faraday
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
      path.join(data['binary']).open('w') {|f|
        f.puts res.body
      }
    end

    def task_id
      @start_result['result']['data']['task_id']
    end

    def task_check
      res = faraday.get("output/#{task_id}")
      raise ApiError.new('response code error') if res.body['code'] != 200
      data = res.body['result']['data']
      @compile_messages = data['new_messages'] || []
      if data['task_complete']
        @task_complete_data = data
        true
      else
        false
      end
    end

    def start
      payload = {
        platform: options.platform,
        repo: options.repo,
        clean: options.clean,
        extra_symbols: options.extra_symbols
      }
      payload.each_key {|key| payload.delete(key) unless payload[key] }
      @start_result = faraday.post('start/', payload).body
    end
  end
end
