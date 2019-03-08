# coding: utf-8
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

    # common URI prefixes
    W3 = 'http://www.w3.org/'
    OA = 'https://www.w3.org/ns/oa#'
    Purl = 'http://purl.org/'
    DC   = Purl + 'dc/terms/'
    DCe  = Purl + 'dc/elements/1.1/'
    SIOC = 'http://rdfs.org/sioc/ns#'
    Link = DC + 'link'
    Schema = 'http://schema.org/'
    Media = 'http://search.yahoo.com/mrss/'
    Podcast = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Comments = 'http://wellformedweb.org/CommentAPI/commentRss'
    Sound    = Purl + 'ontology/mo/Sound'
    Image    = DC + 'Image'
    Video    = DC + 'Video'
    RSS      = Purl + 'rss/1.0/'
    Date     = DC   + 'date'
    Title    = DC   + 'title'
    Abstract = DC   + 'abstract'
    Identifier = DC + 'identifier'
    Post     = SIOC + 'Post'
    To       = SIOC + 'addressed_to'
    From     = SIOC + 'has_creator'
    Creator  = SIOC + 'has_creator'
    Content  = SIOC + 'content'
    BlogPost = SIOC + 'BlogPost'
    Email    = SIOC + 'MailMessage'
    Resource = W3   + '2000/01/rdf-schema#Resource'
    Stat     = W3   + 'ns/posix/stat#'
    Atom     = W3   + '2005/Atom#'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Label    = W3 + '2000/01/rdf-schema#label'
    Size     = Stat + 'size'
    Mtime    = Stat + 'mtime'
    Container = W3  + 'ns/ldp#Container'
    Contains  = W3  + 'ns/ldp#contains'
    Twitter = 'https://twitter.com'

    def + u; (to_s + u.to_s).R end

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
      remainder += '/' if path[-1] == '/'

      @r[:links][:prev] = p + remainder + qs + '#prev' if p && p.R.e
      @r[:links][:next] = n + remainder + qs + '#next' if n && n.R.e
      @r[:links][:up] = dirname + (dirname == '/' ? '' : '/') + qs + '#r' + (path||'/').sha2 unless !path || path=='/'
    end

    def match p; to_s.match p end

    def subdomain
      host.split('.')[1..-1].unshift('').join '.'
    end
  end
  include URIs
  module POSIX

    def cacheFile
      useExtension = %w{aac atom css html jpeg jpg js mp3 mp4 ogg opus pdf png rdf svg ttf ttl webm webp woff woff2}.member? ext.downcase
      ('/' + host + (if host.match?(/google|gstatic|\.redd/) || (qs && !qs.empty?) # new path
                     hash = ((path||'/') + qs).sha2                    # hash original path
                     type = useExtension ? ext : 'cache'               # append suffix
                     '/' + hash[0..1] + '/' + hash[1..-1] + '.' + type # plunk in balanced bins
                    else # upstream path
                      name = path[-1] == '/' ? path[0..-2] : path # strip trailing-slash
                      name + (useExtension ? '' : '.cache') # append suffix
                     end)).R env
    end

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

    # metadata-file location 
    def metafile type = 'meta'
      dir + (dirname[-1] == '/' ? '' : '/') + '.' + basename + '.' + type
    end

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
    def basename; File.basename ( path || '' ) end

    # strip native format suffixes
    def stripDoc; (uri.sub /\.(bu|e|html|json|log|md|msg|opml|ttl|txt|u)$/,'').R end

    # suffix
    def ext; File.extname( path || '' )[1..-1] || '' end

    # SHA2 hashed URI
    def sha2; to_s.sha2 end

  end
  module HTTP

    # GET lambda tables
    HostGET = {}
    PathGET = {}

    # POST lambda tables
    HostPOST = {}
    PathPOST = {}

    HostOPTIONS = {}

    InsecureShorteners = %w{
bhne.ws
bos.gl
feeds.reuters.com
f-st.co
huffp.st
ihe.art
nyer.cm
ow.ly
rss.cnn.com
rssfeeds.usatoday.com
w.bos.gl
}
    def cachedRedirect
      verbose = true
      scheme = 'http' + (InsecureShorteners.member?(host) ? '' : 's') + '://'
      sourcePath = path || ''
      source = scheme + host + sourcePath
      dest = nil
      cache = ('/cache/URL/' + host + (sourcePath[0..2] || '') + '/' + (sourcePath[3..-1] || '') + '.u').R
      puts "redir #{source} ->" if verbose

      if cache.exist?
        puts "cached at #{cache}" if verbose
        dest = cache.readFile
      else
        puts "fetch #{source}" if verbose
        resp = Net::HTTP.get_response (URI.parse source)
        puts resp.body if verbose
        dest = resp['Location'] || resp['location']
        if !dest
          body = Nokogiri::HTML.fragment resp.body
          refresh = body.css 'meta[http-equiv="refresh"]'
          if refresh && refresh.size > 0
            content = refresh.attr('content')
            if content
              dest = content.to_s.split('URL=')[-1]
            end
          end
        end
        cache.writeFile dest if dest
      end

      puts dest if verbose
      dest = dest ? dest.R : nil
      if @r
        # return URI to caller in document
        # [200, {'Content-Type' => 'text/html'}, [htmlDocument({source => {Link => dest}})]]
        # redirect to URI
        dest ? [302, {'Location' =>  dest},[]] : notfound
      else
        dest
      end
    end

  end
  module HTML
    include URIs

    Icons = {
      Abstract => '✍️',
      Contains => '📁',
      Content => '✏️',
      Date => '📅',
      DC+'note' => 'ℹ️',
      DC+'hasFormat' => '📑',
      Identifier => '🆔',
      Image => '🖼️',
      Link => '🔗',
      SIOC + 'attachment' => '📎',
      SIOC + 'reply_of' => '↩️',
      Schema + 'width' => '↔',
      Schema + 'height' => '↕',
      Video => '📼',
    }

    Group = {}
    Markup = {}

    def self.urifyHash h
      u = {}
      h.map{|k,v|
        u[k] = case v.class
               when Hash
                 HTML.urifyHash v
               when String
                 HTML.urifyString v
               else
                 v
               end}
      u
    end

    def self.urifyString str
      str.match(/^(http|\/)\S+$/) ? str.R : str
    end

    Markup[Link] = -> ref, env=nil {
      u = ref.to_s
      [{_: :a, class: :link, title: u, id: 'l'+rand.to_s.sha2,
        href: u, c: u.sub(/^https?.../,'')[0..127]}," \n"]}

  end
  module Webize
    # HTML indexer host->method table
    IndexHTML = {}

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
