# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(assets.squarespace.com cdn.jwplayer.com gitter.im twitter.com w3.cdn.anvato.net www.google.com www.instagram.com www.mixcloud.com www.youtube.com)

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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](ads|gtag|pixel)[-._\/\(\)'"\s:?&=~%]|
ad(.?block|recover|vert)|amazon|acsb|addtoany|algolia|analytic|aswpsdkus|auction|
baidu|bazaarvoice|bidder|bing|BOOMR|browser.?update|btncdn|bugherd|
campaign|chartbeat|chimp|cl(ickcease|oudfront)|co(mscore|n(fiant|natix)|okie.?(consent|law))|cpx\.|cr(iteo|sspxl)|cxense|
detroitchicago|[^a-z]dfp|disqus|dmpxs|dotmetrics|doubleclick|
effectivemeasure|ensighten|evidon|Ezoic|
fa(cebook|stclick)|foresee|fullstory|funnel|
gdpr|get(drip|pocket)|google|grapeshot|gumgum|gwallet|
hotjar|hubspot|
impression|inte(llitxt|rcom)|krxd|kochava|
lexity|li(nkedin|strak)|
ma(iler|rketo|tomo)|me(dia\.net|quoda|trics)|ml314|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
olark|omap[pi]|one(signal|trust)|opt(anon|imizer)|outbrain|
pa(ges(ense|peed)|r(dot|sely)|ypal)|pi(n(gdom|terest)|wik)|porpoiseant|prebid|pub(\.network|m(atic|ine))|
quora|qua(ltrics|nt(cast|serv|um))|r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|lesloft)|sc(ene7|orecard)|se(archiq|edtag|ntry|rviceWorker)|slickstream|snowplow|statcounter|
ta(boola|rgeting)|tiqcdn|track(er|ing)|toutapp|turnto|twitter|typekit|
venatus|viglink|vntsm|woocommerce|wp.?(admin|emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rg)|zo(ho|pim))xi

  end
end
