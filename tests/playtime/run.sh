#!/bin/sh
# Runs the playtime gift harness against the REAL PlaytimeRewardService and its config.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$(cd "$HERE/../.." && pwd)}
OUT=$(mktemp "${TMPDIR:-/tmp}/playtime_test.XXXXXX.luau")
{
  echo "SOURCES = {"
  echo "PlaytimeRewardConfig = [=====["; cat "$ROOT/ReplicatedStorage/shared/Configs/PlaytimeRewardConfig.luau"; echo "]=====],"
  echo "PlaytimeRewardService = [=====["; cat "$ROOT/ServerScriptService/server/Services/PlaytimeRewardService.luau"; echo "]=====],"
  echo "}"
  cat "$HERE/harness.luau"
} > "$OUT"
RESULT=$(luau "$OUT" 2>&1)
rm -f "$OUT"
echo "$RESULT"
echo "$RESULT" | grep -q " 0 failed" || exit 1
