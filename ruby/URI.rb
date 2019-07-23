# coding: utf-8
require 'pathname'
require 'linkeddata'
class RDF::URI
  def R; WebResource.new to_s end
end
class RDF::Node
  def R; WebResource.new to_s end
end
class String
  def R env = nil
    env ? WebResource.new(self).env(env) : WebResource.new(self)
  end
end
class WebResource < RDF::URI
  def R; self end
  alias_method :uri, :to_s
  module URIs
    # vocabulary prefixes
    W3       = 'http://www.w3.org/'
    DC       = 'http://purl.org/dc/terms/'
    OG       = 'http://ogp.me/ns#'
    SIOC     = 'http://rdfs.org/sioc/ns#'

    # common URIs
    Abstract = DC + 'abstract'
    Atom     = W3 + '2005/Atom#'
    Content  = SIOC + 'content'
    Creator  = SIOC + 'has_creator'
    Date     = DC + 'date'
    Image    = DC + 'Image'
    Link     = DC + 'link'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Post     = SIOC + 'Post'
    RSS      = 'http://purl.org/rss/1.0/'
    Schema   = 'http://schema.org/'
    Title    = DC + 'title'
    To       = SIOC + 'addressed_to'
    Type     = W3 + '1999/02/22-rdf-syntax-ns#type'
    Video    = DC + 'Video'

    # single-character representation of URIs
    Icons = {
      'https://twitter.com' => '🐦',
      Abstract => '✍',
      Creator => '👤',
      Content => '✏',
      DC + 'hasFormat' => '≈',
      DC + 'identifier' => '☸',
      Date => '⌚',
      Image => '🖼',
      Link => '☛',
      SIOC + 'attachment' => '✉',
      SIOC + 'generator' => '⚙',
      SIOC + 'reply_of' => '↩',
      Schema + 'height' => '↕',
      Schema + 'width' => '↔',
      To => '☇',
      Video => '🎞',
      W3 + 'ns/ldp#contains' => '📁',
    }

    # metadata-normalization map
    MetaMap = {
      'HandheldFriendly' => :drop,
      'adtargeting' => :drop,
      'al:android:app_name' => :drop,
      'al:android:package' => :drop,
      'al:android:url' => :drop,
      'al:ios:app_name' => :drop,
      'al:ios:app_store_id' => :drop,
      'al:ios:url' => :drop,
      'al:ipad:app_name' => :drop,
      'al:ipad:app_store_id' => :drop,
      'al:ipad:url' => :drop,
      'al:iphone:app_name' => :drop,
      'al:iphone:app_store_id' => :drop,
      'al:iphone:url' => :drop,
      'al:web:should_fallback' => :drop,
      'alternate' => DC + 'hasFormat',
      'apple-itunes-app' => :drop,
      'apple-mobile-web-app-capable' => :drop,
      'apple-mobile-web-app-status-bar-style' => :drop,
      'apple-mobile-web-app-title' => :drop,
      'apple-touch-icon' => Image,
      'apple-touch-icon-precomposed' => Image,
      'application-name' => :drop,
      'article:author' => Creator,
      'article:modified' => Date,
      'article:modified_time' => Date,
      'article:published' => Date,
      'article:published_time' => Date,
      'article:publisher' => To,
      'article:section' => Abstract,
      'article:tag' => Abstract,
      'articleid' => :drop,
      'author' => Creator,
      'canonical' => Link,
      'content:encoded' => Content,
      'copyright' => Schema+'copyright',
      'csrf-param' => :drop,
      'csrf-token' => :drop,
      'description' => Abstract,
      'enabled-features' => :drop,
      'fb:admins' => :drop,
      'fb:app_id' => :drop,
      'fb:pages' => :drop,
      'five_hundred_pixels:author' => Creator,
      'five_hundred_pixels:category' => Abstract,
      'five_hundred_pixels:highest_rating' => :drop,
      'five_hundred_pixels:location:latitude' => Schema+'latitude',
      'five_hundred_pixels:location:longitude' => Schema+'longitude',
      'five_hundred_pixels:tags' => Abstract,
      'five_hundred_pixels:uploaded' => Date,
      'format-detection' => :drop,
      'generator' => SIOC + 'generator',
      'google-site-verification' => :drop,
      'icon' => Image,
      'image' => Image,
      'image_src' => Image,
      'js-proxy-site-detection-payload' => :drop,
      'keywords' => Abstract,
      'mobile-web-app-capable' => :drop,
      'msapplication-TileColor' => :drop,
      'msapplication-TileImage' => Image,
      'news_keywords' => Abstract,
      'og:description' => Abstract,
      'og:first_name' => Creator,
      'og:image' => Image,
      'og:image:alt' => Abstract,
      'og:image:height' => :drop,
      'og:image:secure_url' => Image,
      'og:image:type' => :drop,
      'og:image:url' => Image,
      'og:image:width' => :drop,
      'og:last_name' => Creator,
      'og:locale' => :drop,
      'og:site_name' => To,
      'og:title' => Title,
      'og:type' => Type,
      'og:updated_time' => Date,
      'og:url' => Link,
      'og:username' => Creator,
      'prefetch' => :drop,
      'referrer' => :drop,
      'robots' => :drop,
      'sailthru.date' => Date,
      'sailthru.description' => Abstract,
      'sailthru.image.full' => Image,
      'sailthru.image.thumb' => Image,
      'sailthru.lead_image' => Image,
      'sailthru.secondary_image' => Image,
      'sailthru.title' => Title,
      'shortcut icon' => Image,
      'shortlink' => Link,
      'smartbanner:button' => :drop,
      'smartbanner:button-url-apple' => :drop,
      'smartbanner:button-url-google' => :drop,
      'smartbanner:enabled-platforms' => :drop,
      'smartbanner:icon-apple' => :drop,
      'smartbanner:icon-google' => :drop,
      'smartbanner:price' => :drop,
      'smartbanner:price-suffix-apple' => :drop,
      'smartbanner:price-suffix-google' => :drop,
      'smartbanner:title' => :drop,
      'swift-page-name' => :drop,
      'swift-page-section' => :drop,
      'stylesheet' => :drop,
      'theme-color' => :drop,
      'title' => Title,
      'thumbnail' => Image,
      'twitter:app:id:googleplay' => :drop,
      'twitter:app:id:ipad' => :drop,
      'twitter:app:id:iphone' => :drop,
      'twitter:app:name:googleplay' => :drop,
      'twitter:app:name:ipad' => :drop,
      'twitter:app:name:iphone' => :drop,
      'twitter:app:url:googleplay' => :drop,
      'twitter:app:url:ipad' => :drop,
      'twitter:app:url:iphone' => :drop,
      'twitter:card' => :drop,
      'twitter:creator' => 'https://twitter.com',
      'twitter:creator:id' => :drop,
      'twitter:description' => Abstract,
      'twitter:dnt' => :drop,
      'twitter:domain' => :drop,
      'twitter:image' => Image,
      'twitter:image:height' => :drop,
      'twitter:image:src' => Image,
      'twitter:image:width' => :drop,
      'twitter:player' => Video,
      'twitter:player:height' => :drop,
      'twitter:player:width' => :drop,
      'twitter:site' => 'https://twitter.com',
      'twitter:text:title' => Title,
      'twitter:title' => Title,
      'twitter:url' => Link,
      'video:director' => Creator,
      'viewport' => :drop,
      'http://purl.org/dc/elements/1.1/subject' => Title,
      'http://purl.org/dc/elements/1.1/type' => Type,
      'http://search.yahoo.com/mrss/description' => Abstract,
      'http://search.yahoo.com/mrss/title' => Title,
      Atom+'content' => Content,
      Atom+'enclosure' => SIOC+'attachment',
      Atom+'link' => DC+'link',
      Atom+'summary' => Abstract,
      Atom+'title' => Title,
      DC+'created' => Date,
      OG+'description' => Abstract,
      OG+'first_name' => Creator,
      OG+'image' => Image,
      OG+'image:height' => :drop,
      OG+'image:secure_url' => Image,
      OG+'image:url' => Image,
      OG+'image:width' => :drop,
      OG+'last_name' => Creator,
      OG+'title' => Title,
      OG+'type' => Type,
      OG+'url' => Link,
      OG+'username' => Creator,
      Podcast+'author' => Creator,
      Podcast+'subtitle' => Title,
      Podcast+'title' => Title,
      RSS+'description' => Content,
      RSS+'encoded' => Content,
      RSS+'modules/content/encoded' => Content,
      RSS+'modules/slash/comments' => SIOC+'num_replies',
      RSS+'source' => DC+'source',
      RSS+'title' => Title,
    }

    CacheDir = (Pathname.new ENV['HOME'] + '/.cache/web').relative_path_from(Pathname.new Dir.pwd).to_s + '/'
    def cacheLocation format=nil
      want_suffix = ext.empty?
      hostPart = CacheDir + (host || 'localhost')
      pathPart = if !path || path[-1] == '/'
                   want_suffix = true
                   '/index'
                 elsif path.size > 127
                   want_suffix = true
                   hash = Digest::SHA2.hexdigest path
                   '/' + hash[0..1] + '/' + hash[2..-1]
                 else
                   path
                 end
      qsPart = if qs.empty?
                 ''
               else
                 want_suffix = true
                 '.' + Digest::SHA2.hexdigest(qs)
               end
      suffix = if want_suffix
                 if !ext || ext.empty?
                   if format
                     if xt = Extensions[RDF::Format.content_types[format]]
                       '.' + xt.to_s # suffix found in format-map
                     else
                       '' # content-type unmapped
                     end
                   else
                     '' # content-type unknown
                   end
                 else
                   '.' + ext # restore known suffix
                 end
               else
                 '' # suffix already exists
               end
      (hostPart + pathPart + qsPart + suffix).R env
    end

    def dateMeta
      @r ||= {}
      @r[:links] ||= {}
      n = nil # next page
      p = nil # prev page
      # date parts
      dp = []; ps = parts
      dp.push ps.shift.to_i while ps[0] && ps[0].match(/^[0-9]+$/)
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
      remainder = ps.empty? ? '' : ['', *ps].join('/')
      remainder += '/' if @r['REQUEST_PATH'][-1] == '/'
      @r[:links][:prev] = p + remainder + qs + '#prev' if p && p.R.exist?
      @r[:links][:next] = n + remainder + qs + '#next' if n && n.R.exist?
    end

  end
  include URIs
end
