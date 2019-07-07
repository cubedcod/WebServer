%w{
brotli
cgi csv
date digest/sha2 dimensions
exif
fileutils
httparty
icalendar
json
linkeddata
mail
nokogiri
open-uri
pathname
rack rdf redcarpet
shellwords
}.map{|r|require r}
class RDF::URI
  def R; WebResource.new to_s end
end
class RDF::Node
  def R; WebResource.new to_s end
end
class String
  def R env=nil
    if env
      (WebResource.new self).environment env
    else
      (WebResource.new self)
    end
  end
end
class WebResource < RDF::URI
  def R; self end
  module URIs
    W3       = 'http://www.w3.org/'
    DC       = 'http://purl.org/dc/terms/'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Abstract = DC   + 'abstract'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    Date     = DC   + 'date'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Post     = SIOC + 'Post'
    Schema   = 'http://schema.org/'
    Title    = DC   + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'
    CacheDir = '../.cache/web/'
    ConfDir = Pathname.new(__dir__).join('../config').relative_path_from Pathname.new Dir.pwd
  end
  include URIs
  alias_method :uri, :to_s
end
# require library and site config
%w(POSIX HTTP).map{|_| require_relative _}
%w(Audio Calendar CSS Feed HTML Image JS Mail Text Video Web).map{|_| require_relative 'Formats/' + _}
require_relative '../config/site.rb'
class WebResource
  module URIs # build extension->format mapping after all readers have been defined
    Extensions = RDF::Format.file_extensions.invert
  end
end
