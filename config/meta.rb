class WebResource

  module HTML

    # render resource-type using another type's view
    MarkupMap = {
      'article' => Post,
      'Article' => Post,
      'ArticleGQL' => Post,
      'ImageRendition' => Image,
      'VideoRendition' => Video,
      'http://schema.org/Comment' => Post,
      'http://schema.org/ProfilePage' => Person,
      'https://schema.org/BreadcrumbList' => List,
      'https://schema.org/Comment' => Post,
      'https://schema.org/ImageObject' => Image,
      'https://schema.org/NewsArticle' => Post,
      'https://schema.org/Person' => Person,
      FOAF + 'Image' => Image,
      SIOC + 'MailMessage' => Post,
      SIOC + 'MicroblogPost' => Post,
      SIOC + 'BlogPost' => Post,
      SIOC + 'UserAccount' => Person,
      Schema + 'Answer' => Post,
      Schema + 'Article' => Post,
      Schema + 'BlogPosting' => Post,
      Schema + 'BreadcrumbList' => List,
      Schema + 'Code' => Post,
      Schema + 'DiscussionForumPosting' => Post,
      Schema + 'ImageObject' => Image,
      Schema + 'ItemList' => List,
      Schema + 'NewsArticle' => Post,
      Schema + 'Person' => Person,
      Schema + 'Review' => Post,
      Schema + 'SearchResult' => Post,
      Schema + 'UserComments' => Post,
      Schema + 'VideoObject' => Video,
      Schema + 'WebPage' => Post,
    }

  end

  module URIs

    # predicate normalization map
    MetaMap = {
      'Author' => Creator,
      'DC.Date' => Date,
      'DC.Date.X-MetadataLastModified' => Date,
      'DC.Description' => Abstract,
      'DC.Publisher' => Creator,
      'DC.Publisher.Address' => Creator,
      'DC.Subject' => Abstract,
      'DC.Title' => Title,
      'DC.Type' => Type,
      'DC.author' => Creator,
      'DC.contributor' => Creator,
      'DC.creator' => Creator,
      'DC.date' => Date,
      'DC.date.created' => Date,
      'DC.date.issued' => Date,
      'DC.description' => Abstract,
      'DC.identifier' => DC+'identifier',
      'DC.keywords' => Abstract,
      'DC.language' => DC+'language',
      'DC.publisher' => Creator,
      'DC.rights' => DC+'rights',
      'DC.subject' => Abstract,
      'DC.title' => Title,
      'DC.type' => Type,
      'DCTERMS.issued' => Date,
      'DCTERMS.modified' => Date,
      'Description' => Abstract,
      'EditURI' => :drop,
      'Follow' => Link,
      'Generator' => Creator,
      'Googlebot-News' => :drop,
      'HandheldFriendly' => :drop,
      'Keywords' => Abstract,
      'MobileOptimized' => :drop,
      'Modified' => Date,
      'P3Pv1' => :drop,
      'ROBOTS' => :drop,
      'SHORTCUT ICON' => Image,
      'Shortcut Icon' => Image,
      '__typename' => Type,
      '_id' => :drop,
      'abstract' => Abstract,
      'acct' => Creator,
      'adtargeting' => :drop,
      'advertisingConfig' => :drop,
      'ajs-enabled-dark-features' => :drop,
      'al:android' => :drop,
      'al:android:app_name' => :drop,
      'al:android:package' => :drop,
      'al:android:url' => :drop,
      'al:ios' => :drop,
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
      'alexaVerifyID' => :drop,
      'algolia-public-key' => :drop,
      'alignment' => :drop,
      'allow-comments' => :drop,
      'altText' => Abstract,
      'alt_text' => Abstract,
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
      'apple:content_id' => :drop,
      'application-name' => :drop,
      'archives' => Link,
      'article.created' => Date,
      'article.headline' => Title,
      'article.origheadline' => Title,
      'article.published' => Date,
      'article.summary' => Abstract,
      'article.type' => Type,
      'article.updated' => Date,
      'article_author' => Creator,
      'article:author' => Creator,
      'article:author_name' => Creator,
      'article:content-tier' => :drop,
      'article:content_tier' => :drop,
      'article:expiration_time' => :drop,
      'article:id' => :drop,
      'article:modified' => Date,
      'article:modified_time' => Date,
      'article:opinion' => 'https://schema.org/OpinionNewsArticle',
      'article:post_date' => Date,
      'article:post_modified' => Date,
      'article:published' => Date,
      'article:published_time' => Date,
      'article:publisher' => To,
      'article:section' => Abstract,
      'article:section_url' => Link,
      'article:suggested-social-copy' => Abstract,
      'article:tag' => Abstract,
      'article:title' => Title,
      'articleBody' => Content,
      'articleid' => :drop,
      'artwork_url' => Image,
      'aspectRatio' => :drop,
      'assets' => :drop,
      'author' => Creator,
      'author_name' => Creator,
      'author_url' => Creator,
      'authorName' => Creator,
      'authorUrl' => Creator,
      'authors' => Creator,
      'avatar' => Image,
      'avatar_url' => Image,
      'avatarUrl' => Image,
      'avatarUrlMedium' => Image,
      'avatarUrlSmall' => Image,
      'avatar_static' => Image,
      'baidu-site-verification' => :drop,
      'beat' => Abstract,
      'biography' => Abstract,
      'blurhash' => :drop,
      'body' => Content,
      'bookmark' => Link,
      'bot' => :drop,
      'brightspot.cached' => :drop,
      'brightspot.contentId' => :drop,
      'browser-errors-url' => :drop,
      'browser-stats-url' => :drop,
      'bt:author' => Creator,
      'bt:modDate' => Date,
      'bt:pubDate' => Date,
      'byl' => Creator,
      'bylines' => Creator,
      'calloutText' => Abstract,
      'canonical' => Link,
      'canonical_path' => Link,
      'caption' => Abstract,
      'card_name' => :drop,
      'category' => Abstract,
      'category_mapping' => :drop,
      'checksum' => :drop,
      'ci:canonical' => Link,
      'comments_disabled' => :drop,
      'commentable' => :drop,
      'completeUrl' => Link,
      'componentType' => Type,
      'content' => Content,
      'content-type' => Type,
      'content:encoded' => Content,
      'content_html' => Content,
      'content_text' => Content,
      'cooked' => Content,
      'copyright' => DC + 'rights',
      'crdt' => Creator,
      'createdOn' => Date,
      'created_at' => Date,
      'created-at' => Date,
      'created_date' => Date,
      'createdAt' => Date,
      'csrf-param' => :drop,
      'csrf-token' => :drop,
      'cx_shield' => :drop,
      'data' => :drop,
      'dataLayer' => :drop,
      'date' => Date,
      'dateCreated' => Date,
      'dateModified' => Date,
      'datePublished' => Date,
      'date_modified' => Date,
      'date_published' => Date,
      'datemodified' => Date,
      'datepublished' => Date,
      'dc.creator' => Creator,
      'dc.date' => Date,
      'dc.description' => Abstract,
      'dc.format' => :drop,
      'dc.identifier' => DC+'identifier',
      'dc.language' => DC+'language',
      'dc.publisher' => To,
      'dc.rights' => DC+'rights',
      'dc.source' => Creator,
      'dc.subject' => Title,
      'dc.title' => Title,
      'dc.type' => Type,
      'dct:created' => Date,
      'dct:creator' => Creator,
      'dct:modified' => Date,
      'dct:references' => Link,
      'dcterms.Date' => Date,
      'dcterms.Description' => Abstract,
      'dcterms.Subject' => Title,
      'dcterms.Title' => Title,
      'dcterms.abstract' => Abstract,
      'dcterms.created' => Date,
      'dcterms.creator' => Creator,
      'dcterms.date' => Date,
      'dcterms.description' => Abstract,
      'dcterms.format' => :drop,
      'dcterms.modified' => Date,
      'dcterms.rights' => DC+'rights',
      'dcterms.rightsHolder' => DC+'rightsHolder',
      'dcterms.title' => Title,
      'dcterms.type' => Type,
      'description' => Abstract,
      'dimension1' => :drop,
      'discourse_current_homepage' => :drop,
      'discourse_theme_ids' => :drop,
      'discoverable' => :drop,
      'discussion' => SIOC + 'has_discussion',
      'display_date' => Date,
      'displayName' => Title,
      'display_name' => Title,
      'display-name' => Title,
      'display_type' => Type,
      'dns-prefetch' => :drop,
      'downloadable' => :drop,
      'dsc' => Abstract,
      'duration' => Schema+'duration',
      'editedAt' => Date,
      'email' => :drop,
      'embedCaption' => Abstract,
      'embeddable_by' => :drop,
      'embedHTML' => Content,
      'embedLinkUrl' => Link,
      'enabled-features' => :drop,
      'environment' => :drop,
      'error' => :drop,
      'etag' => :drop,
      'expected-hostname' => :drop,
      'expiration' => :drop,
      'external' => Link,
      'externalId' => :drop,
      'facebook-domain-verification' => :drop,
      'favourited' => :drop,
      'favourites_count' => :drop,
      'fb:admins' => :drop,
      'fb:app_id' => :drop,
      'fb:page_id' => :drop,
      'fb:pages' => :drop,
      'fb:status' => Abstract,
      'fb:ttl' => :drop,
      'first_name' => Creator,
      'firstPublished' => Date,
      'firstWords' => Abstract,
      'five_hundred_pixels:author' => Creator,
      'five_hundred_pixels:category' => Abstract,
      'five_hundred_pixels:highest_rating' => :drop,
      'five_hundred_pixels:location:latitude' => Schema+'latitude',
      'five_hundred_pixels:location:longitude' => Schema+'longitude',
      'five_hundred_pixels:tags' => Abstract,
      'five_hundred_pixels:uploaded' => Date,
      'flattenedCaption' => Abstract,
      'fluid-icon' => Image,
      'fmSubsection' => Abstract,
      'follow' => Link,
      'followers_count' => :drop,
      'following_count' => :drop,
      'format-detection' => :drop,
      'fragment' => :drop,
      'fromUser' => Creator,
      'full_duration' => Schema+'duration',
      'full_name' => Creator,
      'fullName' => Title,
      'fullUrl' => Link,
      'generated' => :drop,
      'generator' => Creator,
      'github-keyboard-shortcuts' => :drop,
      'go-import' => :drop,
      'google-play-app' => :drop,
      'google-signin-client_id' => :drop,
      'google-site-verification' => :drop,
      'googlebot' => :drop,
      'googlebot-news' => :drop,
      'gpt:category:exclusions' => :drop,
      'gpt:params' => :drop,
      'group' => To,
      'gv' => :drop,
      'has_downloads_left' => :drop,
      'hasImage' => :drop,
      'header' => Image,
      'header_static' => Image,
      'headline' => Title,
      'height' => :drop,
      'home' => Link,
      'hostname' => :drop,
      'hovercard-subject-tag' => :drop,
      'html' => Content,
      'html-safe-nonce' => :drop,
      'http://data-vocabulary.org/startDate' => Date,
      'http://data-vocabulary.org/summary' => Abstract,
      'http://data-vocabulary.org/title' => Title,
      'http://data-vocabulary.org/url' => 'uri',
      'http://ogp.me/ns#image:alt' => Abstract,
      'http://ogp.me/ns#video:url' => Video,
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
      'http://purl.org/dc/elements/1.1/title' => Title,
      'http://purl.org/dc/elements/1.1/type' => Type,
      'http://purl.org/atom/ns#modified' =>  Date,
      'http://purl.org/atom/ns#issued' => Date,
      'http://purl.org/atom/ns#author' => Creator,
      'http://purl.org/atom/ns#summary' => Abstract,
      'http://purl.org/atom/ns#title' => Title,
      'http://purl.org/atom/ns#content' => Content,
      'http://purl.org/atom/ns#created' => Date,
      'http://prismstandard.org/namespaces/basic/2.0/publicationDate' => Date,
      'http://search.yahoo.com/mrss/content' => Content,
      'http://search.yahoo.com/mrss/description' => Abstract,
      'http://search.yahoo.com/mrss/title' => Title,
      'http://wellformedweb.org/CommentAPI/commentRss' => Link,
      'https://ogp.me/ns#description' => Abstract,
      'https://ogp.me/ns#image' => Image,
      'https://ogp.me/ns#image:height' => :drop,
      'https://ogp.me/ns#image:width' => :drop,
      'https://ogp.me/ns#title' => Title,
      'https://ogp.me/ns#type' => Type,
      'http://rssnamespace.org/feedburner/ext/1.0#origLink' => Link,
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
      'https://schema.org/name' => Title,
      'https://schema.org/startDate' => Date,
      'https://schema.org/text' => Content,
      'https://schema.org/thumbnailUrl' => Image,
      'https://search.yahoo.com/mrss/content' => Content,
      'icon' => Image,
      'id' => :drop,
      'image' => Image,
      'image:secure_url' => Image,
      'imageMimeType' => :drop,
      'image_src' => Image,
      'image_type' => Type,
      'image_url' => Image,
      'import' => :drop,
      'in_reply_to_account_id' => SIOC+'reply_of',
      'in_reply_to_id' => SIOC+'reply_of',
      'instapp:hashtags' => Abstract,
      'instapp:owner_user_id' => :drop,
      'interactionCount' => :drop,
      'is_nsfw' => :drop,
      'item-type' => Type,
      'js-proxy-site-detection-payload' => :drop,
      'keywords' => Abstract,
      'kind' => Type,
      'krux:description' => Abstract,
      'krux:title' => Title,
      'language' => DC+'language',
      'last_modified' => Date,
      'lastMajorModification' => Date,
      'lastModified' => Date,
      'last_status_at' => Date,
      'last_updated_date' => Date,
      'lastmod' => Date,
      'leadHubLink' => :drop,
      'license' => DOAP+'license',
      'link' => Link,
      'linkedin:owner' => :drop,
      'lnkd:url' => Link,
      'loadedAt' => :drop,
      'loading' => :drop,
      'localLinkUrl' => Link,
      'locked' => :drop,
      'logo' => Image,
      'managementId' => :drop,
      'manifest' => Schema+'manifest',
      'manifest-validation' => :drop,
      'mask-icon' => Image,
      'me' => Creator,
      'mediumKey' => :drop,
      'metered_paywall:json' => :drop,
      'mixpanel:token' => :drop,
      'mobile-web-app-capable' => :drop,
      'modifiedOn' => Date,
      'monetization' => :drop,
      'monetization_model' => :drop,
      'msapplication-TileColor' => :drop,
      'msapplication-TileImage' => Image,
      'msapplication-config' => :drop,
      'msapplication-navbutton-color' => :drop,
      'msapplication-starturl' => :drop,
      'msapplication-tap-highlight' => :drop,
      'msapplication-task' => :drop,
      'msapplication-tooltip' => :drop,
      'msapplication-window' => :drop,
      'msvalidate.01' => :drop,
      'music:song:url' => Audio,
      'name' => Title,
      'news_keywords' => Abstract,
      'next' => LDP+'next',
      'nofollow' => Link,
      'noopen' => Link,
      'noopener' => Link,
      'noreferrer' => Link,
      'norton-safeweb-site-verification' => :drop,
      'note' => Content,
      'og:article:author' => Creator,
      'og:article:modified_time' => Date,
      'og:article:published_time' => Date,
      'og:author' => Creator,
      'og:description' => Abstract,
      'og:fb_appid' => :drop,
      'og:first_name' => Creator,
      'og:ignore_canonical' => :drop,
      'og:image' => Image,
      'og:image:alt' => Abstract,
      'og:image:altText' => Abstract,
      'og:image:description' => Abstract,
      'og:image:height' => :drop,
      'og:image:secure_url' => Image,
      'og:image:title' => Abstract,
      'og:image:type' => :drop,
      'og:image:url' => Image,
      'og:image:user_generated' => :drop,
      'og:image:width' => :drop,
      'og:images' => Image,
      'og:last_name' => Creator,
      'og:locale' => :drop,
      'og:pixelID' => :drop,
      'og:pubdate' => Date,
      'og:section' => Abstract,
      'og:see_also' => Link,
      'og:site_name' => To,
      'og:title' => Title,
      'og:ttl' => :drop,
      'og:type' => Type,
      'og:updated_time' => Date,
      'og:url' => Link,
      'og:username' => Creator,
      'og:video' => Video,
      'og:video:duration' => Schema+'duration',
      'og:video:height' => :drop,
      'og:video:secure_url' => Video,
      'og:video:tag' => Abstract,
      'og:video:type' => :drop,
      'og:video:url' => Video,
      'og:video:width' => :drop,
      'oneLine' => Abstract,
      'opened' => :drop,
      'optimizely-datafile' => :drop,
      'optimizely-sdk-key' => :drop,
      'p:domain_verify' => :drop,
      'page:primary_channel' => Abstract,
      'page:topic' => Abstract,
      'pagetype' => Type,
      'parsely-author' => Creator,
      'parsely-image-url' => Image,
      'parsely-link' => Link,
      'parsely-metadata' => :drop,
      'parsely-page' => :drop,
      'parsely-post-id' => :drop,
      'parsely-pub-date' => Date,
      'parsely-section' => Abstract,
      'parsely-tags' => Abstract,
      'parsely-title' => Title,
      'parsely-type' => Type,
      'partnerConfig' => :drop,
      'partnerFooterConfig' => :drop,
      'pdate' => Date,
      'permalink' => Link,
      'permalink_url' => Link,
      'pingback' => :drop,
      'pinterest-rich-pin' => :drop,
      'pjax-timeout' => :drop,
      'place:location:latitude' => Schema+'latitude',
      'place:location:longitude' => Schema+'longitude',
      'playerType' => :drop,
      'pocket-site-verification' => :drop,
      'preconnect' => :drop,
      'prefetch' => :drop,
      'preload' => :drop,
      'prerender' => Link,
      'prev' => LDP+'prev',
      'preview_url' => Link,
      'profile' => :drop,
      'profile:username' => Creator,
      'profile_image_url' => Image,
      'profilePicture' => Image,
      'promotionalHeadline' => Title,
      'promotionalSummary' => Abstract,
      'propeller' => :drop,
      'provider_name' => To,
      'provider_url' => To,
      'pubdate' => Date,
      'publish-date' => Date,
      'publish_date' => Date,
      'publishDate' => Date,
      'published' => Date,
      'published_at' => Date,
      'publisher' => To,
      'rating' => :drop,
      'readBy' => :drop,
      'reblogged' => :drop,
      'reblogs_count' => :drop,
      'referrer' => Link,
      'regionsAllowed' => :drop,
      'remote_url' => Link,
      'replies_count' => :drop,
      'reply_count' => :drop,
      'request-id' => :drop,
      'resource-type' => Type,
      'revisit-after' => :drop,
      'robots' => :drop,
      'rootVe' => :drop,
      'safe_content' => Content,
      'sailthru.author' => Creator,
      'sailthru.contentid' => :drop,
      'sailthru.contenttype' => Type,
      'sailthru.date' => Date,
      'sailthru.description' => Abstract,
      'sailthru.excerpt' => Abstract,
      'sailthru.image.full' => Image,
      'sailthru.image.thumb' => Image,
      'sailthru.lead_image' => Image,
      'sailthru.secondary_image' => Image,
      'sailthru.socialtitle' => Title,
      'sailthru.tags' => Abstract,
      'sailthru.title' => Title,
      'sailthru.verticals' => Abstract,
      'scriptConfig' => :drop,
      'search' => Link,
      'searchable' => :drop,
      'section' => Abstract,
      'section-name' => Abstract,
      'section-slug' => Abstract,
      'section-url' => Link,
      'self' => Link,
      'sensitive' => :drop,
      'sent' => Date,
      'share-image' => :drop,
      'sharing' => :drop,
      'shenma-site-verification' => :drop,
      'shortcode' => :drop,
      'shortcut' => :drop,
      'shorter' => Link,
      'shortlink' => Link,
      'shortlinkUrl' => Link,
      'shorturl' => Link,
      'showAds' => :drop,
      'site_name' => Abstract,
      'slack-app-id' => :drop,
      'slug' => Abstract,
      'slugline' => Abstract,
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
      'snapchat:sticker' => Image,
      'soundcloud:follower_count' => :drop,
      'soundcloud:sound_count' => :drop,
      'spoiler_text' => Abstract,
      'sponsored' => :drop,
      'sputnik-verification' => :drop,
      'src' => Image,
      'state' => :drop,
      'static_url' => Link,
      'statuses_count' => :drop,
      'storyHTML' => Content,
      'streamable' => :drop,
      'style-nonce' => :drop,
      'stylesheet' => :drop,
      'subtitle' => Abstract,
      'summary' => Abstract,
      'swift-page-name' => :drop,
      'swift-page-section' => :drop,
      'ta:title' => Title,
      'taboola:headline' => Title,
      'taboola:image:large' => Image,
      'taboola:image:medium' => Image,
      'tag' => Abstract,
      'tagIds' => Abstract,
      'tags' => Abstract,
      'tbi-image' => Image,
      'tbi-vertical' => Abstract,
      'text' => Content,
      'text_url' => Link,
      'theme-color' => :drop,
      'thumbnail' => Image,
      'thumbnail_url' => Image,
      'thumbnailUrl' => Image,
      'title' => Title,
      'topics' => Abstract,
      'total_comment_count' => :drop,
      'trigrams' => Abstract,
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
      'twitter:partner' => :drop,
      'twitter:player' => Video,
      'twitter:player:height' => :drop,
      'twitter:player:stream' => Video,
      'twitter:player:stream:content_type' => :drop,
      'twitter:player:width' => :drop,
      'twitter:site' => Link,
      'twitter:site:id' => :drop,
      'twitter:text:title' => Title,
      'twitter:title' => Title,
      'twitter:url' => Link,
      'twitter:widgets:border-color' => :drop,
      'twitter:widgets:link-color' => :drop,
      'twitterId' => :drop,
      'twitterName' => Creator,
      'type' => Type,
      'typename' => Type,
      'ugc' => Link,
      'unlisted' => :drop,
      'unread' => :drop,
      'updated' => Date,
      'updated_at' => Date,
      'updated-at' => Date,
      'updated_time' => Date,
      'updatedAt' => Date,
      'uploadDate' => Date,
      'url' => Link,
      'urlTitle' => Title,
      'user-login' => :drop,
      'userInteractionCount' => :drop,
      'username' => Creator,
      'v' => :drop,
      'validatedAt' => Date,
      'verify-v1' => :drop,
      'video:director' => Creator,
      'video:duration' => Schema+'duration',
      'video:release_date' => Date,
      'video:tag' => Abstract,
      'videoMimeType' => :drop,
      'videoUrl' => Video,
      'video_height' => :drop,
      'video_type' => :drop,
      'video_width' => :drop,
      'viewport' => :drop,
      'visibility' => :drop,
      'visible_in_picker' => :drop,
      'visitor-hmac' => :drop,
      'visitor-payload' => :drop,
      'vk:image' => Image,
      'vr:canonical' => Link,
      'webPageType' => Type,
      'width' => :drop,
      'wlwmanifest' => :drop,
      'xxUpdated' => Date,
      'xx_created' => Date,
      'xx_updated' => Date,
      'y_key' => :drop,
      'yandex-verification' => :drop,
      Atom + 'content' => Content,
      Atom + 'displaycategories' => Abstract,
      Atom + 'enclosure' => SIOC+'attachment',
      Atom + 'link' => DC+'link',
      Atom + 'pubDate' => Date,
      Atom + 'self' => Link,
      Atom + 'summary' => Abstract,
      Atom + 'title' => Title,
      DC + 'created' => Date,
      FOAF + 'Image' => Image,
      OG + 'author' => Creator,
      OG + 'description' => Abstract,
      OG + 'first_name' => Creator,
      OG + 'ignore_canonical' => :drop,
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
      OG + 'video:secure_url' => Video,
      Podcast + 'author' => Creator,
      Podcast + 'subtitle' => Title,
      Podcast + 'summary' => Content,
      Podcast + 'title' => Title,
      RDFs + 'seeAlso' => Link,
      RSS + 'category' => Abstract,
      RSS + 'comments' => Link,
      RSS + 'description' => Content,
      RSS + 'encoded' => Content,
      RSS + 'modules/content/encoded' => Content,
      RSS + 'modules/slash/comments' => :drop,
      RSS + 'source' => DC + 'source',
      RSS + 'title' => Title,
      Schema + 'articleBody' => Content,
      Schema + 'articleSection' => Abstract,
      Schema + 'author' => Creator,
      Schema + 'commentText' => Content,
      Schema + 'commentTime' => Date,
      Schema + 'copyright' => DC + 'rights',
      Schema + 'creator' => Creator,
      Schema + 'dateCreated' => Date,
      Schema + 'dateModified' => Date,
      Schema + 'datePosted' => Date,
      Schema + 'datePublished' => Date,
      Schema + 'description' => Abstract,
      Schema + 'entry-title' => Title,
      Schema + 'headline' => Title,
      Schema + 'image' => Image,
      Schema + 'interactionCount' => :drop,
      Schema + 'interactionStatistic' => :drop,
      Schema + 'keywords' => Abstract,
      Schema + 'mainEntityOfPage' => :drop,
      Schema + 'name' => Title,
      Schema + 'potentialAction' => :drop,
      Schema + 'primaryImageOfPage' => Image,
      Schema + 'published' => Date,
      Schema + 'reviewBody' => Content,
      Schema + 'text' => Content,
      Schema + 'thumbnailUrl' => Image,
      Schema + 'updated' => Date,
      Schema + 'url' => Link,
      Schema + 'video' => Video,
    }
  end
end
