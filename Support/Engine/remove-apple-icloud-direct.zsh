#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DOMAINS="$SCRIPT_DIR/apple-icloud-domains.txt"
DNS="${1:-223.5.5.5}"

if [[ ! -f "$DOMAINS" ]]; then
  echo "Missing $DOMAINS"
  exit 1
fi

echo "Removing Apple/iCloud direct routes"
sudo /sbin/route -n delete -net 17.0.0.0/8 >/dev/null 2>&1 || true

while IFS= read -r domain; do
  [[ -z "$domain" || "$domain" == \#* ]] && continue
  dig @"$DNS" +short +time=4 +tries=1 A "$domain" |
    awk '/^[0-9.]+$/ {print}' |
    sort -u |
    while IFS= read -r ip; do
      sudo /sbin/route -n delete -host "$ip" >/dev/null 2>&1 || true
    done
done < "$DOMAINS"

echo "Done."
