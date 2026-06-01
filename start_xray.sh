#!/bin/sh

# Wrapper that runs xray with a config. If the config contains a "tun" inbound,
# xray creates the tun device itself; once it appears this wrapper hands policy
# routing for that device off to setup_routing.sh, and tears it down on exit.
#
# Usage (drop-in for `xray run -config <cfg>`):
#   start_xray.sh [run] [-config] <config>
# Defaults to xray_config.client.json when no config is given.
#
# Routing parameters (SRC_DEV, marks, tables, ...) are read from
# config; DEV and OUT_DEV are taken from the xray config, and TUNIP is
# read off the tun device once xray has brought it up.

CURRENTDIR=$(dirname $0)
XRAY=$CURRENTDIR/xray

# Parse args so the script can be invoked just like plain xray.
CONFIG=""
while [ $# -gt 0 ]; do
    case "$1" in
        -config|--config) CONFIG=$2; shift 2 ;;
        run)              shift ;;
        *)                CONFIG=$1; shift ;;
    esac
done
CONFIG=${CONFIG:-$CURRENTDIR/xray_config.client.json}

if [ ! -f "$CONFIG" ]; then
    echo "Config $CONFIG not found"
    exit 1
fi

# Pull a value out of the tun inbound's settings. Prefers jq; falls back to a
# scan that grabs the first matching key after the "protocol": "tun" line.
tun_setting()
{
    local KEY=$1
    if command -v jq >/dev/null 2>&1; then
        jq -r "first(.inbounds[]? | select(.protocol==\"tun\") | .settings.$KEY) // empty" "$CONFIG"
    else
        awk -v key="$KEY" '
            /"protocol"[[:space:]]*:[[:space:]]*"tun"/ { intun=1 }
            intun && match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"") {
                v = substr($0, RSTART, RLENGTH)
                sub(".*:[[:space:]]*\"", "", v)
                sub("\".*", "", v)
                print v
                exit
            }
        ' "$CONFIG"
    fi
}

# First IPv4 address configured on an interface (empty if none yet).
device_ipv4()
{
    ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

TUN_DEV=$(tun_setting name)

# No tun inbound -> nothing to route, just run xray directly.
if [ -z "$TUN_DEV" ]; then
    echo "No tun inbound in $CONFIG; starting xray without routing setup"
    exec "$XRAY" run -config "$CONFIG"
fi

echo "Config uses tun device '$TUN_DEV'; routing will be configured once it is up"

# Routing settings come from config; override DEV/OUT_DEV/XRAY_CONFIG
# from the xray config so setup_routing.sh acts on the right device.
[ -f "$CURRENTDIR/config" ] && source "$CURRENTDIR/config"

DEV=$TUN_DEV
TUN_OUT=$(tun_setting autoOutboundsInterface)
[ -n "$TUN_OUT" ] && OUT_DEV=$TUN_OUT
# setup_routing.sh reads XRAY_CONFIG relative to its own dir.
XRAY_CONFIG=$(basename "$CONFIG")

export DEV TUNIP SRC_DEV OUT_DEV OUT_VIA XRAY_CONFIG \
       PROXY_IN_MARK PROXY_IN_TABLE PROXY_OUT_TABLE \
       IPSET_NAME EXTRA_ROUTES_SCRIPT BACKEND NFT_TABLE NFT_SET

ROUTING_UP=0

cleanup()
{
    if [ "$ROUTING_UP" = "1" ]; then
        "$CURRENTDIR/setup_routing.sh" down
        ROUTING_UP=0
    fi
    if [ -n "$XRAY_PID" ] && kill -0 "$XRAY_PID" 2>/dev/null; then
        kill "$XRAY_PID" 2>/dev/null
    fi
}
trap cleanup INT TERM EXIT

"$XRAY" run -config "$CONFIG" &
XRAY_PID=$!

# Wait (up to ~15s) for xray to bring the tun device up with an IPv4 address,
# bailing if xray dies. TUNIP is read off the device rather than from config.
i=0
TUNIP=""
while [ $i -lt 15 ]; do
    TUNIP=$(device_ipv4 "$DEV")
    if [ -n "$TUNIP" ]; then
        break
    fi
    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "xray exited before device '$DEV' was configured"
        wait "$XRAY_PID"
        exit $?
    fi
    sleep 1
    i=$((i + 1))
done

if [ -n "$TUNIP" ]; then
    echo "Detected IP $TUNIP on tun device '$DEV'"
    if "$CURRENTDIR/setup_routing.sh" up; then
        ROUTING_UP=1
    else
        echo "Routing setup failed; stopping xray"
        exit 1
    fi
else
    echo "Device '$DEV' did not get an IPv4 address; stopping xray"
    exit 1
fi

wait "$XRAY_PID"
