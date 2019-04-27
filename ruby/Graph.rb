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

    def [] p; (@data||{})[p].justArray end
    def data d={}; @data = (@data||{}).merge(d); self end
    def types; @types ||= self[Type].select{|t|t.respond_to? :uri}.map(&:uri) end
    def a type; types.member? type end
    def to_json *a; {'uri' => uri}.to_json *a end

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
    def rdfize # call MIME-mapped triplr function, cache output in JSON and return file-reference
      return self if ext == 'e'
      hash = node.stat.ino.to_s.sha2
      doc = ('/cache/RDF/' + hash[0..2] + '/' + hash[3..-1] + '.e').R
      return doc if doc.e && doc.m > m # cache up-to-date
      graph = {}
      # look up triple-producer function
      triplr = Triplr[mime]
      unless triplr
        puts "#{uri}: triplr for #{mime} missing"
        triplr = :triplrFile
      end
      # request triples
      send(*triplr){|s,p,o|
        graph[s]    ||= {'uri' => s}
        graph[s][p] ||= []
        graph[s][p].push o}
      # update cache
      doc.writeFile graph.to_json
    end

  end
  module HTTP
    # load native-JSON and RDF
    def load set # file-set
      g = {}                 # Hash
      graph = RDF::Graph.new # RDF graph

      rdf, non_rdf = set.partition &:isRDF

      # RDF
      # load document(s)
      rdf.map{|n|
        opts = {:base_uri => n}
        opts[:format] = :feed if n.feedMIME?
        graph.load n.localPath, opts rescue puts("load error on #{n}")}
      # visit nodes
      graph.each_triple{|s,p,o|
        s = s.to_s; p = p.to_s # subject URI, predicate URI
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
        g[s] ||= {'uri'=>s} # insert subject
        g[s][p] ||= []      # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object

      # JSON
      non_rdf.map{|n| # visit non-RDF files
        n.rdfize.do{|transcode| # transcode to JSON
          ::JSON.parse(transcode.readFile). # load JSON
            map{|s,re| # visit resources
            re.map{|p,o| # predicate URI, object(s)
              o.justArray.map{|o| # object URI or value
                o = o.R if o.class==Hash # object URI
                g[s] ||= {'uri'=>s} # insert subject
                g[s][p] ||= []      # insert predicate
                g[s][p].push o unless g[s][p].member? o} unless p == 'uri' }}}} # insert object

      g # graph reference for caller
    end

    def graphResponse set
      return notfound if !set || set.empty?

      # check for on-file response body
      if set.size == 1 ; this = set[0]
        # BEST MATCH format doc is on-file
        created = this.isRDF && bestFormat?(this) && this

        # WEAK MATCH but mutually acceptable. reduced server-transcoding solution
        # Recommended only for MIME-agile clients and databrowsers ready for RDF
        #created = (sendable? this) && (receivable? this) && this
      end

      # response metadata
      format = created && created.mime || outputMIME
      dateMeta if localNode?
      @r[:Response].update({'Link' => @r[:links].map{|type,uri|
                              "<#{uri}>; rel=#{type}"}.intersperse(', ').join}) unless @r[:links].empty?
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format,
                            'ETag' => [set.sort.map{|r|[r,r.m]}, format].join.sha2})

      # lazy body-generator
      entity @r, ->{
        if created # body already exists
          created  # return reference
        else # generate
          if format == 'text/html'
            htmlDocument load set
          elsif format == 'application/atom+xml'
            renderFeed load set
          else # RDF format
            g = RDF::Graph.new
            set.map{|n| g.load n.toRDF.localPath, :base_uri => n.stripDoc }
            g.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true
          end
        end}
    end

  end
  module URIs
    def resources; lines.map &:R end
  end
  module HTML

    # group stuff under /
    Group['topdir'] = -> graph {
      containers = {}
      graph.values.map{|resource|
        re = resource.R
        name = re.parts[0] || ''
        # group into decade and alphanumeric-prefix containers
        if name.match /^\d{4}$/
          decade = name[0..2] + '0s'
        else
          alpha = (name.sub(/^www\./,'')[0]||'').upcase
        end
        key = decade || alpha
        containers[key] ||= {name: key, Contains => []}
        containers[key][Contains].push resource }
      containers}

    # URI-indexed
    Group['flat'] = -> graph { graph }

    # build tree from URI path component
    Group['tree'] = -> graph {
      tree = {}

      # for each graph-node
      (graph.class==Array ? graph : graph.values).map{|resource|
        cursor = tree
        r = resource.R

        # locate document-graph
        [r.host || '',
         r.parts.map{|p|p.split '%23'}].flatten.map{|name|
          cursor[Type] ||= Container.R
          cursor[Contains] ||= {}
           # advance cursor to node, creating as needed
          cursor = cursor[Contains][name] ||= {name: name, Type => Container.R}}

        # place data in named-graph
        if !r.fragment # graph-document itself
          resource.map{|k,v|
            cursor[k] = cursor[k].justArray.concat v.justArray}
        else # graph-doc contained resource
          cursor[Contains] ||= {}
          cursor[Contains][r.fragment] = resource
        end}

      tree }

  end
  module Webize
    include MIME

    # index resources on timeline
    def indexRDF options = {}
      newResources = []
      # load resource
      g = RDF::Repository.load self, options

      # visit named-graph containers
      g.each_graph.map{|graph|

        # timestamp for timeline-linkage
        graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value.do{|t|

          # document-URI
          time = t.gsub(/[-T]/,'/').sub(':','/').sub /(.00.00|Z)$/, ''
          slug = (graph.name.to_s.sub(/https?:\/\//,'.').gsub(/[\W_]/,'..').sub(/\d{12,}/,'')+'.').gsub(/\.+/,'.')[0..127].sub(/\.$/,'')
          doc = "/#{time}#{slug}.ttl".R

          # cache graph locally
          unless doc.e
            doc.dir.mkdir
            RDF::Writer.open(doc.localPath){|f|
              f << graph}
            newResources << doc
            puts  "http://localhost:8000" + doc.stripDoc
          end
          true}}

      # indexed resources
      newResources
    end
  end
end
