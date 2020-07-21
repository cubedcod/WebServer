{Formats: %w(RDF Archive Audio Calendar Feed HTML Image JSON Mail MIME PDF Text Video),
 Protocols: %w(POSIX HTTP),
 config: %w(meta site gunk)}.
  map{|cat, components| components.map{|component|
    require_relative "#{cat}/#{component}"}}
