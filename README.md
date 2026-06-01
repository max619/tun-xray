# tun-xray

Very simple set of scripts to use xray socks5 proxy as tun adapter and redirect all requests to specific ip list via socks5 proxy on router level.

I'm using it on Ubiquiti and OpenWRT routers, but i think it should work on any linux based platform with systemd/procd.

## Installation

Download a snapshot of this repository onto the device where the proxy will run
and unpack it into `/opt/tun-xray` (the path the service files expect):

```sh
curl -L https://github.com/max619/tun-xray/archive/refs/heads/main.tar.gz -o tun-xray.tar.gz
tar xzf tun-xray.tar.gz
mv tun-xray-main /opt/tun-xray
cd /opt/tun-xray
```

Then run `install.sh`. It downloads the binaries and installs the services
interactively, detecting the CPU architecture and the init system (systemd or
procd) and creating the matching service symlinks:

```sh
./install.sh
```

It asks:

1. Client or Server.
2. For a client, how the tun device is provided — xray tun inbound (preferred)
   or tun2socks.

and then downloads xray (plus tun2socks only when that mode is chosen) and
symlinks the appropriate service files. Creating users and starting the
services is still manual (see below).

The architecture is auto-detected; override it by passing the xray and
tun2socks arch names explicitly (e.g. for MIPS, whose float ABI can't be
detected):

```sh
./install.sh mips32 mips-hardfloat
```

### Client

Add the list of ips to pass through xray to `/opt/tun-xray/iplist.txt`.

You can specify both subnets and specific ips:

```
220.181.174.0/24
220.181.174.32
```

There are two ways to run the client. The **xray tun inbound** mode is the
preferred one — xray creates and owns the tun device itself, so only a single
service is needed. The older `tun2socks` mode is kept as an alternative.

#### Preferred: xray with a tun inbound

In this mode xray brings up the tun device, and the `start_xray.sh` wrapper
configures policy routing for it. No `tun2socks` process is involved.

Put an Xray config with a `tun` inbound into
`/opt/tun-xray/xray_config.client.json`, for example:

```json
{
  "protocol": "tun",
  "settings": {
    "name": "xray0",
    "mtu": 1500,
    "autoOutboundsInterface": "eth1"
  }
}
```

How it works:

1. `xray.service` / `xray.init` runs `start_xray.sh xray_config.client.json`.
2. The wrapper detects the `tun` inbound, starts xray, and waits for the device
   (`name`, e.g. `xray0`) to come up and receive an IPv4 address.
3. It reads that address as `TUNIP`, takes `DEV`/`OUT_DEV` from the xray config
   (`name` / `autoOutboundsInterface`), pulls the remaining routing parameters
   (`SRC_DEV`, marks, tables, …) from `config`, and runs
   `setup_routing.sh up` to install the nftables (or iptables+ipset) rules and
   policy routing that steer the `iplist.txt` destinations into the tunnel.
4. On stop, the wrapper's signal trap runs `setup_routing.sh down` and stops
   xray (see `term_signal`/`term_timeout` in `xray.init`).

Set at least `SRC_DEV` (your LAN interface) and, if needed, the marks/tables in
`/opt/tun-xray/config`. `DEV`, `OUT_DEV` and `TUNIP` are derived
automatically from the running tun device and do not need to be set here.

Run the installer and choose **Client** → **xray tun inbound** (this links only
the `xray` service), then create the user and start it:

```sh
./install.sh
useradd xray
systemctl start xray   # or: /etc/init.d/xray start
```

#### Alternative: tun2socks

In this mode xray only exposes a socks5 inbound (e.g. on `127.0.0.1:10808`),
and a separate `tun2socks` process creates the tun device and forwards traffic
into that socks proxy. `start_tun2socks.sh` creates the device and delegates the
routing to `setup_routing.sh`.

Put an Xray config with a socks inbound into
`/opt/tun-xray/xray_config.client.json`, then run the installer and choose
**Client** → **tun2socks** (this links both the `xray` and `tun2socks`
services). Create the users and start both services:

```sh
./install.sh
useradd xray
useradd tun2socks
systemctl start xray && systemctl start tun2socks
# or: /etc/init.d/xray start && /etc/init.d/tun2socks start
```

### Server

Put your Xray server config into `/opt/tun-xray/xray_config.server.json`, run the
installer and choose **Server**, then create the user and start it:

```sh
./install.sh
useradd xray
chown -R xray:xray /opt/tun-xray
systemctl start xray-server
```

> Only a systemd unit is provided for the server. On OpenWRT/procd the server config is not yet supported

### Firewall

You might need to allow forwarding in firewall. Replace `tun0` below with your
tun device name — `xray0` (the `name` from the xray config) in the preferred
mode, or `tun0` (the `DEV` from `config`) in the tun2socks mode.

```sh
uci set firewall.proxy=zone
uci set firewall.proxy.name='proxy'
uci set firewall.proxy.input='ACCEPT'
uci set firewall.proxy.output='ACCEPT'
uci set firewall.proxy.forward='ACCEPT'
uci set firewall.proxy.masq='0'
uci add_list firewall.proxy.device='tun0'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='proxy'
uci commit firewall
service firewall restart
```


## Used projects

- [Xray](https://github.com/XTLS/Xray-core)
- [tun2socks](https://github.com/xjasonlyu/tun2socks)

