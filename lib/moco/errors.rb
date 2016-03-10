
module Moco
  class MocoError < StandardError; end
  class ApiError < MocoError
    attr_reader :res
    def initialize(msg, res)
      super(msg)
      @res = res
    end
  end
  class AuthError < MocoError; end
  class CompileError < MocoError; end
  class CompileOptionError < MocoError; end
end
