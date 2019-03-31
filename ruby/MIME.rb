# coding: utf-8
class WebResource
  module MIME
  include URIs

  # name prefix -> MIME map
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

    # name suffix -> MIME map
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
      'lisp' => 'text/x-lisp',
      'list' => 'text/plain',
      'm3u8' => 'application/x-mpegURL',
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
      'yaml' => 'text/plain',
    }

    # MIME -> RDF-emitter map
    Triplr = {
      'application/config'   => [:triplrDataFile],
      'application/font'      => [:triplrFile],
      'application/go'   => [:triplrCode],
      'application/haskell'   => [:triplrCode],
      'application/javascript' => [:triplrCode],
      'application/ino'      => [:triplrCode],
      'application/json'      => [:triplrDataFile],
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

    NoTransform = /^(application\/(font|javascript|json|octet-stream|pdf|vnd|x-mpegURL|(x-)?protobuf(fer)?)|audio|font|image|text\/(css|javascript|vtt)|video)/

    # host-mapped HTML triplers
    TriplrHTML = {
      'twitter.com' => :triplrTweets,
    }

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

    # file matches ordered client preferences head of list
    def bestFormat? file
      preferences.head[1].member? file.mime
    end

    # file format
    def mime
      @mime ||= # memoize
        # parse name components
        (name = path || ''
         prefix = ((File.basename name).split('.')[0]||'').downcase
         suffix = ((File.extname name)[1..-1]||'').downcase
         # prefer specification in name-prefix/suffix or metafile w/ sniff as last resort
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
             puts "MIME undefined for #{localPath}, sniffing content"
             `file --mime-type -b #{Shellwords.escape localPath.to_s}`.chomp
           end
         end)
    end

    def mimeCategory
      [mime.split('/')[0], '*'].join '/'
    end

    def noTransform?; mime&.match? NoTransform end

    # work down preference list, terminate when first writer found
    def outputMIME default = 'text/html'
      return 'application/atom+xml' if q.has_key?('feed')
      preferences.map{|q,formats| # formats indexed on q-value
        formats.map{|mime|
          return default if mime == '*/*' # wildcard acceptance of default
          return mime if RDF::Writer.for(:content_type => mime) ||          # RDF writer defined
                         %w{application/atom+xml text/html}.member?(mime)}} # non-RDF writer defined
      default
    end

    def preferences
      accept.sort.reverse
    end

    # client accepts format (ANY preference level)
    def receivable? file
      accepted = accept.values.flatten
      accepted.member?(file.mime) || accepted.member?(file.mimeCategory) || accepted.member?('*/*')
    end

    # server emits format
    def sendable? file
      # not formats which need a webization
      !%w{message/rfc822 text/uri-list}.member? file.mime
    end

    def setMIME m
      @mime = m
      self
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
      p.e && p.entity(@r) || notfound
    end

  end

end
