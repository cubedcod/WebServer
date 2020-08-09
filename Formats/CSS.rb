# coding: utf-8
module Webize

  module CSS
    def self.cacherefs doc, env
      doc.gsub(/url\(['"]?([^'"\)]+)['"]?\)/){
        m = Regexp.last_match
        ['url(', env[:base].join(m[1]).R(env).href, ')'].join}
    end
  end

end
