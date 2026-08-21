<p align="center">
  <img src="docs/musicpi-logo.png" alt="MusicPI" width="180">
</p>

<h1 align="center">MusicPI</h1>

**One Raspberry Pi + Native Instruments Maschine MK3, two instruments.**
MusicPI ships as a single flashable image that boots into either:

- **MusicPI** — a headless Tracktion-based DAW / groovebox, or
- **MixxxDJ** — Mixxx DJ software with full MK3 control,

chosen from a selector on the MK3 screens at boot. Switch modes, reboot, and
the same hardware becomes a different instrument.

> **About the name.** MusicPI began as *MaschinePI* — Maschine + Raspberry Pi —
> born to unleash the Native Instruments Maschine MK3 beyond the software it
> shipped with, freeing its pads, screens, and knobs as a standalone, portable
> performance platform that needs no laptop. As the project grew into a whole
> music machine the letters stayed (**MPI**) but the M now stands for **Music**.
> This project is a homage to the MK3 that inspired it.

## Download & flash (recommended)

You do not need to build anything. Grab the latest ready-to-run image and flash
it to an SD card.

1. **Download** the newest `mpi-station-*.img.xz` from the
   [Releases page](https://github.com/music-pi/music-pi/releases).
2. **Flash** it to an SD card (16 GB or larger) with
   [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (choose *Use
   custom image*), [balenaEtcher](https://etcher.balena.io/), or `dd`:
   ```bash
   xz -dc mpi-station-vVERSION.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   Replace `/dev/sdX` with your card — double-check it, `dd` is unforgiving.
3. **Boot** the Pi with the MK3 connected. On first boot the image expands to
   fill the card and provisions two data partitions (your Mixxx library and your
   MusicPI samples).
4. **Pick a mode:** wait for the selector on the MK3 screens, then choose
   MixxxDJ or MusicPI.

### First boot

- Default login: **`mpi` / `musicpi`**. Change the password before putting the
  device on an untrusted network.
- Two storage areas are created automatically and grow to fill the card:
  `MIXXX_LIBRARY` → `/home/mpi/Music`, and `MPI_SAMPLES` →
  `/home/mpi/maschinepi/samples` (ready for your own samples).

## What this repository is

This repository is MusicPI's **integrator / delivery** repo. It owns what
neither application repo should: the mutually exclusive systemd mode targets, the
`mk3-mode-selector`, the fused image build, and update policy. A
release is a reproducible combination of three pinned submodules.

| Path | Owns |
|---|---|
| `external/libmk3` | Shared C MK3 driver — single source of truth |
| `external/mixxx-mk3` | Mixxx mapping, screen daemon, and runtime helpers |
| `external/maschinepi-te` | MusicPI DAW and Pi image tooling |
| `image/` | Fused Raspberry Pi OS Lite image build |
| `systemd/` | Mode targets and selector service |
| `mode-selector/` | `mk3-mode-selector` binary |
| `ota/` | Update security policy and OTA backlog |
| `config/` | Mode config store |
| `docs/specs/` | Authoritative design |

## Roadmap

- **Release candidate:** publish the four Music PI repositories, verify their
  documentation and pins, and produce a security-checked image candidate.
- **Beta 0.9.1:** fix the MK3 Wi-Fi password entry defects and land the first
  post-RC fixes.
- **Next:** complete repeatable hardware/audio validation and harden OTA.

See the focused [beta blocker list](docs/beta-blocker-triage.md) for detail.

## Build the image yourself (developers)

```bash
git -c url.https://github.com/.insteadOf=git@github.com: clone --recursive \
  https://github.com/music-pi/music-pi.git
cd music-pi
git submodule update --init --recursive        # if not cloned with --recursive
./scripts/check-submodules.sh
```

Component repositories: [MusicPI DAW](https://github.com/music-pi/daw),
[Mixxx MK3](https://github.com/music-pi/mixxx-mk3), and
[libmk3](https://github.com/music-pi/libmk3).

Build a fused image from a stock Raspberry Pi OS Lite (arm64) base. All
compilation, package installation, and provisioning happen on the host (inside
the `pi-gen` helper container — no host `sudo` needed for the mount step):

```bash
./image/build-image.sh --base /path/to/raspios-lite-arm64.img.xz --mixxx-deb /path/to/mixxx-arm64.deb --compress
```

Required: `--mixxx-deb` supplies the pinned ARM64 Mixxx package from a verified
release asset. Useful flags: `--maschinepi-binary /path/to/arm64/maschinepi`
reuses an existing ARM64 build; `--password-file` securely sets the injected
login; `--data-bootstrap-mb` sizes
the pre-boot data partitions. See [`image/README.md`](image/README.md) for the
full pipeline and [`docs/hardware-test.md`](docs/hardware-test.md) for on-device
validation.

Host-side checks:

```bash
./tests/test-systemd-modes.sh
./tests/test-install-rootfs.sh
./tests/test-mode-selector.sh
```

## Releases & updates

Each submodule is pinned to a specific commit; a release bumps the tested pins
together and tags them here. Current devices update from a checksum-verified
image; OTA remains security-sensitive backlog. See
[`ota/README.md`](ota/README.md).

## Contributing

Read [AGENTS.md](AGENTS.md) and the design spec in `docs/specs/` before working
here. The driver (`external/libmk3`) is canonical
libmk3 — never edit a vendored copy; changes
go upstream and are pulled in by bumping the pin.

## License

Copyright (C) 2026 Sebastian Hines.

The mpi-station tooling (image builder, mode selector, systemd units, and
update-policy files) is released under the **GNU General Public License v3.0** — see
[`LICENSE`](LICENSE).

The **flashable image** it produces is a *mere aggregation* of separately
licensed works, each retaining its own license: Raspberry Pi OS, MixxxDJ
(GPLv2+), MusicPI (GPLv3), the libmk3
driver (MIT), and vendor firmware. Bundling them on one SD card does not
relicense any of them. GPL permits redistribution and does not prevent accepting
donations.
