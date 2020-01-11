%w(digest/sha2 fileutils linkeddata pathname shellwords).map{|_| require _} # library dependencies
class Array
  def R env=nil; find{|el| el.to_s.match? /^https?:/}.R env end
end
class NilClass
  def R env=nil; ''.R env end
end
class RDF::URI
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end
class RDF::Node
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end
class String
  def R env=nil; env ? WebResource.new(self).env(env) : WebResource.new(self) end
end
class WebResource < RDF::URI
  def R e=nil; e ? env(e) : self end
  alias_method :uri, :to_s
end
%w(RDF Audio Calendar Feed HTML Image JS Mail PDF Text Video).map{|f| require_relative 'Formats/' + f } # Formats
%w(POSIX HTTP).map{|p| require_relative 'Protocols/' + p }                                              # Protocols
%w(gunk meta site).map{|config| require_relative 'config/' + config }                                   # Config
