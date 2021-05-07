require 'net/gemini'

class WebResource
  module Gemini
    include URIs
    def fetchGemini
      u = URI(uri)
      puts Net::Gemini.get(u)
    end
  end
  include Gemini
end
