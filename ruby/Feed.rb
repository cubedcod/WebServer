# coding: utf-8
class WebResource
  module URIs

    FeedMIME = /^(application|text)\/(atom|rss|xml)/

    FeedURL = {}
    ConfDir.join('feeds/*.u').R.glob.map{|list|
      list.lines.map{|u| FeedURL[u] = u.R }}

  end

  def self.getFeeds
    FeedURL.values.shuffle.map{|feed|
      begin
        feed.fetch format: 'application/atom+xml', no_response: true
      rescue Exception => e
        puts 'https:' + feed.uri, e.class, e.message
      end}
  end

  module HTTP

    PathGET['/subscribe'] = -> r {
      url = (r.q['u'] || '/').R
      url.subscribe
      [302, {'Location' => url.to_s}, []]}

    PathGET['/unsubscribe']  = -> r {
      url = (r.q['u'] || '/').R
      url.unsubscribe
      [302, {'Location' => url.to_s}, []]}

  end

  module Feed

    include URIs

    def subscribe
      return if subscriptionFile.e
      puts "SUBSCRIBE https:/" + subscriptionFile.dirname
      subscriptionFile.touch
    end

    def subscribed?
      subscriptionFile.exist?
    end
    def subs; puts subscriptions.sort.join ' ' end

    def subscriptions
      subscriptionFile('*').R.glob.map(&:dir).map &:basename
    end

    def unsubscribe
      subscriptionFile.e && subscriptionFile.node.delete
    end

    def renderFeed graph
      HTML.render ['<?xml version="1.0" encoding="utf-8"?>',
                   {_: :feed,xmlns: 'http://www.w3.org/2005/Atom',
                    c: [{_: :id, c: uri},
                        {_: :title, c: uri},
                        {_: :link, rel: :self, href: uri},
                        {_: :updated, c: Time.now.iso8601},
                        graph.map{|u,d|
                          {_: :entry,
                           c: [{_: :id, c: u}, {_: :link, href: u},
                               d[Date].do{|d|   {_: :updated, c: d[0]}},
                               d[Title].do{|t|  {_: :title,   c: t}},
                               d[Creator].do{|c|{_: :author,  c: c[0]}},
                               {_: :content, type: :xhtml,
                                c: {xmlns:"http://www.w3.org/1999/xhtml",
                                    c: d[Content]}}]}}]}]
    end
  end
  include Feed
  module Webize

    def triplrCalendar
      Icalendar::Calendar.parse(File.open localPath).map{|cal|
        cal.events.map{|event|
          subject = event.url || ('#event'+rand.to_s.sha2)
          yield subject, Date, event.dtstart
          yield subject, Title, event.summary
          yield subject, Abstract, CGI.escapeHTML(event.description)
          yield subject, '#geo', event.geo if event.geo
          yield subject, '#location', event.location if event.location
        }}
    end

    def triplrOPML
      # doc
      base = stripDoc
      yield base.uri, Type, (DC+'List').R
      yield base.uri, Title, basename
      # feeds
      Nokogiri::HTML.fragment(readFile).css('outline[type="rss"]').map{|t|
        s = t.attr 'xmlurl'
        yield s, Type, (SIOC+'Feed').R}
    end

  end

end
