# coding: utf-8
require 'pathname'
require 'linkeddata'
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
  def R; self end
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
    Image    = DC + 'Image'
    Link     = DC + 'link'
    LDP      = W3 + 'ns/ldp#'
    Podcast  = 'http://www.itunes.com/dtds/podcast-1.0.dtd#'
    Post     = SIOC + 'Post'
    FOAF     = 'http://xmlns.com/foaf/0.1/'
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
      Stat + 'File' => '🗎',
      To => '☇',
      Type => '📕',
      Video => '🎞',
    }

    # metadata-normalization map
    MetaMap = {
      'HandheldFriendly' => :drop,
      'ROBOTS' => :drop,
      'abstract' => Abstract,
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
      'amphtml' => :drop,
      'apple-itunes-app' => :drop,
      'apple-mobile-web-app-capable' => :drop,
      'apple-mobile-web-app-status-bar-style' => :drop,
      'apple-mobile-web-app-title' => :drop,
      'apple-touch-icon' => Image,
      'apple-touch-icon-precomposed' => Image,
      'apple-touch-startup-image' => Image,
      'application-name' => :drop,
      'article:author' => Creator,
      'article:author_name' => Creator,
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
      'gpt:category:exclusions' => :drop,
      'content:encoded' => Content,
      'copyright' => Schema+'copyright',
      'csrf-param' => :drop,
      'csrf-token' => :drop,
      'date' => Date,
      'datePublished' => Date,
      'dc.creator' => Creator,
      'dc.date' => Date,
      'dc.description' => Abstract,
      'dc.format' => :drop,
      'dc.publisher' => To,
      'dc.source' => Creator,
      'dc.title' => Title,
      'dc.type' => Type,
      'dcterms.abstract' => Abstract,
      'dcterms.created' => Date,
      'dcterms.creator' => Creator,
      'dcterms.date' => Date,
      'dcterms.description' => Abstract,
      'dcterms.format' => :drop,
      'dcterms.modified' => Date,
      'dcterms.title' => Title,
      'dcterms.type' => Type,
      'description' => Abstract,
      'dns-prefetch' => :drop,
      'EditURI' => :drop,
      'enabled-features' => :drop,
      'fb:admins' => :drop,
      'fb:app_id' => :drop,
      'fb:page_id' => :drop,
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
      'gpt:params' => :drop,
      'http://purl.org/dc/elements/1.1/subject' => Title,
      'http://purl.org/dc/elements/1.1/type' => Type,
      'https://search.yahoo.com/mrss/content' => Content,
      'http://search.yahoo.com/mrss/description' => Abstract,
      'http://search.yahoo.com/mrss/title' => Title,
      'https://ogp.me/ns#description' => Abstract,
      'https://ogp.me/ns#image' => Image,
      'https://ogp.me/ns#image:height' => :drop,
      'https://ogp.me/ns#image:width' => :drop,
      'https://ogp.me/ns#title' => Title,
      'https://ogp.me/ns#type' => Type,
      'http://ogp.me/ns#image:alt' => Abstract,
      'http://opengraphprotocol.org/schema/description' => Abstract,
      'http://opengraphprotocol.org/schema/image' => Image,
      'http://opengraphprotocol.org/schema/image:width' => :drop,
      'http://opengraphprotocol.org/schema/image:height' => :drop,
      'http://opengraphprotocol.org/schema/image:secure_url' => Image,
      'http://opengraphprotocol.org/schema/title' => Title,
      'http://opengraphprotocol.org/schema/type' => Type,
      'http://opengraphprotocol.org/schema/updated_time' => Date,
      'http://opengraphprotocol.org/schema/url' => Link,
      'https://schema.org/alternativeHeadline' => Title,
      'https://schema.org/articleBody' => Content,
      'https://schema.org/author' => Creator,
      'https://schema.org/dateCreated' => Date,
      'https://schema.org/dateModified' => Date,
      'https://schema.org/datePublished' => Date,
      'https://schema.org/description' => Abstract,
      'https://schema.org/headline' => Title,
      'https://schema.org/image' => Image,
      'https://schema.org/keywords' => Abstract,
      'https://schema.org/text' => Content,
      'https://schema.org/thumbnailUrl' => Image,
      'http://wellformedweb.org/CommentAPI/commentRss' => Link,
      'icon' => Image,
      'image' => Image,
      'image_src' => Image,
      'js-proxy-site-detection-payload' => :drop,
      'keywords' => Abstract,
      'lastmod' => Date,
      'metered_paywall:json' => :drop,
      'mobile-web-app-capable' => :drop,
      'msapplication-TileColor' => :drop,
      'msapplication-TileImage' => Image,
      'msapplication-task' => :drop,
      'msapplication-tooltip' => :drop,
      'msapplication-window' => :drop,
      'msvalidate.01' => :drop,
      'music:song:url' => Audio,
      'news_keywords' => Abstract,
      'og:author' => Creator,
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
      'og:pubdate' => Date,
      'og:site_name' => To,
      'og:title' => Title,
      'og:type' => Type,
      'og:updated_time' => Date,
      'og:url' => Link,
      'og:username' => Creator,
      'og:video' => Video,
      'og:video:duration' => :drop,
      'og:video:height' => :drop,
      'og:video:secure_url' => Video,
      'og:video:type' => :drop,
      'og:video:url' => Video,
      'og:video:width' => :drop,
      'parsely-metadata' => :drop,
      'preconnect' => :drop,
      'prefetch' => :drop,
      'preload' => :drop,
      'pubdate' => Date,
      'publisher' => To,
      'referrer' => :drop,
      'robots' => :drop,
      'sailthru.author' => Creator,
      'sailthru.date' => Date,
      'sailthru.description' => Abstract,
      'sailthru.image.full' => Image,
      'sailthru.image.thumb' => Image,
      'sailthru.lead_image' => Image,
      'sailthru.secondary_image' => Image,
      'sailthru.tags' => Abstract,
      'sailthru.title' => Title,
      'section' => Abstract,
      'shortcut icon' => Image,
      'Shortcut Icon' => Image,
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
      'https://www.apnews.com/storyHTML' => Content,
      'stylesheet' => :drop,
      'swift-page-name' => :drop,
      'swift-page-section' => :drop,
      'theme-color' => :drop,
      'thumbnail' => Image,
      'title' => Title,
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
      'twitter:image:alt' => Abstract,
      'twitter:image:height' => :drop,
      'twitter:image:src' => Image,
      'twitter:image:width' => :drop,
      'twitter:player' => Video,
      'twitter:player:height' => :drop,
      'twitter:player:stream' => Video,
      'twitter:player:width' => :drop,
      'twitter:site' => 'https://twitter.com',
      'twitter:text:title' => Title,
      'twitter:title' => Title,
      'twitter:url' => Link,
      'video:director' => Creator,
      'viewport' => :drop,
      'vr:canonical' => Link,
      'wlwmanifest' => :drop,
      Atom+'displaycategories' => Abstract,
      Atom+'content' => Content,
      Atom+'enclosure' => SIOC+'attachment',
      Atom+'link' => DC+'link',
      Atom+'summary' => Abstract,
      Atom+'title' => Title,
      DC+'created' => Date,
      FOAF+'Image' => Image,
      OG+'author' => Creator,
      OG+'description' => Abstract,
      OG+'first_name' => Creator,
      OG+'image' => Image,
      OG+'image:height' => :drop,
      OG+'image:secure_url' => Image,
      OG+'image:url' => Image,
      OG+'image:type' => :drop,
      OG+'image:width' => :drop,
      OG+'last_name' => Creator,
      OG+'pubdate' => Date,
      OG+'see_also' => Link,
      OG+'site_name' => To,
      OG+'title' => Title,
      OG+'type' => Type,
      OG+'updated_time' => Date,
      OG+'url' => Link,
      OG+'username' => Creator,
      OG+'video' => Video,
      OG+'video:duration' => :drop,
      Podcast+'author' => Creator,
      Podcast+'subtitle' => Title,
      Podcast+'title' => Title,
      RSS+'comments' => Link,
      RSS+'description' => Content,
      RSS+'encoded' => Content,
      RSS+'modules/content/encoded' => Content,
      RSS+'modules/slash/comments' => SIOC+'num_replies',
      RSS+'source' => DC+'source',
      RSS+'title' => Title,
      Schema+'articleBody' => Content,
      Schema+'articleSection' => Abstract,
      Schema+'author' => Creator,
      Schema+'creator' => Creator,
      Schema+'dateCreated' => Date,
      Schema+'dateModified' => Date,
      Schema+'datePublished' => Date,
      Schema+'description' => Abstract,
      Schema+'headline' => Title,
      Schema+'image' => Image,
      Schema+'interactionStatistic' => :drop,
      Schema+'keywords' => Abstract,
      Schema+'mainEntityOfPage' => :drop,
      Schema+'primaryImageOfPage' => Image,
      Schema+'reviewBody' => Content,
      Schema+'text' => Content,
      Schema+'thumbnailUrl' => Image,
      Schema+'url' => Link,
      Schema+'video' => Video,
    }

    CacheDir = (Pathname.new ENV['HOME'] + '/.cache/web').relative_path_from(PWD).to_s + '/'

    def dateMeta
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
      remainder += '/' if env['REQUEST_PATH'] && env['REQUEST_PATH'][-1] == '/'
      env[:links][:prev] = p + remainder + qs + '#prev' if p && p.R.exist?
      env[:links][:next] = n + remainder + qs + '#next' if n && n.R.exist?
    end

  end
  include URIs
  module HTML
    include URIs
    Markup = {}
  end
  include HTML
end
