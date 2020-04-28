this webserver is an [attempt](http://suckless.org/philosophy/) to get us to the Javascript-free future, promised when developers first started overusing JS in the mid-1990s. it is our position that JS may have a place in highly-dynamic visualizations with runtime-tweakability, but in the majority of cases it's being used as a convoluted, hypercomplex loader for static content like text and images.

the server is talked to by the browser in lieu of the origin server which likely assumes you want to run scripts or have a modern browser, which in its default configuration is a privacy disaster instantly and and silently reporting data to third parties as soon as a modern webpage is loaded. we seek to remedy this situation even in scenarios where you're stuck on a desert island with only a modern web-browser incapable of running plugins like uBlock Origin, such as on a mobile OS or in an embedded webview. this is achieved via a transparent-proxy frontend, the venerable [Squid](http://www.squid-cache.org/). the complete setup is therefore a pair of proxies with one handling HTTPS and network-related gruntwork and a highly-configurable backend proxy for content adaptation.

most sites don't support [content-negotiation](https://www.w3.org/DesignIssues/Conneg) for MIME type agility and only supply data in ad-hoc site-specific JSON (plus occasionally Protobuf/HTML/XML) format. in the worst-case scenario, a generic JSON extractor kicks into gear, but since these formats are site-specific, a site-specific way to define extractors is provided. with the data in RDF, it can then be provided in a multitude of formats to clients, such as [Turtle](https://en.wikipedia.org/wiki/Turtle_(syntax)) for your data-browser, perhaps itself built on modern web technologies, but a codebase that you provided, and crucially, that [you control](https://www.gnu.org/philosophy/keep-control-of-your-computing.en.html#content). 

SOURCE

    mkdir ~/src ; cd ~/src && git clone https://github.com/cubedcod/WebServer && cd WebServer

DEPENDENCIES

    ./DEPENDENCIES.sh

USAGE

    export PATH=$PATH:$HOME/src/WebServer/bin && session

alternately:

    cd ~/web
    squid -f ~/src/WebServer/config/squid.conf
    unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru
