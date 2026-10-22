#!/bin/sh
# Runs the convoy pick checks against the REAL ConvoyConfig.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$(cd "$HERE/../.." && pwd)}
OUT=$(mktemp "${TMPDIR:-/tmp}/convoy_test.XXXXXX.luau")
{
  echo "SOURCE = [=====["; cat "$ROOT/ReplicatedStorage/shared/Configs/ConvoyConfig.luau"; echo "]=====]"
  cat "$HERE/harness.luau"
} > "$OUT"
RESULT=$(luau "$OUT" 2>&1)
rm -f "$OUT"
echo "$RESULT"
echo "$RESULT" | grep -q " 0 failed" || exit 1
