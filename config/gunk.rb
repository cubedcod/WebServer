class WebResource
  module URIs

    Gunk = %r([-.:_\/?&=~]
((block|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|id|rotat[eo]r?|slots?|tools?|types?|units?|words?)?|.*analytics.*|appnexus|audience|(app)?
b(anner|eacon|reakingnew)s?|
c(ampaign|edexis|hartbeat.*|ollector|omscore|onversion|ookie(c(hoice|onsent)|law|notice)?s?|se)|
de(als|tect)|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon)|
(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*
(header|pre)[-_]?bid.*|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|
kr(ux|xd).*|
log(event|g(er|ing))?|(app|s)?
m(e(asurement|t(er|rics?))|ms|odal|tr)|
new(relic|sletters?)|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(a(idpost|rtner|ywall)|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|repopulator|romo(tion)?s?|ubmatic|[vx])|
quantcast|
record(event|stats?)|re?t(ar)?ge?t(ing)?|remote[-_]?(control)?|rpc|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|ervice[-_]?worker|i(ftscience|gnalr|tenotice)|o(cial(shar(e|ing))?|urcepoint)|ponsor(ed)?|so|tat(istic)?s?|ubscri(ber?|ptions?)|urvey|w.js|yn(c|dicat(ed|ion)))|
t(aboola|(arget|rack)(ers?|ing)|ampering|bproxy|ea(lium|ser)|elemetry|hirdparty|inypass|rack?ing(data)?|rend(ing|s)|ypeface)|autotrack|
u(rchin|ser[-_]?(context|location)|tm)|
viral|
wp-rum)
([-.:_\/?&=~]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

    QuietGunk = %w(
activeview activity-stream addthis_widget.js admin-ajax.php ads ad_status.js all.js analytics.js annotations_invideo api.js apstag.js arwing atrk.js attribution avatar
 b.gif bat.js beacon.js blank.gif bullseye buttons.js bz
 c.gif cast_sender.js chartbeat.js collect conv collector config.js core.js count.js counter.js count.json css crx
 download downloads ddljson embed.js embeds.js endscreen.js event.gif events experimentstatus
 falco favicon.ico fbds.js fbevents.js FeedQuery fonts fullHashes:find
 g.gif id inflowcomponent get_endscreen get_midroll_info gpt.js gtm.js icon ima3.js i.js in.js
 jot js json like.php ListAccounts load load.js loader.js log log_event logging_client_events lvz
 m newtab_ogb newtab_promos onejs op.js outbrain.js
 p p.js page_view pay ping ping.gif ping-centre pinit.js platform.js pixel pixel.gif pixel.js pixelpropagate.js ptracking push_service_worker.js pv px.gif px.js
 qoe quant.js query remote.js remote-login.php rtm rundown
 scheduler.js script.js search seed ServiceLogin serviceworker service-worker.js sdk.js service_ajax session sso sw.js sync
 threatListUpdates:fetch tag.js tr track tracker trends uc.js utag.js v3 view w.js widgets.js yql)

  end
end
