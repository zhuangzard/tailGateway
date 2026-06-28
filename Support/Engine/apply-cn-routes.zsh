#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
FILE="$SCRIPT_DIR/cn-ip-list.txt"
GW="${1:-192.168.101.1}"

if [[ ! -f "$FILE" ]]; then
  echo "Missing $FILE"
  exit 1
fi

echo "Adding China CIDR routes via gateway $GW"
echo "Source list: $FILE"

while IFS= read -r cidr; do
  [[ -z "$cidr" || "$cidr" == \#* ]] && continue
  sudo /sbin/route -n add -net "$cidr" "$GW" >/dev/null 2>&1 || true
done < "$FILE"

echo "Done. Verify with:"
echo "  route -n get 119.23.85.51"
echo "  route -n get 128.14.14.141"
