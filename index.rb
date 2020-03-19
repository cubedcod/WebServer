{Formats: %w(RDF Audio Calendar Feed HTML Image JS Mail MIME PDF Text Video),
 Protocols: %w(POSIX HTTP),
 config: %w(gunk meta site)}.
  map{|cat, components| components.map{|component|
    require_relative "#{cat}/#{component}"}}
