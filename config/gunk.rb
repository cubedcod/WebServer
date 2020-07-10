# coding: utf-8
class WebResource
  module URIs

    CDNfile = SiteDir.join 'cdn_hosts'

    CDNhosts = {}

    CDNfile.each_line{|l| CDNhosts[l.chomp] = true }

    Gunk = %r([-._\/'"\s:?&=~%](
affiliate(link)?s?|ad((s|unit)|obe)|ak(am|ismet)|.*analytics.*|apester|appnexus|atrk|audience|(app|smart)?
b(lueconic|ouncee?x.*|ugsnag)|.*bid(d(er|ing).*|s)|
c(ampaigns?|edexis|hartbeat.*|mp|ollector|omscore|on(sent|version)|ookie.?(c(hoice|onsent)|law|notice)|riteo|xense)|
de(mandware|t(ect|roitchicago))|dfp|dis(ney(id)?|qus)|doubleclick|
e(moji|nsighten|proof|scenic|vidon|zoic)|
fbcdn.*gif|frosmo|
g(dpr|eo(ip|locat(e|ion))|igya|pt|tag|tm)|.*(
header|pre)[-_]?bid.*|hotjar|.*hubspot.*|[hp]b.?js|
impression|indexww|
keywee|kr(ux|xd).*|
(app|s)?m(a(ilchimp|r(feel|keto)|tomo|utic)|e(asurement|trics?)|ms|pulse|tr)|
newrelic|
o(m(niture|tr)|nesignal|pt(anon|imera)|utbrain)|
p(erimeter-?x|i(wik|xel(propagate)?)|lacement|op(down|over|up)|orpoiseant|owaboot|repopulator|ro(fitwell|m(o(tion)?s?|pt))|ub(exchange|matic))|/pv|
quantcast|
recaptcha|record(event|stats?)|re?t(ar)?ge?t(ing)?|(rich)?relevance|recirc.*|rubicon.*|
s(a(fe[-_]?browsing|ilthru)|erv(edby|ice[-_]?worker)|(har|tag)e(aholic|count|daddy)|i(ftscience|gnalr|tenotice)|ourcepoint|ponsor(ed)?|w.js)|
t(aboola.*|(arget|rack)(ers?|ing).*|ampering|ealium|elemetry|inypass|ra?c?k?ing(data)?|ricorder|rustx|ype(face|kit))|autotrack|
u(rchin|s(abilla|er[-_]?(context|location))|tm)|
web(font|trends)|wp-?(json|rum)|
xiti|_0x.*|
zerg(net)?)
([-._\/'"\s:?&=~%]|$)|
\.(eot|(bmp|gif)\?|otf|ttf|woff2?))xi

    GunkFile = SiteDir.join 'gunk_hosts'

    GunkHosts = {}

    InitialState = /(app|bio|bootstrap|broadcast(er)?|client|global|init(ial)?|meta|page|player|preload(ed)?|shared|site).?(con(fig|tent)|data|env|node|props|st(ate|ore))|app.bundle|environment|hydrat|SCRIPTS_LOADED|__typename/i

    def self.gunkTree verbose=false
      GunkFile.each_line{|l|
        cursor = GunkHosts
        l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
          cursor = cursor[name] ||= (print '🗑️' + l if verbose;
                                     {})}}
      GunkHosts[:mtime] = GunkFile.mtime
    end

    self.gunkTree # read gunkfile
    #URIs.gunkTree true if GunkFile.mtime > GunkHosts[:mtime] # check for gunkfile changes

    def gunk?
      return true if gunkDomain?
      return true if uri.match? Gunk
      false
    end

    def gunkDomain?
      return false if !host ||
                      CDNhosts.has_key?(host) ||
                      WebResource::HTTP::AllowedHosts.has_key?(host) ||
                      WebResource::HTTP::HostGET.has_key?(host)
      c = GunkHosts                                                 # start cursor at root
      host.split('.').reverse.find{|n| c && (c = c[n]) && c.empty?} # find leaf in gunk tree
    end

    def gunkQuery?
      !(query_values||{}).keys.grep(/^utm/).empty?
    end

  end
end
module Webize
  module HTML

    # script pattern
    GunkExec = %r(_0x[0-9a-f]|(\b|[_'"])(
3gl|6sc|
ad(dtoany|nxs)|.*analytic.*|apptentive.*|auction|aswpsdkus|
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

    # clean HTML String
    def self.clean body, base=nil
      doc = Nokogiri::HTML.parse body.encode('UTF-8', undef: :replace, invalid: :replace, replace: ' ') # parse ass Nokogiri doc
      if content_type = doc.css('meta[http-equiv="Content-Type"]')[0] # in-band content-type tag found
        if content = content_type['content']
          if charset_tag = content.split(';')[1]
            if charset = charset_tag.split('=')[1]
              unless charset.match? /utf.?8/i
                doc = Nokogiri::HTML.parse body.force_encoding(charset).encode('UTF-8') # re-read with specified charset
              end
            end
          end
        end
      end
      clean_doc doc, base
      doc.to_html
    end

    # clean HTML Nokogiri
    def self.clean_doc doc, base=nil
      # strip fonts and preload directives
      doc.css("link[href*='font'], link[rel*='preconnect'], link[rel*='prefetch'], link[rel*='preload'], [class*='cookie'], [id*='cookie']").map &:remove

      # inspect resources
      log = []
      doc.css("iframe, img, [type='image'], link, script").map{|s|
        text = s.inner_text     # inline
        if s['type'] != 'application/json' && s['type'] != 'application/ld+json' && !text.match?(InitialState) && text.match?(GunkExec)
          log << "🚩 " + s.to_s.size.to_s + ' ' + (text.match(GunkExec)[2]||'')[0..42]
          s.remove
        end
        %w(href src).map{|attr| # reference
          if s[attr]
            src = s[attr].R
            if src.gunkDomain?
              log << "🚫 \e[31;1;7m" + src.host + "\e[0m"
              s.remove
            elsif src.uri.match? Gunk
              log << "🚫 \e[31;1m" + src.uri + "\e[0m"
              s.remove
            end
          end}}
      puts log.join ' ' unless log.empty?
    end

  end
end
