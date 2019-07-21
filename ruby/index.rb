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
end

%w(URI POSIX HTTP).map{|component|require_relative component}

%w(Audio Calendar CSS Feed HTML Image JS Mail Markdown PDF Text Video Web).map{|format|require_relative 'Formats/' + format}
class WebResource
  module URIs
    Extensions = RDF::Format.file_extensions.invert
  end
end

require_relative '../config/site.rb'
