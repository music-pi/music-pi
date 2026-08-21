# Getting started with MusicPI

MusicPI (MPI) turns a Raspberry Pi and a Native Instruments Maschine MK3 into a
standalone music machine. One device, two modes, chosen at boot:

- **MusicPI** — a headless Tracktion-based DAW / groovebox.
- **MixxxDJ** — the Mixxx DJ software with full MK3 control.

You don't need a monitor, mouse, or keyboard for normal use — everything runs on
the MK3's screens, pads, and knobs. This guide takes you from an SD card to
making sound.

## What you need

| Item | Notes |
|---|---|
| Raspberry Pi 4 | 4 GB or 8 GB recommended |
| Native Instruments Maschine MK3 | the controller MPI is built for |
| microSD card | 16 GB or larger (32 GB+ if you want a big sample/music library) |
| USB cable | to connect the MK3 to the Pi |
| Power supply | an official Pi 4 USB-C supply; the MK3 also needs its own power |
| Audio output | headphones or speakers via the Pi's output or a USB audio interface |
| A computer | to flash the SD card (Windows, macOS, or Linux) |
| A keyboard | optional — only for first-time setup or advanced changes |

## 1. Get the image

Download the latest `mpi-station-*.img.xz` and its `.sha256` from the
[Releases page](https://github.com/music-pi/music-pi/releases/).

## 2. Flash the SD card

Using Raspberry Pi Imager (recommended): select the MusicPI image (or *Use
custom image* → the `.img.xz` you downloaded), choose your SD card, and write.

Prefer the command line? On Linux/macOS:

```bash
xz -dc mpi-station-vVERSION.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your card device — **double-check it**, `dd` will
happily overwrite the wrong disk.

Verify the download first if a `.sha256` is provided:

```bash
sha256sum -c mpi-station-vVERSION.img.xz.sha256
```

## 3. First boot

1. Insert the SD card, connect the MK3 to the Pi over USB, and power both on.
2. The first boot takes a few minutes: MusicPI expands to fill your card and
   sets up two storage areas — one for your **Mixxx music library**, one for
   your **MPI samples** (preloaded with a starter set). This only happens once.
3. When it settles, the MK3 screens light up and you're ready.

**Default login** (if you connect a keyboard/SSH): `mpi` / `musicpi`. Change
the password before putting the device on a network you don't trust.

## 4. Choose your mode

The mode selector appears automatically on the MK3 screens once the controller
has attached. Choose:

- **MusicPI** — make beats and arrangements.
- **MixxxDJ** — mix and perform with tracks.

To switch later, reboot to return to the selector. The two modes are separate —
only one runs at a time, so each gets the full machine.

## 5. First sounds

### In MusicPI (DAW) mode
- The 16 pads trigger sounds. Hit them — the starter samples are already loaded.
- Load your own sample to a pad from the browser, then play and sequence it.
- Press **Play** to run the pattern; the pads step through your sequence.

See the [MusicPI DAW repository](https://github.com/music-pi/daw) for feature
documentation.

### In MixxxDJ mode
- The MK3 screens mirror Mixxx's decks.
- Load a track to a deck, use the pads for hotcues/loops, and the knobs for EQ
  and filters.
- Beatmatch and mix as you would in Mixxx — the MK3 is your controller.

See the [Mixxx MK3 repository](https://github.com/music-pi/mixxx-mk3) for
controller-specific documentation.

## Adding your own music and samples

Two storage areas were created on the card and grow to fill it:

- **`MIXXX_LIBRARY`** → your Mixxx tracks (mounted at `/home/mpi/Music`).
- **`MPI_SAMPLES`** → your MPI samples (mounted at
  `/home/mpi/maschinepi/samples`).

Copy files there over the network or by mounting the card on your computer. In
MixxxDJ, rescan your library to see new tracks; in MusicPI, new samples appear
in the browser.

## Updating

Grab the latest image from the [Releases page](https://github.com/music-pi/music-pi/releases)
and re-flash, or use the built-in update flow if your release includes it.
Your data partitions (library and samples) are separate from the system, so a
re-flash keeps your content — but back up anything important first.

## Troubleshooting

| Symptom | Try |
|---|---|
| MK3 screens stay dark | Check the USB cable and that the MK3 has its own power; reboot with both connected. |
| No sound | Confirm your output (headphones/speakers/USB interface) is connected before boot; check the volume. |
| Mode selector doesn't appear | Check that the MK3 has power and USB, then allow a moment for it to attach; try again from a full power cycle. |
| Controller stops responding | Reboot. If it persists, note what you were doing and file an issue. |
| First boot seems stuck | The one-time storage setup can take several minutes on large cards — give it time before power-cycling. |

## About the name

MusicPI began as **MaschinePI** — Maschine + Raspberry Pi — born from a single
idea: to unleash the Native Instruments Maschine MK3 beyond the box it shipped
in. The MK3 is a gorgeous instrument, and this project is a homage to it —
freeing its pads, screens, and knobs to stand on their own as a portable
performance platform that needs no laptop. As the project grew past a single
Maschine app into a whole music machine, the name grew with it: the letters
stayed (**MPI**), but the M now stands for **Music**.

## Getting help & the projects behind MusicPI

MusicPI is open source. The pieces:

- **[music-pi/music-pi](https://github.com/music-pi/music-pi)** — image, releases, and docs.
- **[music-pi/daw](https://github.com/music-pi/daw)** — MusicPI DAW (Tracktion Engine).
- **[music-pi/mixxx-mk3](https://github.com/music-pi/mixxx-mk3)** — MixxxDJ integration.
- **[music-pi/libmk3](https://github.com/music-pi/libmk3)** — shared MK3 hardware driver.

Found a bug or have an idea? Open an issue on the relevant repo. If you'd like to
support the work, see the sponsor links on the project pages.
