class WebResource
  module URIs

    Gunk = %r([-.:_\/?&=~]
((block|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|id|rotat[eo]r?|slots?|tech|tools?|types?|units?|words?)?|alerts?|.*analytics.*|appnexus|audience|(app)?
b(anner|eacon|reakingnew)s?|
c(ampaign|edexis|hartbeat.*|loudflare|ollector|omscore|onversion|ookie(c(hoice|onsent)|law|notice)?s?|se)|
de(als|tect)|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon)|(web)?
fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|
jquery|
kr(ux|xd).*|
log(event|g(er|ing))?|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|onitor(ing)?|odal|tr)|
new(relic|sletters?)|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(a(idpost|rtner|ywall)|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic|[vx])|
quantcast|
record(event|stats?)|re?t(ar)?ge?t(ing)?|remote[-_]?(control)?|rpc|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|ervice[-_]?worker|i(ftscience|gnalr|tenotice)|o(cial(shar(e|ing))?|urcepoint)|ponsor(ed)?|tat(istic)?s?|ubscri(ber?|ptions?)|urvey|w.js|yn(c|dicat(ed|ion)))|
t(aboola|(arget|rack)(ers?|ing)|ampering|bproxy|ea(lium|ser)|elemetry|hirdparty|inypass|rack?ing(data)?|rend(ing|s)|ypeface)|autotrack|
u(rchin|ser[-_]?(context|location)|tm)|
viral|
wp-rum)
([-.:_\/?&=~]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

  end
end
