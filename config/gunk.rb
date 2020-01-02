module Webize
  module HTML

    NavGunk = %w{
footer nav sidebar
[class*='cookie']
[class*='foot']
[class*='head']
[class*='nav']
[class*='promo']
[class*='related']
[class*='share']
[class*='side']
[class*='social']
[id*='cookie']
[id*='foot']
[id*='head']
[id*='nav']
[id*='promo']
[id*='related']
[id*='share']
[id*='side']
[id*='social']
}

    SiteGunk = {'www.google.com' => %w(div.logo h1 h2),
                'www.bostonmagazine.com' => %w(a[href*='scrapertrap']),
                'www.theregister.co.uk' => %w(#hot #read_more_on #whitepapers)}

    ScriptGunk = /_0x|analytic|boomr|comscore|criteo|rubicon|tracker|trustx|wpad/i

    ScriptSel = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script"

    SRCnotSRC = %w(
data-baseurl
data-delayed-url
data-hi-res-src
data-img-src
data-lazy-img
data-lazy-src
data-menuimg
data-native-src
data-original
data-raw-src
data-src
image-src
)

  end
end
class WebResource
  module URIs
    GunkURI = %r([-.:_\/?&=~]
((block|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|rotat[eo]r?|slots?|tech|tools?|types?|units?|words?|zones?)?|akismet|alerts?|.*analytics.*|appnexus|audience|(app|smart)?
b(anner|eacon|reakingnew)s?|
c(ampaigns?|edexis|hartbeat.*|loudflare|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)?s?|se)|
de(als|t(ect|roitchicago))|disneyid|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|onitor(ing)?|odal|tr)|
new(relic|sletters?)|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(aywall|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
quantcast|
record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|remote[-_]?(control)?|rpc|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|erv(edby|ice[-_]?worker)|i(ftscience|gnalr|tenotice)|o(cial(shar(e|ing))?|urcepoint)|ponsor(ed)?|tat(istic)?s?|ubscri(ber?|ptions?)|urvey|w.js|yn(c|dicat(ed|ion)))|_static|
t(aboola|(arget|rack)(ers?|ing)|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|ypeface)|autotrack|
u(psell|rchin|ser[-_]?(context|location)|tm)|
viral|
wp-rum|
xiti)
([-.:_\/?&=~]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi
  end
end
