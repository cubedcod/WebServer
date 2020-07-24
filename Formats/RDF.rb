# coding: utf-8
require 'linkeddata'

class WebResource < RDF::URI

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
    def query_hash
      return '' unless query && !query.empty?
      '.' + Digest::SHA2.hexdigest(query)[0..15]
    end
  end

  alias_method :uri, :to_s

  # file(s) -> RDF::Repository (in-memory)
  def loadRDF graph: env[:repository] ||= RDF::Repository.new
    #puts "LOAD #{uri} <- #{fsPath}"
    if node.file?
      stat = node.stat
      unless ext == 'ttl'
        graph << RDF::Statement.new(self, Title.R, basename)
        graph << RDF::Statement.new(self, Date.R, stat.mtime.iso8601)
        graph << RDF::Statement.new(self, (Stat + 'size').R, stat.size)
      end
      if %w(mp4 mkv webm).member? ext
        graph << RDF::Statement.new(self, Type.R, Video.R)
      elsif %w(m4a mp3 ogg opus).member? ext
        graph << RDF::Statement.new(self, Type.R, Audio.R)
      else
        formatHint = if ext != 'ttl' && (basename.index('msg.') == 0 || path.index('/sent/cur') == 0) # path-derived format hints when suffix is ambiguous or missing
                       :mail # procmail doesnt have configurable SUFFIX (.eml), only PREFIX? - presumably due to some sort of maildir suffix-renames to denote state?
                     elsif ext.match? /^html?$/
                       :html
                     elsif %w(changelog license readme todo).member? basename.downcase
                       :plaintext
                     elsif %w(gemfile makefile rakefile).member? basename.downcase
                       :sourcecode
                     end
        options = {base_uri: uri.gsub(/\.ttl$/,'').R(env)}
        options[:format] ||= formatHint if formatHint
        graph.load 'file:' + fsPath, **options
      end
    elsif node.directory?
      subject = self
      subject += '/' unless subject.to_s[-1] == '/'
      graph << RDF::Statement.new(subject, Type.R, (LDP + 'Container').R)
      graph << RDF::Statement.new(subject, Title.R, basename)
      graph << RDF::Statement.new(subject, Date.R, node.stat.mtime.iso8601)
      node.children.map{|child|
        graph << RDF::Statement.new(subject, (LDP+'contains').R, (subject.join child.basename '.ttl'))}
    end
    self
  rescue RDF::FormatError => e
    mime = `file -b --mime-type #{shellPath}`.chomp
    puts e.message,"RDF::FormatError :: #{mime} :: #{fsPath}"
    self
  end

  # RDF::Repository -> file(s)
  def saveRDF repository = nil
    return self unless repository || env[:repository]
    (repository || env[:repository]).each_graph.map{|graph|
      doc = (graph.name || self).R
      turtle = doc.fsPath + '.ttl'
      # write document
      unless File.exist? turtle
        FileUtils.mkdir_p File.dirname turtle
        RDF::Writer.for(:turtle).open(turtle){|f|f << graph}
        puts "\e[32m#{'%2d' % graph.size}⋮🐢 \e[1m#{doc}\e[0m" if doc.path != path
      end
      # link off-timeline nodes to timeline
      if !turtle.match?(/^\d\d\d\d\/\d\d\/\d\d/) && timestamp = graph.query(RDF::Query::Pattern.new(:s, Date.R, :o)).first_value # find timestamp
        tlink = [timestamp.sub('-','/').sub('-','/').sub('T','/').sub(':','/').gsub(/[-:]/,'.'), # hour-dir container
                 %w{host path query}.map{|a|doc.send(a).yield_self{|p|p && p.split(/[\W_]/)}}]. # URI slugs
                  flatten.-([nil, '', *Webize::Plaintext::BasicSlugs]).join('.')[0..123] + '.ttl'
        unless File.exist? tlink
          FileUtils.mkdir_p File.dirname tlink
          FileUtils.ln turtle, tlink rescue nil
        end
      end}
    self
  end

  # file -> Turtle file (big) -> Turtle file (small)
  def summary
    sPath = 'summary/' + fsPath + (path == '/' ? 'index' : '')
    sPath += '.ttl' unless ext == 'ttl'
    summary = sPath.R env                          # summary URI
    sNode = Pathname.new sPath                     # summary fs-storage
    return summary if sNode.exist? && sNode.mtime >= node.mtime # summary up to date, return
    fullGraph = RDF::Repository.new                # full-graph
    miniGraph = RDF::Repository.new                # summary-graph
    puts ['🐢', sNode].join ' '
    loadRDF graph: fullGraph                       # read RDF
    #saveRDF fullGraph unless ext == 'ttl'          # save RDFized from non-RDF graph(s)
    treeFromGraph(fullGraph).values.map{|resource| # bind subject
      subject = (resource['uri'] || '').R
      ps = [Abstract, Creator, Date, Image, LDP+'contains', Link, Title, To, Type, Video]
      type = resource[Type]
      type = [type] unless type.class == Array
      ps.push Content if type.member? (SIOC + 'MicroblogPost').R
      ps.map{|p|                                   # bind predicate
        if o = resource[p] ; p = p.R
          (o.class == Array ? o : [o]).map{|o|     # bind object
            miniGraph << RDF::Statement.new(subject,p,o)} # triple -> summary-graph
        end}}
    FileUtils.mkdir_p sNode.dirname                # allocate fs container
    RDF::Writer.for(:turtle).open(sPath){|f|f << miniGraph} # write summary
    summary                                        # summary reference
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
  module HTML

    include URIs

    # single-character representation of URI
    Icons = {
      Abstract => '✍',
      Audio => '🔊',
      Content => '',
      Creator => '👤',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      DC + 'rights' => '⚖️',
      Date => '⌚', 'http://purl.org/dc/terms/created' => '⌚', 'http://purl.org/dc/terms/modified' => '⌚',
      Image => '🖼️',
      LDP + 'Container' => '📁',
      LDP + 'contains' => '📁',
      Link => '☛',
      Post => '📝',
      SIOC + 'BlogPost' => '📝',
      SIOC + 'MailMessage' => '✉️',
      SIOC + 'MicroblogPost' => '🐦',
      SIOC + 'attachment' => '✉',
      SIOC + 'reply_of' => '↩',
      SIOC + 'richContent' => '',
      Schema + 'height' => '↕',
      Schema + 'width' => '↔',
      Schema + 'DiscussionForumPosting' => '📝',
      Stat + 'File' => '📄',
      To => '☇',
      Type => '📕',
      Video => '🎞',
      W3 + '2000/01/rdf-schema#Resource' => '🌐',
    }

    MarkupMap = {
      'article' => Post,
      'http://schema.org/Comment' => Post,
      'http://schema.org/ProfilePage' => Person,
      'https://schema.org/BreadcrumbList' => List,
      'https://schema.org/Comment' => Post,
      'https://schema.org/ImageObject' => Image,
      'https://schema.org/NewsArticle' => Post,
      'https://schema.org/Person' => Person,
      FOAF + 'Image' => Image,
      SIOC + 'MicroblogPost' => Post,
      SIOC + 'BlogPost' => Post,
      SIOC + 'MailMessage' => Post,
      SIOC + 'UserAccount' => Person,
      Schema + 'Answer' => Post,
      Schema + 'Article' => Post,
      Schema + 'BlogPosting' => Post,
      Schema + 'BreadcrumbList' => List,
      Schema + 'Code' => Post,
      Schema + 'DiscussionForumPosting' => Post,
      Schema + 'ImageObject' => Image,
      Schema + 'ItemList' => List,
      Schema + 'NewsArticle' => Post,
      Schema + 'Person' => Person,
      Schema + 'Review' => Post,
      Schema + 'UserComments' => Post,
      Schema + 'VideoObject' => Video,
      Schema + 'WebPage' => Post,
    }

    # RDF -> Markup
    def self.markup type, v, env
      if [Abstract, Content, 'http://rdfs.org/sioc/ns#richContent'].member? type
        (env[:cacherefs] && v.class == String) ? Webize::HTML.cacherefs(v, env) : v
      elsif Markup[type] # markup lambda defined for explicit type argument
        Markup[type][v,env]
      elsif v.class == Hash # data
        types = (v[Type] || []).map{|t|
          MarkupMap[t.to_s] || t.to_s } # normalize typetags for unified renderer selection
        seen = false
        [types.map{|type|
          if f = Markup[type] # markup lambda defined for RDF type
            seen = true
            f[v,env]
          end},
         (keyval v, env unless seen)] # default key-value renderer
      elsif v.class == WebResource # resource-reference arguments
        if v.path && %w{jpeg jpg JPG png PNG webp}.member?(v.ext)
          Markup[Image][v, env]    # image reference
        else
          v                        # generic reference
        end
      else # renderer undefined
        CGI.escapeHTML v.to_s
      end
    end

    Markup = {} # markup lambdas for RDF types
    MarkupGroup = {}

    Markup['uri'] = -> uri, env {uri.R}

    Markup[DC+'language'] = -> lang, env {
      {'de' => '🇩🇪',
       'en' => '🇬🇧',
       'fr' => '🇫🇷',
       'ja' => '🇯🇵',
      }[lang] || lang}

    MarkupGroup[Link] = -> links, env {
      {_: :table, class: :links,
       c: links.group_by{|l|l.R.host}.map{|host, paths|
         {_: :tr,
          c: [{_: :td, class: :host, c: host ? {_: :a, href: '//' + host, c: host, style: (env[:colors][host] ||= HTML.colorize)[14..-1].sub('background-','')} : []},
              {_: :td, c: paths.map{|path| Markup[Link][path,env]}}]}}}}

    Markup[Link] = -> ref, env {
      u = ref.to_s
      re = u.R env
      [{_: :a, href: re.href, c: (re.path||'/')[0..79], title: u,
        id: 'l' + Digest::SHA2.hexdigest(rand.to_s),
        style: env[:colors][re.host] ||= HTML.colorize},
       " \n"]}

    Markup[Type] = -> t, env {
      if t.class == WebResource
        {_: :a, href: t.uri, c: Icons[t.uri] || t.fragment || (t.path && t.basename)}.update(Icons[t.uri] ? {class: :icon} : {})
      else
        CGI.escapeHTML t.to_s
      end}

  end

end

class Array
  def R env=nil
    puts ['Array#R', self].join ' ' if size > 1
    env ? WebResource.new(self[0].to_s).env(env) : WebResource.new(self[0].to_s)
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

class WebResource
  def R env_=nil; env_ ? env(env_) : self end
end
