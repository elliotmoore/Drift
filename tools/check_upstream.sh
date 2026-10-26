#!/bin/sh
# Confirms DSP/third_party is an unmodified copy of Emilie Gillet's code at the commits
# recorded in DSP/third_party/README.md. Needs git and network access. Run from anywhere.
set -eu

EURORACK_SHA=08460a69a7e1f7a81c5a2abcc7189c9a6b7208d4
STMLIB_SHA=d18def816c51d1da0c108236928b2bbd25c17481

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DSP="$ROOT/DSP/third_party"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch <url> <sha> <dir>: just that commit, no history
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}

echo "Fetching pichenettes/eurorack @ $EURORACK_SHA ..."
fetch https://github.com/pichenettes/eurorack "$EURORACK_SHA" "$TMP/eurorack"
echo "Fetching pichenettes/stmlib @ $STMLIB_SHA ..."
fetch https://github.com/pichenettes/stmlib "$STMLIB_SHA" "$TMP/stmlib"

checked=0
failed=0
for dir in plaits marbles rings stmlib; do
  if [ "$dir" = stmlib ]; then upstream="$TMP/stmlib"; else upstream="$TMP/eurorack/$dir"; fi
  for f in $(cd "$DSP/$dir" && find . -type f | sort); do
    checked=$((checked + 1))
    if ! cmp -s "$DSP/$dir/$f" "$upstream/$f"; then
      echo "DIFFERS: $dir/${f#./}"
      failed=$((failed + 1))
    fi
  done
done

if [ "$failed" -eq 0 ]; then
  echo "OK: all $checked files are identical to upstream."
else
  echo "$failed of $checked files differ from upstream."
  exit 1
fi
