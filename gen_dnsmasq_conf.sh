#!/bin/sh

CURRENT_DIR=$(dirname $0)
IPSET_NAME=XRAY_IPSET
NFT_NAME=xray
NFT_SET_NAME=freedom
OUTPUT_FILE=$CURRENT_DIR/ipset.conf
NFT_SET_FILE=$CURRENT_DIR/nfset.conf
INPUT_FILE=$CURRENT_DIR/hosts.txt


echo "# Generated ipset config" > $OUTPUT_FILE
echo "# Generated ipset config" > $NFT_SET_FILE
while read domain; do
  echo "ipset=/$domain/$IPSET_NAME" >> $OUTPUT_FILE
  echo "nftset=/$domain/4#inet#$NFT_NAME#$NFT_SET_NAME" >> $NFT_SET_FILE
done < "$INPUT_FILE"
