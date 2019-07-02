%w{
brotli
cgi
csv
date
digest/sha2
dimensions
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
rack
rdf
redcarpet
shellwords
}.map{|r|require r}

class Array
  def justArray; self end
  def intersperse i; inject([]){|a,b|a << b << i}[0..-2] end
end
class FalseClass
  def do; self end
end
class Hash
  def R; WebResource.new(uri).data self end # preserve data
  def uri; self['uri'] end
end
class NilClass
  def justArray; [] end
  def do; self end
end
class Object
  def justArray; [self] end
  def do; yield self end
  def to_time; [Time, DateTime].member?(self.class) ? self : Time.parse(self) end
end
class RDF::Node
  def R; WebResource.new to_s end
end
class RDF::URI
  def R; WebResource.new to_s end
end
class Symbol
  def R; WebResource.new to_s end
end
class String
  def R env=nil
    if env
      WebResource.new(self).environment env
    else
      WebResource.new self
    end
  end
end

class WebResource < RDF::URI
  def R; self end

  module URIs
    def + u; (to_s + u.to_s).R end
    def [] p; (@data||{})[p].justArray end
    def data d={}; @data = (@data||{}).merge(d); self end
    def types; @types ||= self[Type].select{|t|t.respond_to? :uri}.map(&:uri) end

    # URI constants
    W3       = 'http://www.w3.org/'
    DC       = 'http://purl.org/dc/terms/'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Abstract = DC   + 'abstract'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    DCelement = 'http://purl.org/dc/elements/1.1/'
    Date     = DC   + 'date'
    From     = SIOC + 'has_creator'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Post     = SIOC + 'Post'
    Schema   = 'http://schema.org/'
    Title    = DC   + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'
  end
  include URIs
  alias_method :uri, :to_s
  CacheDir = '../.cache/web/'
  ConfDir = Pathname.new(__dir__).join('../config').relative_path_from Pathname.new Dir.pwd
end

%w{POSIX Formats HTTP ../config/site.rb}.map{|i|
  require_relative i}
