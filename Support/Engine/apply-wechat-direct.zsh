#!/bin/zsh
set -euo pipefail

GW="${1:-192.168.101.1}"

# Tencent / WeChat ranges that often resolve through Tailscale DNS to
# overseas Tencent edges. These routes force them to the local Wi-Fi gateway.
ROUTES=(
  "43.129.0.0/16"
  "43.130.0.0/16"
  "43.155.0.0/16"
  "43.159.0.0/16"
  "43.163.0.0/16"
  "43.168.0.0/16"
  "43.174.0.0/16"
  "43.175.0.0/16"
  "101.32.0.0/16"
  "101.33.0.0/16"
  "124.156.0.0/16"
  "129.226.0.0/16"
  "203.205.0.0/16"
)

echo "Adding WeChat/Tencent direct routes via gateway $GW"
for cidr in "${ROUTES[@]}"; do
  sudo /sbin/route -n add -net "$cidr" "$GW" >/dev/null 2>&1 || true
done

echo "Done. Quick checks:"
for ip in 43.130.30.247 43.129.0.1 129.226.0.1 203.205.0.1; do
  printf "  %-15s " "$ip"
  route -n get "$ip" 2>/dev/null | awk '/gateway:|interface:/ {printf "%s=%s ", $1, $2} END{print ""}'
done
