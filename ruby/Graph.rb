class Hash
  def R # cast to WebResource
    WebResource.new(uri).data self
  end
  # URI accessor
  def uri; self["uri"] end
end

class WebResource
  module HTTP
    def treeFromGraph graph
      g = {}                    # blank Hash
      graph.each_triple{|s,p,o| # bind subject,predicate,object
        s = s.to_s; p = p.to_s # subject URI, predicate URI
        o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal value
        g[s] ||= {'uri'=>s} # insert subject
        g[s][p] ||= []      # insert predicate
        g[s][p].push o unless g[s][p].member? o} # insert object
      g # graph in JSON
    end

    def graphResponse graph
      @r[:Response] ||= {}

      # response metadata
      dateMeta if localNode?
      @r[:Response].update({'Link' => @r[:links].map{|type,uri|
                              "<#{uri}>; rel=#{type}"}.intersperse(', ').join}) unless !@r[:links] || @r[:links].empty?
      # format
      format = selectFormat
      @r[:Response].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})

      # conditional generator
      entity @r, ->{
        if format == 'text/html'
          if qs == '?data'
            '/mashlib/databrowser.html'.R      # static HTML
          else
            htmlDocument treeFromGraph graph     # HTML
          end
        elsif format == 'application/atom+xml' # Atom/RSS
          renderFeed treeFromGraph graph
        else                                   # RDF
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

    def index format, data
      g = RDF::Repository.new
      puts "#{uri} #{format}"
      RDF::Reader.for(content_type: format).new(data, :base_uri => self) do |reader|
        g << reader
      end
      updates = []
      g.each_graph.map{|graph|               # bind named graph
        n = graph.name.R
        # link to timeline
        graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value.do{|t| # timestamp
          doc = ['/' + t.gsub(/[-T]/,'/').sub(':','/').sub(':','.').sub(/\+?(00.00|Z)$/,''),  # hour-dir
                 %w{host path query fragment}.map{|a|n.send(a).do{|p|p.split(/[\W_]/)}},'ttl']. #  slugs
                 flatten.-([nil,'',*BasicSlugs]).join('.').R  # apply skiplist, mint URI
          unless doc.e
            doc.dir.mkdir
            RDF::Writer.open(doc.localPath){|f|f << graph}
            updates << doc
            puts  "\e[32m+\e[0m http://localhost:8000" + doc.stripDoc
          else
            puts  "= http://localhost:8000" + doc.stripDoc
          end
          true}}
      [g, updates]
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
