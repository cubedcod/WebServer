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

    # turn non-RDF into JSON subset of RDF with defined RDF::Reader for parsing to RDF
    # file -> file
    def rdfize
      return self if ext == 'e'
      hash = node.stat.ino.to_s.sha2
      doc = ('/cache/RDF/'+hash[0..2]+'/'+hash[3..-1]+'.e').R
      unless doc.e && doc.m > m
        tree = {}
        # triplr takes file reference, yields triples (using #yield method in ruby)
        triplr = Triplr[mime]

        unless triplr
          puts "#{uri}: triplr for #{mime} missing"
          triplr = :triplrFile
        end

        send(*triplr){|s,p,o|
          tree[s] ||= {'uri' => s}
          tree[s][p] ||= []
          tree[s][p].push o}
        doc.writeFile tree.to_json
      end
      doc
    end
  end
  module HTTP

    HostPOST['localhost'] = -> r {[202,{},[]]}

    def GETnode
      head = HTTP.unmangle env
      head.delete 'Host'
      formatSuffix = (host.match?(/reddit.com$/) && !parts.member?('w')) ? '.rss' : ''
      useExtension = %w{aac atom css html jpg js mp3 mp4 pdf png rdf svg ttf ttl webm webp woff woff2}.member? ext.downcase
      portNum = port && !([80,443,8000].member? port) && ":#{port}" || ''
      queryHash = q
      queryHash.delete 'host'
      queryString = queryHash.empty? ? '' : (HTTP.qs queryHash)
      # origin URI
      urlHTTPS = scheme && scheme=='https' && uri || ('https://' + host + portNum + path + formatSuffix + queryString)
      urlHTTP  = 'http://'  + host + portNum + (path||'/') + formatSuffix + queryString
      # local URI
      cache = ('/' + host + (if FlatMap.member?(host) || (qs && !qs.empty?) # mint a path
                             hash = ((path||'/') + qs).sha2          # hash origin path
                             type = useExtension ? ext : 'cache' # append suffix
                             '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # plunk in semi-balanced bins
                            else # preserve upstream path
                              name = path[-1] == '/' ? path[0..-2] : path # strip trailing-slash
                              name + (useExtension ? '' : '.cache') # append suffix
                             end)).R env
      cacheMeta = cache.metafile

      # lazy updater, called by need
      updates = []
      update = -> url {
        begin # block to catch 304-return "error"
          # conditional GET
          open(url, head) do |response| # response

            if @r # HTTP-request calling context - preserve origin bits
              @r[:Response]['Access-Control-Allow-Origin'] ||= '*'
              response.meta['set-cookie'].do{|cookie| @r[:Response]['Set-Cookie'] = cookie}
            end

             # index updates
            resp = response.read
            unless cache.e && cache.readFile == resp
              cache.writeFile resp # cache body
              mime = response.meta['content-type'].do{|type| type.split(';')[0] } || ''
              cacheMeta.writeFile [mime, url, ''].join "\n" unless useExtension
              # index content
              updates.concat(case mime
                             when /^application\/atom/
                               cache.indexFeed
                             when /^application\/rss/
                               cache.indexFeed
                             when /^application\/xml/
                               cache.indexFeed
                             when /^text\/html/
                               if feedURL? # HTML typetag on specified feed URL
                                 cache.indexFeed
                               else
                                 cache.indexHTML host
                               end
                             when /^text\/xml/
                               cache.indexFeed
                             else
                               []
                             end || [])
            end
          end
        rescue OpenURI::HTTPError => e
          raise unless e.message.match? /304/
        end}

      # conditional update
      static = cache? && cache.e && cache.noTransform?
      throttled = cacheMeta.e && (Time.now - cacheMeta.mtime) < 60
      unless static || throttled
        head["If-Modified-Since"] = cache.mtime.httpdate if cache.e
        begin # prefer HTTPS w/ fallback HTTP attempt
          update[urlHTTPS]
        rescue
          update[urlHTTP]
        end
        cacheMeta.touch if cacheMeta.e # bump timestamp
      end

      # response
      if @r # called over HTTP
        @r.delete 'HTTP_TRACK'
        if cache.exist?
          # preserve upstream format for runtime preference, static preference or immutable MIME
          if UpstreamToggle[@r['SERVER_NAME']] || UpstreamFormat.member?(@r['SERVER_NAME']) || cache.noTransform?
            cache.fileResponse
          else # transcoding enabled
            graphResponse (updates.empty? ? [cache] : updates)
          end
        else
          notfound
        end
      else # REPL/script/shell caller
        updates.empty? ? self : updates
      end

    rescue Exception => e
      msg = [uri, e.class, e.message].join " "
      trace = e.backtrace.join "\n"
      puts msg, trace
      @r ? [500, {'Content-Type' => 'text/html'},
            [htmlDocument({uri => {Content => [{_: :style, c: "body {background-color: red !important}"},
                                               {_: :h3, c: msg.hrefs}, {_: :pre, c: trace.hrefs},
                                               {_: :h4, c: 'request'},
                                               (HTML.kv (HTML.urifyHash head), @r), # request header
                                               ([{_: :h4, c: "response #{e.io.status[0]}"},
                                                (HTML.kv (HTML.urifyHash e.io.meta), @r), # response header
                                                (CGI.escapeHTML e.io.read.to_utf8)] if e.respond_to? :io) # response body
                                              ]}})]] : self
    end

    # merge native-JSON and RDF to loaded graph
    def load set # file-set
      g = {}                 # Hash
      graph = RDF::Graph.new # RDF graph
      rdf, non_rdf = set.partition &:isRDF # split for the two input pipelines

      # RDF
      # load document(s)
      rdf.map{|n|
        opts = {:base_uri => n}
        opts[:format] = :feed if n.feedMIME?
        graph.load n.localPath, opts rescue puts("loaderror: #{n}")}
      # merge to graph
      graph.each_triple{|s,p,o|
        s = s.to_s; p = p.to_s # subject URI, predicate URI
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object
        g[s] ||= {'uri'=>s} # insert subject
        g[s][p] ||= []      # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert full triple

      # almost-RDF
      non_rdf.map{|n| # non-RDF
        n.rdfize.do{|transcode| # convert to almost-RDF
          ::JSON.parse(transcode.readFile).map{|s,re| # load almost-RDF resources
            re.map{|p,o| # (predicate URI, object(s)) tuples for subject URI
              o.justArray.map{|o| # object URI(s) and/or literals
                o = o.R if o.class==Hash # cast to WebResource instance
                g[s] ||= {'uri'=>s} # insert subject
                g[s][p] ||= []      # insert predicate
                g[s][p].push o unless g[s][p].member? o} unless p == 'uri' }}}} # insert full triple

      g # graph reference for caller
    end

    def graphResponse set
      return notfound if !set || set.empty?

      # check for on-file response body
      if set.size == 1 ; this = set[0]
        # document on file is RDF in BEST MATCH format?
        created = this.isRDF && bestFormat?(this) && this
        # WEAK MATCH but mutually acceptable: reduced transcoding-load solution
        # Recommended only for MIME-agile clients and databrowsers ready for RDF
        #created = (sendable? this) && (receivable? this) && this
      end

      # response metadata
      format = created && created.mime || outputMIME
      dateMeta if localResource?
      @r[:Response].update({'Link' => @r[:links].map{|type,uri|
                              "<#{uri}>; rel=#{type}"}.intersperse(', ').join}) unless @r[:links].empty?
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format,
                            'ETag' => [set.sort.map{|r|[r,r.m]}, format].join.sha2})

      # lazy body-generator lambda
      entity @r, ->{
        if created # nothing to merge or transcode
          created  # return body-reference
        else # merge and/or transcode
          if format == 'text/html'
            htmlDocument load set
          elsif format == 'application/atom+xml'
            renderFeed load set
          else # RDF formats
            g = RDF::Graph.new
            set.map{|n|
              g.load n.toRDF.localPath, :base_uri => n.stripDoc }
            g.dump (RDF::Writer.for :content_type => format).to_sym, :base_uri => self, :standard_prefixes => true
          end
        end}
    end

  end
  module URIs
    def resources; lines.map &:R end
  end
  module HTML

    # group stuff at /
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
            puts  "\e[32;7mhttp://localhost" + doc.stripDoc +  "\e[0m"
          end
          true}}

      # indexed resources
      newResources
    end
  end
end
