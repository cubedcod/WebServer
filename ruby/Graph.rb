class Hash
  def R # cast to WebResource
    WebResource.new(uri).data self
  end
  # URI accessor
  def uri; self["uri"] end
end

class WebResource

  module JSON
    include URIs

    class Format < RDF::Format
      content_type     'application/json+rdf', :extension => :e
      content_encoding 'utf-8'
      reader { WebResource::JSON::Reader }
    end

    # JSON -> RDF
    class Reader < RDF::Reader
      format Format
      def initialize(input = $stdin, options = {}, &block)
        @graph = ::JSON.parse (input.respond_to?(:read) ? input : StringIO.new(input.to_s)).read
        @base = options[:base_uri]
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end
      def each_statement &fn
        @graph.map{|s,r|
          r.map{|p,o|
            o.justArray.map{|o|
              fn.call RDF::Statement.new(@base.join(s), RDF::URI(p),
                                         o.class==Hash ? @base.join(o['uri']) : (l = RDF::Literal o
                                                                                 l.datatype=RDF.XMLLiteral if p == 'http://rdfs.org/sioc/ns#content'
                                                                                 l))} unless p=='uri'}}
      end
      def each_triple &block; each_statement{|s| block.call *s.to_triple} end
    end
  end

  include JSON

  module MIME
    # file -> bool
    def isRDF
      if %w{atom n3 owl rdf ttl}.member? ext
        return true
      elsif feedMIME?
        return true
      end
      false
    end

    # file -> file
    def toRDF
      isRDF ? self : rdfize
    end

    # file -> file
    def rdfize # call MIME-mapped triplr, cache output in JSON file, return swapped file-reference
      return self if ext == 'e'
      hash = node.stat.ino.to_s.sha2
      doc = ('/cache/RDF/' + hash[0..2] + '/' + hash[3..-1] + '.e').R
      return doc if doc.e && doc.m > m # rdfization up to date
      graph = {}
      triplrFile{|s,p,o|     graph[s] ||= {'uri' => s}; graph[s][p] ||= []; graph[s][p].push o.class == WebResource ? {'uri' => o.uri} : o unless p == 'uri'}
      if triplr = Triplr[mime]
       send(*triplr){|s,p,o| graph[s] ||= {'uri' => s}; graph[s][p] ||= []; graph[s][p].push o.class == WebResource ? {'uri' => o.uri} : o unless p == 'uri'}
      else
       puts "#{uri}: triplr for #{mime} missing" unless triplr
      end
      doc.writeFile graph.to_json
    end

  end
  module HTTP
    # merge-load JSON and RDF to JSON-pickleable Hash
    def load files
      g = {}                 # init Hash
      graph = RDF::Graph.new # init RDF::Graph

      rdf, misc = files.partition &:isRDF # input-file categories
#      puts "load RDF: ",   rdf.join(' ') unless  rdf.empty?
#      puts "load JSON: ", misc.join(' ') unless misc.empty?

      # RDF
      rdf.map{|n| # each file
        opts = {:base_uri => n}
        opts[:format] = :feed if n.feedMIME?
        graph.load n.localPath, opts rescue puts("error parsing #{n} as RDF")} # load data
      graph.each_triple{|s,p,o| # bind subject,predicate,object
        s = s.to_s; p = p.to_s # subject URI, predicate URI
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal value
        g[s] ||= {'uri'=>s} # insert subject
        g[s][p] ||= []      # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object

      # JSON
      misc.map{|n| # each file
        n.rdfize.do{|transcode| # transcode to RDF
          ::JSON.parse(transcode.readFile). # load data
            map{|s,re| # each resource
            re.map{|p,o| # bind predicate URI  + object(s)
              o.justArray.map{|o| # normalize array of objects
                o = o.R if o.class==Hash # object URI
                g[s] ||= {'uri'=>s} # insert subject
                g[s][p] ||= []      # insert predicate
                g[s][p].push o unless g[s][p].member? o} unless p == 'uri' }}}} # insert object

      g # graph reference
    end

    def graphResponse set
      return notfound if !set || set.empty?

      # output format
      if set.size == 1
        this = set[0]
        extant = this.isRDF && preferredFormat?(this) && this
      end
      format = extant && extant.mime || selectFormat

      # response metadata
      dateMeta if localNode?
      @r[:Response] ||= {}
      @r[:Response].update({'Link' => @r[:links].map{|type,uri| "<#{uri}>; rel=#{type}"}.intersperse(', ').join}) unless !@r[:links] || @r[:links].empty?
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format,
                            'ETag' => [set.sort.map{|r|[r,r.m]}, format].join.sha2})

      # entity generation
      entity @r, ->{
        if extant # body on file
          extant  # return ref to body
        else # generate entity
          if format == 'text/html' # HTML
            htmlDocument load set
          elsif format == 'application/atom+xml' # feed
            renderFeed load set
          else # RDF formats
            g = RDF::Graph.new # initialize graph
            set.map{|n| g.load n.toRDF.localPath, :base_uri => n.stripDoc } # data to graph
            g.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true # serialize output
          end
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

    Group['tree'] = -> graph {
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

    def indexRDF options = {}
      g = RDF::Repository.load self, options # load resource
      updates = []
      g.each_graph.map{|graph|               # bind named graph
        n = graph.name.R
        # link to timeline
        graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value.do{|t| # timestamp
          doc = ['/' + t.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/(00.00|Z)$/,''),     # hour-dir
                 %w{host path query fragment}.map{|a|n.send(a).do{|p|p.split(/[\W_]/)}},'ttl']. #  slugs
                 flatten.-([nil,'',*BasicSlugs]).grep_v(/^\d+$/).join('.').R  # apply skiplist, mint URI
          unless doc.e
            doc.dir.mkdir
            RDF::Writer.open(doc.localPath){|f|f << graph}
            updates << doc; puts  "http://localhost:8000" + doc.stripDoc
          end
          true}}
      updates
    end
  end
end
