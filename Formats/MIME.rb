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
    # formats we don't offer transcoding for. could hook into ffmpeg/imagemagick for webized A/V transcoding..
    FixedFormat = /audio|css|image|script|video/
  end
  module URIs

    # MIME -> extension map - adjunct to Rack's list

    Suffixes = {
      'application/gzip' => '.gz',
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
      'text/turtle' => '.🐢',
      'text/x-c' => '.cc',
      'text/xml' => '.rss',
      'video/MP2T' => '.ts'}

    Suffixes_Rack = Rack::Mime::MIME_TYPES.invert

    MIME_Types = Suffixes.invert

  end
end
