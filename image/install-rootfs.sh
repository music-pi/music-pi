#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: install-rootfs.sh --root ROOT --boot BOOT --release-tree DIR
                         [--artifacts-dir DIR] [--password-file FILE]
EOF
  exit 2
}

root=""
boot=""
release_tree=""
artifacts_dir=""
password_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --boot) boot="$2"; shift 2 ;;
    --release-tree) release_tree="$2"; shift 2 ;;
    --artifacts-dir) artifacts_dir="$2"; shift 2 ;;
    --password-file) password_file="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -d "$root" && -d "$boot" && -d "$release_tree" ]] || usage
[[ -z "$password_file" || -f "$password_file" ]] || { echo "Missing password file: $password_file" >&2; exit 1; }
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

install -d -m 755 "$root/opt/mpi-station"
cp -a "$release_tree/." "$root/opt/mpi-station/"

install -d -m 755 "$root/etc/systemd/system" "$root/usr/local/sbin"
install -m 644 "$repo_root"/systemd/*.service "$repo_root"/systemd/*.target \
  "$root/etc/systemd/system/"
install -m 755 "$repo_root/scripts/mpi-mode-select" "$root/usr/local/sbin/"
install -m 755 "$repo_root/scripts/mpi-mode-switch" "$root/usr/local/sbin/"
install -m 755 "$repo_root/scripts/mpi-audio-profile" "$root/usr/local/sbin/"
install -m 755 "$repo_root/scripts/mpi-rebind-mk3-hid" "$root/usr/local/sbin/"
install -m 755 "$repo_root/scripts/mpi-prepare-data-partitions" "$root/usr/local/sbin/"
install -m 755 "$repo_root/scripts/mpi-configure-mixxx-controller" "$root/usr/local/sbin/"
install -m 755 "$repo_root/image/provision-rootfs" \
  "$root/usr/local/sbin/mpi-station-provision-rootfs"

if [[ -n "$artifacts_dir" ]]; then
  [[ -f "$artifacts_dir/mixxx.deb" ]] || { echo "Missing Mixxx package: $artifacts_dir/mixxx.deb" >&2; exit 1; }
  [[ "$(dpkg-deb -f "$artifacts_dir/mixxx.deb" Architecture)" == arm64 ]] || { echo "Mixxx package is not ARM64: $artifacts_dir/mixxx.deb" >&2; exit 1; }
  for artifact in maschinepi mk3-screen-daemon mk3 mk3-mode-selector; do
    [[ -f "$artifacts_dir/$artifact" ]] || {
      echo "Missing host-built artifact: $artifacts_dir/$artifact" >&2
      exit 1
    }
    file "$artifacts_dir/$artifact" | grep -Eq 'ARM aarch64|ARM64' || {
      echo "Artifact is not ARM64: $(file "$artifacts_dir/$artifact")" >&2
      exit 1
    }
  done
  install -D -m 755 "$artifacts_dir/maschinepi" "$root/usr/local/bin/maschinepi"
  install -D -m 755 "$artifacts_dir/mk3-screen-daemon" \
    "$root/usr/local/bin/mk3-screen-daemon"
  install -D -m 755 "$artifacts_dir/mk3" "$root/usr/local/bin/mk3"
  install -D -m 755 "$artifacts_dir/mk3-mode-selector" \
    "$root/usr/local/sbin/mk3-mode-selector"
fi

install -d -m 755 "$root/var/lib/mk3-mode" "$root/var/lib/mpi-station"
if [[ -n "$artifacts_dir" ]]; then
  install -m 644 "$artifacts_dir/mixxx.deb" "$root/var/lib/mpi-station/mixxx.deb"
fi
install -m 644 "$repo_root/config/mk3-mode.conf" "$root/var/lib/mk3-mode/config"
if [[ -n "$password_file" ]]; then
  openssl passwd -6 -stdin < "$password_file" > "$root/var/lib/mpi-station/password.hash"
else
  printf '%s\n' musicpi | openssl passwd -6 -stdin > "$root/var/lib/mpi-station/password.hash"
fi
chmod 600 "$root/var/lib/mpi-station/password.hash"

install -d -m 755 \
  "$root/home/mpi/.mixxx/controllers" "$root/home/mpi/.mixxx/skins" \
  "$root/home/mpi/.config/openbox" "$root/home/mpi/Music" \
  "$root/home/mpi/maschinepi/samples" "$root/home/mpi/maschinepi/projects"
install -m 644 "$release_tree/external/mixxx-mk3/mapping/Native-Instruments-Maschine-MK3.hid.xml" \
  "$root/home/mpi/.mixxx/controllers/"
install -m 644 "$release_tree/external/mixxx-mk3/mapping/Native-Instruments-Maschine-MK3.js" \
  "$root/home/mpi/.mixxx/controllers/"
cp -a "$release_tree/external/mixxx-mk3/skin/MK3" "$root/home/mpi/.mixxx/skins/MK3"
install -m 644 "$release_tree/config/mixxx-soundconfig.xml" \
  "$root/home/mpi/.mixxx/soundconfig.xml"
cat > "$root/home/mpi/.mixxx/mixxx.cfg" <<'EOF'
[Config]
ResizableSkin MK3
StartInFullscreen 1
hide_menubar 1
show_menubar_hint 0

[Library]
RescanOnStartup 1
EOF
cat > "$root/home/mpi/.config/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications>
    <application name="*">
      <decor>no</decor>
      <maximized>yes</maximized>
      <fullscreen>yes</fullscreen>
    </application>
  </applications>
</openbox_config>
EOF
cat > "$root/home/mpi/maschinepi/maschinepi.conf" <<'EOF'
# MusicPI configuration installed by mpi-station
samples_dir=/home/mpi/maschinepi/samples
projects_dir=/home/mpi/maschinepi/projects
EOF
chown -R 1000:1000 "$root/home/mpi"

install -d -m 755 "$root/usr/share/mpi-station/samples"
sample_source="$release_tree/external/maschinepi-te/samples"
if [[ -d "$sample_source" ]]; then
  cp -a "$sample_source/." "$root/usr/share/mpi-station/samples/"
fi

install -d -m 755 "$root/etc/sysctl.d" "$root/etc/udev/rules.d"
cat > "$root/etc/sysctl.d/99-realtime-audio.conf" <<'EOF'
vm.swappiness=10
vm.dirty_ratio=3
vm.dirty_background_ratio=1
kernel.sched_rt_runtime_us=-1
EOF
cat > "$root/etc/udev/rules.d/99-mk3-controller.rules" <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="1600", MODE="0664", GROUP="audio"
KERNEL=="hidraw*", ATTRS{idVendor}=="17cc", ATTRS{idProduct}=="1600", MODE="0660", GROUP="audio"
EOF

install -d -m 755 "$root/etc/systemd/system/multi-user.target.wants"
install -d -m 755 "$root/etc/systemd/system/local-fs.target.wants"
ln -sfn /etc/systemd/system/mpi-prepare-data.service \
  "$root/etc/systemd/system/local-fs.target.wants/mpi-prepare-data.service"
ln -sfn /lib/systemd/system/ssh.service \
  "$root/etc/systemd/system/multi-user.target.wants/ssh.service"
ln -sfn /etc/systemd/system/mode-selector.target "$root/etc/systemd/system/default.target"

printf 'mpi-station\n' > "$root/etc/hostname"
if [[ -f "$root/etc/hosts" ]]; then
  sed -i -E 's/([[:space:]])raspberrypi([[:space:]]|$)/\1mpi-station\2/g' "$root/etc/hosts"
fi

touch "$boot/ssh"

echo "Installed mpi-station release into $root"
echo "Default mode: maschinepi"
echo "First boot user: mpi"
