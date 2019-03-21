# INSTALL
mkdir ~/{src,web} ; cd ~/src
git clone https://gitlab.com/ix/WebServer
cd WebServer && sh bin/deps
cd ruby && bundle install

# RUN
cd ~/web && ../src/WebServer/bin/session
