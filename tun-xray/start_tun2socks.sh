#!/bin/sh

# setup tun device
DEV=tun0
OUT_DEV=eth1
SRC_DEV=br-lan
TUNIP=192.168.128.1
TUNNET=$TUNIP/32
CURRENTDIR=$(dirname $0)
ACTION=$1
IPSET_NAME=XRAY_IPSET
XRAY_CONFIG=xray_config.json
PROXY_IN_MARK=777
PROXY_IN_TABLE=134
PROXY_OUT_TABLE=135
EXTRA_ROUTES_SCRIPT=$CURRENTDIR/extra_routes.sh

if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ] && [ "$ACTION" != "" ]; then
    echo "Unknown action $ACTION"
    exit 1
fi

IPTABLES_FOUND=1
IPTABLES=$(which iptables)
if [ $? -ne 0 ]; then
    IPTABLES_FOUND=0
    echo "No iptables found"
fi

IPSET_FOUND=1
IPSET=$(which ipset)
if [ $? -ne 0 ]; then
    IPSET_FOUND=0
    echo "No ipset found"
fi

IP_FOUND=1
IP=$(which ip)
if [ $? -ne 0 ]; then
    IP_FOUND=0
    echo "No ip found"
fi

if [ $IP_FOUND -eq 0 ]; then
    echo "ip is required"
    exit 1
fi

run_and_exit_on_fail()
{
   $@
   local ERROR=$?
   if [ $ERROR -ne 0 ]; then
      echo "'$@' failed with exit code $ERROR"
      exit $ERROR
   fi
}

add_routes()
{
    local IP_LIST_PATH=$CURRENTDIR/iplist.txt
    if [ -f "$IP_LIST_PATH" ]; then
        for ITEM in `cat $IP_LIST_PATH`
        do
            local NET=$ITEM
            if [[ $ITEM != *"/"* ]]; then
                NET=$NET/32
            fi

            $1 $NET
        done
    else
        echo "No ip list provided $IP_LIST_PATH"
    fi
}

add_route_ip()
{
    run_and_exit_on_fail $IP route add $1 via $TUNIP dev $DEV
}

add_route_ipset()
{
    run_and_exit_on_fail $IPSET add $IPSET_NAME $1
}

setup_drop_routes_ipset()
{
    local IPTABLES_CMD=$1
    local IP_CMD=$2

    # Setup marking for an ip set
    $IPTABLES -t mangle $IPTABLES_CMD PREROUTING -i $SRC_DEV -m set --match-set $IPSET_NAME dst -p tcp -m multiport --dports 443,80,8080  -j MARK --set-mark $PROXY_IN_MARK/$PROXY_IN_MARK
    $IPTABLES -t mangle $IPTABLES_CMD PREROUTING -i $SRC_DEV -m set --match-set $IPSET_NAME dst -p udp --dport 443  -j MARK --set-mark $PROXY_IN_MARK/$PROXY_IN_MARK
    
    # Allow forwarding to an from tun
    local FORWARD_CMD=$IPTABLES_CMD
    if [ "$FORWARD_CMD" == "-A" ]; then
        FORWARD_CMD=-I
    fi

    $IPTABLES $FORWARD_CMD FORWARD -i $SRC_DEV -o $DEV -j ACCEPT

    $IP route $IP_CMD default via $TUNIP dev $DEV table $PROXY_IN_TABLE
    $IP rule $IP_CMD fwmark $PROXY_IN_MARK table $PROXY_IN_TABLE priority 1000
    
    $IP route $IP_CMD default dev $OUT_DEV table $PROXY_OUT_TABLE
    for ITEM in `cat $CURRENTDIR/$XRAY_CONFIG | grep mark | cut -d : -f 2,3 | uniq`
    do
        $IP rule $IP_CMD fwmark $ITEM table $PROXY_OUT_TABLE  priority 1001
    done
}

setup_drop_extra_routes()
{
    if [ -f "$EXTRA_ROUTES_SCRIPT" ]; then
        echo "Setting up extra routes"
        $EXTRA_ROUTES_SCRIPT $1 $DEV $PROXY_IN_MARK
    else
        echo "No extra routes script provided"
    fi
}

setup_routes_ipset()
{
    $IPSET create $IPSET_NAME hash:ip hashsize 16384 maxelem 1000000
    add_routes add_route_ipset

    setup_drop_routes_ipset -A add
}

setup_routes_ip()
{
    add_routes add_route_ip
}

setup_routes()
{
    if [ $IPSET_FOUND -eq 1 ] && [ $IPTABLES_FOUND -eq 1 ]; then
        echo "Setting up routing with ipset..."
        setup_routes_ipset
    else
        echo "Setting up routing with ip..."
        setup_routes_ip
    fi

    setup_drop_extra_routes up

    echo "Done"
}

setup_device()
{
    run_and_exit_on_fail ip tuntap add mode tun user $(id -u) group $(id -g) one_queue dev $DEV
    run_and_exit_on_fail ip addr add $TUNNET dev $DEV
    run_and_exit_on_fail ip link set dev $DEV up
}

run_up()
{
    setup_device
    setup_routes

    exec $CURRENTDIR/tun2socks -device $DEV -proxy socks5://127.0.0.1:10808 -interface lo -loglevel warn
}

run_down()
{
    ip tuntap delete mode tun dev $DEV

    if [ $IPSET_FOUND -eq 1 ] && [ $IPTABLES_FOUND -eq 1 ]; then
        setup_drop_routes_ipset -D del

        # $IPSET destroy $IPSET_NAME
    fi

    setup_drop_extra_routes down
}

if [ "$ACTION" == "up" ] || [ "$ACTION" == "" ]; then
    run_up
fi

if [ "$ACTION" == "down" ] || [ "$ACTION" == "" ]; then
    run_down
fi