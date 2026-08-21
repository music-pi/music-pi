#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Fill image/os-list/mpi-station.json with the size/hash/url fields that only
# exist once an image is built, producing a release-ready os_list JSON for the
# Raspberry Pi Imager custom-repository feature.
#
# Usage:
#   generate-os-list.sh --image path/to/mpi-station-vVERSION.img.xz \
#                       --url https://host/mpi-station-vVERSION.img.xz \
#                       [--icon https://host/icon.png] \
#                       [--date YYYY-MM-DD] \
#                       [--output image/os-list/mpi-station.release.json]
#
# The compressed image must be .xz. extract_sha256 is computed by streaming the
# decompressed image through sha256sum (no need to write the full .img to disk).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
template="$here/mpi-station.json"

image=""
url=""
icon=""
date_str="$(date +%F)"
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)  image="$2";  shift 2 ;;
    --url)    url="$2";    shift 2 ;;
    --icon)   icon="$2";   shift 2 ;;
    --date)   date_str="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$image" && -n "$url" ]] || { echo "error: --image and --url are required" >&2; exit 2; }
[[ -f "$image" ]] || { echo "error: image not found: $image" >&2; exit 2; }
[[ "$image" == *.xz ]] || { echo "error: --image must be a .xz file" >&2; exit 2; }
command -v xz >/dev/null || { echo "error: xz not found" >&2; exit 2; }

echo "Reading download size..." >&2
image_download_size="$(stat -c%s "$image")"

echo "Reading uncompressed size from xz index..." >&2
# --robot 'totals' line: field 5 is the total uncompressed size in bytes.
extract_size="$(xz --robot --list "$image" | awk '/^totals/ { print $5 }')"
[[ -n "$extract_size" ]] || { echo "error: could not read uncompressed size" >&2; exit 1; }

echo "Hashing decompressed image (streaming, may take a minute)..." >&2
extract_sha256="$(xz -dc "$image" | sha256sum | awk '{ print $1 }')"

# Default icon: raw asset in the repo if the caller didn't supply one.
if [[ -z "$icon" ]]; then
  icon="https://raw.githubusercontent.com/music-pi/music-pi/main/image/os-list/icon.png"
fi

result="$(sed \
  -e "s|__IMAGE_URL__|$url|g" \
  -e "s|__ICON_URL__|$icon|g" \
  -e "s|__RELEASE_DATE__|$date_str|g" \
  -e "s|__EXTRACT_SIZE__|$extract_size|g" \
  -e "s|__EXTRACT_SHA256__|$extract_sha256|g" \
  -e "s|__IMAGE_DOWNLOAD_SIZE__|$image_download_size|g" \
  "$template")"

# Validate JSON if a parser is available.
if command -v jq >/dev/null; then
  echo "$result" | jq -e . >/dev/null || { echo "error: produced invalid JSON" >&2; exit 1; }
fi

if [[ -n "$output" ]]; then
  printf '%s\n' "$result" > "$output"
  echo "Wrote $output" >&2
else
  printf '%s\n' "$result"
fi

# Emit the plain checksum file alongside the image for out-of-band verification.
sha_file="${image}.sha256"
sha256sum "$image" > "$sha_file"
echo "Wrote $sha_file (compressed-image checksum)" >&2

cat >&2 <<EOF

Done.
  download size (compressed) : $image_download_size bytes
  extract size (uncompressed): $extract_size bytes
  extract_sha256             : $extract_sha256
EOF
