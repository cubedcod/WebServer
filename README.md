this webserver is an [attempt](http://suckless.org/philosophy/) to get us to the Javascript-free future, promised when developers first started overusing JS in the mid-1990s. it is our position that JS may have a place in highly-dynamic visualizations with runtime-tweakability, but in the majority of cases it's being used as a convoluted, hypercomplex loader for static content like text and images.

this server is talked to by the browser in lieu of the origin server which likely assumes you want to run scripts or have a modern browser, which in its default configuration is a privacy disaster instantly and silently reporting data to third parties as soon as a modern webpage is loaded. we seek to remedy this situation even in scenarios where you're stuck on a desert island with only a modern web-browser incapable of running plugins like [uBlock Origin](https://github.com/gorhill/uBlock), such as on a mobile OS or embedded webview. this is achieved via a transparent-proxy frontend, the venerable [Squid](http://www.squid-cache.org/). the complete setup is therefore a pair of proxies with one handling HTTPS and network-related gruntwork and a highly-configurable backend proxy (this project) for content adaptation.

most sites don't support [content-negotiation](https://www.w3.org/DesignIssues/Conneg) for MIME type agility and only supply data in ad-hoc site-specific JSON (plus occasionally Protobuf/HTML/XML) format. in the worst-case scenario, a generic JSON extractor kicks into gear, but since these formats are site-specific, a site-specific way to define extractors is provided. with the data in RDF, it can then be provided in a multitude of formats to clients, such as [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)) for your [data-browser](https://github.com/solid/data-kitchen), perhaps itself built on modern web technologies, but a codebase that you provided, and crucially, that [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content).

content is cached and indexed on a timeline and light search-facilities backed by [find](https://www.gnu.org/software/findutils/manual/html_mono/find.html) and [grep](https://www.gnu.org/software/grep/manual/grep.html) are provided. files are the canonical source of local state and synchronization (personal darknet / mesh) scenarios can be handled by underlying fs tools like [scp](https://github.com/openssh/openssh-portable/blob/master/scp.c), [rsync](https://wiki.archlinux.org/index.php/Rsync), or [syncthing](https://syncthing.net/). higher-level graph-data streaming is in the experimental testing-ground phase. expect current code to not exist, break, or go away if we find suitable 3rd party tools to delegate this to - solid-websocket, dat-project p2p libraries, ipfs/protocol-labs tools etc

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
