class Hash
  def R # cast to WebResource
    WebResource.new(uri).data self
  end
  # URI accessor
  def uri; self["uri"] end
end

class WebResource
  module NotRDF
    class Format < RDF::Format
      content_encoding 'utf-8'
      reader { WebResource::NotRDF::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

    def initialize(input = $stdin, options = {}, &block)
        @doc = (input.respond_to?(:read) ? input : StringIO.new(input.to_s)).read.to_utf8
        @base = options[:base_uri]
        @host = @base.host
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
        scanContent{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal (if [Abstract,Content].member? p
                                                                                    WebResource::HTML.clean o
                                                                                   else
                                                                                     o
                                                                                    end)
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

    end
  end
  module HTTP

    # tree with nested S -> P -> O indexing
    def treeFromGraph graph
      g = {}                    # empty tree

      # traverse
      graph.each_triple{|s,p,o| # (subject,predicate,object) triple
        s = s.to_s; p = p.to_s  # subject, predicate
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
        g[s] ||= {'uri'=>s}                      # insert subject
        g[s][p] ||= []                           # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object

      g # tree
    end

    def graphResponse graph
      return notfound if graph.empty?

      # response metadata
      @r[:Response] ||= {}
      dateMeta if localNode?
      format = selectFormat
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      unless !@r[:links] || @r[:links].empty?
        @r[:Response].update({'Link' => @r[:links].map{|type,uri|
                                "<#{uri}>; rel=#{type}"}.intersperse(', ').join})
      end

      # generator called by need
      entity @r, ->{
        case format
        when /^text\/html/
          if qs == '?data'
            '/mashlib/databrowser.html'.R    # static HTML w/ databrowser source
          else
            htmlDocument treeFromGraph graph # generated HTML
          end
        when FeedMIME
          renderFeed treeFromGraph graph     # generated feed
        else                                 # RDF
          graph.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true
        end}
    end

  end
  module URIs

    def [] p; (@data||{})[p].justArray end
    def a type; types.member? type end
    def data d={}; @data = (@data||{}).merge(d); self end
    def resources; lines.map &:R end
    def types; @types ||= self[Type].select{|t|t.respond_to? :uri}.map(&:uri) end

  end
  module HTML

    Treeize = -> graph {
      t = {}
      # visit nodes
      (graph.class==Array ? graph : graph.values).map{|node| re = node.R
        cursor = t  # cursor start
        # traverse
        [re.host ? re.host.split('.').reverse : nil, re.parts, re.qs, re.fragment].flatten.compact.map{|name|
          cursor = cursor[name] ||= {}}
        if cursor[:RDF] # merge to node
          node.map{|k,v|
            cursor[:RDF][k] = cursor[:RDF][k].justArray.concat v.justArray unless k == 'uri'}
        else
          cursor[:RDF] = node # insert node
        end}
      t } # tree

  end
  module Webize
    include MIME
    Triplr = {}

    BasicSlugs = %w{
 article archives articles
 blog blogs blogspot
 columns co com comment comments
 edu entry
 feed feeds feedproxy forum forums
 go google gov
 html index local medium
 net news org p php post
 r reddit rss rssfeed
 sports source story
 t the threads topic tumblr
 uk utm www}

    def index g
      updates = []
      g.each_graph.map{|graph|
        n = graph.name.R
        graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value.do{|t| # timestamp
          # doc URI in timeline
          doc = ['/' + t.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),  # hour-dir
                 %w{host path query fragment}.map{|a|n.send(a).do{|p|p.split(/[\W_]/)}},'ttl']. #  slugs
                 flatten.-([nil,'',*BasicSlugs]).join('.').R  # apply skiplist, mint URI
          # store version
          unless doc.e
            doc.dir.mkdir
            RDF::Writer.open(doc.localPath){|f|f << graph}
            updates << doc
            puts  "\e[32m+\e[0m http://localhost:8000" + doc.stripDoc
          else
            #puts  "= http://localhost:8000" + doc.stripDoc
          end
          true}}
      updates
    end

    def triplrJSON &f
      tree = ::JSON.parse readFile.to_utf8
      if hostTriples = @r && Triplr[:JSON][@r['SERVER_NAME']]
        send hostTriples, tree, &f
      end
    rescue
      puts "triplrJSON error on #{uri}"
    end

  end
end
