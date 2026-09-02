#!/usr/bin/env bash
# Apply the WS4945 decode fixes to a fresh OpenMQTTGateway v1.8.1 clone.
# Usage: from inside the OMG repo root: bash /path/to/apply.sh /path/to/patches
set -euo pipefail

PATCH_DIR="${1:?usage: apply.sh <patches-dir>}"
PATCH_DIR="$(cd "$PATCH_DIR" && pwd)"

echo "==> Fetching rtl_433_ESP library dependencies"
pio run -e esp32dev-rtl_433 >/dev/null 2>&1 || true

LIB=".pio/libdeps/esp32dev-rtl_433/rtl_433_ESP"
if [ ! -d "$LIB" ]; then
  echo "ERROR: rtl_433_ESP not found at $LIB — run 'pio run -e esp32dev-rtl_433' first" >&2
  exit 1
fi

echo "==> Patching rtl_433_ESP (lib)"
(cd "$LIB" && patch -p1 < "$PATCH_DIR/0001-rtl433-esp-default-tolerance.patch")
(cd "$LIB" && patch -p1 < "$PATCH_DIR/0002-rtl433-esp-trailing-gap.patch")

echo "==> Patching OpenMQTTGateway (main)"
patch -p1 < "$PATCH_DIR/0003-omg-closed-entity-and-dedup.patch"

echo "==> Done. Rebuild: pio run -e esp32dev-rtl_433"
echo "    (Disconnect CC1101 from GPIO12 before flashing.)"
