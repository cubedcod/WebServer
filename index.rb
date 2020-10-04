{Formats: %w(URI Archive Audio Calendar Code CSS CSV Feed HTML Image JSON Mail Markdown MIME PDF RDF Subtitle Text Video),
 Protocols: %w(POSIX HTTP),
 config: %w(gunk meta site)}.
  map{|category, components| components.map{|component|
    require_relative "#{category}/#{component}"}}
