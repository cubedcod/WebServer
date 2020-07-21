# coding: utf-8
class WebResource
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

    def format_icon mime=nil
      mime ||= ''
      x = path ? ext.downcase : ''
      if x == 'css' || mime.match?(/text\/css/)
        '🎨'
      elsif x == 'js' || mime.match?(/script/)
        '📜'
      elsif x == 'json' || mime.match?(/json/)
        '🗒'
      elsif %w(gif jpeg jpg png svg webp).member?(x) || mime.match?(/^image/)
        '🖼️'
      elsif %w(aac flac m4a mp3 ogg opus).member?(x) || mime.match?(/^audio/)
        '🔉'
      elsif %w(mp4 webm).member?(x) || mime.match?(/^video/)
        '🎬'
      elsif x == 'txt' || mime.match?(/text\/plain/)
        '🇹'
      elsif x == 'ttl' || mime.match?(/text\/turtle/)
        '🐢'
      elsif %w(htm html).member?(x) || mime.match?(/html/)
        '📃'
      elsif mime.match? /^(application\/)?font/
        '🇦'
      elsif mime.match? /octet.stream/
        '🧱'
      else
        mime
      end
    end
  end
end
