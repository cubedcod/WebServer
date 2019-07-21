require 'pathname'
require 'linkeddata'
class RDF::URI
  def R; WebResource.new to_s end
end
class RDF::Node
  def R; WebResource.new to_s end
end
class String
  def R env = nil
    env ? WebResource.new(self).env(env) : WebResource.new(self)
  end
end
class WebResource < RDF::URI
  def R; self end
  alias_method :uri, :to_s

  module URIs
    PWD = Pathname.new Dir.pwd
    CacheDir = (Pathname.new ENV['HOME'] + '/.cache/web').relative_path_from(PWD).to_s + '/'

    W3       = 'http://www.w3.org/'
    DC       = 'http://purl.org/dc/terms/'
    OG       = 'http://ogp.me/ns#'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Abstract = DC + 'abstract'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    Date     = DC + 'date'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Post     = SIOC + 'Post'
    Schema   = 'http://schema.org/'
    Title    = DC + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'
  end
  include URIs
end

%w(POSIX HTTP).map{|component|require_relative component}

%w(Audio Calendar CSS Feed HTML Image JS Mail Markdown PDF Text Video Web).map{|format|
  require_relative 'Formats/' + format}

class WebResource
  module URIs
    Extensions = RDF::Format.file_extensions.invert
  end
end

require_relative '../config/site.rb'
