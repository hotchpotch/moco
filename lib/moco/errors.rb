
module Moco
  class MocoError < StandardError; end
  class ApiError < MocoError; end
  class AuthError < MocoError; end
  class CompileOptionError < MocoError; end
end
