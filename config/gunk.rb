# coding: utf-8
module Webize
  module HTML

    GunkScript = /_0x[0-9a-f]|google.?(a[dn]|tag)|\.(3gl|bing|bounceexchange|chartbeat|clickability|cloudfront|disqus|doubleclick|ensighten|evidon|facebook|go-mpulse|googleapis|hotjar|krxd|licdn|linkedin|marketo|moatads|newrelic|newsmaxfeednetwork|ntv|outbrain|parsely|petametrics|pressboard|quantserve|quora|revcontent|scorecardresearch|sophi|sumo|taboola|tinypass|tiqcdn|twitter|tynt|visualwebsiteoptimizer|yieldmo|yimg|zergnet|zopim|zqtk)\./i

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

    Scripts = "a[href^='javascript'], a[onclick], link[type='text/javascript'], link[as='script'], script"

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

    # full reformat to local conventions
    def self.clean body, base
      html = Nokogiri::HTML.fragment body

      # strip iframes, stylesheets, and scripts
      html.css('iframe, style, link[rel="stylesheet"], ' + Scripts).remove

      # tag site-nav elements
      [*NavGunk, *SiteGunk[base.host]].map{|selector|
        html.css(selector).map{|node|
          base.env[:site_chrome] ||= true
          node['class'] = 'site'}}

      # map image references
      # CSS:background-image → <img>
      html.css('[style*="background-image"]').map{|node|
        node['style'].match(/url\(['"]*([^\)'"]+)['"]*\)/).yield_self{|url|
          node.add_child "<img src=\"#{url[1]}\">" if url}}
      # <amp-img> → <img>
      html.css('amp-img').map{|amp|amp.add_child "<img src=\"#{amp['src']}\">"}
      # <div> → <img>
      html.css("div[class*='image'][data-src]").map{|div|
        div.add_child "<img src=\"#{div['data-src']}\">"}

      html.traverse{|e| # visit node
        e.attribute_nodes.map{|a| # visit attribute

          # map media references
          e.set_attribute 'src', a.value if SRCnotSRC.member? a.name
          e.set_attribute 'srcset', a.value if %w{data-srcset}.member? a.name

          # strip attrs
          a.unlink if a.name.match?(/^(aria|data|js|[Oo][Nn])|react/) ||
                      %w(bgcolor height http-equiv layout ping role style tabindex target theme width).member?(a.name)}

        # annotate hrefs
        if e['href']
          ref = e['href'].R
          e.add_child " <span class='uri'>#{CGI.escapeHTML e['href'].sub(/^https?:..(www.)?/,'')[0..127]}</span> " # show full(er) URL
          e.set_attribute 'id', 'id' + Digest::SHA2.hexdigest(rand.to_s) unless e['id'] # identify node for traversal
          css = [:uri]; css.push :path if !ref.host || (ref.host == base.host)
          e['href'] = base.join e['href'] unless ref.host              # resolve relative references
          e['class'] = css.join ' '                                    # node CSS-class for styling
        elsif e['id']                                                  # identified node w/ no href
          e.set_attribute 'class', 'identified'                        # node CSS-class for styling
          e.add_child " <a class='idlink' href='##{e['id']}'>##{CGI.escapeHTML e['id']}</span> " # link to identified node
        end

        e['src'] = base.join e['src'] if e['src'] && !e['src'].R.host} # resolve image locations

      html.to_xhtml indent: 0
    end

    def self.degunk body, verbose=true
      doc = Nokogiri::HTML.parse body          # parse body
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove
      doc.css('iframe, img, ' + Scripts).map{|s| # clean body
        if s['src'] && (s['src'].match?(WebResource::URIs::Gunk) || s['src'].R.gunkDomain)
          print "\n🚫 \e[31;7;1m" + s['src'] + "\e[0m " if verbose
          s.remove # script links
        elsif s.inner_text.match? GunkScript
          print "\n🚫 #{s.inner_text.size} \e[31;1m" + s.inner_text.gsub(/[\n\r\t]+/,'').gsub(/\s\s+/,' ')[0..200] + "\e[0m " if verbose
          s.remove # inline scripts
        end}
      doc.to_html                              # write body
    end
  end
end
class WebResource
  module URIs
    Gunk= %r([-.:_\/?&=~'"%\s]
((block|load|page|show)?a(d(vert(i[sz](ement|ing))?)?|ffiliate)s?(bl(oc)?k(er|ing)?.*|frame|id|obe|rotat[eo]r?|slots?|system|tech|tools?|types?|units?|words?|zones?)?|akismet|alerts?|.*analytics?.*|appnexus|audience|(app|smart)?
b(anner|eacon|lueconic|ouncee?x.*|reakingnew)s?|.*bid(d(er|ing)|s).*|
c(ampaigns?|edexis|hartbeat.*|loudfront|mp|ollector|omscore|on(sent|version)|ookie(c(hoice|onsent)|law|notice)?s?|riteo|se)|
de(als|t(ect|roitchicago))|.*dfp.*|dis(neyid|qus)|doubleclick|
e(moji.*\.js|ndscreen|nsighten|proof|scenic|vidon|zoic)|
firebase|(web)?fonts?(awesome)?|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|ima[0-9]?|
impression|indexww|
kr(ux|xd).*|
log(event|g(er|ing))|(app|s)?
m(atomo|e(asurement|t(er|rics?))|ms|onitor(ing)?|odal|tr)|
new(relic|sletters?)|.*notifications?.*|
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
