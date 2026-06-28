#!/bin/zsh
set -euo pipefail

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

echo "Removing WeChat/Tencent direct routes"
for cidr in "${ROUTES[@]}"; do
  sudo /sbin/route -n delete -net "$cidr" >/dev/null 2>&1 || true
done

echo "Done."
