class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # stash Turtle in index locations derived from graph URI(s)
  def index g
    updates = []
    g.each_graph.map{|graph|
      if n = graph.name
        n = n.R
        docs = []
        # local docs are already stored on timeline (mails/chatlogs in hour-dirs), so we only try for canonical location (messageID, username-derived indexes)
        # canonical location
        docs.push (n.path + '.ttl').R unless n.host || n.uri.match?(/^_:/)
        # timeline location
        if n.host && (timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value)
          docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''), # hour-dir
                     %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # slugs
                      flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist
        end
        # store
        #puts docs
        docs.map{|doc|
          unless doc.exist?
            doc.dir.mkdir
            RDF::Writer.open(doc.relPath){|f|f << graph}
            updates << doc
            puts  "\e[32m+\e[0m http://localhost:8000" + doc.path.sub(/\.ttl$/,'')
          end}
      end}
    updates
  end

  def load graph, options = {}
    if basename.split('.')[0] == 'msg'
      options[:format] = :mail
    elsif ext == 'html'
      options[:format] = :html
    end
    graph.load relPath, options
  end

end
