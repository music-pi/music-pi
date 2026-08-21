#!/usr/bin/env bash
# Verify the mpi-station composition is intact: all required pins are present.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
check() { # path expected_short_sha
  local path="$1" want="$2"
  if [[ ! -e "$path/.git" ]]; then
    echo "MISSING: $path (run: git submodule update --init --recursive)"
    fail=1
    return
  fi

  local got
  got="$(git -C "$path" rev-parse --short HEAD)"
  if [[ "$got" != "$want"* ]]; then
    echo "PIN DRIFT: $path at $got, expected $want"
    fail=1
  else
    echo "OK: $path @ $got"
  fi
}

check external/libmk3                         ca3627a
check external/mixxx-mk3                      dd61c32
check external/maschinepi-te                  841c01d
check external/mixxx-mk3/external/mk3         ca3627a
check external/maschinepi-te/external/mk3      ca3627a

exit "$fail"
