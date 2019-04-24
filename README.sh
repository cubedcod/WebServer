#!/usr/bin/sh
name=WebServer

# INSTALLATION
git clone https://gitlab.com/ix/$name ~/src
~/src/$name/bin/INSTALL

# USAGE
~/src/$name/bin/session
