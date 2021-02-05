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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](6sc|acsbapp?|b0e8|fyre|gaq|kr(ux|xd)|licdn|marketo|sumo|tawk|turnto|zqtk)[-._\/\(\)'"\s:?&=~%]|
ad(blade|r(ecover|oll)|dthis)|alexametrics|am(azon-adsystem|plitude)\.com|addtoany|algolia|aswpsdk|audioeye|
baidu|bazaarvoice|bing\.com|BO(OMe?R(ang)?|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
chartbeat|chimp|cl(ick(cea|fu)se)|co(mscore\.com|n(fiant|n(atix|ect\.facebook))|okie.?(consent|law))|cpx\.|cr(i(sp\.chat|teo)|sspxl|wdcntrl)|cxense|
datadog|de(mdex|troitchicago)|disqus(cdn)?\.com|dmpxs|dotmetrics|
effectivemeasure|ensighten|evidon|Ezoic|
fa(cebook\.com|stclick)|firebase|foresee|fullstory|funnel|
gaug\.es|g[eo]t(chosen|drip|pocket)|google.?(analytics|syndication|tag(manager|services))\.com|grapeshot|gumgum\.com|
hotjar|hs-analytics|hubspot|
in(folink|te(llitxt|rcom))|iubenda|
kochava|
lexity|li(strak|veperson)|
ma(rfeel|tomo)|me(dia\.net|quoda)|ml314|mouseflow|mpulse|
narrativ\.|newrelic|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely))|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|y(pal\.com|wall))|petametrics|pi(co\.tools|n(gdom|img)|wik)|porpoiseant|prebid|pub(\.network|m(atic\.com|ine))|push(ly|nami)|
quora|qua(l(aroo|trics)|nt(cast|serv))|
radiateb2b|r-login|rightmessage|rlcdn|
sa(il.?(horizon|thr)|les(force|loft))|sc(ene7|orecardresearch)|se(archiq|edtag|gment\.(com|io)|ntry-cdn|rvedby|ssioncam)|shopify|slickstream|smart(asset|look)|snowplow|spot\.im|statcounter|
taboola|ti(qcdn|nypass)|toutapp|trustpilot|typekit|
unruly|
venatus|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
yandex|\.yimg|yotpo|
ze(ndesk|rgnet)|zo(ominfo|pim))xi

  end
end
