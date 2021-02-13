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

    ScriptGunk = %r([-._\/\(\)'"\s:?&=~%](6sc|acsbapp?|ad(miral|s)?|aksb|b0e8|dmpxs|en25|fyre|g(aq|t(ag|m))|kr(ux|xd)|licdn|m(ar(insm|keto)|pulse)|nr-data|o(mtrdc|penx)|paq|s(hare[a-z]*|umo)|t(aw|rac)k[a-z]*|turnto|zqtk)[-._\/\(\)'"\s:?&=~%]|
ad.?(bl(ade|ock[a-z]*)|r(ecover|oll)|dthis|layer|s(afeprotected|ense|lot)|unit|zone)|alexametrics|am(azon[a-z]*|plitude)\.com|analytics|addtoany|algolia|app(dynamics|nexus)|apstag|aswpsdk|au(ction|dioeye)|
bazaarvoice|beacon|bi(d(d(er|ing)|s)[a-z]*|ng\.com)|BO(mbora|OMe?R(ang)?|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
campaign|ch(artbeat|impstatic)|cl(arity\.ms|ick(cea|fu )se)|co(mscore\.com|n(fiant|natix|sent|vers(ant|ion))|okie.?[a-z]*)|cpx\.|cr(i(sp\.chat|teo)|sspxl|wdcntrl)|cxense|
datadog\.com|de(m(andbase|dex)|troitchicago)|dis(qus(cdn)?\.com|trictm)|do(ubleclick|t(metrics|omi))|
effectivemeasure|email|ensighten|evidon|\.ex\.co|Ezoic|
fa(cebook|stclick)|feedbackify|firebase|foresee\.com|freshchat|fullstory|(function|var)[\s\(]+_0x|
gaug\.es|g[eo]t(chosen|drip|pocket)|geo(ip|loc)|google.?[a-z]+|grapeshot|gumgum|
heatmap\.it|hotjar|hs-analytics|htlbid|hu?bspo?t|
ibclick\.stream|impression[a-z]*|in(folink|stagram|te(llitxt|r(com\.(com|io)|stitial)))|iperceptions|iubenda|
kochava|
lexity\.com|li(nkedin|strak|veperson)|
ma(iler[a-z]*|r(feel|keting)|t(htag|omo)|ven\.io)|me(dia\.net|quoda)|ml314|mouseflow|munchkin|mxpnl|
narrativ\.|new(relic|sletter)|noti[cf][a-z]+|npttech|nreum|
olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imizely\.com))|outbrain|owneriq|
pa(ge(s(ense|peed)|.?view)|r(dot|sely)|y[pw]all?)|pbjs|pe(r(formance|imeter.?x|mutive|sonaliz[a-z]*)|tametrics)|pi(ano\.io|co\.tools|n(gdom|img|terest)|wik)|po(rpoiseant|strelease)|prebid[a-z]+|pub(\.network|m(atic|ine))|push(bullet|ly|nami)|px-cloud|
quora|qua(l(aroo|trics)|nt(cast|serve?)\.)|
radiateb2b|r-login|revcontent|rightmessage|rlcdn|rubicon|
sa(il.?(horizon|thr[a-z]+)|lesloft\.com)|sc(ene7|(arab|orecard)research)|se(archiq|edtag|gment\.(com|io)|ntry-cdn|rv(edby|ice.?worker)|ssioncam)|shopify|signup|slickstream|smart(asset|look)|snowplow|so(cial|nobi|vrn)|spo(nsor[a-z]*|t.?im)|statcounter|swoop\.com|
ta(boola|rgeting)|tempest|ti(qcdn|nypass)|thinglink|toutapp|[a-z]*tr(ack(cmp|er|ing)[a-z]*|iplelift|ust(pilot|x))|twitter|typekit|
unruly|urbanairship|us(abilla|er.?agent)|
ve(natus|rizon)|viglink|vuukle|vntsm|
woocommerce|wp.?(emoji|groho|rum)|
\.yimg|yotpo|
zergnet|zo(ominfo|pim))xi

  end
end
