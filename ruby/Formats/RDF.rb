# coding: utf-8
class WebResource
  RDFformats = /^(application|text)\/(atom|html|json|rss|turtle|.*urlencoded|xml)/

  # Repository -> file(s)
  def index
    return unless env[:repository]
    updates = []
    env[:repository].each_graph.map{|graph|
      if n = graph.name # named graph
        n = n.R
        docs = []

        # local graph already in canonical location and on timeline (mail/chatlogs in hour-dirs)
        # link nonlocal-origin graph to canonical location
        docs.push (n.path + '.ttl').R unless n.host || n.uri.match?(/^(_|data):/) # don't store blank node or data-URI directly, only in doc-context
        # link nonlocal-origin graph to timeline
        if n.host && (timestamp=graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value) # find timestamp
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
    updates # indexed resources
  end

  def isRDF?; ext == 'ttl' end

  # WebResource -> Graph (RDF#load with format hints)
  def load options = {base_uri: (path.R env)}
    env[:repository] ||= RDF::Repository.new
    nodeStat unless isRDF?
    if file?
      if basename.index('msg.')==0 || path.index('/mail/sent/cur')==0
        # procmail doesnt allow suffix (like .eml), only prefix? email author if you find solution
        # presumably this is due to crazy maildir suffix-rewrites etc
        options[:format] = :mail
      elsif ext.match? /^html?$/
        options[:format] = :html
      elsif %w(Cookies).member? basename
        options[:format] = :sqlite
      elsif %w(Makefile).member?(basename) || %w(cls sty).member?(ext)
        options[:format] = :plaintext
      end
      env[:repository].load relPath, options
    end
  end

  # Graph -> Hash
  def treeFromGraph
    tree = {}
    head = env[:query].has_key? 'head'
    env[:repository].each_triple{|s,p,o|
      s = s.to_s # subject URI
      p = p.to_s # predicate URI
      unless p == 'http://www.w3.org/1999/xhtml/vocab#role' || (head && p == Content)
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
        tree[s] ||= {'uri' => s}                      # subject
        tree[s][p] ||= []                             # predicate
        tree[s][p].push o unless tree[s][p].member? o # object
      end}
    env[:graph] = tree
  end

  module HTTP

    # Graph -> HTTP Response
    def graphResponse
      return notfound if env[:repository].empty?
      format = selectFormat
      dateMeta if local?
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument treeFromGraph # HTML
        when /^application\/atom+xml/
          renderFeed treeFromGraph   # Atom/RSS-feed
        else                         # RDF
          base = ('https://' + env['SERVER_NAME']).R.join env['REQUEST_PATH']
          env[:repository].dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => base, :standard_prefixes => true
        end}
    end

    # WebResource -> HTTP Response
    def localGraph
      rdf, nonRDF = nodes.partition &:isRDF?
      if rdf.size==1 && nonRDF.size==0 && selectFormat == 'text/turtle'
        rdf[0].fileResponse # response on file
      else
        nonRDF.map &:load # load  non-RDF
        index             # index non-RDF
        rdf.map &:load    # load  RDF
        graphResponse     # response
      end
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
        @base = options[:base_uri].R.path.sub(/.u$/,'').R
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
        @doc.lines.map(&:chomp).map{|line|
          fn.call RDF::Statement.new @base, ('https://schema.org/itemListElement').R, line.R unless line.empty?
        }
      end
    end
  end
end
