#!/bin/sh

# setup routing for an already-configured tun device
# (supports nftables OR iptables+ipset, with a plain-ip fallback)
#
# The tun device itself is created/destroyed by the caller (start_tun2socks.sh);
# this script assumes $DEV already exists.
#
# Settings are read from the environment (not from config) so this
# script is independent of the tun2socks daemon. The caller is responsible for
# exporting the variables below; required ones are validated up front.
#
# Required: DEV TUNIP SRC_DEV OUT_DEV XRAY_CONFIG
#           PROXY_IN_MARK PROXY_IN_TABLE PROXY_OUT_TABLE
# Optional: OUT_VIA EXTRA_ROUTES_SCRIPT BACKEND NFT_TABLE NFT_SET
#           IPSET_NAME (required for the ipset backend)
CURRENTDIR=$(dirname $0)
ACTION=$1

# nft table/set names. Defaults keep both backends driven by the same env.
NFT_TABLE=${NFT_TABLE:-xray}
NFT_SET=${NFT_SET:-freedom}

if [ "$ACTION" != "up" ] && [ "$ACTION" != "down" ] && [ "$ACTION" != "" ]; then
    echo "Unknown action $ACTION"
    exit 1
fi

require_var()
{
    eval "local VALUE=\$$1"
    if [ -z "$VALUE" ]; then
        echo "Required environment variable $1 is not set"
        exit 1
    fi
}

for VAR in DEV TUNIP SRC_DEV OUT_DEV XRAY_CONFIG \
           PROXY_IN_MARK PROXY_IN_TABLE PROXY_OUT_TABLE; do
    require_var $VAR
done

NFT=$(which nft 2>/dev/null)
IPTABLES=$(which iptables 2>/dev/null)
IPSET=$(which ipset 2>/dev/null)
IP=$(which ip 2>/dev/null)

if [ -z "$IP" ]; then
    echo "ip is required"
    exit 1
fi

# Backend selection. Set BACKEND in config to force one of
# nft | ipset | ip ; otherwise auto-detect, preferring nft.
if [ -z "$BACKEND" ]; then
    if [ -n "$NFT" ]; then
        BACKEND=nft
    elif [ -n "$IPTABLES" ] && [ -n "$IPSET" ]; then
        BACKEND=ipset
    else
        BACKEND=ip
    fi
fi

case "$BACKEND" in
    nft)
        [ -n "$NFT" ] || { echo "BACKEND=nft but nft not found"; exit 1; }
        ;;
    ipset)
        { [ -n "$IPTABLES" ] && [ -n "$IPSET" ]; } || { echo "BACKEND=ipset but iptables/ipset not found"; exit 1; }
        ;;
    ip)
        ;;
    *)
        echo "Unknown BACKEND $BACKEND (expected nft|ipset|ip)"
        exit 1
        ;;
esac

echo "Using backend: $BACKEND"

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

# nft: comma-separated element list from iplist.txt (blanks/# comments skipped).
build_elements()
{
    local IP_LIST_PATH=$CURRENTDIR/iplist.txt
    if [ -f "$IP_LIST_PATH" ]; then
        awk 'NF && $1 !~ /^#/ { printf "%s%s", sep, $1; sep="," }' "$IP_LIST_PATH"
    else
        echo "No ip list provided $IP_LIST_PATH" 1>&2
    fi
}

# Shared iproute2 policy routing (identical for nft and ipset). $1 = add|del.
setup_policy_routing()
{
    local IP_CMD=$1

    $IP route $IP_CMD default via $TUNIP dev $DEV table $PROXY_IN_TABLE
    $IP rule $IP_CMD fwmark $PROXY_IN_MARK table $PROXY_IN_TABLE priority 1000

    if [ "$OUT_VIA" != "" ]; then
        $IP route $IP_CMD default via $OUT_VIA dev $OUT_DEV table $PROXY_OUT_TABLE
    else
        $IP route $IP_CMD default dev $OUT_DEV table $PROXY_OUT_TABLE
    fi

    for ITEM in `cat $CURRENTDIR/$XRAY_CONFIG | grep mark | cut -d : -f 2 | uniq`
    do
        $IP rule $IP_CMD fwmark $ITEM table $PROXY_OUT_TABLE priority 1001
    done
}

# ---- iptables/ipset backend ------------------------------------------------

