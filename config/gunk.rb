# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(assets.squarespace.com cdn.jwplayer.com twitter.com w3.cdn.anvato.net www.google.com www.instagram.com www.mixcloud.com www.youtube.com)

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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](ads?|gtag|pixel)[-._\/\(\)'"\s:?&=~%]|
amazon|acsb|addtoany|algolia|analytic|aswpsdkus|auction|
baidu|bidder|bing|BOOMR|browser-update|
campaign|chartbeat|chimp|cl(ickcease|oudfront)|co(mscore|n(fiant|natix)|okielaw)|cpx\.|cr(iteo|sspxl)|cxense|
detroitchicago|[^a-z]dfp|disqus|dotmetrics|doubleclick|
effectivemeasure|ensighten|evidon|Ezoic|
facebook|foresee|fullstory|funnel|
get(drip|pocket)|google|grapeshot|gumgum|gwallet|
hotjar|hubspot|
impression|intercom|krxd|li(nkedin|strak)|
ma(rketo|tomo)|me(dia\.net|quoda|trics)|ml314|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
omap[pi]|onesignal|optanon|outbrain|
pa(gespeed|r(dot|sely)|ypal)|pi(n(gdom|terest)|wik)|porpoiseant|prebid|pub(\.network|m(atic|ine))|
quora|qua(ltrics|nt(cast|serv))|rightmessage|
sa(il.?(horizon|thr)|lesloft)|scorecard|snowplow|statcounter|
ta(boola|rgeting)|tiqcdn|track(er|ing)|toutapp|turnto|twitter.com|typekit|
venatus|viglink|vntsm|wp.?(admin|emoji|rum)|
yandex|\.yimg|zergnet|zo(ho|pim))xi

  end
end
