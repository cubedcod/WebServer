#!/usr/bin/sh
name=WebServer
src=~/src/$name

# INSTALLATION
git clone https://gitlab.com/ix/$name $src
$src/bin/INSTALL

# USAGE
$src/bin/session
