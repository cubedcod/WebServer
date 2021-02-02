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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](6sc|acsbapp?|b0e8|bing|dfp|fyre|g(aq|dpr)|kr(ux|xd)|sumo|tawk|turnto|zqtk)[-._\/\(\)'"\s:?&=~%]|
ad(blade|push|r(ecover|oll)|dthis)|amplitude\.com|addtoany|algolia|aswpsdk|audioeye|
baidu|bazaarvoice|bidder|BO(OMe?R(ang)?|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
chartbeat|chimp|cl(ick(cea|fu)se)|co(mscore|n(fiant|n(atix|ect\.facebook))|okie.?(consent|law))|cpx\.|cr(i(sp\.chat|teo)|sspxl|wdcntrl)|cxense|
datadog|detroitchicago|disqus|dmpxs|dotmetrics|
effectivemeasure|ensighten|evidon|Ezoic|
fastclick|fi(ngerprint|rebase)|foresee|fullstory|funnel|
gaug\.es|g[eo]t(chosen|drip|pocket)|google.?(analytic|tag)|grapeshot|gumgum|
hotjar|hubspot|
in(folink|te(llitxt|rcom))|iubenda|
kochava|
lexity|li(strak|veperson)|
matomo|me(dia\.net|quoda)|ml314|mouseflow|mpulse|
narrativ\.|newrelic|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely))|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|y(pa|wal)l)|petametrics|pi(n(gdom|img)|wik)|porpoiseant|prebid|pub(\.network|m(atic|ine))|pushly|
quora|qua(l(aroo|trics)|nt(cast|serv))|
r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|les(force|loft))|sc(ene7|orecard)|se(archiq|edtag|gment\.io|rvedby|ssioncam)|shopify|slickstream|smart(asset|look)|snowplow|spot\.im|statcounter|
taboola|ti(qcdn|nypass)|toutapp|typekit|
unruly|
venatus|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rgnet)|zopim)xi

  end
end
