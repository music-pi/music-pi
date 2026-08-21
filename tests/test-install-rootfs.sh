#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

root="$tmp_dir/root"
boot="$tmp_dir/boot"
release="$tmp_dir/release"
mkdir -p \
  "$root/etc" "$boot" "$release/config" \
  "$release/external/mixxx-mk3/mapping" \
  "$release/external/mixxx-mk3/skin/MK3" \
  "$release/external/maschinepi-te/samples/Drums"
printf '127.0.1.1 raspberrypi\n' > "$root/etc/hosts"
printf '# fixture\n' > "$release/README.md"
cp "$repo_root/config/mixxx-soundconfig.xml" "$release/config/"
printf '<controller/>\n' > \
  "$release/external/mixxx-mk3/mapping/Native-Instruments-Maschine-MK3.hid.xml"
printf '// controller fixture\n' > \
  "$release/external/mixxx-mk3/mapping/Native-Instruments-Maschine-MK3.js"
printf '<skin/>\n' > "$release/external/mixxx-mk3/skin/MK3/skin.xml"
printf 'sample fixture\n' > "$release/external/maschinepi-te/samples/Drums/kick.wav"
printf '%s\n' test-only > "$tmp_dir/password"
chmod 600 "$tmp_dir/password"

"$repo_root/image/install-rootfs.sh" \
  --root "$root" --boot "$boot" --release-tree "$release" --password-file "$tmp_dir/password"

[[ -L "$root/etc/systemd/system/default.target" ]]
[[ "$(readlink "$root/etc/systemd/system/default.target")" == /etc/systemd/system/mode-selector.target ]]
[[ ! -e "$root/etc/systemd/system/multi-user.target.wants/mpi-station-first-boot.service" ]]
[[ ! -e "$root/etc/systemd/system/multi-user.target.wants/maschinepi.service" ]]
[[ ! -e "$root/etc/systemd/system/multi-user.target.wants/mixxx.service" ]]
grep -qx 'default_mode=maschinepi' "$root/var/lib/mk3-mode/config"
[[ ! -e "$boot/userconf.txt" ]]
[[ -e "$boot/ssh" ]]
[[ -x "$root/usr/local/sbin/mpi-mode-switch" ]]
[[ -x "$root/usr/local/sbin/mpi-rebind-mk3-hid" ]]
[[ -x "$root/usr/local/sbin/mpi-prepare-data-partitions" ]]
[[ -L "$root/etc/systemd/system/local-fs.target.wants/mpi-prepare-data.service" ]]
grep -q '^ExecStart=/usr/local/sbin/mk3-mode-selector --force-menu$' \
  "$root/etc/systemd/system/mk3-mode-selector.service"
grep -q '^Wants=NetworkManager.service$' \
  "$root/etc/systemd/system/mk3-mode-selector.service"
grep -q '^TimeoutStartSec=infinity$' \
  "$root/etc/systemd/system/mk3-mode-selector.service"
grep -q '^Before=home-mpi-Music.mount home-mpi-maschinepi-samples.mount local-fs.target$' \
  "$root/etc/systemd/system/mpi-prepare-data.service"
grep -q -- '--status-file' "$root/usr/local/sbin/mpi-prepare-data-partitions"
grep -q 'ACT LED pattern: three short flashes' \
  "$root/usr/local/sbin/mpi-prepare-data-partitions"
[[ -f "$root/usr/share/mpi-station/samples/Drums/kick.wav" ]]
grep -q 'KERNEL=="hidraw\*"' "$root/etc/udev/rules.d/99-mk3-controller.rules"
[[ -x "$root/usr/local/sbin/mpi-station-provision-rootfs" ]]
grep -q 'network-manager' "$repo_root/image/provision-rootfs"
grep -q '^samples_dir=/home/mpi/maschinepi/samples$' \
  "$root/home/mpi/maschinepi/maschinepi.conf"
grep -q 'config/mixxx-soundconfig.xml' "$repo_root/image/install-rootfs.sh"
[[ -f "$root/var/lib/mpi-station/password.hash" ]]
grep -q 'mixxx_deb="$STATE_DIR/mixxx.deb"' "$repo_root/image/provision-rootfs"
! grep -q 'mixxx_2.6.0-beta-1_arm64.deb' "$repo_root/image/provision-rootfs"
grep -q 'mpi-station' "$root/etc/hosts"

echo "install-rootfs fixture: PASS"
