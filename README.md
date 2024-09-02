# tun-xray

Very simple set of scripts to use xray socks5 proxy as tun adapter and redirect all requests to specific ip list via socks5 proxy on router level.

I'm using it on Ubiquiti router, but i think it should work on any linux based platform with systemd.

## Installation

To download binaries run:

```sh
./install.sh <xray arch> <tun2socks arch>
```

ex:
```sh
./install.sh mips32 mips-hardfloat
```

Create file 'tun-xray/iplist.txt' and add list of ips to pass through xray

You can specify both subnets and specific ips:

```
220.181.174.0/24
220.181.174.32
```

Put Xray config into `tun-xray/xray_config.json`

Then copy the `tun-xray` directory to the router or device on which you want to run the proxy

```sh
scp -r tun-xray user@192.168.0.1:~/
```

Connect to the device and move the `tun-xray` to `/opt/tun-xray`.

Create symlinks for services

```sh
ln -s /opt/tun-xray/xray.service /etc/systemd/system/xray.service
ln -s /opt/tun-xray/tun2socks.service /etc/systemd/system/tun2socks.service
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

## Used projects

- [Xray](https://github.com/XTLS/Xray-core)
- [tun2socks](https://github.com/xjasonlyu/tun2socks)

