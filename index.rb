{Formats: %w(RDF Audio Calendar Feed HTML Image JS Mail PDF Text Video), Protocols: %w(POSIX HTTP),
 config: %w(gunk meta site)}.
  map{|cat, parts| parts.map{|p| require_relative "#{cat}/#{p}" }}
