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
p(aywall|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
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
