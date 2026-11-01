#!/bin/sh
# Runs the collector harness against the REAL CollectorConfig and RoamingCarService.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$(cd "$HERE/../.." && pwd)}
OUT=$(mktemp "${TMPDIR:-/tmp}/collector_test.XXXXXX.luau")
{
  echo "SOURCES = {"
  echo "CollectorConfig = [=====["; cat "$ROOT/ReplicatedStorage/shared/Configs/CollectorConfig.luau"; echo "]=====],"
  echo "RoamingCarService = [=====["; cat "$ROOT/ServerScriptService/server/Services/RoamingCarService/init.luau"; echo "]=====],"
  echo "}"
  cat "$HERE/harness.luau"
} > "$OUT"
RESULT=$(luau "$OUT" 2>&1)
rm -f "$OUT"
echo "$RESULT"
echo "$RESULT" | grep -q " 0 failed" || exit 1
