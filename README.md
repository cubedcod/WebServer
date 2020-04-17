get source:

    mkdir ~/src ; cd ~/src && git clone https://github.com/cubedcod/WebServer && cd WebServer

add system and language-library dependencies:

    ./DEPENDENCIES.sh

export PATH=$PATH:$HOME/src/WebServer/bin to run 'session', or manually:

    cd ~/web
    squid -f ~/src/WebServer/config/squid.conf
    unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru
