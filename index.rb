
%w(URI Archive Audio Calendar CSS Feed HTML Image JS LaTeX Markdown Message PDF RDF SQL Text Video Web YAML).map{|format|
  require_relative 'Formats/' + format}
%w(Gopher HTTP NNTP).map{|protocol|
  require_relative 'Protocols/' + protocol}
%w(meta site).map{|config|
  require_relative 'config/' + config}
