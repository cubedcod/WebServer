## WHAT / WHY

fix the web in post-production

formative-era browsers incapable of JS often just show a blank page in the era of "single-page webapps" while newer browsers assume execution of remote proprietary-code or they too suffer the "blank page problem". default browser configuration - a privacy disaster instantly and silently reporting data to third parties as soon as a page is loaded (and thereafter via the magic of service-workers) - is increasingly the only state of affairs due to unavailability of plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on most popular mobile and embedded-webview browsers. browsers that aren't privacy messes eager to display a blank page and call it a day would be nice, but if business motives of the large browser vendors - coincidentally the biggest tracking companies themselves - haven't aligned to give the user this basic functionality outside of defaults-modifying plugins at risk of breakage on "desktop" browsers and unavailable on mobile, it may not be coming. [Palemoon](https://forum.palemoon.org/) has shown that lone-rangers can maintain a fork of a large browser which behaves sanely by default, but this requires individuals of exceptional motivation, of which there are apparently only a few on the planet, and relying on their continued interest is hardly a safe bet.

clients are bad, but servers are too - most don't support [content negotiation](https://www.w3.org/DesignIssues/Conneg) of MIME types or supply globally-identified graph data, only offering data in ad-hoc site-specific HTML/JSON/Protobuf formats, making cross-site data integration difficult and practically tossing notions of serendipitous reuse or low/no-code mashups to the wayside and begging the user to deal with crafting bespoke integrations involving site-specific APIs, account registrations, API keys, all glued together by fiddling around writing code even managing to depend on some site-specific API-client libraries not in your upstream package manager. nothing says 'browse a webserver's content' like 'do a bunch of tedious stuff including write some code involving dependencies not in upstream package manager', right? that's considered normal these days.

our approach is presenting a better server to the client and vice-versa via the ubiquitous proxy capability (a feature more readily available than browser plugins or fork maintainers) - [Squid](http://www.squid-cache.org/) frontend handles HTTPS and network-related gruntwork while highly-configurable request handlers are spun up as needed. servers can be made to ["suck less"](http://suckless.org/philosophy/)) - all are now blessed with conneg - and extended further with site-handlers for maybe a bit of token-management for clients that don't support cookies or enabling generic, [Solid-compliant](https://gitter.im/solid/specification) clients by hiding [API requests](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/) behind canonical URLs. the "blank page problem" can often be solved as easily as a CSS selector and/or regex to fish an "initial state" JSON object out of the document on a site-wide or CMS/static-generator-variant basis and is pre-solved globally for the case of JSON-LD in a properly-annotated script element. a variety of common privacy-leaks such as URLs encoded into off-site URLs for the sole basis of activity recording, or scripted dialogs erroneously stating a signup with email-address or phone-number is required can trivially be patched up. the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to begin to respond. if you've been deprived of developer tools on a "mobile" OS it may be the only way to have a shred of a clue to what's going on - for a fun time click the alembic emoji and let it run 3rd-party JS to see what happens. cyan entries in the log are often fresh trackingware startups that you didn't know about yet. on the format front, generic JSON and HTML RDF-izations are defined, but since schema and propertynames are usually site-specific, a site-specific way to define extractor mappings is provided. once data is mapped to the intermediate model it is available to clients in a multitude of formats such as [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)), for your [data browser](https://github.com/solid/data-kitchen), perhaps itself built on modern web technologies, but on a codebase that you provided, and crucially, that [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content).

content given graph-model processing is indexed and cached, the daemon offers search by webizing [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [glob](https://en.wikipedia.org/wiki/Glob_(programming)) and [grep](https://www.gnu.org/software/grep/manual/grep.html). if you prefer, you can use [SPARQL](https://github.com/ruby-rdf/sparql). files are the canonical source of local state and synchronization between instances can be handled by underlying fs tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/). graph-delta notification/syndication is in an experimental testing-ground phase. expect current code to not exist, break, appear in a sibling repo or go away if we find suitable 3rd party tools to delegate this to - solid-websocket, dat-project libraries, ipfs/protocol-labs tools etc. 

in theory, this proxy can go away once clients and servers get better, but in typical situations theyre getting worse - we've seen the reduction in browser flexibility on mobile and tossing of the browser entirely for "mobile apps" harking back to the 1980s CompuServe walled-garden, while "sexy" (according to corporate evangalism campaigns) new technologies on the server are moving us further than ever from the generic browsing ideal with site-specific GRAPHQL queries being sent to servers instead of GET requests, now often via non-HTTP protocols like gRPC lacking mature and ubiquitous proxy tooling, using site-specific binary wire-formats with protobuf definitions as proprietary code unavailable for inspection or 3rd-party client-code generation, and we don't know what the queries are either since theyre just referred to with the shortcut of an opaque hash. Bigtech "thought leaders" are giving proprietary platforms tooling for the the inscrutable black-box dumb-terminal model they've loved selling since the 1960s and they're unsurprisingly lapping it up.

## SOURCE
    cd; mkdir src; cd src
    git clone https://gitlab.com/ix/WebServer

## INSTALL

there is no install step, code can be run from the checkout dir or moved to a library dir of your taste. for alpine/arch/debian/termux deps:

    sh DEPENDENCIES

## USAGE

server

    ./bin/session
    #alternately:
    cd $HOME/web && squid -f ../src/WebServer/config/squid.conf
    unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru

client

    http_proxy=http://localhost:8080 https_proxy=http://localhost:8080 no_proxy=localhost palemoon

advanced scenarios like transparent-proxy require network or SSL configuration. see [bin/](bin/) for sample scripts
