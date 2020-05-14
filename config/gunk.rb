# coding: utf-8
class WebResource
  module URIs

    # URI pattern
    Gunk = %r([-._\/'"\s:?&=~%]
((block|load|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|obe|rotat[eo]r?|slots?|system|tech|tools?|types?|units?|words?|zones?)?|ak(am|ismet)|alerts?|appnexus|audience|(app|smart)?
b(lueconic|ouncee?x.*)s?|.*bid(d(er|ing).*|s)|
c(ampaigns?|edexis|hartbeat.*|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)|riteo|(xen)?se)|
de(als|mandware|t(ect|roitchicago))|dfp|disney(id)?|doubleclick|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|indexww|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(a(rfeel|tomo)|e(asurement|trics?)|ms|pulse|tr)|
newrelic|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(aywall|erimeter-?x|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
quantcast|
record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|recirc.*|rpc|rubicon.*|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|erv(edby|ice[-_]?worker)|harecount|i(ftscience|gnalr|tenotice)|ponsor(ed)?|tats?|ubscriber?|urvey|w.js|yn(dicat(ed|ion)))|
t(aboola.*|(arget|rack)(ers?|ing).*|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|rustx|ype(face|kit))|autotrack|
u(psell|rchin|s(abilla|er[-_]?(context|location))|tm)|
webtrends|wp-?(ad.*|rum)|
xiti|_0x.*|
zerg(net)?)
([-._\/'"\s:?&=~%]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

  end
end
module Webize
  module HTML

    # <script> pattern
    GunkExec = %r(_0x[0-9a-f]|(\b|[_'"])(
3gl|6sc|
ad(dtoany|nxs)?|.*analytic.*|apptentive.*|auction|aswpsdkus|
bid(d(er|ing)|s)?|bing|bouncee?x.*|
cedexis|chartbeat|clickability|cloudfront|COMSCORE|consent|cr(azyegg|iteo)|c(rss)?pxl?|crwdcntrl|
doubleclick|d[fm]p|driftt|
ensighten|evidon|facebook|feedbackify|
g(a|dpr|pt|t(ag|m))|gu-web|gumgum|gwallet|
hotjar|imrworldwide|indexww|intercom|ipify|kr(ux|xd)|licdn|linkedin|
mar(feel|keto)|ml314|moatads|mpulse|newrelic|newsmax|npttech|nreum|ntv.io|
olark|OneSignal|outbrain|
parsely|petametrics|pgmcdn|pinimg|pressboard|pushcrew|quantserve|quora|revcontent|
sail-horizon|scorecard.*|segment|snapkit|sophi|sp-prod|ssp|sumo|survicate|
taboola|.*targeting.*|tinypass|tiqcdn|.*track.*|twitter|tynt|
viglink|visualwebsiteoptimizer|wp.?emoji|yieldmo|yimg|zergnet|zopim|zqtk
)(\b|[_'"]))xi

  end
end
