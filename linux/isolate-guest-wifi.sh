#!/bin/bash

#
# RT-AC52U_B1
# Изолирование гостевой сети в режиме "Режим точки доступа (AP)"
#

brctl delif br0 ra1
brctl addbr br1
brctl addif br1 ra1

ifconfig br1 10.15.0.1 netmask 255.255.255.0
ip link set dev br1 up

cat > /tmp/dnsmasq-guest.conf <<EOF
port=0
bogus-priv
interface=br1
dhcp-range=10.15.0.100,10.15.0.200,1h
dhcp-option=1,255.255.255.0
dhcp-option=2,10800
dhcp-option=3,10.15.0.1
dhcp-option=6,1.1.1.1,8.8.8.8
dhcp-authoritative
log-dhcp
EOF

dnsmasq -C /tmp/dnsmasq-guest.conf

iptables -t nat -A POSTROUTING -s 10.15.0.0/24 -o br0 -j MASQUERADE
iptables -A INPUT -s 10.15.0.0/24 -d 10.15.0.1/32 -p tcp -m multiport --dports 22,80 -j REJECT --reject-with icmp-port-unreachable
echo 1 > /proc/sys/net/ipv4/ip_forward
ip ru add unreachable from 192.168.1.0/24 to 10.15.0.0/24
ip ru add unreachable from 10.15.0.0/24 to 192.168.1.0/24
