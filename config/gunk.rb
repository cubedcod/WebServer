# coding: utf-8
class WebResource
  module URIs
    SiteDir  = Pathname.new(__dir__).relative_path_from Pathname.new Dir.pwd

    AllowJS = %w(twitter.com www.instagram.com www.mixcloud.com www.youtube.com)
    AllowGET = %w(www.amazon.com)

    AllowFile = SiteDir.join 'allow_domains' # allow everything - POST, cookies etc
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

    ScriptGunk = %r(
acsb|addtoany|algolia|analytic|aswpsdkus|auction|
bidder|bing|BOOMR|
campaign|chartbeat|chimp|cloudfront|co(mscore|nnatix|okielaw)|criteo|
detroitchicago|disqus|doubleclick|effectivemeasure|ensighten|Ezoic|
facebook\.(com|net)|fullstory|google.?[acst]|gtag|hotjar|
impression|krxd|
marketo|matomo|media\.net|ml314|mpulse|
narrativ\.|newrelic|newsletter|omap[pi]|optanon|outbrain|
paypal|pi(ngdom|wik)|porpoiseant|prebid|pubmatic|quora|
salesloft|scorecard|snowplow|
ta(boola|rgeting)|tiqcdn|track(er|ing)|twitter.com|typekit|
qua(ltrics|nt(cast|serv))|viglink|yandex|zergnet|zoho)xi

  end
end
