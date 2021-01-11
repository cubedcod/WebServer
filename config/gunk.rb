# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(twitter.com www.instagram.com www.youtube.com)
    AllowGET = %w(www.amazon.com)

    # allow everything - POST, cookies etc
    AllowFile = SiteDir.join 'allow_domains'
    AllowDomains = {}
    AllowFile.each_line{|l|
      cursor = AllowDomains
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
        cursor = cursor[name] ||= {}}}

    DenyFile = SiteDir.join 'deny_domains'
    DenyDomains = {}
    DenyFile.each_line{|l|
      cursor = DenyDomains
      l.chomp.sub(/^\./,'').split('.').reverse.map{|name|
        cursor = cursor[name] ||= {}}}

    Gunk = Regexp.new SiteDir.join('gunk.regex').read.chomp

    ScriptGunk = %r([-._\/'"\s:?&=~%+](ads?|cookie|createElement..script|track(er|ing)?)[-._\/'"\s:?&=~%]|
addtoany|algolia|analytic|aswpsdkus|auction|
bidder|BOOMR|
campaign|chartbeat|cloudfront|criteo|
detroitchicago|doubleclick|effectivemeasure|ensighten|Ezoic|
facebook\.(com|net)|google.?[ast]|gtag|
impression|krxd|marketo|matomo|media\.net|ml314|mpulse|
narrativ\.|newrelic|newsletter|omap[pi]|outbrain|
pi(wik|xel)|porpoiseant|prebid|pubmatic|quora|
salesloft|scorecard|snowplow|
ta(boola|rget[a-z])|tiqcdn|twitter.com|
quant(cast|serv)|viglink|yandex)xi

  end
end
