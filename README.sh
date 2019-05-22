#!/bin/sh
name=WebServer
src=~/src/$name
[ -e $src ] || git clone https://gitlab.com/ix/$name $src
$src/bin/INSTALL
