#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
STATE="${1:-$SCRIPT_DIR/cn-cdn-fallback-routes.state}"

if [[ ! -f "$STATE" ]]; then
  echo "No fallback CDN route state file: $STATE"
  exit 0
fi

count=0
while IFS= read -r cidr; do
  [[ -z "$cidr" ]] && continue
  sudo /sbin/route -n delete -net "$cidr" >/dev/null 2>&1 || true
  count=$((count + 1))
done < "$STATE"

echo "Removed $count China-site fallback CDN routes."
