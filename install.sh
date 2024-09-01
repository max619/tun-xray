#!/bin/sh

set -e

XRAY_ARCH=$1
TUN2SOCKS_ARCH=$XRAY_ARCH

if [ "$2" != "" ]; then
   TUN2SOCKS_ARCH=$2
fi;

curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-linux-$XRAY_ARCH.zip
curl -L -o tun2socks.zip https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-$TUN2SOCKS_ARCH.zip 

unzip -o xray.zip -d tun-xray
unzip -o tun2socks.zip -d tun-xray

mv tun-xray/tun2socks-linux-$TUN2SOCKS_ARCH tun-xray/tun2socks
