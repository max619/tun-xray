#!/bin/sh

CURRENT_DIR=$(dirname $0)

# Pull the ipset/nft names from the shared config so they stay in sync with
# setup_routing.sh. Fall back to the same defaults it uses when unset.
[ -f "$CURRENT_DIR/config" ] && source "$CURRENT_DIR/config"
IPSET_NAME=${IPSET_NAME:-XRAY_IPSET}
NFT_TABLE=${NFT_TABLE:-xray}
NFT_SET=${NFT_SET:-freedom}

OUTPUT_FILE=$CURRENT_DIR/ipset.conf
NFT_SET_FILE=$CURRENT_DIR/nfset.conf
INPUT_FILE=$CURRENT_DIR/hosts.txt


echo "# Generated ipset config" > $OUTPUT_FILE
echo "# Generated ipset config" > $NFT_SET_FILE
while read domain; do
  echo "ipset=/$domain/$IPSET_NAME" >> $OUTPUT_FILE
  echo "nftset=/$domain/4#inet#$NFT_TABLE#$NFT_SET" >> $NFT_SET_FILE
done < "$INPUT_FILE"
