#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cmake -S "$repo_root/mode-selector" -B "$tmp_dir/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON >/dev/null
cmake --build "$tmp_dir/build" --target mk3-mode-selector selector-support-tests >/dev/null
ctest --test-dir "$tmp_dir/build" -R '^selector-support-tests$' --output-on-failure >/dev/null
selector="$tmp_dir/build/mk3-mode-selector"
config="$tmp_dir/config"
cp "$repo_root/config/mk3-mode.conf" "$config"

output="$($selector --config "$config" --dry-run --select mixxx)"
[[ "$output" == 'systemctl --no-block isolate mixxx.target' ]]

"$selector" --config "$config" --set-default mixxx
grep -qx 'default_mode=mixxx' "$config"
grep -qx 'slot1=maschinepi.target|MusicPI' "$config"
grep -qx 'slot2=mixxx.target|MixxxDJ' "$config"

output="$($selector --config "$config" --dry-run --poll-ms 0)"
[[ "$output" == 'systemctl --no-block isolate mixxx.target' ]]

if "$selector" --config "$config" --dry-run --select '../bad' 2>/dev/null; then
  echo "Unsafe selector target was accepted" >&2
  exit 1
fi

printf '45|FORMATTING LIBRARY\n' > "$tmp_dir/status"
output="$($selector --config "$config" --dry-run --status-file "$tmp_dir/status")"
[[ "$output" == 'status 45 FORMATTING LIBRARY' ]]

printf 'ERROR\n' > "$tmp_dir/status"
output="$($selector --dry-run --status-file "$tmp_dir/status")"
[[ "$output" == 'status 0 PREPARING STORAGE error' ]]

fake_nmcli="$tmp_dir/nmcli"
{
  printf '%s\n' '#!/bin/sh'
  printf '%s\n' 'if [ "$*" = "radio wifi on" ]; then exit 0; fi'
  printf '%s\n' "printf '%s\\n' ' :Cafe\\:Lab:40:WPA2' '*:Open:55:--' ' :Cafe\\:Lab:90:WPA2'"
} > "$fake_nmcli"
chmod +x "$fake_nmcli"
output="$($selector --nmcli "$fake_nmcli" --wifi-scan)"
[[ "$output" == $'active\t55\t--\tOpen\navailable\t90\tWPA2\tCafe:Lab' ]]

echo "mode selector behavior: PASS"
