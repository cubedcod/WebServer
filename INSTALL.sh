#!/bin/sh

# Alpine Linux https://www.alpinelinux.org/
which apk && su -c 'apk add alpine-sdk iptables ip6tables graphicsmagick ruby ruby-dev python python3-dev py3-cffi py3-pip openssl-dev rsync libexif-dev libxslt-dev tmux squid'

# Arch Linux https://www.archlinux.org/
which pacman && su -c 'pacman -S graphicsmagick git base-devel ruby ruby-bundler ruby-rdoc python-pip pkg-config tmux squid make rsync'

# Debian https://www.debian.org/
which apt-add-repository && su -c 'apt-get install graphicsmagick git ruby ruby-dev bundler grep file pkg-config libexif-dev libssl-dev libxslt-dev libzip-dev tmux squid make rsync libffi-dev python-pip python-dev'

# Termux https://termux.com/
which pkg && pkg install graphicsmagick git ruby grep file findutils pkg-config libiconv libexif libprotobuf libxslt clang tmux squid make rsync libffi python libcap libcrypt openssl-tool zlib

# Python
pip install --upgrade pip pygments

# Ruby
rm Gemfile.lock
which bundle || gem install bundler
bundle install

# su -c '/usr/lib/squid/security_file_certgen -c -s /var/cache/squid/ssl_db -M 4MB'
# mkdir ~/web
