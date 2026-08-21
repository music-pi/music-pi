# AGENTS.md — contributor guide

This is **music-pi/music-pi**, the integrator / delivery repo for the MusicPI MK3
dual-mode rig: one Raspberry Pi 4 + Native Instruments Maschine MK3 that boots
into **either** the MusicPI DAW **or** MixxxDJ, chosen from the MK3 boot selector.
Start from the [README](README.md).

## What this repo does

It composes three pinned submodules into a single flashable image plus the
switching machinery neither application repo should own:

- `external/libmk3` — shared MK3 driver (single source of truth)
- `external/mixxx-mk3` — MixxxDJ integration
- `external/maschinepi-te` — MusicPI DAW
- `image/` — fused Raspberry Pi OS Lite image build (+ `image/os-list/` for the
  Raspberry Pi Imager integration)
- `systemd/`, `mode-selector/` — the mutually exclusive mode targets and selector
- `ota/` — over-the-air update tooling
- `config/` — mode config store

The authoritative design is in `docs/specs/`. The release process is in
[RELEASING.md](RELEASING.md); the beta scope in `docs/beta-blocker-triage.md`.

## Ground rules

- **Never mutate the application repos in-tree.** `libmk3`, `mixxx-mk3`, and
  `maschinepi-te` are referenced by commit via submodules. Changes go upstream
  and are pulled in by bumping the pin — never edit a vendored submodule tree.
- **Pinning policy:** submodules are pinned to specific commits and bumped
  together as a release. Do not set them to track branches. OTA advances the
  pinned set as a unit so every device runs a known-good combination.
- **Always clone/update with `--recursive`** — `mixxx-mk3` and `maschinepi-te`
  each nest their own `libmk3` submodule.
- **Releases follow [RELEASING.md](RELEASING.md).** Images are published as
  Release assets (never committed to the repo); each release records the exact
  submodule pins and the image sha256 for reproducibility.

## Build & test

```bash
git -c url.https://github.com/.insteadOf=git@github.com: clone --recursive \
  https://github.com/music-pi/music-pi.git && cd music-pi
./scripts/check-submodules.sh
./image/build-image.sh --base /path/to/raspios-lite-arm64.img.xz --mixxx-deb /path/to/mixxx-arm64.deb --compress
./tests/test-systemd-modes.sh && ./tests/test-install-rootfs.sh && ./tests/test-mode-selector.sh
```
