#!/bin/sh

open_UDP () {
    iptables  -A INPUT  -p udp --sport $1 -j ACCEPT
    ip6tables -A INPUT  -p udp --sport $1 -j ACCEPT
    iptables  -A INPUT  -p udp --dport $1 -j ACCEPT
    ip6tables -A INPUT  -p udp --dport $1 -j ACCEPT
    iptables  -A OUTPUT -p udp --sport $1 -j ACCEPT
    ip6tables -A OUTPUT -p udp --sport $1 -j ACCEPT
    iptables  -A OUTPUT -p udp --dport $1 -j ACCEPT
    ip6tables -A OUTPUT -p udp --dport $1 -j ACCEPT
}
open_TCP () {
    iptables  -A INPUT  -p tcp --sport $1 -j ACCEPT
    ip6tables -A INPUT  -p tcp --sport $1 -j ACCEPT
    iptables  -A INPUT  -p tcp --dport $1 -j ACCEPT
    ip6tables -A INPUT  -p tcp --dport $1 -j ACCEPT
    iptables  -A OUTPUT -p tcp --sport $1 -j ACCEPT
    ip6tables -A OUTPUT -p tcp --sport $1 -j ACCEPT
    iptables  -A OUTPUT -p tcp --dport $1 -j ACCEPT
    ip6tables -A OUTPUT -p tcp --dport $1 -j ACCEPT
}
open_port () {
    open_UDP $1 $2
    open_TCP $1 $2
}

# default policy
iptables  -P INPUT DROP
ip6tables -P INPUT DROP
iptables  -A INPUT -p icmp -j ACCEPT
ip6tables -A INPUT -p icmp -j ACCEPT
iptables  -A INPUT -i lo   -j ACCEPT
ip6tables -A INPUT -i lo   -j ACCEPT
iptables  -P OUTPUT DROP
ip6tables -P OUTPUT DROP
iptables  -A OUTPUT -p icmp -j ACCEPT
ip6tables -A OUTPUT -p icmp -j ACCEPT
iptables  -A OUTPUT -o lo   -j ACCEPT
ip6tables -A OUTPUT -o lo   -j ACCEPT
iptables -F
iptables -F INPUT
iptables -F OUTPUT

# services
open_TCP     22 SSH
open_port    53 DNS
open_port    67 DHCP
open_port    68 DHCP
iptables  -t nat -A OUTPUT -p tcp --dport  80 -j REDIRECT --to-ports 8081 -m owner ! --uid-owner $1 # redirect HTTP traffic not originating from proxy
ip6tables -t nat -A OUTPUT -p tcp --dport  80 -j REDIRECT --to-ports 8081 -m owner ! --uid-owner $1
iptables  -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 8081 -m owner ! --uid-owner $1
ip6tables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 8081 -m owner ! --uid-owner $1
iptables  -A INPUT  -p tcp --sport 80 -j ACCEPT -m owner --uid-owner $1                             # allow proxy network access
ip6tables -A INPUT  -p tcp --sport 80 -j ACCEPT -m owner --uid-owner $1
iptables  -A INPUT  -p tcp --dport 80 -j ACCEPT -m owner --uid-owner $1
ip6tables -A INPUT  -p tcp --dport 80 -j ACCEPT -m owner --uid-owner $1
iptables  -A OUTPUT -p tcp --sport 80 -j ACCEPT -m owner --uid-owner $1
ip6tables -A OUTPUT -p tcp --sport 80 -j ACCEPT -m owner --uid-owner $1
iptables  -A OUTPUT -p tcp --dport 80 -j ACCEPT -m owner --uid-owner $1
ip6tables -A OUTPUT -p tcp --dport 80 -j ACCEPT -m owner --uid-owner $1
iptables  -A INPUT  -p tcp --sport 443 -j ACCEPT -m owner --uid-owner $1
ip6tables -A INPUT  -p tcp --sport 443 -j ACCEPT -m owner --uid-owner $1
iptables  -A INPUT  -p tcp --dport 443 -j ACCEPT -m owner --uid-owner $1
ip6tables -A INPUT  -p tcp --dport 443 -j ACCEPT -m owner --uid-owner $1
iptables  -A OUTPUT -p tcp --sport 443 -j ACCEPT -m owner --uid-owner $1
ip6tables -A OUTPUT -p tcp --sport 443 -j ACCEPT -m owner --uid-owner $1
iptables  -A OUTPUT -p tcp --dport 443 -j ACCEPT -m owner --uid-owner $1
ip6tables -A OUTPUT -p tcp --dport 443 -j ACCEPT -m owner --uid-owner $1
open_TCP    587 SMTP
open_TCP   8000 HTTP
open_TCP   8080 HTTP
open_TCP   8081 HTTP
open_TCP   9418 Git
open_UDP  60001 Mosh
open_UDP  60002 Mosh
open_UDP  60003 Mosh

iptables -A INPUT -j LOG
iptables -A OUTPUT -j LOG
