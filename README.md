this=WebServer
src=$HOME/src
mkdir $src; cd $src
git clone https://gitlab.com/ix/$this
cd $this/ruby && bundle install
$src/$this/bin/$this
