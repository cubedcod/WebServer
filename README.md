## INSTALL

code is run/edited in checkout dir. for alpine+arch+debian+termux dependencies:

    sh DEPENDENCIES

## USAGE

daemon launch shortcuts in [bin/](bin/)

    port443       # listen on default HTTPS port, configure transparent proxy, gateway, DNS options to taste
    port8080      # default HTTP/HTTPS forward-proxy port
    port80        # classic port 80 HTTP - assumes you have bind permissions. you probably want a variant:
    port80_socat  # HTTP - socat redirect to high-port daemon
    port80_setcap # HTTP - SETCAP(8) allows process to bind port 80

client launch shortcuts in [bin/browse](bin/browse/)

email 'inbox'. today's messages (bookmark)
 http://localhost:8000/d?f=msg*

google w/ local UI (search engine)
 http://localhost:8000/www.google.com/search?q=%s

jump to local UI from upstream UI (bookmarklet)
 javascript:location.href='http://localhost:8000/'+location.href+'?cookie='+document.cookie


## WHAT

fix the web in post-production

## WHY

formative-era browsers incapable of JS often just show a blank page in the era of "single-page webapps" while newer browsers execute remote code or too suffer the [empty page](https://docs.google.com/presentation/d/120CBI6_gIGqKflXoGp8UMpge1OJ7hfHNNl7JLARUT_o/edit#slide=id.p) problem. default browser configuration - a privacy disaster instantly and silently reporting data to third parties as soon as a page is loaded is increasingly the only state of affairs due to unavailability of plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on most popular mobile and embedded-webview browsers. browsers that aren't privacy messes or eager to display a blank page and call it a day would be nice, but if business motives of the large browser vendors - coincidentally the biggest tracking companies themselves - haven't aligned to give the user this basic functionality outside of defaults-modifying plugins at risk of breakage on "desktop" browsers and unavailable on mobile, it may not be coming. [Palemoon](https://forum.palemoon.org/) has shown that lone-rangers can maintain a fork of a large browser which behaves sanely by default, but this requires individuals of exceptional motivation, of which there are apparently only a few on the planet, and relying on their continued interest is hardly a safe bet.

clients are bad, but servers are too - most don't support [content negotiation](https://www.w3.org/DesignIssues/Conneg) or globally-identified graph data, only offering ad-hoc site-specific HTML/JSON/Protobuf formats, which makes supplying your own interface and even browsers or configuring cross-site data integrations unecessarily difficult, tossing notions of low/no-code serendipitous mashups & data-reuse to the wayside while begging the user to deal with crafting bespoke integrations involving site-specific APIs involving account registrations and API keys, all glued together by fiddling around writing code even managing to depend on site-specific API-client libraries not in your upstream package manager. nothing says 'browse a webserver's content' like 'do a bunch of tedious stuff including write code involving dependencies not in upstream package manager'. that's considered normal these days  - snowflake APIs demanding special treatment and the vast make-work project of one-off integrations.

## HOW

present a better server to the client via proxy (more readily available than browser plugins or fork maintainers and achievable via URL-rewrite compatible back to pre-HTTPS browsers or cert-pinned kiosks). a configuration for [Squid](http://www.squid-cache.org/) is provided to handle HTTPS and network-related gruntwork and customizable request handlers are spun up as needed. servers are made to ["suck less"](http://suckless.org/philosophy/), now bestowed with content-negotiation, their data now available via a standard API in a multitude of formats. clients now just need to know [one API, HTTP](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/). the "blank page problem" on SinglePageApps is solved in the slightly site-specific manner of defining a CSS selector and regex to fish the "initial state" JSON object out of the document or automatically in the case of JSON-LD in a properly-annotated script element. third-party requests are visibly highlighted in the log - the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to begin to respond, by never running Javascript again. if you've been deprived of developer tools on a "mobile" OS, the local server in egress-MITM mode is a way to have a [shred of a clue](https://github.com/OxfordHCC/tracker-control-android) to what's going on, and control it - for a fun time click the alembic emoji to let it run 3rd-party JS to see what happens. cyan entries in the log are often fresh trackingware startups that you didn't know about yet.

aside from a HTML interface for dillo/elinks/links/lynx/w3m browsers, graph-formats like [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)) provide for your user-supplied UI such as a [Solid-compliant](https://gitter.im/solid/specification) [data browser](https://github.com/solid/data-kitchen) or other codebases [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content). content that has been seen at the proxy is indexed on a timeline and searchable on the web, powered by [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [glob](https://en.wikipedia.org/wiki/Glob_(programming)) and [grep](https://www.gnu.org/software/grep/manual/grep.html). if you prefer, you can write [SPARQL](https://github.com/ruby-rdf/sparql) as the data-store is a URI-space full of RDF. with files the [offline-first](https://offlinefirst.org/) / [local-first](https://www.inkandswitch.com/local-first.html) source of state, synchronization between instances can be handled by underlying fs tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/). web-native graph-delta notification/syndication is in an experimental testing-ground phase - expect current code to not exist, break, appear in a sibling repo or go away as we find suitable 3rd party tools to delegate this to from the solid-websocket, ipfs/protocol-labs and datproject/hypercore  camps. 

## WHEN

in theory, this proxy can go away once clients and servers become more standards-compliant in read/write API and formats. in reality, we've now seen the reduction in user agency on mobile and tossing of the browser entirely for "mobile apps" harking back to the 1980s CompuServe walled-garden, while sexy (implied by the corporate branding campaigns) new technologies on the server are moving us further than ever from the generic browsing ideal with site-specific GRAPHQL queries being sent to servers instead of GET requests, now often via non-HTTP protocols like gRPC lacking mature and ubiquitous proxy tooling, using site-specific binary wire-formats with protobuf definitions as proprietary code unavailable for inspection or 3rd-party client-code generation, and we don't know what the queries are either since theyre just referred to with the shortcut of an opaque hash. Bigplatform thought-leaders are giving proprietary platforms tooling for the inscrutable black-box dumb-terminal model they've loved selling since the 1960s and they're unsurprisingly lapping it up.
