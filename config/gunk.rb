# coding: utf-8
class WebResource
  module URIs

    Gunk = %r([-.:_\/?&=~'"%\s]
((block|load|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|obe|rotat[eo]r?|slots?|system|tech|tools?|types?|units?|words?|zones?)?|akismet|alerts?|.*analytics?.*|appnexus|audience|(app|smart)?
b(anner|eacon|lueconic|ouncee?x.*)s?|.*bid(d(er|ing)|s).*|
c(ampaigns?|edexis|hartbeat.*|loudfront|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)?s?|riteo|se)|
de(als|t(ect|roitchicago))|.*dfp.*|disney(id)?|doubleclick|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|indexww|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|onitor(ing)?|odal|tr)|
newrelic|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(aywall|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
quantcast|
recaptcha|record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|remote[-_]?(control)?|recirc.*|rpc|rubicon.*|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|erv(edby|ice[-_]?worker)|i(ftscience|gnalr|tenotice)|o(cial(shar(e|ing))?|urcepoint)|ponsor(ed)?|tat(istic)?s?|ubscri(ber?|ptions?)|urvey|w.js|yn(c|dicat(ed|ion)))|
t(aboola.*|(arget|rack)(ers?|ing).*|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|rustx|ype(face|kit))|autotrack|
u(psell|rchin|ser[-_]?(context|location)|tm)|
viral|
wp-?(ad.*|rum)|
xiti|_0x.*|
zerg(net)?)
([-.:_\/?&=~'"%\s]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

  end
end
module Webize
  module HTML

    GunkScript = /_0x[0-9a-f]|google.?(a[dn]|tag)|\.(3gl|amazon.[a-z]+|bing|bounceexchange|chartbeat|clickability|cloudfront|crwdcntrl|doubleclick|ensighten|evidon|facebook|feedbackify|go-mpulse|googleapis|hotjar|indexww|krxd|licdn|linkedin|mar(feel|keto)|moatads|newrelic|newsmaxfeednetwork|npttech|ntv|outbrain|parsely|petametrics|pgmcdn|pinimg|pressboard|quantserve|quora|revcontent|sail-horizon|scorecardresearch|sophi|sumo|taboola|tinypass|tiqcdn|([a-z]+-)?twitter|tynt|visualwebsiteoptimizer|yieldmo|yimg|zergnet|zopim|zqtk)\./i

    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script"

    SiteNav = %w{
footer nav sidebar
[class*='foot']
[class*='head']
[class*='nav']
[class*='related']
[class*='share']
[class*='social']
[id*='foot']
[id*='head']
[id*='nav']
[id*='related']
[id*='share']
[id*='social']
}

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

    def self.degunk body, verbose = true
      doc = Nokogiri::HTML.parse body # parse
      if content_type = doc.css('meta[http-equiv="Content-Type"]')[0]
        if content = content_type['content']
          if charset_tag = content.split(';')[1]
            if charset = charset_tag.split('=')[1]
              doc = Nokogiri::HTML.parse body.force_encoding(charset).encode('UTF-8') # in-band charset tag found. re-read document
            end
          end
        end
      end
      degunkDoc doc, verbose         # degunk
      doc.to_html                    # serialize
    end

    def self.degunkDoc doc, verbose = true
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove
      doc.css('iframe, img, ' + Scripts).map{|s| # clean body
        text = s.inner_text
        if s['src'] && (s['src'].match?(Gunk) || s['src'].R.gunkDomain?)
          print "\n🚫 \e[31;7;1m" + s['src'] + "\e[0m " if verbose
          s.remove # script links
        elsif s['type'] != 'application/ld+json' && text.size < 4096 && text.match?(GunkScript) && !text.match?(/initial.?state/i)
          print "\n🚫 #{text.size} \e[31;1m" + text.gsub(/[\n\r\t]+/,'').gsub(/\s\s+/,' ')[0..200] + "\e[0m " if verbose
          s.remove # inline scripts
        end}
    end

  end
end
