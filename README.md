# tun-xray

Very simple set of scripts to use xray socks5 proxy as tun adapter and redirect all requests to specific ip list via socks5 proxy on router level.

I'm using it on Ubiquiti and OpenWRT routers, but i think it should work on any linux based platform with systemd/procd.

## Installation

To download binaries run:

```sh
./install.sh <xray arch> <tun2socks arch>
```

ex:
```sh
./install.sh mips32 mips-hardfloat
```

### Client

Create file 'tun-xray/iplist.txt' and add list of ips to pass through xray

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

Put an Xray config with a `tun` inbound into `tun-xray/xray_config.client.json`,
for example:

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
   (`SRC_DEV`, marks, tables, …) from `tun2socks.config`, and runs
   `setup_routing.sh up` to install the nftables (or iptables+ipset) rules and
   policy routing that steer the `iplist.txt` destinations into the tunnel.
4. On stop, the wrapper's signal trap runs `setup_routing.sh down` and stops
   xray (see `term_signal`/`term_timeout` in `xray.init`).

Set at least `SRC_DEV` (your LAN interface) and, if needed, the marks/tables in
`tun-xray/tun2socks.config`. `DEV`, `OUT_DEV` and `TUNIP` are derived
automatically from the running tun device and do not need to be set here.

Copy the `tun-xray` directory to the router or device on which you want to run
the proxy

```sh
scp -r tun-xray user@192.168.0.1:/opt/tun-xray
```

Create a symlink for the systemd service

```sh
ln -s /opt/tun-xray/xray.service /etc/systemd/system/xray.service
```

Or for proc.d on OpenWRT

```sh
ln -s /opt/tun-xray/xray.init /etc/init.d/xray
```

Create the user

```sh
useradd xray
```

Start the service

```sh
systemctl start xray
```

Or

```sh
/etc/init.d/xray start
```

#### Alternative: tun2socks

In this mode xray only exposes a socks5 inbound (e.g. on `127.0.0.1:10808`),
and a separate `tun2socks` process creates the tun device and forwards traffic
into that socks proxy. `start_tun2socks.sh` creates the device and delegates the
routing to `setup_routing.sh`.

Put an Xray config with a socks inbound into `tun-xray/xray_config.client.json`,
then copy the directory as above and create symlinks for **both** services

```sh
ln -s /opt/tun-xray/xray.service /etc/systemd/system/xray.service
ln -s /opt/tun-xray/tun2socks.service /etc/systemd/system/tun2socks.service
```

Or for proc.d on OpenWRT

```sh
ln -s /opt/tun-xray/xray.init /etc/init.d/xray
ln -s /opt/tun-xray/tun2socks.init /etc/init.d/tun2socks
```

Create users

```sh
useradd xray
useradd tun2socks
```

Start services

```sh
systemctl start xray
systemctl start tun2socks
```

Or

```sh
/etc/init.d/xray start
/etc/init.d/tun2socks start
```

### Server

Put Xray config into `tun-xray/xray_config.server.json`

Then copy the `tun-xray` directory to the router or device on which you want to run the server

```sh
scp -r tun-xray user@192.168.0.1:/opt/tun-xray
```

Create symlinks for systemd services

```sh
ln -s /opt/tun-xray/xray-server.service /etc/systemd/system/xray-server.service
```

Create user and update acess rights

```sh
useradd xray
chown -R xray:xray /opt/tun-xray
```

### Firewall

You might need to allow forwarding in firewall. Replace `tun0` below with your
tun device name — `xray0` (the `name` from the xray config) in the preferred
mode, or `tun0` (the `DEV` from `tun2socks.config`) in the tun2socks mode.

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

