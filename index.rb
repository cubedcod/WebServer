%w(URI Archive Audio Calendar Feed HTML Image JS Mail PDF SQL Text Video).
                     map{|f| require_relative 'Formats/'   + f }

%w(Gopher HTTP NNTP).map{|p| require_relative 'Protocols/' + p }

%w(gunk meta site).map{|config| require_relative 'config/' + config }
