# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(cdn.jwplayer.com twitter.com w3.cdn.anvato.net www.google.com www.instagram.com www.mixcloud.com www.youtube.com)

    AllowFile = SiteDir.join 'allow_domains'
    AllowDomains = {}
    AllowFile.each_line{|l|
      cursor = AllowDomains
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
        cursor = cursor[name] ||= {}}}

    DenyFile = SiteDir.join 'deny_domains'
    DenyDomains = {}
    DenyFile.each_line{|l|
      cursor = DenyDomains
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
        cursor = cursor[name] ||= {}}}

    Gunk = Regexp.new SiteDir.join('gunk.regex').read.chomp, Regexp::IGNORECASE

    ScriptGunk = %r(
acsb|addtoany|algolia|analytic|aswpsdkus|auction|
bidder|bing|BOOMR|browser-update|
campaign|chartbeat|chimp|cloudfront|co(mscore|nnatix|okielaw)|cpx\.|cr(iteo|sspxl)|cxense|
detroitchicago|[^a-z]dfp|disqus|dotmetrics|doubleclick|
effectivemeasure|ensighten|Ezoic|
facebook\.(com|net)|fullstory|
google.?[acst]|grapeshot|gumgum|gwallet|hotjar|
impression|intercom|krxd|li(nkedin|strak)|
marketo|matomo|media\.net|mequoda|ml314|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
omap[pi]|onesignal|optanon|outbrain|
pa(gespeed|rdot|ypal)|pi(ngdom|wik)|porpoiseant|prebid|pubmatic|
quora|qua(ltrics|nt(cast|serv))|rightmessage|
salesloft|scorecard|snowplow|
ta(boola|rgeting)|tiqcdn|track(er|ing)|turnto|twitter.com|typekit|
venatus|viglink|vntsm|
yandex|\.yimg|zergnet|zoho)xi

  end
end
