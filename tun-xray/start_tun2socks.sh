#!/bin/sh

set -e

# setup tun device
DEV=tun0
TUNIP=192.168.128.1
TUNNET=$TUNIP/32
CURRENTDIR=$(realpath $(dirname $0))

ip tuntap add mode tun user $(id -u) group $(id -g) one_queue dev $DEV
ip addr add $TUNNET dev $DEV
ip link set dev $DEV up

# setup routes
$CURRENTDIR/routes.sh add $TUNIP $DEV

$CURRENTDIR/tun2socks -device $DEV -proxy socks5://127.0.0.1:10808 -interface lo -loglevel error
