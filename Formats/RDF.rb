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
    Container = LDP + 'Container'
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
    if node.file?
      formatHint = if ext != 'ttl' && (basename.index('msg.') == 0 || path.index('/sent/cur') == 0)
                     :mail # procmail doesnt have configurable SUFFIX (.eml), only PREFIX? - presumably due to some sort of maildir suffix-renames to denote state?
                   elsif ext.match? /^html?$/
                     :html
                   elsif %w(changelog license readme todo).member? basename.downcase
                     :plaintext
                   elsif %w(gemfile makefile rakefile).member? basename.downcase
                     :sourcecode
                   end # path-derived format hints when suffix is ambiguous or missing
      options[:base_uri] ||= (localNode? ? path : uri).gsub(/\.ttl$/,'').R env
      options[:format] ||= formatHint if formatHint
      graph.load fsPath, **options
    elsif node.directory?
      subject = localNode? ? path.R : self
      subject += '/' unless subject.to_s[-1] == '/'
      graph << RDF::Statement.new(subject, Type.R, Container.R)
      graph << RDF::Statement.new(subject, Title.R, basename)
      graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
      node.children.map{|child|
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename '.ttl'))}
    end
  rescue RDF::FormatError => e
    mime = `file -b --mime-type #{shellPath}`.chomp
    puts e.message,"FILE(1) suggests type #{mime}, retrying"
    options.delete :content_type
    options.delete :format
    if mime == 'text/html'
      options[:format] = :html
    else
      options[:content_type] = mime
    end
    graph.load fsPath, **options
  end

  # RDF::Repository -> file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]
    (repository || env[:repository]).each_graph.map{|graph|
      doc = (graph.name || self).R
      turtle = doc.fsPath + '.ttl'
      puts "graph #{graph} -> #{turtle}" if ENV.has_key? 'VERBOSE'

      unless File.exist? turtle # write document
        FileUtils.mkdir_p File.dirname turtle
        RDF::Writer.for(:turtle).open(turtle){|f|f << graph}
        puts "\e[32m#{'%2d' % graph.size}⋮🐢 \e[1m#{doc}\e[0m" if doc.path != path
      end

      # link to timeline , if not already on it
      if !turtle.match?(/^\d\d\d\d\/\d\d\/\d\d/) && timestamp = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value # timestamp query
        tlink = [timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # hour-dir
                 %w{host path query}.map{|attr|
                   doc.send(attr).yield_self{|p|p && p.split(/[\W_]/)}}, 'ttl']. # URI slugs
                  flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join '.'  # apply slug skiplist

        unless File.exist? tlink # link to timeline
          FileUtils.mkdir_p File.dirname tlink
          begin
            FileUtils.ln turtle, tlink
          rescue
            FileUtils.cp turtle, tlink
          end
        end
      end}
    self
  end

  # Turtle file (big) -> Turtle file (small)
  def summary
    return self if basename.split('.')[0].upcase == 'README'
    isRDF = ext == 'ttl'
    sPath = '../.cache/RDF/' + fsPath + (path == '/' ? 'index' : '') + (isRDF ? '' : '.ttl')
    summary = sPath.R env                                 # summary name
    sNode = Pathname.new sPath                            # summary node
    return summary if sNode.exist? && sNode.mtime >= node.mtime # summary exists and up to date
    fullGraph = RDF::Repository.new                       # full graph
    miniGraph = RDF::Repository.new                       # summary graph
    loadRDF repository: fullGraph                         # read RDF
    saveRDF fullGraph unless isRDF                        # save RDF-ized graph(s)
    treeFromGraph(fullGraph).values.map{|resource|        # each subject
      subject = (resource['uri'] || '').R
      ps = [Abstract, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]
      type = resource[Type]
      type = [type] unless type.class == Array
      ps.push Content if type.member? (SIOC + 'MicroblogPost').R
      ps.map{|p|                                          # each predicate
        if o = resource[p] ; p = p.R
          (o.class == Array ? o : [o]).map{|o|            # each object
            miniGraph << RDF::Statement.new(subject,p,o)} # triple to summary
        end}}
    FileUtils.mkdir_p sNode.dirname                       # create containing dir
    RDF::Writer.for(:turtle).open(sPath){|f|f << miniGraph} # write summary
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
          env[:repository].dump RDF::Writer.for(content_type: format).to_sym, base_uri: self
        end}
    end

  end

end
class Array
  def R env=nil
    puts ['Array#R', self].join ' ' if size > 1
    env ? WebResource.new(self[0].to_s).env(env) : WebResource.new(self[0].to_s)
  end
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
