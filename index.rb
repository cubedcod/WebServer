{Formats: %w(URI Archive Audio Calendar Chat Code CSV Feed HTML Image JSON Mail Markdown MIME Org PDF RDF Subtitle Text Video),
 Protocols: %w(Gemini POSIX HTTP NNTP),
 config: %w(gunk meta site)}.
  map{|category, components|
  components.map{|component|
    require_relative "#{category}/#{component}"}}

Verbose = ENV.has_key? 'Verbose'
