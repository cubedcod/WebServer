# coding: utf-8
require 'rack'

module Webize

  def self.clean baseURI, body, format
    if format.index('text/css') == 0     # clean CSS
      Webize::CSS.clean body
    elsif format.index('text/html') == 0 # clean HTML
      Webize::HTML.clean body, baseURI
    elsif format.index('application/javascript') # clean JS
      Webize::Code.clean body, baseURI
    else
      body
    end
  end

end

class WebResource
  module HTTP
    FixedFormat = /audio|css|image|script|video/
  end
  module URIs

    # MIME to extension mapping, adjunct to Rack's list
    Suffixes = {
      'application/manifest+json' => '.json',
      'application/octet-stream' => '.bin',
      'application/ruby' => '.rb',
      'application/vnd.google.octet-stream-compressible' => '.bin',
      'application/x-www-form-urlencoded' => '.wwwform',
      'application/x-javascript' => '.js',
      'application/x-mpegURL' => '.m3u8',
      'application/x-rss+xml' => '.rss',
      'application/x-turtle' => '.ttl',
      'application/xml' => '.xml',
      'audio/mpeg' => '.mp3',
      'audio/opus' => '.opus',
      'binary/octet-stream' => '.bin',
      'image/avif' => '.avif',
      'image/GIF' => '.gif',
      'image/jpg' => '.jpg',
      'image/svg+xml' => '.svg',
      'image/webp' => '.webp',
      'image/x-icon' => '.ico',
      'text/javascript' => '.js',
      'text/json' => '.json',
      'text/turtle' => '.ttl',
      'text/x-c' => '.cc',
      'text/xml' => '.rss',
      'video/MP2T' => '.ts',
    }

    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert

    def named_format # format in filename suffix
      x = ext.to_sym
      RDF::Format.file_extensions[x][0].content_type[0] if RDF::Format.file_extensions.has_key? x
    end

    def static_node? # no transcodes or invalidation (mint new URI for new version)
      %w(bin c cc css geojson gif h ico jpeg jpg js m3u8 m4a mp3 mp4 oga ogg opus pem png rb svg tar ts wav webm webp).member? ext.downcase
    end

  end
end
