# coding: utf-8
class WebResource
  module URIs

    # URI pattern
    Gunk = %r([-._\/'"\s:?&=~%]
((block|load|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|obe|rotat[eo]r?|slots?|system|tech|tools?|types?|units?|words?|zones?)?|ak(am|ismet)|alerts?|.*analytics?.*|appnexus|audience|(app|smart)?
b(lueconic|ouncee?x.*)s?|.*bid(d(er|ing)|s).*|
c(ampaigns?|edexis|hartbeat.*|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)?s?|riteo|se)|
de(als|mandware|t(ect|roitchicago))|dfp|disney(id)?|doubleclick|
e(asylist|moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|Incapsula|indexww|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|odal|pulse|tr)|
newrelic|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(aywall|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
quantcast|
recaptcha|record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|remote[-_]?(control)?|recirc.*|rpc|rubicon.*|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|erv(edby|ice[-_]?worker)|harecount|i(ftscience|gnalr|tenotice)|ponsor(ed)?|tat(istic)?s?|ubscriber?|urvey|w.js|yn(c|dicat(ed|ion)))|
t(aboola.*|(arget|rack)(ers?|ing).*|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|rustx|ype(face|kit))|autotrack|
u(psell|rchin|s(abilla|er[-_]?(context|location))|tm)|
viral|
webtrends|wp-?(ad.*|rum)|
xiti|_0x.*|
zerg(net)?)
([-._\/'"\s:?&=~%]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

    # script pattern
    GunkExec = %r(_0x[0-9a-f]|(\b|[_'"])(
3gl|6sc|
ad(dtoany|nxs)?|.*analytic.*|apptentive.*|auction|
bid(d(er|ing)|s)?|bing|bouncee?x.*|
chartbeat|clickability|cloudfront|COMSCORE|consent|crazyegg|c(rss)?pxl?|crwdcntrl|
doubleclick|d[fm]p|driftt|
ensighten|evidon|facebook|feedbackify|
google.*|g(a|dpr|pt|t(ag|m))|gu-web|gumgum|gwallet|
hotjar|indexww|intercom|ipify|kr(ux|xd)|licdn|linkedin|
mar(feel|keto)|ml314|moatads|mpulse|newrelic|newsmax|npttech|nreum|ntv.io|
olark|outbrain|
parsely|petametrics|pgmcdn|pinimg|pressboard|pushcrew|quantserve|quora|revcontent|
sail-horizon|scorecard.*|segment|snapkit|sophi|sp-prod|ssp|sumo|survicate|
taboola|.*targeting.*|tinypass|tiqcdn|.*track.*|twitter|tynt|
viglink|visualwebsiteoptimizer|wp.?emoji|yieldmo|yimg|zergnet|zopim|zqtk
)(\b|[_'"]))xi

    # script pattern with JSON state data
    InitialState = /(bootstrap|client|global|init(ial)?|preload(ed)?|shared).?(content|data|env|state)|SCRIPTS_LOADED/i
  end
end
module Webize
  module HTML

    # CSS selector for script elements
    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script"

    # alternatives to @src
    SRCnotSRC = %w(
data-baseurl
data-delayed-url
data-hi-res-src
data-image
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
