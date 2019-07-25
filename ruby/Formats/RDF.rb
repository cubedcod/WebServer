class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # stash Turtle in locations derived from graph URI(s)
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

  # load resource to RDF graph
  def load graph, options = {}
    if basename.split('.')[0] == 'msg'
      options[:format] = :mail
    elsif ext == 'html'
      options[:format] = :html
    elsif %w(Cookies).member? basename
      options[:format] = :sqlite
    end
    #puts "load #{relPath}"
    graph.load relPath, options
  end

  # RDF::Graph -> Hash with URI keys (HTML/Feed renderer input)
  def treeFromGraph graph ; tree = {}
    head = q.has_key? 'head'
    graph.each_triple{|s,p,o|
      s = s.to_s; p = p.to_s # subject URI, predicate URI
      unless head && p == Content
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        tree[s][p].push o unless tree[s][p].member? o # object
      end}
    @r[:graph] = tree
    tree
  end

end
module Webize
  module URIlist
    class Format < RDF::Format
      content_type 'text/uri-list',
                   extension: :u
      content_encoding 'utf-8'

      reader { Reader }
    end

    class Reader < RDF::Reader
      include WebResource::URIs
      format Format

      def initialize(input = $stdin, options = {}, &block)
        @base = options[:base_uri].path.sub(/.u$/,'').R
        @doc = input.respond_to?(:read) ? input.read : input
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        fn.call RDF::Statement.new(@base, Type.R, (Schema+'BreadcrumbList').R)
        @doc.lines.map{|line|
          fn.call RDF::Statement.new(@base, ('https://schema.org/itemListElement').R, line.chomp.R)}
      end
    end
  end
end
