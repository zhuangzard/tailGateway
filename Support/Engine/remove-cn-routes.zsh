#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
FILE="$SCRIPT_DIR/cn-ip-list.txt"

if [[ ! -f "$FILE" ]]; then
  echo "Missing $FILE"
  exit 1
fi

echo "Removing China CIDR routes from $FILE"

while IFS= read -r cidr; do
  [[ -z "$cidr" || "$cidr" == \#* ]] && continue
  sudo /sbin/route -n delete -net "$cidr" >/dev/null 2>&1 || true
done < "$FILE"

echo "Done."
