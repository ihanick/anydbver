#!/bin/bash
URL="$1"
FPATH=$(echo "$URL" | cut -d/ -f 4-100)
export MC_HOSTS_bkp=$(echo "$URL" | cut -d/ -f 1-3)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
MC="$SCRIPT_DIR/mc"
if ! [[ -f "$MC" ]] ; then
  curl https://dl.min.io/client/mc/release/linux-amd64/mc -o "$MC"
  chmod +x "$MC"
fi

$MC cat bkp/"$FPATH"
