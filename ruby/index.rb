# dependencies
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
    Purl     = 'http://purl.org/'
    DC       = Purl + 'dc/terms/'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Stat     = W3   + 'ns/posix/stat#'
    Abstract = DC   + 'abstract'
    Atom     = W3   + '2005/Atom#'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    DCelement = Purl + 'dc/elements/1.1/'
    Date     = DC   + 'date'
    Email    = SIOC + 'MailMessage'
    From     = SIOC + 'has_creator'
    Image    = DC + 'Image'
    Label    = W3 + '2000/01/rdf-schema#label'
    Link     = DC + 'link'
    Mtime    = Stat + 'mtime'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Post     = SIOC + 'Post'
    RSS      = Purl + 'rss/1.0/'
    Resource = W3   + '2000/01/rdf-schema#Resource'
    Schema   = 'http://schema.org/'
    Size     = Stat + 'size'
    Title    = DC   + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'
  end
  include URIs
  alias_method :uri, :to_s
  Cache = '../cache/web/'
  ConfDir = Pathname.new(__dir__).join('../config').relative_path_from Pathname.new Dir.pwd
end
# library components
%w{POSIX Formats HTML HTTP}.map{|i|require_relative i}
# site config
require_relative '../config/site.rb'
