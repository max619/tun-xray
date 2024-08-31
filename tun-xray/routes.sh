#!/bin/sh

set -e

CMD=$1
TARGET=$2
DEV=$3
CURRENTDIR=$(realpath $(dirname $0))

for item in `cat $CURRENTDIR/iplist.txt`
do
        ip route $CMD $item/32 via $TARGET dev $DEV
done
