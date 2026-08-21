#!/usr/bin/env bash
set -euo pipefail

image_path="${1:?image path required}"
release_tree="${2:?release tree required}"
artifacts_dir="${3:?artifact directory required}"
password_file="${4:?password file required}"
original_size_bytes="${5:?original image size required}"
rootfs_headroom_mb="${6:?rootfs headroom required}"
mixxx_library_mb="${7:?Mixxx library size required}"
samples_mb="${8:?samples size required}"

boot_loop=""
root_loop=""
mixxx_loop=""
samples_loop=""
root_mount="$(mktemp -d)"
boot_mount="$(mktemp -d)"
mixxx_mount="$(mktemp -d)"
samples_mount="$(mktemp -d)"
next_loop_minor=200

attach_loop() {
  local destination="$1"
  shift
  local node="/dev/loop$next_loop_minor"
  [[ -b "$node" ]] || mknod "$node" b 7 "$next_loop_minor"
  losetup "$node" "$@"
  printf -v "$destination" '%s' "$node"
  next_loop_minor=$((next_loop_minor + 1))
}

cleanup() {
  mountpoint -q "$samples_mount" && umount "$samples_mount" || true
  mountpoint -q "$mixxx_mount" && umount "$mixxx_mount" || true
  mountpoint -q "$root_mount" && umount "$root_mount" || true
  mountpoint -q "$boot_mount" && umount "$boot_mount" || true
  [[ -n "$samples_loop" ]] && losetup -d "$samples_loop" || true
  [[ -n "$mixxx_loop" ]] && losetup -d "$mixxx_loop" || true
  [[ -n "$root_loop" ]] && losetup -d "$root_loop" || true
  [[ -n "$boot_loop" ]] && losetup -d "$boot_loop" || true
  rmdir "$root_mount" "$boot_mount" "$mixxx_mount" "$samples_mount" 2>/dev/null || true
}
trap cleanup EXIT

# Preserve the stock boot/root pair and append two separately mountable data
# filesystems. Official images use whole-MiB boundaries, as do the new parts.
[[ "$original_size_bytes" =~ ^[0-9]+$ && $((original_size_bytes % 1048576)) -eq 0 ]] || {
  echo "Base image size is not MiB-aligned: $original_size_bytes" >&2
  exit 1
}
sectors_per_mib=2048
original_sectors=$((original_size_bytes / 512))
root_end=$((original_sectors + rootfs_headroom_mb * sectors_per_mib - 1))
mixxx_start=$((root_end + 1))
mixxx_end=$((mixxx_start + mixxx_library_mb * sectors_per_mib - 1))
samples_start=$((mixxx_end + 1))
samples_end=$((samples_start + samples_mb * sectors_per_mib - 1))

parted -s "$image_path" unit s resizepart 2 "${root_end}s"
parted -s "$image_path" unit s mkpart primary ext4 "${mixxx_start}s" "${mixxx_end}s"
parted -s "$image_path" unit s mkpart primary ext4 "${samples_start}s" "${samples_end}s"

mapfile -t partitions < <(
  sfdisk -d "$image_path" | awk -F'[=,]' '/start=.*size=/ {
    gsub(/[^0-9]/, "", $2)
    gsub(/[^0-9]/, "", $4)
    print $2 " " $4
  }'
)
[[ "${#partitions[@]}" -eq 4 ]] || {
  echo "Expected four partitions in $image_path" >&2
  exit 1
}

read -r boot_start boot_size <<< "${partitions[0]}"
read -r root_start root_size <<< "${partitions[1]}"
read -r mixxx_partition_start mixxx_partition_size <<< "${partitions[2]}"
read -r samples_partition_start samples_partition_size <<< "${partitions[3]}"

attach_loop boot_loop \
  --offset "$((boot_start * 512))" --sizelimit "$((boot_size * 512))" "$image_path"
attach_loop root_loop \
  --offset "$((root_start * 512))" --sizelimit "$((root_size * 512))" "$image_path"
attach_loop mixxx_loop \
  --offset "$((mixxx_partition_start * 512))" \
  --sizelimit "$((mixxx_partition_size * 512))" "$image_path"
attach_loop samples_loop \
  --offset "$((samples_partition_start * 512))" \
  --sizelimit "$((samples_partition_size * 512))" "$image_path"

set +e
e2fsck -f -y "$root_loop"
fsck_status=$?
set -e
[[ "$fsck_status" -lt 4 ]] || exit "$fsck_status"
resize2fs "$root_loop"
mkfs.ext4 -q -F -L MIXXX_LIBRARY "$mixxx_loop"
mkfs.ext4 -q -F -L MPI_SAMPLES "$samples_loop"

mount "$boot_loop" "$boot_mount"
mount "$root_loop" "$root_mount"
mount "$mixxx_loop" "$mixxx_mount"
mount "$samples_loop" "$samples_mount"

/repo/image/install-rootfs.sh \
  --root "$root_mount" \
  --boot "$boot_mount" \
  --release-tree "$release_tree" \
  --artifacts-dir "$artifacts_dir" \
  --password-file "$password_file"

cat >> "$root_mount/etc/fstab" <<'EOF'
LABEL=MIXXX_LIBRARY /home/mpi/Music ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2
LABEL=MPI_SAMPLES /home/mpi/maschinepi/samples ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2
EOF

sample_source="$release_tree/external/maschinepi-te/samples"
if [[ -d "$sample_source" ]]; then
  cp -a "$sample_source/." "$samples_mount/"
fi
printf '%s\n' 'MusicPI samples partition - copy samples here.' > "$samples_mount/README.txt"
printf '%s\n' 'Mixxx library partition - copy music files here.' > "$mixxx_mount/README.txt"
chown -R 1000:1000 "$mixxx_mount" "$samples_mount"

# Stock Raspberry Pi OS grows partition 2 when the kernel command line contains
# "resize". Partition 2 is no longer last, so suppress that one-shot action.
sed -i -E \
  's/(^|[[:space:]])resize([[:space:]]|$)/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
  "$boot_mount/cmdline.txt"

/repo/image/run-in-rootfs.sh "$root_mount"
sync
