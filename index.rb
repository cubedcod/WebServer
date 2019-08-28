
%w(URI Archive Audio Calendar CSS Feed HTML Image JS LaTeX Markdown Message PDF RDF SQL Text Video Web YAML).map{|format|
  require_relative 'Formats/' + format}
%w(Gopher HTTP NNTP).map{|proto|
  require_relative 'Protocols/' + proto}

require_relative 'config/site.rb'
