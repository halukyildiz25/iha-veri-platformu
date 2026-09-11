#!/usr/bin/env bash
# Build an offline wheelhouse for the host .venv from a frozen requirement set.
# Per-package download so one stalled fetch cannot block the whole set.
#
# Usage:
#   PY=/path/to/python3.12/python.exe \
#   airgap_download_wheels.sh <venv-freeze.txt> <dest-dir>
#
# Tip to produce the freeze file:
#   VIRTUAL_ENV=./.venv uv pip freeze > venv-freeze.txt
set -u

REQ="${1:?path to venv-freeze.txt}"
DEST="${2:?destination wheelhouse dir}"
PY="${PY:-python}"
FAIL="$DEST/_failed.txt"
mkdir -p "$DEST"; : > "$FAIL"

dl() {
  local spec="$1"
  "$PY" -m pip download --no-deps --prefer-binary --retries 5 --timeout 60 \
    "$spec" -d "$DEST" >/dev/null 2>&1 \
    && echo "ok   $spec" \
    || { echo "FAIL $spec"; echo "$spec" >> "$FAIL"; }
}

# build backends first (needed if any pure-python dep is sdist-only)
for b in pip setuptools wheel hatchling flit-core poetry-core hatch-vcs setuptools-scm editables; do
  dl "$b"
done

grep -vE '^\s*#|^\s*$' "$REQ" | tr -d '\r' | while IFS= read -r spec; do
  [ -n "$spec" ] && dl "$spec"
done

echo "=== DONE ==="
echo "wheels: $(ls "$DEST"/*.whl 2>/dev/null | wc -l)  sdists: $(ls "$DEST"/*.tar.gz 2>/dev/null | wc -l)"
[ -s "$FAIL" ] && { echo "FAILED:"; cat "$FAIL"; }
du -sh "$DEST"
