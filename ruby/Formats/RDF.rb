# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # Repository -> file(s)
  def index g
    updates = []
    g.each_graph.map{|graph|
      if n = graph.name
        n = n.R
        docs = []
        # local docs are already stored on timeline (mails+chatlogs stored to hour-dirs) so we only try to index canonical location
        docs.push (n.path + '.ttl').R unless n.host || n.uri.match?(/^_:/)                                     # canonical location
        if n.host && (timestamp=graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value) # timeline location
          docs.push ['/' + timestamp.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),       # hour-dir
                     %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p&&p.split(/[\W_]/)}},'ttl']. # slugs
                      flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                         # skiplist
        end
        docs.map{|doc|
          unless doc.exist? # new document
            doc.dir.mkdir
            RDF::Writer.open(doc.relPath){|f|f << graph}
            updates << doc
            puts  "\e[32m+\e[0m " + ServerAddr + doc.path.sub(/\.ttl$/,'')
          end}
      end}
    updates
  end

  # WebResource -> Graph
  def load graph, options = {}
    if basename.split('.')[0] == 'msg'
      options[:format] = :mail
    elsif ext == 'html'
      options[:format] = :html
    elsif %w(Cookies).member? basename
      options[:format] = :sqlite
    end
    graph.load relPath, options
  end

  # Graph -> Hash
  def treeFromGraph graph ; tree = {}
    head = env[:query].has_key? 'head'
    graph.each_triple{|s,p,o|
      s = s.to_s; p = p.to_s # subject URI, predicate URI
      unless head && p == Content
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        tree[s][p].push o unless tree[s][p].member? o # object
      end}
    @r[:graph] = tree
    tree # renderer input
  end

  module HTTP

    # Graph -> HTTP Response
    def graphResponse graph
      return notfound if graph.empty?
      format = selectFormat
      dateMeta if local?
      @r ||= {resp: {}}
      @r[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      @r[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      @r[:resp].update({'Link' => @r[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !@r[:links] || @r[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument treeFromGraph graph # HTML
        when /^application\/atom+xml/
          renderFeed treeFromGraph graph   # feed
        else                               # RDF
          base = ('https://' + env['SERVER_NAME']).R.join env['REQUEST_PATH']
          graph.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => base, :standard_prefixes => true
        end}
    end

    # WebResource -> HTTP Response
    def localGraph
      graph = RDF::Repository.new
      rdf, nonRDF = nodes.select(&:file?).partition{|node| node.ext == 'ttl'}
      nonRDF.map{|node| node.load graph} # load non-RDF nodes
      index graph                        # index resources from RDFization
      rdf.map{|node| node.load graph}    # load RDF nodes
      nonRDF.map{|node|                  # fs metadata, omitting raw emails and native graph-storage
        node.fsStat graph unless node.basename.split('.')[0]=='msg'}
      graphResponse graph
    end
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
