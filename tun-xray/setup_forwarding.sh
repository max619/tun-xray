#!/bin/sh

set -e

CURRENTDIR=$(dirname $0)
XRAY_CONFIG_FILE=$1
ACTION=$2
FORWARD_FILE=$CURRENTDIR/forward_to.txt

if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ]; then
    echo "Unknown action $ACTION"
    exit 1
fi

IPTABLES_ACTION=-A
if [ "$ACTION" = "down" ]; then
    IPTABLES_ACTION=-D
fi

# $1 action
# $2 target address 
# $3 source and target port
# $4 protocol
setup_forwarding()
{
    iptables -t nat $1 PREROUTING -i eth0 -p $4 -m $4 --dport $3 -j DNAT --to-destination $2:$3
    iptables -t nat $1 POSTROUTING -d $2/32 -p $4 -m $4 --dport $3 -j MASQUERADE
}

if [ "$ACTION" = "up" ]; then
    TARGET_HOST=$(cat $XRAY_CONFIG_FILE | sed -n -E 's/^[[:space:]]*"dest"[[:space:]]*:[[:space:]]*"(.+):.*/\1/p')
    IP_ADDRESS=$(nslookup $TARGET_HOST | grep Address | tail -n 1 | awk '{print $2}')
    echo "$IP_ADDRESS" > $FORWARD_FILE
    echo "Forwarding $TARGET_HOST@$IP_ADDRESS"
else
    if [ ! -f "$FORWARD_FILE" ]; then
        echo "Warning: $FORWARD_FILE not found. Cannot determine IP address to remove forwarding rules."
        echo "This might happen if the 'up' action was never run or the file was deleted."
        exit 1
    fi
    IP_ADDRESS=$(cat $FORWARD_FILE)
    rm $FORWARD_FILE
fi


setup_forwarding $IPTABLES_ACTION $IP_ADDRESS 80 tcp
setup_forwarding $IPTABLES_ACTION $IP_ADDRESS 443 udp