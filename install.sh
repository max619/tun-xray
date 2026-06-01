#!/bin/sh

#set -e


CURRENTDIR=$(dirname $0)

# Map the host architecture (uname -m) to the release-asset names used by xray
# and tun2socks. The two projects use different naming conventions, so each is
# resolved separately. MIPS float ABI can't be detected reliably here; a
# softfloat default is used and can be overridden via the CLI args.
detect_arch()
{
   local MACHINE=$(uname -m)
   case "$MACHINE" in
      x86_64|amd64)        XRAY_ARCH=64;        TUN2SOCKS_ARCH=amd64 ;;
      i386|i486|i586|i686) XRAY_ARCH=32;        TUN2SOCKS_ARCH=386 ;;
      aarch64|arm64)       XRAY_ARCH=arm64-v8a; TUN2SOCKS_ARCH=arm64 ;;
      armv7l|armv7)        XRAY_ARCH=arm32-v7a; TUN2SOCKS_ARCH=armv7 ;;
      armv6l|armv6)        XRAY_ARCH=arm32-v6;  TUN2SOCKS_ARCH=armv6 ;;
      armv5l|armv5|armv5tel) XRAY_ARCH=arm32-v5; TUN2SOCKS_ARCH=armv5 ;;
      mips)                XRAY_ARCH=mips32;    TUN2SOCKS_ARCH=mips-softfloat ;;
      mipsel|mipsle)       XRAY_ARCH=mips32le;  TUN2SOCKS_ARCH=mipsle-softfloat ;;
      mips64)              XRAY_ARCH=mips64;    TUN2SOCKS_ARCH=mips64 ;;
      mips64el|mips64le)   XRAY_ARCH=mips64le;  TUN2SOCKS_ARCH=mips64le ;;
      s390x)               XRAY_ARCH=s390x;     TUN2SOCKS_ARCH=s390x ;;
      ppc64le)             XRAY_ARCH=ppc64le;   TUN2SOCKS_ARCH=ppc64le ;;
      riscv64)             XRAY_ARCH=riscv64;   TUN2SOCKS_ARCH=riscv64 ;;
      *)
         echo "Could not detect architecture for '$MACHINE'."
         echo "Pass it explicitly: $0 <xray arch> <tun2socks arch>"
         exit 1 ;;
   esac
   echo "Detected architecture '$MACHINE' -> xray=$XRAY_ARCH tun2socks=$TUN2SOCKS_ARCH"
}

XRAY_ARCH=$1
TUN2SOCKS_ARCH=$2

# No arch given on the CLI -> auto-detect both from the host.
if [ -z "$XRAY_ARCH" ]; then
   detect_arch
fi

# Only the xray arch given -> reuse it for tun2socks (legacy behavior).
if [ -z "$TUN2SOCKS_ARCH" ]; then
   TUN2SOCKS_ARCH=$XRAY_ARCH
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

run_curl()
{
   local CURL="curl -s -L -f"
   run_and_exit_on_fail $CURL $@
}

download_latest()
{
   local LATEST_VERSION=$(run_curl https://api.github.com/repos/$1/releases/latest | grep tag_name | cut -d : -f 2,3 | tr -d '\", ')
   local URL=https://github.com/$1/releases/download/$LATEST_VERSION/$2
   echo "Downloading $1@$LATEST_VERSION from $URL"
   run_curl -o $3 $URL
}

link_service()
{
   # $1 = file in install dir, $2 = symlink destination
   local SRC="$INSTALL_DIR/$1" DST="$2"
   if [ ! -f "$SRC" ]; then
      echo "Warning: $SRC not found; skipping $DST"
      return
   fi
   ln -sf "$SRC" "$DST"
   echo "Linked $DST -> $SRC"
}

INSTALL_DIR=$(cd "$CURRENTDIR" && pwd)

# --- ask what to install ----------------------------------------------------

echo
echo "Which configuration do you want to install?"
echo "  1) Client"
echo "  2) Server"
printf "Selection [1]: "
read -r ROLE
case "$ROLE" in
   2|server|Server) ROLE=server ;;
   *)               ROLE=client ;;
esac

# For the client, choose how the tun device is provided.
MODE=""
if [ "$ROLE" = "client" ]; then
   echo
   echo "How should the tun device be provided?"
   echo "  1) xray tun inbound (preferred, single service)"
   echo "  2) tun2socks"
   printf "Selection [1]: "
   read -r MODE
   case "$MODE" in
      2|tun2socks) MODE=tun2socks ;;
      *)           MODE=tun ;;
   esac
fi

# --- download binaries ------------------------------------------------------

download_latest XTLS/Xray-core Xray-linux-$XRAY_ARCH.zip xray.zip
unzip -o xray.zip -x README.md -d $CURRENTDIR

# tun2socks is only needed for the client tun2socks mode.
if [ "$MODE" = "tun2socks" ]; then
   download_latest xjasonlyu/tun2socks tun2socks-linux-$TUN2SOCKS_ARCH.zip tun2socks.zip
   unzip -o tun2socks.zip -x README.md -d $CURRENTDIR
   mv tun2socks-linux-$TUN2SOCKS_ARCH tun2socks
fi

# --- install services -------------------------------------------------------

# Detect the init system; fall back to asking if unsure.
INIT=""
if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
   INIT=systemd
elif [ -d /etc/init.d ] && [ -f /etc/rc.common ]; then
   INIT=procd
fi

if [ -z "$INIT" ]; then
   echo
   echo "Could not detect the init system. Which one should be used?"
   echo "  1) systemd"
   echo "  2) procd (OpenWRT)"
   printf "Selection [1]: "
   read -r INIT
   case "$INIT" in
      2|procd) INIT=procd ;;
      *)       INIT=systemd ;;
   esac
fi

if [ "$INIT" = "systemd" ]; then
   DEST=/etc/systemd/system
   if [ "$ROLE" = "server" ]; then
      link_service xray-server.service $DEST/xray-server.service
   else
      link_service xray.service $DEST/xray.service
      if [ "$MODE" = "tun2socks" ]; then
         link_service tun2socks.service $DEST/tun2socks.service
      fi
   fi
else
   DEST=/etc/init.d
   if [ "$ROLE" = "server" ]; then
      if [ -f "$INSTALL_DIR/xray-server.init" ]; then
         link_service xray-server.init $DEST/xray-server
      else
         echo "No procd init script for the server is provided; install it manually."
      fi
   else
      link_service xray.init $DEST/xray
      if [ "$MODE" = "tun2socks" ]; then
         link_service tun2socks.init $DEST/tun2socks
      fi
   fi
fi

echo
echo "Done. Review the config files in $INSTALL_DIR before starting the services."