# coding: utf-8
require 'linkeddata'

class WebResource < RDF::URI
  def R env_=nil; env_ ? env(env_) : self end

  module URIs # URI constants
    W3       = 'http://www.w3.org/'
    Atom     = W3 + '2005/Atom#'
    LDP      = W3 + 'ns/ldp#'
    List     = W3 + '1999/02/22-rdf-syntax-ns#List'
    RDFs     = W3 + '2000/01/rdf-schema#'
    Stat     = W3 + 'ns/posix/stat#'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'

    DC       = 'http://purl.org/dc/terms/'
    Abstract = DC + 'abstract'
    Audio    = DC + 'Audio'
    Date     = DC + 'date'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Title    = DC + 'title'
    Video    = DC + 'Video'

    SIOC     = 'http://rdfs.org/sioc/ns#'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    To       = SIOC + 'addressed_to'
    Post     = SIOC + 'Post'

    FOAF     = 'http://xmlns.com/foaf/0.1/'
    Person   = FOAF + 'Person'

    DOAP     = 'http://usefulinc.com/ns/doap#'
    OG       = 'http://ogp.me/ns#'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'

    def basename; File.basename path end
    def ext; File.extname(path)[1..-1] || '' end
    def parts; path ? (path.split('/') - ['']) : [] end

  end

  alias_method :uri, :to_s

  def loadRDF options = {}
    graph = options[:repository] || env[:repository] ||= RDF::Repository.new
    options[:base_uri] ||= self
    #puts  "loading #{uri} data from #{fsPath}"
    if node.file?
      # further path-derived format hints for when suffix (extension) is too ambiguous to determine type
      options[:format] ||= if basename.index('msg.')==0 || path.index('/sent/cur')==0
                             # procmail doesnt allow suffix (like .eml extension), only prefix?
                             # presumably this is due to maildir suffix-rewrites to denote state
                             :mail
                           elsif ext.match? /^html?$/
                             :html
                           elsif ext == 'nfo'
                             :nfo
                           elsif %w(Cookies).member? basename
                             :sqlite
                           elsif %w(changelog gophermap gophertag license makefile readme todo).member?(basename.downcase) || %w(cls gophermap old plist service socket sty textile xinetd watchr).member?(ext.downcase)
                             :plaintext
                           elsif %w(markdown).member? ext.downcase
                             :markdown
                           elsif %w(gemfile rakefile).member?(basename.downcase) || %w(gemspec).member?(ext.downcase)
                             :sourcecode
                           elsif %w(bash c cpp h hs js pl py rb sh).member? ext.downcase
                             :sourcecode
                           end unless ext == 'ttl'
      graph.load fsPath, **options
    elsif node.directory?
      container = self
      container += '/' unless container.to_s[-1] == '/'

      graph << RDF::Statement.new(container, Type.R, (W3+'ns/ldp#Container').R)
      graph << RDF::Statement.new(container, Title.R, basename)
      graph << RDF::Statement.new(container, Date.R, node.stat.mtime.iso8601)

      node.children.map{|n|
        isDir = n.directory?
        name = n.basename.to_s + (isDir ? '/' : '')
        item = container.join(name).R env
        unless name[0] == '.' # elide invisible nodes
          if n.file?          # summarize contained document
            graph.load item.summary.uri
          elsif isDir         # list contained directory
            graph << RDF::Statement.new(container, (W3+'ns/ldp#contains').R, item)
            graph << RDF::Statement.new(item, Type.R, (W3+'ns/ldp#Container').R)
            graph << RDF::Statement.new(item, Title.R, name)
            graph << RDF::Statement.new(item, Date.R, n.mtime.iso8601)
          end
        end
      }
    end
    self
  rescue RDF::FormatError => e
    puts [e.class, e.message].join ' '
  end

  def saveRDF
    return self unless env[:repository]
    env[:repository].each_graph.map{|graph|
      n = (graph.name || env[:base_uri]).R # graph identity
      docs = []                            # storage refs
      unless n.uri.match?(/^(_|data):/)    # blank-nodes/data-URIs stored in context of identified graph
        docs.push n
        if n.host && timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value # find timestamp
            docs.push ['/' + timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # build hour-dir path
                       %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p && p.split(/[\W_]/)}}]. # tokenize slugs
                        flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                     # apply slug skiplist
        end
      end

      # store documents
      docs.map{|doc|
        turtle = doc.fsPath + '.ttl'
        unless File.exist? turtle
          FileUtils.mkdir_p File.dirname turtle
          RDF::Writer.for(:turtle).open(turtle){|f|f << graph}
          print "\n🐢 \e[32;1m" + doc.fsPath + "\e[0m "
        end
      }
    }
    self
  end

  def summary
    sPath = '../.cache/RDF/' + fsPath + (ext == 'ttl' ? '' : '.ttl')
    summary = sPath.R env
    sNode = Pathname.new sPath
    return summary if sNode.exist? && sNode.mtime >= node.mtime # summary exists and up to date
    fullGraph = RDF::Repository.new                       # full graph
    miniGraph = RDF::Repository.new                       # summary graph
    loadRDF repository: fullGraph                         # load RDF
    treeFromGraph(fullGraph).values.map{|resource|        # each subject
      subject = (resource['uri'] || '').R
      ps = [Abstract, Creator, Date, Image, Link, Title, To, Type, Video]
      type = resource[Type]
      type = [type] unless type.class == Array
      ps.push Content if type.member? (SIOC + 'MicroblogPost').R
      ps.map{|p|                                          # each predicate
        if o = resource[p] ; p = p.R
          (o.class == Array ? o : [o]).map{|o|            # each object
            miniGraph << RDF::Statement.new(subject,p,o)} # add triple to summary graph
        end}}
    FileUtils.mkdir_p sNode.dirname                       # create containing dir
    RDF::Writer.for(:turtle).open(sPath){|f|f << miniGraph} # write graph
    summary
  end
  alias_method :summarize, :summary

  # Repository -> Hash
  def treeFromGraph graph = nil
    graph ||= env[:repository]
    return {} unless graph

    tree = {}

    graph.each_triple{|s,p,o|
      s = s.to_s               # subject URI
      p = p.to_s               # predicate URI
      o = [RDF::Node, RDF::URI, WebResource].member?(o.class) ? o.R : o.value # object URI or literal
      tree[s] ||= {'uri' => s} # insert subject
      tree[s][p] ||= []        # insert predicate
      if tree[s][p].class == Array
        tree[s][p].push o unless tree[s][p].member? o # insert in object array
          else
            tree[s][p] = [tree[s][p],o] unless tree[s][p] == o # new object array
      end}

    tree
  end

  include URIs

end

class Pathname
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class RDF::URI
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class RDF::Node
  def R env=nil; env ? WebResource.new(to_s).env(env) : WebResource.new(to_s) end
end

class String
  def R env=nil; env ? WebResource.new(self).env(env) : WebResource.new(self) end
end
