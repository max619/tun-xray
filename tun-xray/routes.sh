#!/bin/sh

set -e

CMD=$1
TARGET=$2
DEV=$3
CURRENTDIR=$(realpath $(dirname $0))

# can be ip, iptables
MODE=iptables

IPTABLES=$(which iptables)
if [ $? -ne 0 ]; then
    MODE=ip
    echo "No iptables found, fallback to ip"
fi

IP=$(which ip)
if [ $? -ne 0 ]; then
    MODE=
    echo "No ip found"
fi

if ["$MODE" == ""]; then
    echo "Unable to determine mode"
    exit 1
fi



# for ITEM in `cat $CURRENTDIR/iplist.txt`
# do
#   NET=$ITEM
#   if [[ $ITEM != *"/"* ]]; then
#     NET=$NET/32
#   fi
#   ip route $CMD $NET via $TARGET dev $DEV
#   #echo "ip route $CMD $NET via $TARGET dev $DEV"
# done
