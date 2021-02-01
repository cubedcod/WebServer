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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](acsbapp?|b0e8|bing|dfp|g(aq|dpr|tag)|kr(ux|xd)|s(entry|umo)|tawk|zqtk)[-._\/\(\)'"\s:?&=~%]|
ad(blade|push|r(ecover|oll)|dthis)|amplitude\.com|addtoany|algolia|aswpsdk|au(ction|dioeye)|
baidu|bazaarvoice|bidder|BO(OMR|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
chartbeat|chimp|cl(ick(cea|fu)se)|co(mscore|n(fiant|natix)|okie.?(consent|law))|cpx\.|cr(iteo|sspxl|wdcntrl)|cxense|
datadog|detroitchicago|disqus|dmpxs|dotmetrics|
effectivemeasure|ensighten|evidon|Ezoic|
fastclick|fingerprint|foresee|fullstory|funnel|
ge(oloc|t(drip|pocket))|google[-._]?(an|tag)|grapeshot|gumgum|gwallet|
hotjar|hubspot|
in(folink|te(llitxt|rcom))|iubenda|
kochava|
lexity|li(strak|veperson)|
matomo|me(dia\.net|quoda)|ml314|mouseflow|mpulse|
narrativ\.|newrelic|newsletter|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely))|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|y(pa|wal)l)|pi(n(gdom|img)|wik)|porpoiseant|pr(ebid|omotion)|pub(\.network|m(atic|ine))|pushly|
quora|qua(l(aroo|trics)|nt(cast|serv|um))|
r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|les(force|loft))|sc(ene7|orecard)|se(archiq|edtag|rvedby)|shopify|slickstream|smart(asset|look)|snowplow|spot\.im|st(atcounter|umbleupon)|
taboola|ti(qcdn|nypass)|toutapp|turnto|typekit|
unruly|
venatus|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rgnet)|zopim)xi

  end
end
