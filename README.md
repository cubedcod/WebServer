### INSTALL
``` sh
mkdir ~/src ; cd ~/src
git clone https://gitlab.com/ix/WebServer
cd WebServer && sh bin/deps
cd ruby && bundle install
```
### RUN
``` sh
mkdir ~/web ; cd ~/web
~/src/WebServer/bin/daemon
```
