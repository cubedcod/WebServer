%w(URI Archive Audio Calendar Code CSS Feed HTML Image JS LaTeX Markdown Message PDF RDF SQL Text Video Web YAML).
                     map{|f| require_relative 'Formats/'   + f }

%w(Gopher HTTP NNTP).map{|p| require_relative 'Protocols/' + p }

%w(gunk meta site).map{|config| require_relative 'config/' + config }
