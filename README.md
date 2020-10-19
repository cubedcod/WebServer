## INSTALL

    git clone https://gitlab.com/ix/webserver.git

code can be run in checkout dir or moved to your preferred location. to install dependencies (Alpine/Arch/Debian/Termux):

    sh DEPENDENCIES

## USAGE

server launch shortcuts in [bin/](bin/)
client launch shortcuts in [bin/browse](bin/browse/)

launch 'webd' for a common configuration

browser settings:
google (search engine) http://localhost:8000/www.google.com/search?q=%s
[local UI](javascript:location.href='http://localhost:8000/'+location.hostname+location.pathname+'?cookie='+encodeURIComponent(document.cookie)) bookmarklet

## WHAT

fix the web in post-production

## WHY

formative-era browsers often display a blank page in the era of "single-page webapps" while newer browsers execute remote proprietary code or too suffer the [blank-page](https://docs.google.com/presentation/d/120CBI6_gIGqKflXoGp8UMpge1OJ7hfHNNl7JLARUT_o/edit#slide=id.p) problem. default browser configuration - a privacy disaster instantly and silently reporting data to third parties as soon as a page is loaded - is increasingly the only state of affairs due to unavailability of plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on popular mobile and embedded-webview browsers. browsers that aren't privacy messes riddled with spyware eager to just display a blank page would be nice, but if business motives of the large browser vendors - coincidentally the biggest tracking companies themselves - haven't aligned to give the user this basic functionality outside of defaults-modifying plugins at risk of breakage on desktop browsers and unavailable on mobile, it may not be coming. [Palemoon](https://forum.palemoon.org/) has shown that lone-rangers can maintain a fork of a large browser, but this requires individuals of exceptional motivation, of which there are apparently only a few on the planet, and relying on their continued interest is hardly a safe bet.

clients are bad, but servers are too - most don't support [content negotiation](https://www.w3.org/DesignIssues/Conneg) or globally-identified graph data, only offering ad-hoc site-specific HTML/JSON/Protobuf formats, which makes supplying your own interface and browser or configuring cross-site data integrations unecessarily difficult, tossing notions of low/no-code serendipitous mashups & data-reuse to the wayside while begging the user to deal with crafting bespoke integrations involving site-specific APIs involving account registrations and API keys, all glued together by fiddling around writing code even managing to depend on site-specific API-client libraries not in your upstream package manager. nothing says 'browse a webserver's content' like 'do a bunch of tedious stuff including write code involving dependencies not in upstream package manager'. that's considered normal these days  - snowflake APIs demanding special treatment and the vast make-work project of one-off integrations.

## HOW

present a better server to the client via proxy (more readily available than browser plugins or fork maintainers and achievable via URL-rewrite on pre-HTTPS browsers and cert-pinned kiosks). a configuration for [Squid](http://www.squid-cache.org/) is provided to handle HTTPS-related gruntwork and customizable request handlers are spun up as needed. servers are made to ["suck less"](http://suckless.org/philosophy/), bestowed with content-negotiation, data mapped to a standard [RDF graph model](https://www.w3.org/RDF/) available via standard API in a multitude of formats. clients now just need to know [one API, HTTP](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/). "blank-page SPAs" are solved in the site-specific manner of defining a CSS selector and/or regex to fish the "initial state" JSON out of the document or automatically in the case of JSON-LD/Microdata/RDFa in properly-annotated elements. we're obsessed with finding all the data on offer, so in addition to all of the formats already supported by Ruby's excellent RDF libraries, we've added a framework to add additional site-specific extractors and created readers for a variety of non-RDF formats, including Atom feeds and e-mail, employable whether data is on the web, the local filesystem, or RAM.

whether mapping the modern web to static HTML for browsers like [dillo](https://www.dillo.org/)/[elinks](http://elinks.or.cz/)/[eww](https://www.gnu.org/software/emacs/manual/html_mono/eww.html)/[links](http://links.twibright.com/)/[lynx](https://lynx.browser.org/)/[w3m](http://w3m.sourceforge.net/) or requesting [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)) from modern UI such as [Solid-compliant](https://gitter.im/solid/specification) [data browsers](https://github.com/solid/data-kitchen) the interface is user-supplied from a codebase [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content), but since user-freedom and autonomy is paramount, one may opt to run 3rd-party JS even if just to see what happens. in such case cyan entries in the log are often fresh trackingware startups that you didn't know about yet. the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to begin to respond, by never running Javascript again, and reducing, even eliminating, requests that make it out to the net and its proprietary cloud-services that buy and sell your data. if you're deprived of developer tools on a mobile OS, the local proxy egress-MITM mode is a way to have a [shred of a clue](https://github.com/OxfordHCC/tracker-control-android) to what's going on, and control it, via customized site-handlers or simply the domain deny list.

it's your data, and finding what you're looking for should be easy, so content the system has seen is indexed on a timeline and searchable by webizations of [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [glob](https://en.wikipedia.org/wiki/Glob_(programming)) and [grep](https://www.gnu.org/software/grep/manual/grep.html). if you prefer, you can write [SPARQL](https://github.com/ruby-rdf/sparql) as the data-store as automatically populated by the proxy is a URI-space full of graph data. with Turtle files the [offline-first](https://offlinefirst.org/) / [local-first](https://www.inkandswitch.com/local-first.html) source of state, synchronization between devices is handled by underlying fs-distribution tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/)

## WHEN

in theory, this proxy can go away once clients and servers become more standards-compliant in read/write API and formats. in reality, we've now seen the reduction in user agency on mobile and tossing of the browser entirely for mobile apps harking back to the 1980s CompuServe walled-garden, while sexy (implied by the corporate branding campaigns) new technologies on the server are moving us further than ever from the generic browsing ideal with site-specific GRAPHQL queries being sent to servers instead of GET requests, now often via non-HTTP protocols like gRPC lacking mature and ubiquitous proxy tooling, using site-specific binary wire-formats with protobuf definitions as proprietary code unavailable for inspection or 3rd-party client-code generation, and we don't know what the queries are either since theyre just referred to with the shortcut of an opaque hash. Bigplatform thought-leaders are giving proprietary platforms tooling for the inscrutable black-box dumb-terminal model they've loved selling since the 1960s and they're unsurprisingly lapping it up.
