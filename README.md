## INSTALL

until a release is ready, there is no install step, code is run/edited in checkout dir. to install alpine/arch/debian/termux dependencies:

    sh DEPENDENCIES

## USAGE

daemon: script launches daemon, proxy (if needed) and performs any network configuration 

    port443       # HTTPS - apps use default port, transparent proxy configuration
    port8080      # HTTP/HTTPS - explicit proxy configuration
    port80        # HTTP - assumes you have permission to bind port 80. you probably want a variant:
    port80_socat  # HTTP - socat redirect from port 80 to high-port daemon
    port80_setcap # HTTP - SETCAP(8) allows process to bind port 80

client:

      http_proxy=http://localhost:8080 https_proxy=http://localhost:8080 firefox

see [bin/browse](bin/browse/) for more client-launching examples

## WHAT

fix the web in post-production

## WHY

formative-era browsers incapable of JS often just show a blank page in the era of "single-page webapps" while newer browsers execute remote proprietary-code or too suffer the "blank page problem". default browser configuration - a privacy disaster instantly and silently reporting data to third parties as soon as a page is loaded (and thereafter via the magic of service-workers) - is increasingly the only state of affairs due to unavailability of plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on most popular mobile and embedded-webview browsers. browsers that aren't privacy messes or eager to display a blank page and call it a day would be nice, but if business motives of the large browser vendors - coincidentally the biggest tracking companies themselves - haven't aligned to give the user this basic functionality outside of defaults-modifying plugins at risk of breakage on "desktop" browsers and unavailable on mobile, it may not be coming. [Palemoon](https://forum.palemoon.org/) has shown that lone-rangers can maintain a fork of a large browser which behaves sanely by default, but this requires individuals of exceptional motivation, of which there are apparently only a few on the planet, and relying on their continued interest is hardly a safe bet.

clients are bad, but servers are too - most don't support [content negotiation](https://www.w3.org/DesignIssues/Conneg) of MIME types or globally-identified graph data, only offering ad-hoc site-specific HTML/JSON/Protobuf formats, making cross-site data integration difficult and tossing notions of low/no-code mashup serendipitous reuse to the wayside while begging the user to deal with crafting bespoke integrations involving site-specific APIs, account registrations, API keys, all glued together by fiddling around writing code even managing to depend on some site-specific API-client libraries not in your upstream package manager. nothing says 'browse a webserver's content' like 'do a bunch of tedious stuff including write some code involving dependencies not in upstream package manager', right? that's considered normal these days  - snowflake APIs demanding special treatment and the vast make-work project of one-off integrations.

## HOW

present a better server to the client and vice-versa in proxy mode (more readily available than browser plugins or fork maintainers) and URL-rewrite mode for pre-HTTPS browsers or cert-pinned kiosks. a configuration for [Squid](http://www.squid-cache.org/) is provided to handle HTTPS and network-related gruntwork and request handlers are spun up as needed. servers and clients are made to ["suck less"](http://suckless.org/philosophy/)) - both are now blessed with content-negotiation - and extendable further with site handlers. mapping to a generic API and graph formats enables provisioning of user-supplied UI code now that servers appear to have [one true API, HTTP](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/). the "blank page problem" on SinglePageApps is solved in the slightly site-specific manner of defining a CSS selector and regex to fish the "initial state" JSON object out of the document or automatically in the case of JSON-LD in a properly-annotated script element. third-party requests are visibly highlighted in the log - the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to begin to respond. if you've been deprived of developer tools on a "mobile" OS it may be the only way to have a shred of a clue to what's going on - for a fun time click the alembic emoji and let it run 3rd-party JS to see what happens. cyan entries in the log are often fresh trackingware startups that you didn't know about yet.

content is made available in a multitude of formats such as [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)), for your [Solid-compliant](https://gitter.im/solid/specification) [data browser](https://github.com/solid/data-kitchen), from a client codebase [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content). content is searchable via webizations of [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [glob](https://en.wikipedia.org/wiki/Glob_(programming)) and [grep](https://www.gnu.org/software/grep/manual/grep.html). if you prefer, you can use [SPARQL](https://github.com/ruby-rdf/sparql). with files as the canonical source of state, synchronization between instances can be handled by underlying fs tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/). graph-delta notification/syndication is in an experimental testing-ground phase. expect current code to not exist, break, appear in a sibling repo or go away if we find suitable 3rd party tools to delegate this to - solid-websocket, dat-project libraries, ipfs/protocol-labs tools etc. 

## WHEN

now. in theory, this adaptor can go away once clients and servers become more standards-compliant in read/write API and formats. in reality, we've now seen the reduction in user agency on mobile and tossing of the browser entirely for "mobile apps" harking back to the 1980s CompuServe walled-garden, while "sexy" (according to corporate evangalism campaigns) new technologies on the server are moving us further than ever from the generic browsing ideal with site-specific GRAPHQL queries being sent to servers instead of GET requests, now often via non-HTTP protocols like gRPC lacking mature and ubiquitous proxy tooling, using site-specific binary wire-formats with protobuf definitions as proprietary code unavailable for inspection or 3rd-party client-code generation, and we don't know what the queries are either since theyre just referred to with the shortcut of an opaque hash. Bigplatform thought-leaders are giving proprietary platforms tooling for the inscrutable black-box dumb-terminal model they've loved selling since the 1960s and they're unsurprisingly lapping it up.
