# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(w3.cdn.anvato.net code.jquery.com cdn.jwplayer.com gitter.im www.google.com twitter.com www.instagram.com www.mixcloud.com assets.squarespace.com www.youtube.com)

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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](ads|bing|gt(ag|m)|pi(ng|xel)|s(entry|umo)|utm)[-._\/\(\)'"\s:?&=~%]|
ad(.?bl(ade|ock)|push|r(ecover|oll)|vert)|am(azon|plitude)|acsb|addtoany|algolia|analytic|aswpsdkus|auction|
baidu|bazaarvoice|bidder|BO(OMR|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
campaign|chartbeat|chimp|cl(ickcease|oudfront)|co(mscore|n(fiant|natix|sent)|okie.?(consent|law))|cpx\.|cr(iteo|sspxl)|cxense|
detroitchicago|[^a-z]dfp|disqus|dmpxs|dotmetrics|doubleclick|
effectivemeasure|ensighten|evidon|Ezoic|
fa(cebook|stclick)|feedbackify|fingerprint|foresee|fullstory|funnel|
gdpr|get(drip|pocket)|google|grapeshot|gumgum|gwallet|
hotjar|hubspot|
im(pression|rworldwide)|inte(llitxt|rcom)|
kr(ux|xd)|kochava|
lexity|li(nkedin|strak|veperson)|
ma(iler|rketo|tomo)|me(dia\.net|quoda|tri(cs|x))|ml314|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
olark|omappapi|one(signal|trust)|opt(anon|imize)|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|ypal)|pi(n(gdom|img|terest)|wik)|porpoiseant|prebid|pub(\.network|m(atic|ine))|pushly|
quora|qua(ltrics|nt(cast|serv|um))|
r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|les(force|loft))|sc(ene7|orecard)|se(archiq|edtag|rviceWorker)|slickstream|smartlook|snowplow|sponsor|st(atcounter|umbleupon)|
ta(boola|rgeting)|ti(qcdn|nypass)|track(er|ing)|toutapp|turnto|twitter|typekit|
unruly|
venatus|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rg)|zo(ho|pim)|zqtk)xi

  end
end
