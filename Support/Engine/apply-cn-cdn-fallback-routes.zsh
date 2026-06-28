#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
GW="${1:-192.168.101.1}"
DOMAINS="${2:-$SCRIPT_DIR/cn-fast-route-domains.txt}"
STATE="${3:-$SCRIPT_DIR/cn-cdn-fallback-routes.state}"
DNS="${4:-223.5.5.5}"

[[ -f "$DOMAINS" ]] || { echo "Missing domain list: $DOMAINS" >&2; exit 1; }
[[ "$GW" =~ '^[0-9]+(\.[0-9]+){3}$' ]] || { echo "Invalid gateway: $GW" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

add_ip() {
  local ip="$1"
  [[ "$ip" =~ '^[0-9]+(\.[0-9]+){3}$' ]] || return 0

  local prefix
  prefix="$(print -r -- "$ip" | awk -F. '{print $1"."$2"."$3".0/24"}')"
  print -r -- "$prefix" >> "$tmp"
}

resolve_host() {
  local host="$1"
  [[ -z "$host" || "$host" == cn ]] && return 0

  dig +short +time=1 +tries=1 A "$host" 2>/dev/null | awk '/^[0-9.]+$/ {print}' | while read -r ip; do add_ip "$ip"; done
  dig @"$DNS" +short +time=1 +tries=1 A "$host" 2>/dev/null | awk '/^[0-9.]+$/ {print}' | while read -r ip; do add_ip "$ip"; done
}

while IFS= read -r suffix; do
  suffix="${suffix%%#*}"
  suffix="${suffix#"${suffix%%[![:space:]]*}"}"
  suffix="${suffix%"${suffix##*[![:space:]]}"}"
  [[ -z "$suffix" ]] && continue
  [[ "$suffix" == cn ]] && continue

  resolve_host "$suffix"
done < "$DOMAINS"

# Known China-site CDN ranges that Tailscale DNS often returns outside
# APNIC China allocations. Keep them narrow enough to avoid general leakage.
cat >> "$tmp" <<'ROUTES'
8.25.82.0/24
43.129.0.0/16
43.130.0.0/16
43.155.0.0/16
43.159.0.0/16
43.163.0.0/16
43.168.0.0/16
43.174.0.0/16
43.175.0.0/16
101.32.0.0/16
101.33.0.0/16
103.235.46.0/24
124.156.0.0/16
129.226.0.0/16
148.153.0.0/16
192.254.0.0/16
203.205.0.0/16
ROUTES

sort -u "$tmp" > "$STATE"

count=0
while IFS= read -r cidr; do
  [[ -z "$cidr" ]] && continue
  sudo /sbin/route -n add -net "$cidr" "$GW" >/dev/null 2>&1 || true
  count=$((count + 1))
done < "$STATE"

echo "Added/refreshed $count China-site fallback CDN routes via $GW."
echo "State: $STATE"
