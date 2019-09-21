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
  def R env_=nil; env_ ? env(env_) : self end
  alias_method :uri, :to_s
  module URIs
    PWD = Pathname.new Dir.pwd

    # vocab prefixes
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
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'
    Stat     = W3 + 'ns/posix/stat#'
    Title    = DC + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'

    Icons = { # single-character representation of URI
      'https://twitter.com' => '🐦',
      Abstract => '✍',
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

    StaticFormats = %w(css gif ico jpeg jpg js mp3 mp4 png svg wasm webm webp)

    def cache; (hostpath + path).R env end
    def hostname; env && env['SERVER_NAME'] || host || 'localhost' end
    def hostpath; '/' + hostname.split('.').reverse.join('/') end
    def isRDF?; ext == 'ttl' end

  end

  include URIs

  module HTML
    include URIs
    Markup = {}
  end

  include HTML

  module POSIX
    include URIs
    def basename; File.basename ( path || '/' ) end                 # BASENAME(1)
    def dir; dirname.R if path end                                  # DIRNAME(1)
    def dirname; File.dirname path if path end                      # DIRNAME(1)
    def du; `du -s #{shellPath}| cut -f 1`.chomp.to_i end           # DU(1)
    def exist?; node.exist? end
    def ext; File.extname( path || '' )[1..-1] || '' end
    def find p; `find #{shellPath} -iname #{Shellwords.escape p}`.lines.map{|p|('/'+p.chomp).R} end # FIND(1)
    def glob; Pathname.glob(relPath).map{|p|('/'+p.to_s).R env} end # GLOB(7)
    def grep # URI -> file(s)                                       # GREP(1)
      args = POSIX.splitArgs env[:query]['q']
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
    def node; @node ||= (Pathname.new relPath) end
    def parts; @parts ||= path ? path.split('/').-(['']) : [] end
    def relPath; ['/','',nil].member?(path) ? '.' : (path[0]=='/' ? path[1..-1] : path) end
    def self.splitArgs args; args.shellsplit rescue args.split /\W/ end
    def shellPath; Shellwords.escape relPath.force_encoding 'UTF-8' end
    def write o; dir.mkdir; File.open(relPath,'w'){|f|f << o}; self end
  end
  include POSIX
end
