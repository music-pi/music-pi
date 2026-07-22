# Raspberry Pi 4 image and mode test

This procedure validates the complete host-built image, selector, and systemd
targets on a Raspberry Pi 4 with a Maschine MK3.

## 1. Build the image

Download a stock Raspberry Pi OS Lite **arm64** image, then run:

```bash
./image/build-image.sh \
  --base /path/to/raspios-lite-arm64.img.xz \
  --output image/output/mpi-station-test.img \
  --compress
```

To reuse an existing ARM64 MusicPI binary instead of cross-compiling it, add:

```bash
--maschinepi-binary /path/to/maschinepi
```

Without it, the host cross-compiles MusicPI before assembling the image. The
build emits the image and a neighboring `.sha256` file. Verify it before flashing:

```bash
(cd image/output && sha256sum -c mpi-station-test.img.xz.sha256)
MPI_BUILD_TMPDIR=/dev/shm ./image/inspect-image.sh \
  image/output/mpi-station-test.img.xz
```

## 2. Flash and boot

Use a 16 GB or larger card.

Prefer Raspberry Pi Imager's “Use custom image” flow. If using `dd`, identify
the SD-card device carefully; the output device is overwritten:

```bash
xz -dc image/output/mpi-station-test.img.xz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

The image is already provisioned: first boot requires no network, compilation,
package installation, or automatic reboot. Attach the MK3 before power-on. The
image login is:

- user: `mpi`
- password: `maschinepi` (or the `--password` value used at build time)
- hostname: `mpi-station`

When the card is inspected on another Linux machine it exposes four filesystems:

- Raspberry Pi boot
- Raspberry Pi root
- `MIXXX_LIBRARY`
- `MPI_SAMPLES`

On the Pi, the last two mount at `/home/mpi/Music` and
`/home/mpi/maschinepi/samples`; the sample partition already contains the
pinned starter samples. During the first boot only, their partition boundary is
adjusted so each receives half of all card space remaining after root. The Pi
ACT LED repeats three short flashes during this operation. If the MK3 has
enumerated, both screens show milestone progress through resize, format, sample
copy, and sync; an absent MK3 does not block preparation.

Every boot opens the selector and waits without a timeout for the MK3 to attach.
D1/D2 choose a mode directly; the encoder and push navigate/activate; D8 saves
the highlighted default. D7 opens Wi-Fi setup: turn the encoder to select a
network and push to connect. For secured networks, enter the password with the
T9 pads (pad 8 cycles lower/upper/symbols, pad 4 submits, pad 12 cancels, and
pad 16 backspaces). D6 adds a hidden network by entering its SSID and selecting
Secure/Open with D7. A successful connection is saved system-wide and is
available in either mode.

Before release, verify one visible secured network, one open or hidden network,
and a reboot reconnect. Confirm `nmcli connection show` lists the new profile
without a user-specific `connection.permissions` value.

## 3. Verify target ownership and switching

```bash
systemctl get-default
systemctl is-active maschinepi.target
systemctl is-active mixxx.target
systemctl status maschinepi.service --no-pager
```

Expected after selecting MusicPI: default is `mode-selector.target`,
MusicPI target/service are active, and Mixxx is inactive.

Switch to Mixxx:

```bash
sudo mpi-mode-switch mixxx
systemctl is-active mixxx.target
systemctl is-active maschinepi.service
systemctl status mixxx.service mk3-screen-daemon.service --no-pager
```

Expected: Mixxx appears across both MK3 screens, its controller mapping is live,
master audio uses MK3 outputs, and cue/headphone audio uses the Pi jack. The
MusicPI service must be inactive.

Switch back:

```bash
sudo mpi-mode-switch maschinepi
systemctl is-active maschinepi.target
systemctl is-active mixxx.service xvfb.service openbox.service \
  mk3-screen-daemon.service mk3-t9-daemon.service mk3-mouse-daemon.service \
  mk3-overlay.service
```

Expected: MusicPI owns the displays/controller and every listed Mixxx unit is
inactive. Repeat Mixxx → MusicPI → Mixxx at least twice to catch delayed USB
or PipeWire release.

Return to the selector without rebooting when a terminal is available:

```bash
sudo mpi-mode-switch selector
```

Without terminal access, reboot or power-cycle; the selector is the default
boot target and will wait for the MK3 again.

Inspect audio and logs after each transition:

```bash
sudo -u mpi XDG_RUNTIME_DIR=/run/user/1000 wpctl status
journalctl -b -u maschinepi.service -u mixxx.service \
  -u mk3-screen-daemon.service -u '*audio-profile.service' --no-pager
```

Persist a different default and reboot:

```bash
sudo mpi-mode-switch --set-default mixxx
sudo reboot
```

Expected: the next boot still has `mode-selector.target` as the system default
and initially highlights Mixxx; activate it to isolate `mixxx.target`.

## 4. Capture failures

If startup fails, capture:

```bash
journalctl -b -u mk3-mode-selector.service --no-pager
systemctl --failed --no-pager
git -C /opt/mpi-station submodule status --recursive
```

For mode-switch failures, also record `lsusb -t`, `wpctl status`, and the unit
logs above before rebooting; teardown behavior cannot be diagnosed afterward.
