#require 'crass'
module Webize
  module CSS

    def self.clean str
      str.gsub(/@font-face\s*{[^}]+}/, '').gsub(/@import ('[^']+'|"[^"]+"|url\([^\)]+\));/,'')
    end

    def self.cleanNode node
      node.content = (clean node.inner_text)
    end

  end
end
