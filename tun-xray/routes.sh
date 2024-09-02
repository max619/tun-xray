#!/bin/sh

set -e

CMD=$1
TARGET=$2
DEV=$3
CURRENTDIR=$(realpath $(dirname $0))

for ITEM in `cat $CURRENTDIR/iplist.txt`
do
  NET=$ITEM
  if [[ $ITEM != *"/"* ]]; then
    NET=$NET/32
  fi
  ip route $CMD $NET via $TARGET dev $DEV
  #echo "ip route $CMD $NET via $TARGET dev $DEV"
done
