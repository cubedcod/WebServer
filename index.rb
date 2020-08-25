{Formats: %w(URI Archive Audio Calendar CSS CSV Feed HTML Image JSON Mail MIME PDF RDF Text Video),
 Protocols: %w(POSIX HTTP),
 config: %w(gunk meta site)}.
  map{|category, components| components.map{|component|
    require_relative "#{category}/#{component}"}}
