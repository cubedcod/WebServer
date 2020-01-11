{Formats: %w(RDF Audio Calendar Feed HTML Image JS Mail PDF Text Video), Protocols: %w(POSIX HTTP), config: %w(gunk meta site)}.
map{|a,b| b.map{|c| require_relative "#{a}/#{c}"}}
