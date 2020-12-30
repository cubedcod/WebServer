#require 'crass'
module Webize
  module CSS

    def self.cleanNode node
      node.content = (cleanString node.inner_text)
    end

    def self.cleanString str
      str.gsub /@font-face\s*{[^}]+}/, ''
    end

  end
end
