#!/usr/bin/env bash
# Fail if anything in a Linux bundle needs a newer glibc than we support.
#
# libserialport.so is loaded at the first port scan, not at startup, so a build
# that needs too new a glibc still launches and just finds no USB ports.
#
# Usage: check-glibc.sh <bundle-dir> <max-glibc>
set -euo pipefail

bundle="$1"
max="$2"
failed=0

for f in "$bundle"/OpenView "$bundle"/lib/*.so; do
  # Some files, such as libapp.so, use no glibc symbols, so grep may match nothing.
  need=$(objdump -T "$f" | { grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' || true; } | sed 's/GLIBC_//' | sort -Vu | tail -1)
  [ -n "$need" ] || continue
  echo "$(basename "$f"): glibc $need"
  if [ "$(printf '%s\n%s\n' "$need" "$max" | sort -V | tail -1)" != "$max" ]; then
    echo "::error::$(basename "$f") needs glibc $need, newer than the supported $max."
    failed=1
  fi
done

exit "$failed"
