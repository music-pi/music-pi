---
title: MusicPI
---

# MusicPI

Turn a Raspberry Pi 4 and Native Instruments Maschine MK3 into a standalone
music machine. Choose the MusicPI DAW or MixxxDJ from the MK3 at boot.

## First steps

1. Download the newest image and checksum from the
   [MusicPI releases](https://github.com/music-pi/music-pi/releases).
2. Verify the checksum, then flash the compressed image with Raspberry Pi
   Imager or balenaEtcher.
3. Connect and power the MK3, insert the card, and boot the Pi.
4. Choose **MusicPI** or **MixxxDJ** on the MK3 screens.

The default Linux login is `mpi` / `musicpi`. Change it before using an
untrusted network.

Read the full [getting-started guide](getting-started.md) for flashing,
first boot, storage, updates, and troubleshooting.

## Project links

- [MusicPI image and releases](https://github.com/music-pi/music-pi)
- [MusicPI DAW](https://github.com/music-pi/daw)
- [Mixxx MK3 integration](https://github.com/music-pi/mixxx-mk3)
- [Shared libmk3 driver](https://github.com/music-pi/libmk3)
