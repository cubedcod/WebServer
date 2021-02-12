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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](6sc|acsbapp?|ad(miral|s)|aksb|b0e8|dmpxs|fyre|gaq|kr(ux|xd)|licdn|m(ar(insm|keto)|pulse)|omtrdc|sumo|tawk|turnto|zqtk)[-._\/\(\)'"\s:?&=~%]|
ad.?(bl(ade|ock[a-z]*)|r(ecover|oll)|dthis|s(afeprotected|ense|lot|-twitter)|unit|zone)|alexametrics|am(azon-adsystem|plitude)\.com|analytics|addtoany|algolia|app(dynamics|nexus)|apstag|aswpsdk|audioeye|
bazaarvoice|beacon|bi(d(d(er|ing)|s)|ng\.com)|BO(mbora|OMe?R(ang)?|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
ch(artbeat|impstatic)|cl(arity\.ms|ick(cea|fu )se)|co(mscore\.com|n(fiant|n(atix|ect\.facebook\.net)|versant)|okie.?(bot|consent|law|notice))|cpx\.|cr(i(sp\.chat|teo)|sspxl|wdcntrl)|cxense|
datadog\.com|de(m(andbase|dex)|troitchicago)|dis(qus(cdn)?\.com|trictm)|do(ubleclick|tmetrics)|
effectivemeasure|ensighten|evidon|\.ex\.co|Ezoic|
fa(cebook|stclick)|feedbackify|firebase|foresee\.com|freshchat|fullstory|(function|var)[\s\(]+_0x|
gaug\.es|g[eo]t(chosen|drip|pocket)|google.?[a-z]+|grapeshot|gumgum|
heatmap\.it|hotjar|hs-analytics|hu?bspo?t|
ibclick\.stream|in(folink|te(llitxt|rcom\.(com|io)))|iperceptions|iubenda|
kochava|
lexity\.com|li(strak|veperson)|
ma(r(feel|keting)|tomo|ven\.io)|me(dia\.net|quoda)|ml314|mouseflow|mxpnl|
narrativ\.|new(relic|sletter)|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely\.com))|outbrain|owneriq|
pa(ges(ense|peed)|r(dot|sely)|ypal\.com)|pbjs|pe(r(formance|imeter.?x)|tametrics)|pi(ano\.io|co\.tools|n(gdom|img|terest)|wik)|porpoiseant|prebid|pub(\.network|m(atic|ine))|push(ly|nami)|px-cloud|
quora|qua(l(aroo|trics)|nt(cast|serve?)\.)|
radiateb2b|r-login|revcontent|rightmessage|rlcdn|rubicon|
sa(il.?(horizon|thr[a-z]+)|lesloft\.com)|sc(ene7|(arab|orecard)research)|se(archiq|edtag|gment\.(com|io)|ntry-cdn|rv(edby|ice.?worker)|ssioncam)|shopify|slickstream|smart(asset|look)|snowplow|so(nobi|vrn)|spo(nsor[a-z]*|t.?im)|statcounter|swoop\.com|
ta(boola|rgeting)|tempest|ti(qcdn|nypass)|thinglink|toutapp|[a-z]*tr(ack(cmp|er|ing)[a-z]*|iplelift|ustpilot)|platform.twitter|typekit|
unruly|urbanairship|us(abilla|er.?agent)|
ve(natus|rizon)|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
\.yimg|yotpo|
zergnet|zo(ominfo|pim))xi

  end
end
