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
  end

  alias_method :uri, :to_s

  def loadRDF graph = nil
    graph ||= env[:repository] ||= RDF::Repository.new
    if node.file?
      options = {base_uri: base}
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
                           elsif %w(bash c cpp h hs pl py rb sh).member? ext.downcase
                             :sourcecode
                           end unless ext == 'ttl'
      options[:file_path] = self
      graph.load relPath, **options
    elsif node.directory?
      container = base.join relFrom base.fsPath # container URI
      container += '/' unless container.to_s[-1] == '/'

      graph << RDF::Statement.new(container, Type.R, (W3+'ns/ldp#Container').R)
      graph << RDF::Statement.new(container, Title.R, basename)
      graph << RDF::Statement.new(container, Date.R, node.stat.mtime.iso8601)

      node.children.map{|n|
        isDir = n.directory?
        name = n.basename.to_s + (isDir ? '/' : '')
        unless name[0] == '.' # elide invisible nodes
          if n.file?          # summarize contained document
            graph.load n.R.summarized
          elsif isDir         # list contained directory
            subdir = container.join name
            graph << RDF::Statement.new(container, (W3+'ns/ldp#contains').R, subdir)
            graph << RDF::Statement.new(subdir, Type.R, (W3+'ns/ldp#Container').R)
            graph << RDF::Statement.new(subdir, Title.R, name)
            graph << RDF::Statement.new(subdir, Date.R, n.mtime.iso8601)
          end
        end
      }
    end
    self
  end

  def saveRDF
    return self unless env[:repository]
    env[:repository].each_graph.map{|graph|
      n = (graph.name || env[:base_uri]).R # graph identity
      docs = []                            # storage refs
      unless n.uri.match?(/^(_|data):/)    # blank-nodes/data-URIs stored in context of identified graph
        if n.host
          # canonical path
          docs.push (n.hostpath + (n.path ? (n.path[-1]=='/' ? (n.path + 'index') : n.path) : '')).R
          # temporal-index path
          if timestamp = graph.query(RDF::Query::Pattern.new(:s,(WebResource::Date).R,:o)).first_value       # find timestamp
            docs.push ['/' + timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # build hour-dir path
                       %w{host path query fragment}.map{|a|n.send(a).yield_self{|p|p && p.split(/[\W_]/)}}]. # tokenize slugs
                        flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R                     # apply slug skiplist
          end
        else # local path
          docs.push n
        end
      end

      # store documents
      docs.map{|doc|
        turtle = doc.relPath + '.ttl'
        unless File.exist? turtle
          if dir = doc.dir
            dir.mkdir
            RDF::Writer.for(:turtle).open(turtle){|f|f << graph}
            print "\n🐢 \e[32;1m" + doc.path + "\e[0m "
          end
        end
      }
    }
    self
  end

  def summarized
    summary = summaryFile
    return summary if summary.node.exist? && summary.node.mtime >= node.mtime

    summary.dir.mkdir
    doc = path[-1] == '/' ? (self + 'index.ttl').R : self  # document to summarize
    fullGraph = RDF::Repository.new; doc.loadRDF fullGraph # full graph
    miniGraph = RDF::Repository.new                        # summary graph

    treeFromGraph(fullGraph).values.map{|resource|  # subject
      subject = (resource['uri'] || '').R
      [Abstract,Creator,Date,Image,Link,Title,To,Type,Video].map{|p| # predicate
        if o = resource[p]
          (o.class == Array ? o : [o]).map{|o|      # object
            miniGraph << RDF::Statement.new(subject, p.R, o)} # triple to summary graph
        end}}

    RDF::Writer.for(:turtle).open(summary){|f|f << miniGraph} # write summary graph
    summary                                                   # summary graph
  end

  def summaryFile
    ('../.cache/RDF/' + relPath + (path[-1] == '/' ? 'index' : '') + (ext == 'ttl' ? '' : '.ttl')).R env
  end

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
