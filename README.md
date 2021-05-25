## INSTALL

    git clone https://gitlab.com/ix/WebServer.git
    cd WebServer
    ./INSTALL

## USAGE

### SERVERS
``` sh
cd ~/web/ && unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ~/src/WebServer/config/unicorn.rb ~/src/WebServer/config/rack.ru

cd ~/src/WebServer/bin
./ports # optional, enable port 53/80
./dnsd
```
### CLIENTS

shortcuts in [bin/browse](bin/browse/)

[local UI bookmark](javascript:location.href='http://localhost:8000/https://'+location.hostname+location.pathname+'?cookie='+encodeURIComponent(document.cookie))

## WHAT

fix the web in post-production. some suggest we [abandon it](https://drewdevault.com/2020/11/01/What-is-Gemini-anyway.html) - i'm attempting to fix it by presenting a server with the desired capabilities at localhost which makes use of incomplete and semibroken origin servers to facilitate its implementation. this effectively inserts a local cache [into a hierarchy](https://gist.github.com/paniq/bf5b291949be14771344b19a38f042c0) ahead of the global web and facilitates offline scenarios and [automatic archiving](https://beepb00p.xyz/sad-infra.html)

## WHY

formative-era browsers display blank pages in the era of "single-page apps" while newer browsers execute remote code or too suffer the [blank-page](https://docs.google.com/presentation/d/120CBI6_gIGqKflXoGp8UMpge1OJ7hfHNNl7JLARUT_o/edit#slide=id.p) problem. default browser configuration - a privacy disaster instantly and silently reporting data to third parties as soon as a page is loaded - is increasingly the only state of affairs due to unavailability of plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on popular mobile and embedded-webview browsers. browsers that aren't privacy messes riddled with surveillytics eager to display a blank page would be nice, but if business motives of the large browser vendors - coincidentally the biggest surveilllance companies themselves - haven't aligned to give users this basic functionality save for third-party plugins at risk of breakage on desktop browsers and unavailable on mobile, it may not be coming. [Palemoon](https://forum.palemoon.org/) has shown that lone-rangers can maintain a browser fork, but this requires individuals of exceptional motivation of which there are apparently only a few on the planet, and relying on their continued interest is hardly a safe bet.

clients are bad, but servers are too - most don't support [content negotiation](https://www.w3.org/DesignIssues/Conneg) or globally-identified graph data, only offering ad-hoc site-specific HTML/JSON/Protobuf formats, which makes supplying your own interface and browser or configuring cross-site data integrations unecessarily difficult, tossing notions of low/no-code serendipitous mashups & data-reuse to the wayside while begging the user to deal with crafting bespoke integrations involving site-specific APIs including account registrations and API keys, all glued together by fiddling around writing code even managing to depend on site-specific API-client libraries not in your upstream package manager. nothing says 'browse a webserver's content' like 'do a bunch of tedious stuff including write code involving dependencies not in upstream package manager'. that's [considered normal](https://doriantaylor.com/the-symbol-management-problem#:~:text=age%20of%20APIs) these days  - snowflake APIs demanding special treatment and the vast make-work project of one-off integrations.

## HOW

present a better server to the client via proxy (more readily available than browser plugins or fork maintainers and available via URL-rewrite on pre-HTTPS browsers or cert-pinned kiosks). a configuration for [Squid](http://www.squid-cache.org/) is provided as a HTTPS frontend while highly-customizable request handlers are spun up as needed. servers are made [less bad](http://suckless.org/philosophy/), bestowed with content-negotiation, data mapped to a standard [RDF graph model](https://www.w3.org/RDF/) available via standard API in a multitude of formats. clients now need to know just [one API, HTTP](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/). blank-page SPAs are solved in the site-specific manner of defining a CSS selector and/or regex to fish the initial-state JSON out of the document or automatically in the case of JSON-LD/Microdata/RDFa in properly-annotated elements. we're obsessed with finding all the data on offer, so in addition to all the formats enabled by Ruby's RDF library, we've created a framework to add site-specific extractors and readers for a variety of non-RDF formats, including Atom/RSS feeds and e-mail, employable whether data is on the web, the local filesystem, or RAM.

whether mapping the modern web to static HTML for browsers like [dillo](https://www.dillo.org/)/[elinks](http://elinks.or.cz/)/[eww](https://www.gnu.org/software/emacs/manual/html_mono/eww.html)/[links](http://links.twibright.com/)/[lynx](https://lynx.browser.org/)/[w3m](http://w3m.sourceforge.net/) or requesting [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)) from modern UI such as [Solid-compliant](https://gitter.im/solid/specification) [data browsers](https://github.com/solid/data-kitchen), your interface is user-supplied from a codebase [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content). since user freedom and autonomy is paramount, one may opt to run 3rd-party JS even if just to see what happens - in this case cyan entries in the log are often fresh trackingware startups you didn't know about yet. the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to begin to respond, by never running someone else's Javascript again, and reducing, even eliminating, requests that make it out to the net and its proprietary cloud-services that buy and sell your data. when deprived of developer tools and plugins on a mobile OS, transparent-proxy mode is a way to have desktop-grade [visibility](https://github.com/OxfordHCC/tracker-control-android) into what's going on, and control it, via customized site-handlers or simply the domain deny list, all while recording and archiving the data so that it's not trapped in some proprietary app that won't run on the next version of Android or when the VC funding runs out 6 months from now.

## WHERE

it's [your data](https://www.youtube.com/watch?v=-RoINZt-0DQ), and finding what you're looking for should be easy, even if your internet is down or you don't have cloud accounts, so on [localhost](http://localhost/) time-ordered data is made searchable by lightweight and venerable [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [glob](https://en.wikipedia.org/wiki/Glob_(programming)) and [grep](https://www.gnu.org/software/grep/manual/grep.html). for more complicated queries, one can write [SPARQL](https://github.com/ruby-rdf/sparql) as the store comprises a [URI space](https://www.w3.org/DesignIssues/Axioms.html#uri) of RDF graph data. with Turtle files the [offline-first](https://offlinefirst.org/) / [local-first](https://www.inkandswitch.com/local-first.html) source of state, synchronization between devices can be handled by underlying fs-distribution tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/), or at a higher-level by streaming the RDF data to other devices via [CRDTs](https://openengiadina.gitlab.io/dmc/) or [gossip networks](https://github.com/libp2p/specs/blob/master/pubsub/gossipsub/gossipsub-v1.1.md).

## WHEN

in theory, this proxy can go away once clients and servers become more standards-compliant in read/write API and formats. in reality, we've now seen the reduction in user agency on mobile and tossing of the browser entirely for mobile apps harking back to the 1980s CompuServe walled-garden, while sexy (implied by the corporate branding campaigns) new technologies on the server are moving us further than ever from the generic browsing ideal with site-specific GRAPHQL queries being sent to servers instead of GET requests, now often via non-HTTP protocols like gRPC lacking mature and ubiquitous proxy tooling, using site-specific binary wire-formats with protobuf definitions as proprietary code unavailable for inspection or 3rd-party client-code generation, and we don't know what the queries are either since theyre just referred to with the shortcut of an opaque hash. Bigplatform thought-leaders are giving proprietary platforms tooling for the inscrutable black-box dumb-terminal model they've loved selling since the 1960s and they're unsurprisingly lapping it up.
