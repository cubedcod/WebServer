# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    FileModified = {allow: 0,
                    deny: 0}

    AllowFile = SiteDir.join 'allow_domains'
    AllowDomains = {}

    DenyFile = SiteDir.join 'deny_domains'
    DenyDomains = {}

    def self.allowlist
      ts = AllowFile.mtime.to_i
      return unless ts > FileModified[:allow]
      FileModified[:allow] = ts
      AllowFile.each_line{|l|
        cursor = AllowDomains
        l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
          cursor = cursor[name] ||= {}}}
    end
    self.allowlist

    def self.denylist
      ts = DenyFile.mtime.to_i
      return unless ts > FileModified[:deny]
      FileModified[:deny] = ts
      DenyFile.each_line{|l|
        cursor = DenyDomains
        l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
          cursor = cursor[name] ||= {}}}
    end
    self.denylist

    Gunk = Regexp.new SiteDir.join('gunk.regex').read.chomp, Regexp::IGNORECASE

    ScriptGunk = %r([-._\/\(\)\\{}'"\s:?&=~%](6sc|acsbapp?|ad(miral|s|vance)?|affirm|aksb|apple|atrk|b(0e8|eop)|d([fm]p(xs)?)|en25|fyre|g(aq|eo|igya|t(ag|m))|kr(ux|xd)|licdn|m(ar(insm|keto)|pulse)|n(r-data|tv)|o(mtrdc|penx)|p(aq|ixel)|(app|grow|king)?sumo|t(aw|rac)k[a-z]*|t(urnto|ynt)|utm|xtlo|zqtk)[-._\/\(\)\\{}'"\s:?&=~%]|
ad.?(bl(ade|ock[a-z]*)|r(ecover|oll)|dthis|(lay|mix)er|push|s(afeprotected|ense|lot)|unit|vert|z(erk|one))|alexametrics|am(azon[a-z]*|plitude)\.com|addtoany|algolia|app(dynamics|nexus)|apstag|aswpsdk|au(ction|di(ence[a-z]*|oeye))|
ba(idu|nner|zaarvoice)|bdstatic|beacon|bi(d(d(er|ing)|s)[a-z]*|ng\.com)|blackbaud|BO(mbora|OMe?R(ang)?|uncee?x)|browser.?update|btncdn|bu(gherd|zzfeed)|
ca(mpaign|rambo)|ch(artbeat|impstatic)|cl(arity\.ms|ick(cea|fu)se|oudfront)|co(mscore\.com|n(fiant|natix|sent|versant)|okie.?[a-z]*)|cpx\.|cr(azyegg|i(sp\.chat|teo)|sspxl|wdcntrl)|cxense|
datado(g|me)\.co|de(m(andbase|dex)|troitchicago)|di(ffuser|s(qus|trictm))|do(ubleclick|t(metrics|omi))|dpmsrv|
effectivemeasure|email|ensighten|evidon|\.ex\.co|extreme-dm|Ezoic|
fa(cebook|stclick)|feedbackify|firebase|fo(nt|resee\.com)|freshchat|fullstory|(function|var)[\s\(]+_0x|
gaug\.es|gdpr|g[eo]t(chosen|drip|pocket)|geo(ip|loc)|\.gif\?|google|grapeshot|gumgum|
heatmap\.it|hotjar|hs-analytics|htlbid|hu?bspo?t|
ibclick\.stream|imp(actradius|ression[a-z]*)|in(dex(exchange|ww)|folink|stagram|te(llitxt|r(com\.(com|io)|stitial)))|iperceptions|iubenda|
kochava|
le(aderboard|xity\.com)|li(nkedin|strak|veperson)|lockerdome|lytics|
ma(iler[a-z]*|r(feel|keting)|t(htag|omo)|ven\.io)|me(dia\.net|quoda|trics)|ml314|mouseflow|munchkin|mxpnl|
narrativ\.|new(relic|sletter)|npttech|nreum|
oktopost|olark|omappapi|one(signal|trust)|online-metrix|op(t?n?mn?str|t(anon|imize))|outbrain|owneriq|
pa(ge(s(ense|peed)|.?view)|r(dot|sely|tner)|y[pw]all?)|pbjs|pe(r(imeter.?x|mutive|sonaliz[a-z]*)|tametrics)|pi(ano\.io|co\.tools|n(gdom|img|terest)|wik)|po(rpoiseant|strelease)|pr(e(bid[a-z]+|ssboard)|ivacy-center|ofitwell)|pub(ads|exchange|\.network|m(atic|ine))|pu(rechat|sh(bullet|ly|nami))|px-cloud|
quora|qua(l(aroo|trics)|nt(cast|serve?)\.)|
radiateb2b|r-login|rev(boost|content)|rightmessage|rlcdn|rollbar|rubicon|
sa(il.?(horizon|thr[a-z]+)|lesloft\.com)|sc(ene7|(arab|orecard)research)|se(archiq|edtag|gment\.(com|io)|ntry-cdn|rv(edby|ice.?worker)|ssioncam)|sh(arethis|opify)|si(ftscience|gnup)|slickstream|smart(asset|look)|snowplow|so(cial|nobi|vrn)|spo(nsor[a-z]*|t.?im)|st(atcounter|umbleupon)|swoop\.com|synacor[a-z]*|
ta(boola|rgeting)|te(mpest|rmly)|ti(dio|qcdn|nypass)|thinglink|toutapp|[a-z]*tr(ack(cmp|er|ing)[a-z]*|iplelift|ust(pilot|x))|twitter|typekit|
unruly|urbanairship|usabilla|
ve(natus|rizon)|vi(glink|sitorid)|vuukle|vntsm|
widget|wo(ocommerce|rdfence)|wp.?(emoji|groho|rum)|
\.yimg|y(adro|otpo)|
ze(ndesk|rgnet)|zo(ominfo|pim))xi

  end
end
