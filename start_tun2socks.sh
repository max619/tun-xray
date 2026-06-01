#!/bin/sh

# start the tun2socks daemon: create the tun device, hand routing off to
# setup_routing.sh, then run tun2socks. On 'down' the steps are reversed.
CURRENTDIR=$(dirname $0)
ACTION=$1

source $CURRENTDIR/config

# Export the settings setup_routing.sh expects from the environment.
export DEV TUNIP SRC_DEV OUT_DEV OUT_VIA XRAY_CONFIG \
       PROXY_IN_MARK PROXY_IN_TABLE PROXY_OUT_TABLE \
       IPSET_NAME EXTRA_ROUTES_SCRIPT BACKEND NFT_TABLE NFT_SET

run_and_exit_on_fail()
{
   $@
   local ERROR=$?
   if [ $ERROR -ne 0 ]; then
      echo "'$@' failed with exit code $ERROR"
      exit $ERROR
   fi
}

setup_device()
{
    run_and_exit_on_fail ip tuntap add mode tun user $(id -u) group $(id -g) one_queue dev $DEV
    run_and_exit_on_fail ip addr add $TUNNET dev $DEV
    run_and_exit_on_fail ip link set dev $DEV up
}

if [ "$ACTION" == "up" ] || [ "$ACTION" == "" ]; then
    setup_device
    $CURRENTDIR/setup_routing.sh up

    exec $CURRENTDIR/tun2socks -device $DEV -proxy socks5://127.0.0.1:10808 -interface lo -loglevel warn
fi

if [ "$ACTION" == "down" ] || [ "$ACTION" == "" ]; then
    $CURRENTDIR/setup_routing.sh down

    ip tuntap delete mode tun dev $DEV
fi
