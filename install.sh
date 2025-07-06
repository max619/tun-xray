#!/bin/sh

#set -e

XRAY_ARCH=$1
TUN2SOCKS_ARCH=$XRAY_ARCH

if [ "$2" != "" ]; then
   TUN2SOCKS_ARCH=$2
fi;

run_and_exit_on_fail()
{
   $@
   local ERROR=$?
   if [ $ERROR -ne 0 ]; then
      echo "'$@' failed with exit code $ERROR"
      exit $ERROR
   fi
}

run_curl()
{
   local CURL="curl -s -L -f"
   run_and_exit_on_fail $CURL $@
}

download_latest()
{
   local LATEST_VERSION=$(run_curl https://api.github.com/repos/$1/releases/latest | grep tag_name | cut -d : -f 2,3 | tr -d '\", ')
   local URL=https://github.com/$1/releases/download/$LATEST_VERSION/$2
   echo "Downloading $1@$LATEST_VERSION from $URL"
   run_curl -o $3 $URL
}

download_latest XTLS/Xray-core Xray-linux-$XRAY_ARCH.zip xray.zip
download_latest xjasonlyu/tun2socks tun2socks-linux-$TUN2SOCKS_ARCH.zip tun2socks.zip

unzip -o xray.zip -d tun-xray
unzip -o tun2socks.zip -d tun-xray

mv tun-xray/tun2socks-linux-$TUN2SOCKS_ARCH tun-xray/tun2socks