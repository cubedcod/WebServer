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
    def ext; path ? (File.extname(path)[1..-1] || '') : '' end
    def extension; '.' + ext end
    def parts; path ? (path.split('/') - ['']) : [] end

  end

  alias_method :uri, :to_s

  # file(s) -> RDF::Repository
  def loadRDF options = {}
    graph = options[:repository] || env[:repository] ||= RDF::Repository.new
    options[:base_uri] ||= uri.gsub(/\.ttl$/,'').R env
    if node.file?
      # path-derived format hints when suffix is ambiguous or missing
      formatHint = if ext != 'ttl' && (basename.index('msg.')==0 || path.index('/sent/cur')==0)
                     # procmail doesnt allow configurable SUFFIX (say .eml), only PREFIX? - presumably due to some sort of maildir suffix-renames to denote state?
                     # sometimes the autogenerated 3-char suffix from procmail is .ttl. concede defeat until we figure out a SUFFIX capability from procmail
                     :mail
                   elsif ext.match? /^html?$/ # use our HTML rdfizer and allow .htm pathnames
                     :html
                   elsif %w(Bookmarks Cookies History).member? basename
                     :sqlite
                   elsif %w(changelog license readme todo).member? basename.downcase
                     :plaintext
                   elsif %w(gemfile rakefile).member? basename.downcase
                     :sourcecode
                   end
      options[:format] ||= formatHint if formatHint
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

  # RDF::Repository -> Turtle file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]

    (repository || env[:repository]).each_graph.map{|graph|
      n = (graph.name || self).R # graph URI
      docs = [n] # canonical location
      # doc on timeline TODO hard/symlink? other locations?
      if ts = graph.query(RDF::Query::Pattern.new(:s, (WebResource::Date).R, :o)).first_value   # timestamp query
        docs.push ['/'+ts.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # build hour-dir path
                   %w{host path query}.map{|a|n.send(a).yield_self{|p|p && p.split(/[\W_]/)}}]. # tokenize slugs
                    flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.').R            # apply slug skiplist
      end
      docs.map{|doc|
        turtle = doc.fsPath + '.ttl'
        triples = ('%4d' % graph.size) + '⋮'
        if File.exist? turtle
        # TODO write version? (or continue requiring new URI for that)
          print "\n⚪ #{triples} #{doc.fsPath}" if ENV.has_key? 'VERBOSE'
        else
          FileUtils.mkdir_p File.dirname turtle
          RDF::Writer.for(:turtle).open(turtle){|f|f << graph}
          print "\n🐢 \e[32m#{triples} \e[1m#{doc}\e[0m " if doc == docs[0]
        end}}
    self
  end

  # Turtle file -> Turtle file
  def summary
    rdfized = ext == 'ttl'
    sPath = '../.cache/RDF/' + fsPath + (rdfized ? '' : '.ttl')
    summary = sPath.R env
    sNode = Pathname.new sPath
    return summary if sNode.exist? && sNode.mtime >= node.mtime # summary exists and up to date
    fullGraph = RDF::Repository.new                       # full graph
    miniGraph = RDF::Repository.new                       # summary graph
    loadRDF repository: fullGraph                         # read RDF
    saveRDF fullGraph unless rdfized                      # store RDF-ized graph(s)
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
    RDF::Writer.for(:turtle).open(sPath){|f|f << miniGraph} # write summary graph
    summary
  end
  alias_method :summarize, :summary

  include URIs

  module HTTP

    def graphResponse
      return notfound if !env.has_key?(:repository) || env[:repository].empty?
      format = selectFormat
      env[:resp]['Access-Control-Allow-Origin'] ||= allowedOrigin
      env[:resp].update({'Content-Type' => %w{text/html text/turtle}.member?(format) ? (format+'; charset=utf-8') : format})
      env[:resp].update({'Link' => env[:links].map{|type,uri|"<#{uri}>; rel=#{type}"}.join(', ')}) unless !env[:links] || env[:links].empty?
      entity ->{
        case format
        when /^text\/html/
          htmlDocument
        when /^application\/atom+xml/
          feedDocument
        else
          env[:repository].dump (RDF::Writer.for content_type: format).to_sym, standard_prefixes: true, base_uri: self
        end}
    end

  end

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
