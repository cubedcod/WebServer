# coding: utf-8
%w(digest/sha2 fileutils linkeddata pathname shellwords).map{|_| require _}
class Array
  def R env=nil; find{|el| el.to_s.match? /^https?:/}.R env end
end

class NilClass
  def R env=nil; ''.R env end
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

class WebResource < RDF::URI

  def R e=nil; e ? env(e) : self end

  alias_method :uri, :to_s

  module URIs
    GraphExt = /\.(md|ttl|u)$/                                                                        # pattern of native graph file types
    PWD = Pathname.new Dir.pwd                                                                        # working directory
    LocalAddr = %w{l [::1] 127.0.0.1 localhost}.concat(Socket.ip_address_list.map(&:ip_address)).uniq # local addresses and hostnames
    StaticExt = %w(css geojson gif html ico jpeg jpg js json m3u8 m4a md mp3 mp4 opus pdf png svg ts webm webp xml) # cached file-types

    # vocabulary base-URIs
    W3       = 'http://www.w3.org/'
    DC       = 'http://purl.org/dc/terms/'
    OG       = 'http://ogp.me/ns#'
    SIOC     = 'http://rdfs.org/sioc/ns#'
    Abstract = DC + 'abstract'
    Atom     = W3 + '2005/Atom#'
    Audio    = DC + 'Audio'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    Date     = DC + 'date'
    DOAP     = 'http://usefulinc.com/ns/doap#'
    FOAF     = 'http://xmlns.com/foaf/0.1/'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    List     = W3 + '1999/02/22-rdf-syntax-ns#List'
    LDP      = W3 + 'ns/ldp#'
    Person   = FOAF + 'Person'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Post     = SIOC + 'Post'
    RDFs     = W3 + '2000/01/rdf-schema#'
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'
    Stat     = W3 + 'ns/posix/stat#'
    Title    = DC + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'

    # single-character representations of a URI
    Icons = {
      'https://twitter.com' => '🐦',
      Abstract => '✍',
      Audio => '🔊',
      Content => '✏',
      Creator => '👤',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      Date => '⌚',
      Image => '🖼',
      LDP + 'contains' => '📁',
      Link => '☛',
      SIOC + 'attachment' => '✉',
      SIOC + 'generator' => '⚙',
      SIOC + 'reply_of' => '↩',
      Schema + 'height' => '↕',
      Schema + 'width' => '↔',
      Stat + 'File' => '📄',
      To => '☇',
      Type => '📕',
      Video => '🎞',
    }

    def formatHint
      if basename.index('msg.')==0 || path.index('/sent/cur')==0
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
      end
    end

    def hostname; env && env['SERVER_NAME'] || host || 'localhost' end
    def hostpath; '/' + hostname.split('.').reverse.join('/') end

  end

  include URIs

  module HTML
    include URIs
    Markup = {}
  end

  include HTML

  module POSIX
    include URIs
    GlobChars = /[\*\{\[]/
    def basename; File.basename ( path || '/' ) end                 # BASENAME(1)
    def dir; dirname.R env if path end                              # DIRNAME(1)
    def directory?; node.directory? end
    def dirname; File.dirname path if path end                      # DIRNAME(1)
    def du; `du -s #{shellPath}| cut -f 1`.chomp.to_i end           # DU(1)
    def exist?; node.exist? end
    def ext; File.extname( path || '' )[1..-1] || '' end
    def file?; node.file? end
    def find p; `find #{shellPath} -iname #{Shellwords.escape p}`.lines.map{|p|('/'+p.chomp).R} end # FIND(1)
    def glob; Pathname.glob(relPath).map{|p|('/'+p.to_s).R env} end # GLOB(7)
    def grep # URI -> file(s)                                       # GREP(1)
      args = POSIX.splitArgs (env[:query]['Q'] || env[:query]['q'])
      case args.size
      when 0
        return []
      when 2 # two unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -il #{Shellwords.escape args[1]}"
      when 3 # three unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -il #{Shellwords.escape args[2]}"
      when 4 # four unordered terms
        cmd = "grep -rilZ #{Shellwords.escape args[0]} #{shellPath} | xargs -0 grep -ilZ #{Shellwords.escape args[1]} | xargs -0 grep -ilZ #{Shellwords.escape args[2]} | xargs -0 grep -il #{Shellwords.escape args[3]}"
      else # N ordered terms
        pattern = args.join '.*'
        cmd = "grep -ril #{Shellwords.escape pattern} #{shellPath}"
      end
      `#{cmd} | head -n 1024`.lines.map{|path|('/'+path.chomp).R}
    end
    def mkdir; FileUtils.mkdir_p relPath unless exist?; self end    # MKDIR(1)
    def name; basename.sub GraphExt, '' end
    def node; @node ||= (Pathname.new relPath) end
    def parts; @parts ||= path ? path.split('/').-(['']) : [] end
    def relFrom src; node.relative_path_from src.R.node end
    def relPath; ['/','',nil].member?(path) ? '.' : (path[0]=='/' ? path[1..-1] : path) end
    def self.splitArgs args; args.shellsplit rescue args.split /\W/ end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def write o; dir.mkdir; File.open(relPath,'w'){|f|f << o.force_encoding('UTF-8')}; self end
  end
  include POSIX
end
