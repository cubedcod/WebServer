# coding: utf-8
class WebResource
  module MIME
  include URIs

  # prefix -> MIME
    MIMEprefix = {
      'authors' => 'text/plain',
      'changelog' => 'text/plain',
      'contributors' => 'text/plain',
      'copying' => 'text/plain',
      'dockerfile' => 'text/x-docker',
      'gemfile' => 'text/x-ruby',
      'licence' => 'text/plain',
      'license' => 'text/plain',
      'makefile' => 'text/x-makefile',
      'notice' => 'text/plain',
      'procfile' => 'text/x-ruby',
      'rakefile' => 'text/x-ruby',
      'readme' => 'text/plain',
      'thanks' => 'text/plain',
      'todo' => 'text/plain',
      'unlicense' => 'text/plain',
      'msg' => 'message/rfc822',
    }

    # suffix -> MIME
    MIMEsuffix = {
      'aac' => 'audio/aac',
      'asc' => 'text/plain',
      'atom' => 'application/atom+xml',
      'bat' => 'text/x-batch',
      'bu' => 'text/based-uri-list',
      'cfg' => 'text/ini',
      'chk' => 'text/plain',
      'conf' => 'application/config',
      'dat' => 'application/octet-stream',
      'db' => 'application/octet-stream',
      'desktop' => 'application/config',
      'doc' => 'application/msword',
      'docx' => 'application/msword+xml',
      'e' => 'application/json',
      'eot' => 'application/font',
      'go' => 'application/go',
      'haml' => 'text/plain',
      'hs' => 'application/haskell',
      'in' => 'text/x-makefile',
      'ini' => 'text/ini',
      'ino' => 'application/ino',
      'jpg' => 'image/jpeg',
#      'jpg:large' => 'image/jpeg',
      'js' => 'application/javascript',
      'lisp' => 'text/x-lisp',
      'list' => 'text/plain',
      'm3u8' => 'application/x-mpegURL',
      'map' => 'application/json',
      'mbox' => 'application/mbox',
      'md' => 'text/markdown',
      'msg' => 'message/rfc822',
      'ogg' => 'audio/ogg',
      'opus' => 'audio/opus',
      'opml' => 'text/xml+opml',
      'pid' => 'text/plain',
      'rb' => 'text/x-ruby',
      'rst' => 'text/restructured',
      'ru' => 'text/x-ruby',
      'sample' => 'application/config',
      'sh' => 'text/x-shellscript',
      'terminfo' => 'application/config',
      'tmp' => 'application/octet-stream',
      'ttl' => 'text/turtle',
      'u' => 'text/uri-list',
      'vtt' => 'text/vtt',
      'webp' => 'image/webp',
      'woff' => 'application/font',
      'yaml' => 'text/plain'}

    # MIME -> suffix
    Extension = MIMEsuffix.invert

      # MIME -> RDF-emitter
    Triplr = {
      'application/config'   => [:triplrDataFile],
      'application/font'      => [:triplrFile],
      'application/go'   => [:triplrCode],
      'application/haskell'   => [:triplrCode],
      'application/javascript' => [:triplrCode],
      'application/ino'      => [:triplrCode],
      'application/json'      => [:triplrJSON],
      'application/mbox'      => [:triplrMbox],
      'application/octet-stream' => [:triplrFile],
      'application/org'      => [:triplrOrg],
      'application/pdf'      => [:triplrFile],
      'application/msword'   => [:triplrWordDoc],
      'application/msword+xml' => [:triplrWordXML],
      'application/pkcs7-signature' => [:triplrFile],
      'application/rtf'      => [:triplrRTF],
      'application/ruby'     => [:triplrCode],
      'application/sh'      => [:triplrCode],
      'application/x-sh'     => [:triplrCode],
      'application/xml'     => [:triplrDataFile],
      'application/x-executable' => [:triplrFile],
      'application/x-gzip'   => [:triplrArchive],
      'application/zip'   => [:triplrArchive],
      'application/vnd.oasis.opendocument.text' => [:triplrOpenDocument],
      'audio/mpeg'           => [:triplrAudio],
      'audio/x-wav'          => [:triplrAudio],
      'audio/3gpp'           => [:triplrAudio],
      'image/bmp'            => [:triplrImage],
      'image/gif'            => [:triplrImage],
      'image/png'            => [:triplrImage],
      'image/svg+xml'        => [:triplrImage],
      'image/tiff'           => [:triplrImage],
      'image/jpeg'           => [:triplrImage],
      'inode/directory'      => [:triplrContainer],
      'message/rfc822'       => [:triplrMail],
      'text/cache-manifest'  => [:triplrText],
      'text/calendar'        => [:triplrCalendar],
      'text/chatlog'         => [:triplrChatLog],
      'text/css'             => [:triplrCode],
      'text/csv'             => [:triplrCSV,/,/],
      'text/html'            => [:triplrHTML],
      'text/man'             => [:triplrMan],
      'text/xml+opml'        => [:triplrOPML],
      'text/x-batch'         => [:triplrBat],
      'text/x-c'             => [:triplrCode],
      'text/x-asm'           => [:triplrCode],
      'text/x-lisp'          => [:triplrLisp],
      'text/x-docker'        => [:triplrDocker],
      'text/ini'             => [:triplrIni],
      'text/x-makefile'      => [:triplrMakefile],
      'text/x-java-source'   => [:triplrCode],
      'text/x-ruby'          => [:triplrRuby],
      'text/x-perl'          => [:triplrPerl],
      'text/x-php'           => [:triplrCode],
      'text/x-python'        => [:triplrCode],
      'text/x-script.ruby'   => [:triplrCode],
      'text/x-script.python' => [:triplrCode],
      'text/x-shellscript'   => [:triplrShellScript],
      'text/markdown'        => [:triplrMarkdown],
      'text/nfo'             => [:triplrText,'cp437'],
      'text/plain'           => [:triplrText],
      'text/restructured'    => [:triplrCode],
      'text/rtf'             => [:triplrRTF],
      'text/semicolon-separated-values' => [:triplrCSV,/;/],
      'text/tab-separated-values' => [:triplrCSV,/\t/],
      'text/uri-list'        => [:triplrUriList],
      'text/based-uri-list'        => [:triplrUriList,true],
      'text/x-tex'           => [:triplrTeX],
    }

    RDFmimes = /^(application|text)\/(atom|html|rss|turtle|xml)/

    # environment -> acceptable formats
    def accept k = 'HTTP_ACCEPT'
      index = {}
      @r && @r[k].do{|v| # header data
        (v.split /,/).map{|e|  # split to (MIME,q) pairs
          format, q = e.split /;/ # split (MIME,q) pair
          i = q && q.split(/=/)[1].to_f || 1.0 # find q-value
          index[i] ||= []              # initialize index-entry
          index[i].push format.strip}} # index on q-value
      index
    end

    # file format
    def mime
      @mime ||= # memoize
        # parse name components
        (name = path || ''
         prefix = ((File.basename name).split('.')[0]||'').downcase
         suffix = ((File.extname name)[1..-1]||'').downcase
         # prefer specification in name prefix/suffix or metadata file, sniff as last resort
         if node.directory?
           'inode/directory'
         elsif MIMEsuffix[suffix]
           MIMEsuffix[suffix]
         elsif MIMEprefix[prefix]
           MIMEprefix[prefix]
         elsif Rack::Mime::MIME_TYPES['.'+suffix]
           Rack::Mime::MIME_TYPES['.'+suffix]
         else
           meta = metafile
           if meta.exist?
             meta.lines[0]
           else
             mimeSniff
           end
         end)
    end

    def mimeSniff
      puts "MIME undefined for #{localPath}, sniffing content"
      `file --mime-type -b #{Shellwords.escape localPath.to_s}`.chomp
    end

    def mimeCategory
      [mime.split('/')[0], '*'].join '/'
    end

    def selectFormat default = 'text/html'
      preferences.map{|q, formats| # q values in descending order
        formats.map{|mime|
          return default if mime == '*/*'
          return mime if RDF::Writer.for(:content_type => mime) ||          # RDF Writer definition found
                         %w{application/atom+xml text/html}.member?(mime)}} # non-RDF
      default
    end

    def preferences
      accept.sort.reverse
    end

    def bestFormat?
      preferences.head.do{|q, formats|
        (formats.member? '*/*') ||
        (formats.member? mime)}
    end

  end

  include MIME

  module HTTP

    # file -> HTTP Response
    def filePreview
      p = join('.' + basename + '.jpg').R
      if !p.e
        if mime.match(/^video/)
          `ffmpegthumbnailer -s 256 -i #{sh} -o #{p.sh}`
        else
          `gm convert #{sh} -thumbnail "256x256" #{p.sh}`
        end
      end
      p.e && p.entity || notfound
    end

  end
  module JPEG
    class Format < RDF::Format
      content_type 'image/jpeg', :extension => :jpg
      content_encoding 'utf-8'
      reader { WebResource::JPEG::Reader }
    end

    class Reader < RDF::Reader
      include URIs
      format Format

    def initialize(input = $stdin, options = {}, &block)
        @data = (input.respond_to?(:read) ? input : StringIO.new(input.to_s)).read.to_utf8
        if block_given?
          case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
          end
        end
        nil
      end

      def each_triple &block; each_statement{|s| block.call *s.to_triple} end

      def each_statement &fn
        image_triples{|s,p,o|
          fn.call RDF::Statement.new(s.class == String ? s.R : s,
                                     p.class == String ? p.R : p,
                                     (o.class == WebResource || o.class == RDF::Node ||
                                      o.class == RDF::URI) ? o : (l = RDF::Literal (if [Abstract,Content].member? p
                                                                                    WebResource::HTML.clean o
                                                                                   else
                                                                                     o
                                                                                    end)
                                                                  l.datatype=RDF.XMLLiteral if p == Content
                                                                  l),
                                     :graph_name => s.R)}
      end

      def image_triples
        
      end

    end
  end
  module Webize
    include MIME
    Triplr = {}

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
