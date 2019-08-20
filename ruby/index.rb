require_relative 'URI'

%w(Gopher HTTP NNTP).map{|proto|
  require_relative 'Protocols/' + proto}

%w(Audio Calendar CSS Feed HTML Image JS LaTeX Markdown Message PDF RDF SQL Text Video Web YAML).map{|format|
  require_relative 'Formats/' + format}

require_relative '../config/site.rb'
