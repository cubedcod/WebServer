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
pathname pdf/reader
rack rdf redcarpet
shellwords
}.map{|r|require r}
class Array
  def justArray; self end
end
class Hash
  def R; WebResource.new(self['uri']).data self end
end
class NilClass
  def justArray; [] end
end
class Object
  def justArray; [self] end
  def R env=nil
    if env
      (WebResource.new to_s).environment env
    else
      (WebResource.new to_s)
    end
  end
end
class WebResource < RDF::URI
  def R; self end
  def [] p; (@data||{})[p].justArray end
  def data d={}; @data = (@data||{}).merge(d); self end
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

    BasicSlugs = %w{
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r reddit rss rssfeed
 sports source story
 t the threads topic tumblr
 uk utm www}
  end
  include URIs
  alias_method :uri, :to_s
end

%w(POSIX HTTP).map{|_| require_relative _}
%w(Calendar CSS Feed GIF HTML JPEG JSON JS Mail Markdown Plaintext Playlist PNG WebP).map{|_| require_relative 'Formats/' + _}

class WebResource
  module URIs
    Extensions = RDF::Format.file_extensions.invert
  end
end

require_relative '../config/site.rb'