setup_iptables_rules()
{
    local IPTABLES_CMD=$1

    $IPTABLES -t mangle $IPTABLES_CMD PREROUTING -i $SRC_DEV -m set --match-set $IPSET_NAME dst -p tcp -m multiport --dports 443,80,8080 -j MARK --set-mark $PROXY_IN_MARK/$PROXY_IN_MARK
    $IPTABLES -t mangle $IPTABLES_CMD PREROUTING -i $SRC_DEV -m set --match-set $IPSET_NAME dst -p udp --dport 443 -j MARK --set-mark $PROXY_IN_MARK/$PROXY_IN_MARK

    local FORWARD_CMD=$IPTABLES_CMD
    if [ "$FORWARD_CMD" == "-A" ]; then
        FORWARD_CMD=-I
    fi
    $IPTABLES $FORWARD_CMD FORWARD -i $SRC_DEV -o $DEV -j ACCEPT
}

setup_routes_ipset()
{
    require_var IPSET_NAME

    $IPSET create $IPSET_NAME hash:ip hashsize 16384 maxelem 1000000
    local ERROR=$?
    if [ "$ERROR" -eq 0 ]; then
        echo "Created ipset $IPSET_NAME, filling ips"
        add_routes add_route_ipset
    else
        echo "Unable to create ipset. Exists already? Skipped filling the ips"
    fi

    setup_iptables_rules -A
    setup_policy_routing add
}

# ---- nftables backend ------------------------------------------------------

setup_routes_nft()
{
    # Make 'up' idempotent: drop a stale table first, ignore "doesn't exist".
    $NFT delete table inet $NFT_TABLE 2>/dev/null

    local ELEMENTS=$(build_elements)
    local SET_ELEMENTS=""
    if [ -n "$ELEMENTS" ]; then
        SET_ELEMENTS="elements = { $ELEMENTS }"
    fi

    # 'meta mark set meta mark or X' == iptables '--set-mark X/X'.
    # auto-merge collapses overlapping/adjacent CIDRs so the load never fails.
    $NFT -f - <<EOF
table inet $NFT_TABLE {
    set $NFT_SET {
        type ipv4_addr
        flags interval
        auto-merge
        $SET_ELEMENTS
    }

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "$SRC_DEV" ip daddr @$NFT_SET tcp dport { 80, 443, 8080 } meta mark set meta mark or $PROXY_IN_MARK counter
        iifname "$SRC_DEV" ip daddr @$NFT_SET udp dport 443 meta mark set meta mark or $PROXY_IN_MARK counter
    }

    chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "$SRC_DEV" oifname "$DEV" counter accept
    }
}
EOF
    local ERROR=$?
    if [ $ERROR -ne 0 ]; then
        echo "Failed to load nft ruleset (exit $ERROR)"
        exit $ERROR
    fi

    setup_policy_routing add
}

# ---- plain ip fallback -----------------------------------------------------

setup_routes_ip()
{
    add_routes add_route_ip
}

# ----------------------------------------------------------------------------

setup_drop_extra_routes()
{
    if [ -f "$EXTRA_ROUTES_SCRIPT" ]; then
        echo "Setting up extra routes"
        $EXTRA_ROUTES_SCRIPT $1 $DEV $PROXY_IN_MARK
    else
        echo "No extra routes script provided"
    fi
}

setup_routes()
{
    case "$BACKEND" in
        nft)   echo "Setting up routing with nftables...";      setup_routes_nft ;;
        ipset) echo "Setting up routing with ipset/iptables..."; setup_routes_ipset ;;
        ip)    echo "Setting up routing with ip...";             setup_routes_ip ;;
    esac

    setup_drop_extra_routes up

    echo "Done"
}

run_up()
{
    setup_routes
}

run_down()
{
    case "$BACKEND" in
        nft)
            $NFT delete table inet $NFT_TABLE 2>/dev/null
            setup_policy_routing del
            ;;
        ipset)
            setup_iptables_rules -D
            setup_policy_routing del
            # $IPSET destroy $IPSET_NAME
            ;;
    esac

    setup_drop_extra_routes down
}

if [ "$ACTION" == "up" ] || [ "$ACTION" == "" ]; then
    run_up
fi

if [ "$ACTION" == "down" ] || [ "$ACTION" == "" ]; then
    run_down
fi
