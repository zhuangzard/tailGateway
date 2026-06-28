#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOMAINS="$SCRIPT_DIR/apple-icloud-domains.txt"
GW="${1:-192.168.101.1}"
DNS="${2:-223.5.5.5}"

if [[ ! -f "$DOMAINS" ]]; then
  echo "Missing $DOMAINS"
  exit 1
fi

echo "Adding Apple/iCloud direct routes via gateway $GW"
sudo /sbin/route -n add -net 17.0.0.0/8 "$GW" >/dev/null 2>&1 || true

while IFS= read -r domain; do
  [[ -z "$domain" || "$domain" == \#* ]] && continue
  dig @"$DNS" +short +time=4 +tries=1 A "$domain" |
    awk '/^[0-9.]+$/ {print}' |
    sort -u |
    while IFS= read -r ip; do
      sudo /sbin/route -n add -host "$ip" "$GW" >/dev/null 2>&1 || true
    done
done < "$DOMAINS"

echo "Done. Try iCloud sync again."
