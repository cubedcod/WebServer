# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](ads|b0e8|bing|g(aq|tag)|pixel|s(entry|umo)|tawk|utm)[-._\/\(\)'"\s:?&=~%]|
ad(.?bl(ade|ock)|push|r(ecover|oll)|sense|dthis)|amplitude\.com|acsb|addtoany|algolia|analytic|aswpsdk|au(ction|dioeye)|
baidu|bazaarvoice|bidder|BO(OMR|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
campaign|chartbeat|chimp|cl(ick(cea|fu)se|oudfront)|co(mscore|n(fiant|natix)|okie.?(consent|law))|cpx\.|cr(iteo|sspxl|wdcntrl)|cxense|
datadog|detroitchicago|[^a-z]dfp|disqus|dmpxs|dotmetrics|doubleclick\.net|
effectivemeasure|ensighten|evidon|Ezoic|
fa(cebook\.(com|net)|stclick)|fingerprint|foresee|fullstory|funnel|
gdpr|ge(oloc|t(drip|pocket))|google[-._]?(a[dn]|tag|syn)|grapeshot|gumgum|gwallet|
hotjar|hubspot|
im(pression|rworldwide)|in(folink|te(llitxt|rcom))|iubenda|
kr(ux|xd)|kochava|
lexity|li(nkedin|strak|veperson)|
matomo|me(dia\.net|quoda|trics)|ml314|mouseflow|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely))|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|y(pa|wal)l)|pi(n(gdom|img|terest)|wik)|porpoiseant|pr(ebid|omo(s|tion))|pub(\.network|m(atic|ine))|pushly|
quora|qua(l(aroo|trics)|nt(cast|serv|um))|
r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|les(force|loft))|sc(ene7|orecard)|se(archiq|edtag|rv(edby|iceWorker))|shopify|slickstream|smart(asset|look)|snowplow|spo(nsor|t\.im)|st(atcounter|umbleupon)|
ta(boola|rgeting)|ti(qcdn|nypass)|toutapp|turnto|twitter|typekit|
unruly|
venatus|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rgnet)|zopim|zqtk)xi

  end
end
