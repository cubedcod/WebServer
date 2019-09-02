class WebResource
  module URIs
    # metadata-normalization map
    MetaMap = {
      'DC.author' => Creator,
      'DC.contributor' => Creator,
      'DC.creator' => Creator,
      'DC.description' => Abstract,
      'DC.keywords' => Abstract,
      'DC.language' => :drop,
      'DC.publisher' => Creator,
      'DC.rights' => Link,
      'DC.title' => Title,
      'EditURI' => :drop,
      'Googlebot-News' => :drop,
      'HandheldFriendly' => :drop,
      'MobileOptimized' => :drop,
      'ROBOTS' => :drop,
      'SHORTCUT ICON' => Image,
      'Shortcut Icon' => Image,
      'abstract' => Abstract,
      'adtargeting' => :drop,
      'advertisingConfig' => :drop,
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
      'al:web:url' => Link,
      'al:windows_phone:app_id' => :drop,
      'al:windows_phone:app_name' => :drop,
      'al:windows_phone:url' => :drop,
      'alternate' => DC + 'hasFormat',
      'amphtml' => :drop,
      'aplus-auto-clk' => :drop,
      'aplus-auto-exp' => :drop,
      'apple-itunes-app' => :drop,
      'apple-mobile-web-app-capable' => :drop,
      'apple-mobile-web-app-status-bar-style' => :drop,
      'apple-mobile-web-app-title' => :drop,
      'apple-touch-icon' => Image,
      'apple-touch-icon-precomposed' => Image,
      'apple-touch-startup-image' => Image,
      'application-name' => :drop,
      'article.created' => Date,
      'article.headline' => Title,
      'article:id' => :drop,
      'article.origheadline' => Title,
      'article.published' => Date,
      'article.summary' => Abstract,
      'article.type' => Type,
      'article.updated' => Date,
      'article:author' => Creator,
      'article:author_name' => Creator,
      'article:content_tier' => :drop,
      'article:expiration_time' => :drop,
      'article:modified' => Date,
      'article:modified_time' => Date,
      'article:published' => Date,
      'article:published_time' => Date,
      'article:publisher' => To,
      'article:section' => Abstract,
      'article:suggested-social-copy' => Abstract,
      'article:tag' => Abstract,
      'articleid' => :drop,
      'author' => Creator,
      'authors' => Creator,
      'baidu-site-verification' => :drop,
      'brightspot.cached' => :drop,
      'brightspot.contentId' => :drop,
      'browser-errors-url' => :drop,
      'browser-stats-url' => :drop,
      'canonical' => Link,
      'card_name' => :drop,
      'category' => Abstract,
      'content-type' => Type,
      'content:encoded' => Content,
      'copyright' => Schema+'copyright',
      'csrf-param' => :drop,
      'csrf-token' => :drop,
      'date' => Date,
      'datePublished' => Date,
      'datemodified' => Date,
      'datepublished' => Date,
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
      'Description' => Abstract,
      'description' => Abstract,
      'dns-prefetch' => :drop,
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
      'fluid-icon' => Image,
      'format-detection' => :drop,
      'generator' => SIOC + 'generator',
      'google-site-verification' => :drop,
      'googlebot' => :drop,
      'gpt:category:exclusions' => :drop,
      'gpt:params' => :drop,
      'http://ogp.me/ns#image:alt' => Abstract,
      'http://ogp.me/ns/fb#pages' => :drop,
      'http://opengraphprotocol.org/schema/description' => Abstract,
      'http://opengraphprotocol.org/schema/image' => Image,
      'http://opengraphprotocol.org/schema/image:height' => :drop,
      'http://opengraphprotocol.org/schema/image:secure_url' => Image,
      'http://opengraphprotocol.org/schema/image:width' => :drop,
      'http://opengraphprotocol.org/schema/title' => Title,
      'http://opengraphprotocol.org/schema/type' => Type,
      'http://opengraphprotocol.org/schema/updated_time' => Date,
      'http://opengraphprotocol.org/schema/url' => Link,
      'http://purl.org/dc/elements/1.1/subject' => Title,
      'http://purl.org/dc/elements/1.1/type' => Type,
      'http://search.yahoo.com/mrss/description' => Abstract,
      'http://search.yahoo.com/mrss/title' => Title,
      'http://wellformedweb.org/CommentAPI/commentRss' => Link,
      'https://ogp.me/ns#description' => Abstract,
      'https://ogp.me/ns#image' => Image,
      'https://ogp.me/ns#image:height' => :drop,
      'https://ogp.me/ns#image:width' => :drop,
      'https://ogp.me/ns#title' => Title,
      'https://ogp.me/ns#type' => Type,
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
      'https://search.yahoo.com/mrss/content' => Content,
      'https://www.apnews.com/storyHTML' => Content,
      'icon' => Image,
      'id' => :drop,
      'image' => Image,
      'image:secure_url' => Image,
      'image_src' => Image,
      'import' => :drop,
      'js-proxy-site-detection-payload' => :drop,
      'keywords' => Abstract,
      'lastmod' => Date,
      'license' => DOAP+'license',
      'linkedin:owner' => :drop,
      'manifest' => :drop,
      'mask-icon' => Image,
      'metered_paywall:json' => :drop,
      'mobile-web-app-capable' => :drop,
      'msapplication-TileColor' => :drop,
      'msapplication-TileImage' => Image,
      'msapplication-config' => :drop,
      'msapplication-tap-highlight' => :drop,
      'msapplication-task' => :drop,
      'msapplication-tooltip' => :drop,
      'msapplication-window' => :drop,
      'msvalidate.01' => :drop,
      'music:song:url' => Audio,
      'news_keywords' => Abstract,
      'next' => LDP+'next',
      'og:author' => Creator,
      'og:description' => Abstract,
      'og:first_name' => Creator,
      'og:image' => Image,
      'og:image:alt' => Abstract,
      'og:image:altText' => Abstract,
      'og:image:description' => Abstract,
      'og:image:height' => :drop,
      'og:image:secure_url' => Image,
      'og:image:title' => Abstract,
      'og:image:type' => :drop,
      'og:image:url' => Image,
      'og:image:width' => :drop,
      'og:last_name' => Creator,
      'og:locale' => :drop,
      'og:pixelID' => :drop,
      'og:pubdate' => Date,
      'og:section' => Abstract,
      'og:site_name' => To,
      'og:title' => Title,
      'og:ttl' => :drop,
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
      'P3Pv1' => :drop,
      'p:domain_verify' => :drop,
      'page:topic' => Abstract,
      'page:primary_channel' => Abstract,
      'parsely-author' => Creator,
      'parsely-image-url' => Image,
      'parsely-metadata' => :drop,
      'parsely-page' => :drop,
      'parsely-post-id' => :drop,
      'parsely-pub-date' => Date,
      'parsely-section' => Abstract,
      'parsely-tags' => Abstract,
      'parsely-title' => Title,
      'parsely-type' => Type,
      'pingback' => :drop,
      'pjax-timeout' => :drop,
      'place:location:latitude' => Schema+'latitude',
      'place:location:longitude' => Schema+'longitude',
      'preconnect' => :drop,
      'prefetch' => :drop,
      'preload' => :drop,
      'prev' => LDP+'prev',
      'profile' => :drop,
      'pubdate' => Date,
      'publish-date' => Date,
      'published_at' => Date,
      'publisher' => To,
      'referrer' => :drop,
      'request-id' => :drop,
      'robots' => :drop,
      'sailthru.author' => Creator,
      'sailthru.contentid' => :drop,
      'sailthru.date' => Date,
      'sailthru.description' => Abstract,
      'sailthru.image.full' => Image,
      'sailthru.image.thumb' => Image,
      'sailthru.lead_image' => Image,
      'sailthru.secondary_image' => Image,
      'sailthru.tags' => Abstract,
      'sailthru.title' => Title,
      'sailthru.verticals' => Abstract,
      'search' => Link,
      'section' => Abstract,
      'shenma-site-verification' => :drop,
      'shortcut icon' => Image,
      'shortlink' => Link,
      'site_name' => Abstract,
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
      'stylesheet' => :drop,
      'swift-page-name' => :drop,
      'swift-page-section' => :drop,
      'ta:title' => Title,
      'tags' => Abstract,
      'tbi-image' => Image,
      'tbi-vertical' => Abstract,
      'theme-color' => :drop,
      'thumbnail' => Image,
      'title' => Title,
      'tweet_id' => :drop,
      'twitter:account_id' => :drop,
      'twitter:app:country' => :drop,
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
      'twitter:player:stream:content_type' => :drop,
      'twitter:player:width' => :drop,
      'twitter:site' => 'https://twitter.com',
      'twitter:text:title' => Title,
      'twitter:title' => Title,
      'twitter:url' => Link,
      'type' => Type,
      'updated_time' => Date,
      'url' => Link,
      'video:director' => Creator,
      'video:duration' => :drop,
      'video:release_date' => Date,
      'videoUrl' => Video,
      'viewport' => :drop,
      'vr:canonical' => Link,
      'wlwmanifest' => :drop,
      'yandex-verification' => :drop,
      Atom + 'content' => Content,
      Atom + 'displaycategories' => Abstract,
      Atom + 'enclosure' => SIOC+'attachment',
      Atom + 'link' => DC+'link',
      Atom + 'summary' => Abstract,
      Atom + 'title' => Title,
      DC + 'created' => Date,
      FOAF + 'Image' => Image,
      OG + 'author' => Creator,
      OG + 'description' => Abstract,
      OG + 'first_name' => Creator,
      OG + 'image' => Image,
      OG + 'image:height' => :drop,
      OG + 'image:secure_url' => Image,
      OG + 'image:type' => :drop,
      OG + 'image:url' => Image,
      OG + 'image:width' => :drop,
      OG + 'last_name' => Creator,
      OG + 'pubdate' => Date,
      OG + 'see_also' => Link,
      OG + 'site_name' => To,
      OG + 'title' => Title,
      OG + 'type' => Type,
      OG + 'updated_time' => Date,
      OG + 'url' => Link,
      OG + 'username' => Creator,
      OG + 'video' => Video,
      OG + 'video:duration' => :drop,
      Podcast + 'author' => Creator,
      Podcast + 'subtitle' => Title,
      Podcast + 'title' => Title,
      RSS + 'comments' => Link,
      RSS + 'description' => Content,
      RSS + 'encoded' => Content,
      RSS + 'modules/content/encoded' => Content,
      RSS + 'modules/slash/comments' => SIOC + 'num_replies',
      RSS + 'source' => DC + 'source',
      RSS + 'title' => Title,
      Schema + 'articleBody' => Content,
      Schema + 'articleSection' => Abstract,
      Schema + 'author' => Creator,
      Schema + 'commentText' => Content,
      Schema + 'commentTime' => Date,
      Schema + 'creator' => Creator,
      Schema + 'dateCreated' => Date,
      Schema + 'dateModified' => Date,
      Schema + 'datePublished' => Date,
      Schema + 'description' => Abstract,
      Schema + 'headline' => Title,
      Schema + 'image' => Image,
      Schema + 'interactionStatistic' => :drop,
      Schema + 'keywords' => Abstract,
      Schema + 'mainEntityOfPage' => :drop,
      Schema + 'primaryImageOfPage' => Image,
      Schema + 'reviewBody' => Content,
      Schema + 'text' => Content,
      Schema + 'thumbnailUrl' => Image,
      Schema + 'url' => Link,
      Schema + 'video' => Video,
    }
  end
end
