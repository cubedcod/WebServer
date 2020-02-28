# coding: utf-8
class WebResource
  module URIs

    # URI gunk
    Gunk = %r([-._\/'"\s:?&=~%]
((block|load|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|obe|rotat[eo]r?|slots?|system|tech|tools?|types?|units?|words?|zones?)?|akismet|alerts?|.*analytics?.*|appnexus|audience|(app|smart)?
b(lueconic|ouncee?x.*)s?|.*bid(d(er|ing)|s).*|
c(ampaigns?|edexis|hartbeat.*|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)?s?|riteo|se)|
de(als|mandware|t(ect|roitchicago))|dfp|disney(id)?|doubleclick|
e(asylist|moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|indexww|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|odal|pulse|tr)|
newrelic|.*notifications?.*|
o(m(niture|tr)|nboarding|nesignal|ptanon|utbrain)|
p(aywall|er(imeter-?x|sonali[sz](ation|e))|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ubmatic)|/pv|
quantcast|
recaptcha|record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|remote[-_]?(control)?|recirc.*|rpc|rubicon.*|
s?s(a(fe[-_]?browsing|ilthru)|cheduler|erv(edby|ice[-_]?worker)|i(ftscience|gnalr|tenotice)|ponsor(ed)?|tat(istic)?s?|ubscriber?|urvey|w.js|yn(c|dicat(ed|ion)))|
t(aboola.*|(arget|rack)(ers?|ing).*|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|rustx|ype(face|kit))|autotrack|
u(psell|rchin|s(abilla|er[-_]?(context|location))|tm)|
viral|
wp-?(ad.*|rum)|
xiti|_0x.*|
zerg(net)?)
([-._\/'"\s:?&=~%]|$)|
\.(eot|gif\?|otf|ttf|woff2?))xi

    # executable-code gunk
    GunkExec = %r(_0x[0-9a-f]|[\b_'"](
3gl|6sc|
ad|[a-z]*analytic[a-z]*|auction|
bid(d(er|ing)|s)?|bing|bouncee?x[a-z]*|
chartbeat|clickability|cloudfront|consent|crazyegg|crwdcntrl|
doubleclick|d[fm]p|driftt|
ensighten|evidon|facebook|feedbackify|
ga|gdpr|google.?[a-z]*|g(a|pt|tm)|
hotjar|indexww|intercom|krxd|licdn|linkedin|
mar(feel|keto)|moatads|mpulse|newrelic|newsmax|npttech|nreum|ntv.io|outbrain|
parsely|petametrics|pgmcdn|pinimg|pressboard|quantserve|quora|revcontent|
sail-horizon|scorecard|segment|snapkit|sophi|ssp|sumo|survicate|
taboola|[a-z]*targeting[a-z]*|tinypass|tiqcdn|[a-z]*track[a-z]*|twitter|tynt|
visualwebsiteoptimizer|wp.?emoji|yieldmo|yimg|zergnet|zopim|zqtk
)[\b_'"])xi

  end

  module HTTP

    def gunk?
      return false if (query_values||{})['allow'] == ServerKey
      gunkTag? || gunkURI
    end

    def gunkDomain?
      return false if !host || AllowedHosts.has_key?(host) || HostGET.has_key?(host)
      c = GunkHosts
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf on gunk-domain tree
    end

    def gunkTag?
      return false if AllowedHosts.has_key? host
      env.has_key? 'HTTP_GUNK'
    end

    def gunkURI
      ('/' + host + (env && env['REQUEST_URI'] || path || '/')).match? Gunk
    end

  end

end
module Webize
  module HTML

    # CSS selector for script elements
    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script"

    # CSS selectors for site-navigation elements
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

    # alternatives to the src attribute
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

    # degunk HTML string
    def self.degunk body, verbose = false
      doc = Nokogiri::HTML.parse body # parse
      if content_type = doc.css('meta[http-equiv="Content-Type"]')[0]
        if content = content_type['content']
          if charset_tag = content.split(';')[1]
            if charset = charset_tag.split('=')[1]
              # in-band charset tag found
              unless charset.match? /utf.?8/i
                puts "charset specified in <head> :: #{charset}"
                doc = Nokogiri::HTML.parse body.force_encoding(charset).encode('UTF-8')
              end
            end
          end
        end
      end
      degunkDoc doc, verbose         # degunk
      doc.to_html                    # serialize
    end

    # degunk parsed HTML (nokogiri/nokogumbo) document
    def self.degunkDoc doc, verbose = false
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove
      doc.css("iframe, img, [type='image']," + Scripts).map{|s|
        text = s.inner_text
        if s['src']
          # content pointer
          src = s['src'].R

          if src.uri.match?(Gunk) || (src.gunkDomain? && !src.allowCDN?)
            puts "🚩\e[31;7;1m" + src.uri + "\e[0m " if verbose
            s.remove
          end

        # inline content
        elsif s['type'] != 'application/ld+json' && text.match?(GunkExec) && !text.match?(/(bootstrap|global|init(ial)?|preload(ed)?|shared).?(content|data|state)|SCRIPTS_LOADED|window.app/i)
          puts "🚩#{text.size} \e[30;1m" + text.gsub(/[\n\r\t]+/,'').gsub(/\s\s+/,' ').gsub(GunkExec,"\e[31m\\1\e[30m") + "\e[0m" if verbose
          s.remove
        end}
    end

  end
end
