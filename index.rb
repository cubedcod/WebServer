{Formats: %w(RDF HTML Archive Audio Calendar CSV Feed Image JSON Mail MIME PDF Text Video),
 Protocols: %w(POSIX HTTP),
 config: %w(meta site gunk)}.
  map{|category, components| components.map{|component|
    require_relative "#{category}/#{component}"}}
