class WebResource
  module URIs
    # MIME to extension mapping, adjunct to Rack's list for obscure/new/nonstandard format-identities
    Suffixes = {
      'application/manifest+json' => '.json',
      'application/x-www-form-urlencoded' => '.wwwform',
      'application/x-javascript' => '.js',
      'application/x-mpegURL' => '.m3u8',
      'application/x-rss+xml' => '.rss',
      'application/x-turtle' => '.ttl',
      'audio/mpeg' => '.mp3',
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
  end
end
