get the source:

    mkdir ~/src ; cd ~/src && git clone https://github.com/cubedcod/WebServer && cd WebServer

install dependencies:

    ./DEPENDENCIES.sh

add bin/ to PATH. 'session' launches proxy (frontend) and daemon (backend), or:

    ~/web squid -f ~/src/WebServer/config/squid.conf
    ~/web unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru
