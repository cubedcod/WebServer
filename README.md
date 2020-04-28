fix the web in post-production

this is an attempt to bring about a Javascript-free future, promised when developers first started abusing JS soon after its creation. while JS may have a place in highly-dynamic visualizations with runtime-tweakability, in a majority of cases it's used as a convoluted, hypercomplex loader for static content like text and images, along with relentless user-tracking initiatives.

the browser interacts with a proxy server which doesn't expect you to execute remote proprietary-code or even have a modern browser, which in its default configuration is a privacy disaster instantly and silently reporting data to third parties as soon as its first page is loaded (and thereafter via the magic of service-workers). formative-era browsers incapable of JS often just show a blank page in the era of "single-page webapps" while latter browsers are often incapable of running plugins like [uBlock Origin](https://github.com/gorhill/uBlock) on a mobile OS or embedded webview. in the latter case web content may be rewritten at runtime to ["suck less"](http://suckless.org/philosophy/) or in the former case to be visible at all, via transparent-proxy frontended by the venerable [Squid](http://www.squid-cache.org/). the complete setup is a pair of proxies with the performant frontend handling HTTPS and network-related gruntwork while the highly-configurable backend is consulted as needed for content adaptation. the lightweight codebase is designed to "hack the web" as you see fit by extending the server to suit your needs with site-handlers for maybe a bit of token-management for clients that don't support cookies or hiding [API requests](https://ruben.verborgh.org/blog/2013/11/29/the-lie-of-the-api/) behind canonical URLs. the "blank page problem" can often be solved as easily as a CSS selector and/or regex to fish an "initial state" JSON object out of the document on a site-wide or CMS/static-generator-variant basis and is pre-solved globally for the case of JSON-LD in a properly-annotated script element. a variety of common privacy-leaks such as URLs encoded into off-site URLs for the sole basis of activity recording, or scripted dialogs erroneously stating a signup with an email-address or phone-number is required to read the content can trivially be patched up when in many cases. the imagination of the [surveillance economy](https://news.harvard.edu/gazette/story/2019/03/harvard-professor-says-surveillance-capitalism-is-undermining-democracy/) to think up new tricks is seemingly unbounded, and you may find this a useful toolkit to response to their latest ideas, or if you've been deprived of developer-tools on a "mobile OS" it may be the only way to have a shred of a clue to what's going on.

most sites don't support [content-negotiation](https://www.w3.org/DesignIssues/Conneg) of MIME types or RDF and only supply data in ad-hoc site-specific HTML/JSON/Protobuf/XML formats. generic JSON and HTML RDF-izations are defined, but since these formats are site-specific, a site-specific way to define extractors is provided. once data is mapped to the intermediate model it is available to clients in a multitude of formats such as [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)), for your [data browser](https://github.com/solid/data-kitchen), perhaps itself built on modern web technologies, but on a codebase that you provided, and crucially, that [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content).

content is cached and indexed on a timeline and search facilities powered by [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html) and [grep](https://www.gnu.org/software/grep/manual/grep.html) are provided. files are the canonical source of local state and synchronization between instances can be handled by underlying fs tools such as [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync) or [syncthing](https://syncthing.net/). higher-level graph-streaming is in an experimental testing-ground phase. expect current code to not exist, break, or go away if we find suitable 3rd party tools to delegate this to - solid-websocket, dat-project libraries, ipfs/protocol-labs tools etc

## SOURCE
    cd; mkdir src; cd src
    git clone https://gitlab.com/ix/WebServer

## DEPENDENCIES

    ./DEPENDENCIES.sh

## USAGE

    ./bin/session

alternately:

    cd $HOME/web
    squid -f ../src/WebServer/config/squid.conf
    unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru

advanced scenarios like transparent-proxy require network or SSL configuration. see bin/ for further tools
