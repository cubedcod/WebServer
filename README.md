get the source:

    mkdir ~/src ; cd ~/src && git clone https://github.com/cubedcod/WebServer && cd WebServer

to run the server, there are some dependencies:

    ./DEPENDENCIES.sh

add bin/ to PATH and run 'session' to launch the frontend proxy / backend webserver pairing

or just the server:

    ~/web unicorn -N -l 127.0.0.1:8000 -l [::1]:8000 -c ../src/WebServer/config/unicorn.rb ../src/WebServer/config/rack.ru
