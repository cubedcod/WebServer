# coding: utf-8
class Hash
  def R
    WebResource.new(uri).data self
  end
  def uri; self["uri"] end
end
class Pathname
  def R; WebResource.new to_s end
end
class RDF::Node
  def R; WebResource.new to_s end
end
class RDF::URI
  def R; WebResource.new to_s end
end
class Symbol
  def R; WebResource.new to_s end
end
class String
  def R env=nil
    if env
      WebResource.new(self).environment env
    else
      WebResource.new self
    end
  end
end
class WebResource < RDF::URI
  def R; self end

  module URIs
    ConfDir = Pathname.new(__dir__).join('../config').relative_path_from Pathname.new Dir.pwd
    W3       = 'http://www.w3.org/'
    Purl     = 'http://purl.org/'
    DC       = Purl + 'dc/terms/'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Stat     = W3   + 'ns/posix/stat#'
    Abstract = DC   + 'abstract'
    Atom     = W3   + '2005/Atom#'
    BlogPost = SIOC + 'BlogPost'
    Comments = 'http://wellformedweb.org/CommentAPI/commentRss'
    Container = W3  + 'ns/ldp#Container'
    Contains = W3  + 'ns/ldp#contains'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    DCe      = Purl + 'dc/elements/1.1/'
    Date     = DC   + 'date'
    Email    = SIOC + 'MailMessage'
    From     = SIOC + 'has_creator'
    Identifier = DC + 'identifier'
    Image    = DC + 'Image'
    Label    = W3 + '2000/01/rdf-schema#label'
    Link     = DC + 'link'
    Media    = 'http://search.yahoo.com/mrss/'
    Mtime    = Stat + 'mtime'
    OA       = 'https://www.w3.org/ns/oa#'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Post     = SIOC + 'Post'
    RSS      = Purl + 'rss/1.0/'
    Resource = W3   + '2000/01/rdf-schema#Resource'
    Schema   = 'http://schema.org/'
    Size     = Stat + 'size'
    Sound    = Purl + 'ontology/mo/Sound'
    Title    = DC   + 'title'
    To       = SIOC + 'addressed_to'
    Twitter  = 'https://twitter.com'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'
    YouTube  = 'http://www.youtube.com/xml/schemas/2015#'

    def + u; (to_s + u.to_s).R end
    def [] p; (@data||{})[p].justArray end
    def a type; types.member? type end
    def data d={}; @data = (@data||{}).merge(d); self end
    def resources; lines.map &:R end
    def types; @types ||= self[Type].select{|t|t.respond_to? :uri}.map(&:uri) end

    def dateMeta
      @r ||= {}
      @r[:links] ||= {}
      n = nil # next page
      p = nil # prev page
      # date parts
      dp = []
      dp.push parts.shift.to_i while parts[0] && parts[0].match(/^[0-9]+$/)
      case dp.length
      when 1 # Y
        year = dp[0]
        n = '/' + (year + 1).to_s
        p = '/' + (year - 1).to_s
      when 2 # Y-m
        year = dp[0]
        m = dp[1]
        n = m >= 12 ? "/#{year + 1}/#{01}" : "/#{year}/#{'%02d' % (m + 1)}"
        p = m <=  1 ? "/#{year - 1}/#{12}" : "/#{year}/#{'%02d' % (m - 1)}"
      when 3 # Y-m-d
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          p = (day-1).strftime('/%Y/%m/%d')
          n = (day+1).strftime('/%Y/%m/%d')
        end
      when 4 # Y-m-d-H
        day = ::Date.parse "#{dp[0]}-#{dp[1]}-#{dp[2]}" rescue nil
        if day
          hour = dp[3]
          p = hour <=  0 ? (day - 1).strftime('/%Y/%m/%d/23') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour-1)))
          n = hour >= 23 ? (day + 1).strftime('/%Y/%m/%d/00') : (day.strftime('/%Y/%m/%d/')+('%02d' % (hour+1)))
        end
      end
      remainder = parts.empty? ? '' : ['', *parts].join('/')
      remainder += '/' if @r['REQUEST_PATH'][-1] == '/'
      @r[:links][:prev] = p + remainder + qs + '#prev' if p && p.R.e
      @r[:links][:next] = n + remainder + qs + '#next' if n && n.R.e
    end

  end
  include URIs
  module POSIX

    def self.fromRelativePath p
      ('/' + p.gsub(' ','%20').gsub('#','%23')).R
    end

    def toRelativePath
      URI.unescape case path
                   when '/'
                     '.'
                   when /^\//
                     path[1..-1]
                   else
                     path
                   end
    end
    alias_method :localPath,:toRelativePath

    # dirname as reference
    def dir; dirname.R if path end

    # dirname as string
    def dirname; File.dirname path if path end

    # shell-escaped path
    def shellPath; localPath.force_encoding('UTF-8').sh end
    alias_method :sh, :shellPath

    # path nodes
    def parts
      @parts ||= if path
                   if path[0]=='/'
                     path[1..-1]
                   else
                     path
                   end.split '/'
                 else
                   []
                 end
    end

    # basename of path
    def basename; File.basename ( path || '/' ) end

    # strip native format suffixes
    def stripDoc; (uri.sub /\.(bu|e|html|json|log|md|msg|opml|ttl|txt|u)$/,'').R end

    # suffix
    def ext
      #path && File.extname(path)[1..-1] # TODO return nil instead of empty-string
      File.extname( path || '' )[1..-1] || ''
    end

    # SHA2 hashed URI
    def sha2; to_s.sha2 end

  end
  module HTML
    include URIs

    Icons = {
      Abstract => '✍',
      Contains => '📁',
      Content => '✏',
      Date => '⌚',
      DC+'hasFormat' => '≈',
      Identifier => '☸',
      Image => '🖼',
      Link => '☛',
      SIOC + 'attachment' => '✉',
      SIOC + 'reply_of' => '↩',
      Schema + 'width' => '↔',
      Schema + 'height' => '↕',
      Twitter => '🐦',
      Video => '🎞',
    }

    Markup = {}

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      [{_: :a, class: :link, title: u, id: 'l'+rand.to_s.sha2,
        href: u, c: u.sub(/^https?.../,'')[0..127]}," \n"]}

  end
  module Webize
    Triplr = {}
    def triplrUriList addHost = false
      base = stripDoc
      name = base.basename

      # containing file
      yield base.uri, Type, Container.R
      yield base.uri, Title, name
      prefix = addHost ? "https://#{name}/" : ''

      # resources
      lines.map{|line|
        t = line.chomp.split ' '
        unless t.empty?
          uri = prefix + t[0]
          resource = uri.R
          title = t[1..-1].join ' ' if t.size > 1
          yield uri, Title, title if title
          alpha = resource.host && resource.host.sub(/^www\./,'')[0] || ''
          container = base.uri + '#' + alpha
          yield container, Type, Container.R
          yield container, Title, alpha
          yield container, Contains, resource
        end}
    end
  end
  alias_method :uri, :to_s
end
