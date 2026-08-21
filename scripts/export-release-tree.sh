#!/usr/bin/env bash
set -euo pipefail

destination="${1:-}"
[[ -n "$destination" ]] || { echo "Usage: $0 DESTINATION" >&2; exit 2; }
[[ ! -e "$destination" ]] || { echo "Destination already exists: $destination" >&2; exit 1; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

git -C "$repo_root" bundle create "$tmp_dir/mpi-station.bundle" main
git clone --branch main "$tmp_dir/mpi-station.bundle" "$destination"
git -C "$destination" remote set-url origin https://github.com/music-pi/music-pi.git
git -C "$destination" submodule update --init --recursive --depth 1
"$destination/scripts/check-submodules.sh"
