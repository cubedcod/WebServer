# coding: utf-8
require 'rack'
class WebResource
  module HTTP

    def selectFormat default = 'text/html'
      return default unless env.has_key? 'HTTP_ACCEPT' # no preference specified

      index = {} # q-value -> format

      env['HTTP_ACCEPT'].split(/,/).map{|e| # split to (MIME,q) pairs
        format, q = e.split /;/             # split (MIME,q) pair
        i = q && q.split(/=/)[1].to_f || 1  # q-value with default
        index[i] ||= []                     # init index
        index[i].push format.strip}         # index on q-value

      index.sort.reverse.map{|q,formats| # formats sorted on descending q-value
        formats.sort_by{|f|{'text/turtle'=>0}[f]||1}.map{|f|  # tiebreak with 🐢-winner
          return default if f == '*/*'                        # default via wildcard
          return f if RDF::Writer.for(:content_type => f) ||  # RDF via writer definition
            ['application/atom+xml','text/html'].member?(f)}} # non-RDF via writer definition

      default                                                 # default
    end

  end
  module URIs

    # MIME to extension mapping, adjunct to Rack's list
    Suffixes = {
      'application/manifest+json' => '.json',
      'application/octet-stream' => '.bin',
      'application/vnd.google.octet-stream-compressible' => '.bin',
      'application/x-www-form-urlencoded' => '.wwwform',
      'application/x-javascript' => '.js',
      'application/x-mpegURL' => '.m3u8',
      'application/x-rss+xml' => '.rss',
      'application/x-turtle' => '.ttl',
      'audio/mpeg' => '.mp3',
      'audio/opus' => '.opus',
      'binary/octet-stream' => '.bin',
      'image/jpg' => '.jpg',
      'image/svg+xml' => '.svg',
      'image/webp' => '.webp',
      'image/x-icon' => '.ico',
      'text/javascript' => '.js',
      'text/json' => '.json',
      'text/turtle' => '.ttl',
      'text/xml' => '.rss',
      'video/MP2T' => '.ts',
    }

    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert

    def named_format # format in filename suffix
      x = ext.to_sym
      RDF::Format.file_extensions[x][0].content_type[0] if RDF::Format.file_extensions.has_key? x
    end

    def static_node? # format and content is static - no transcode or invalidation - mint new URI for new version
      %w(bin css geojson ico jpeg jpg js m3u8 m4a mp3 mp4 opus pem pdf png svg tar ts wav webm webp).member? ext.downcase
    end

  end
end
