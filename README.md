mkdir ~/src
cd ~/src
git clone https://gitlab.com/ix/WebServer
cd WebServer/ruby
bundle install
export PATH=$PATH:$HOME/src/WebServer/bin
pw
