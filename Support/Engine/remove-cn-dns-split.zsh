#!/bin/zsh
set -euo pipefail

RESOLVER_DIR="/etc/resolver"
MARKERS=("tailGateway-dns-split" "bridgeMode-cn-dns-split")

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ ! -d "$RESOLVER_DIR" ]]; then
  echo "No $RESOLVER_DIR directory."
  exit 0
fi

count=0
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  if grep -Eq "(${(j:|:)MARKERS})" "$file" 2>/dev/null; then
    as_root rm -f "$file"
    count=$((count + 1))
  fi
done < <(find "$RESOLVER_DIR" -maxdepth 1 -type f -print 2>/dev/null)

dscacheutil -flushcache >/dev/null 2>&1 || true
as_root killall -HUP mDNSResponder >/dev/null 2>&1 || true

echo "Removed $count TailGateway DNS split resolver files from $RESOLVER_DIR."
