#!/usr/bin/env bash
set -euo pipefail

image_path="${1:?image path required}"
boot_loop=""
root_loop=""
mixxx_loop=""
samples_loop=""
root_mount="$(mktemp -d)"
boot_mount="$(mktemp -d)"
mixxx_mount="$(mktemp -d)"
samples_mount="$(mktemp -d)"
next_loop_minor=220

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

mapfile -t partitions < <(
  sfdisk -d "$image_path" | awk -F'[=,]' '/start=.*size=/ {
    gsub(/[^0-9]/, "", $2)
    gsub(/[^0-9]/, "", $4)
    print $2 " " $4
  }'
)
[[ "${#partitions[@]}" -eq 4 ]]
read -r boot_start boot_size <<< "${partitions[0]}"
read -r root_start root_size <<< "${partitions[1]}"
read -r mixxx_start mixxx_size <<< "${partitions[2]}"
read -r samples_start samples_size <<< "${partitions[3]}"

attach_loop boot_loop --read-only \
  --offset "$((boot_start * 512))" --sizelimit "$((boot_size * 512))" "$image_path"
attach_loop root_loop --read-only \
  --offset "$((root_start * 512))" --sizelimit "$((root_size * 512))" "$image_path"
attach_loop mixxx_loop --read-only \
  --offset "$((mixxx_start * 512))" --sizelimit "$((mixxx_size * 512))" "$image_path"
attach_loop samples_loop --read-only \
  --offset "$((samples_start * 512))" --sizelimit "$((samples_size * 512))" "$image_path"
mount -o ro "$boot_loop" "$boot_mount"
mount -o ro "$root_loop" "$root_mount"
mount -o ro "$mixxx_loop" "$mixxx_mount"
mount -o ro "$samples_loop" "$samples_mount"

default_target="$(readlink "$root_mount/etc/systemd/system/default.target")"
[[ "$default_target" == /etc/systemd/system/mode-selector.target ]]
[[ -e "$boot_mount/ssh" && ! -e "$boot_mount/userconf.txt" ]]
if grep -Eq '(^|[[:space:]])resize([[:space:]]|$)' "$boot_mount/cmdline.txt"; then
  echo "Stock root resize flag would overwrite the data partitions" >&2
  exit 1
fi
[[ -e "$root_mount/var/lib/mpi-station/provisioned" ]]
[[ ! -e "$root_mount/var/lib/mpi-station/password.hash" ]]
grep -q '^mpi:x:1000:' "$root_mount/etc/passwd"

for binary in \
  usr/local/bin/maschinepi \
  usr/local/bin/mixxx \
  usr/local/bin/mk3-screen-daemon \
  usr/local/bin/mk3 \
  usr/local/sbin/mk3-mode-selector; do
  [[ -x "$root_mount/$binary" ]]
  file "$root_mount/$binary" | grep -Eq 'ARM aarch64|ARM64'
done

for unit in maschinepi.service mixxx.service xvfb.service openbox.service mk3-screen-daemon.service; do
  [[ ! -e "$root_mount/etc/systemd/system/multi-user.target.wants/$unit" ]]
done

grep -q '^ExecStart=/usr/local/sbin/mk3-mode-selector --force-menu$' \
  "$root_mount/etc/systemd/system/mk3-mode-selector.service"
grep -q '^Wants=NetworkManager.service$' \
  "$root_mount/etc/systemd/system/mk3-mode-selector.service"
grep -q '^TimeoutStartSec=infinity$' \
  "$root_mount/etc/systemd/system/mk3-mode-selector.service"
grep -q '^Before=home-mpi-Music.mount home-mpi-maschinepi-samples.mount local-fs.target$' \
  "$root_mount/etc/systemd/system/mpi-prepare-data.service"
grep -q -- '--status-file' \
  "$root_mount/usr/local/sbin/mpi-prepare-data-partitions"
grep -q 'ACT LED pattern: three short flashes' \
  "$root_mount/usr/local/sbin/mpi-prepare-data-partitions"

grep -q '^LABEL=MIXXX_LIBRARY /home/mpi/Music ' "$root_mount/etc/fstab"
grep -q '^LABEL=MPI_SAMPLES /home/mpi/maschinepi/samples ' "$root_mount/etc/fstab"
[[ "$(e2label "$mixxx_loop")" == MIXXX_LIBRARY ]]
[[ "$(e2label "$samples_loop")" == MPI_SAMPLES ]]
[[ -f "$mixxx_mount/README.txt" ]]
[[ -f "$samples_mount/README.txt" ]]
sample_source="$root_mount/opt/mpi-station/external/maschinepi-te/samples"
expected_samples=0
if [[ -d "$sample_source" ]]; then
  expected_samples="$(find "$sample_source" -type f | wc -l)"
fi
actual_samples="$(find "$samples_mount" -type f ! -name README.txt | wc -l)"
[[ "$actual_samples" -eq "$expected_samples" ]]

echo "OS: $(. "$root_mount/etc/os-release"; echo "$PRETTY_NAME")"
echo "Default target: $default_target"
echo "Partitions: boot, root, MIXXX_LIBRARY, MPI_SAMPLES"
echo "Root filesystem space:"
df -h "$root_mount" | tail -n1
echo "Mixxx library filesystem:"
df -h "$mixxx_mount" | tail -n1
echo "MusicPI samples filesystem:"
df -h "$samples_mount" | tail -n1

git config --global --add safe.directory '*'
git -C "$root_mount/opt/mpi-station" submodule status --recursive
"$root_mount/opt/mpi-station/scripts/check-submodules.sh"
echo "Image inspection: PASS"
