# MK3 Dual-Mode (Shared-Base) — Design

- **Date:** 2026-07-21
- **Status:** Approved (pending written-spec review)
- **Author:** Sebastian Hines
- **Scope:** Run both the MusicPI DAW and the MixxxDJ system on one Raspberry Pi 4, selectable from the MK3 controller, without dual-booting.

## Goal

Let a single Pi 4 + MK3 rig run either system:

- **MusicPI** — headless DAW (JUCE/Tracktion), C++ MK3 driver renders directly to the two MK3 screens.
- **MixxxDJ** — Mixxx 2.6 (Qt6) rendered into a virtual X display and mirrored to the MK3 screens.

Selection happens on the MK3 itself: normal power-on waits for the controller and brings up an on-screen menu to choose the mode. The stored default determines the initial highlight. Switching modes must not require re-flashing and should be as fast as possible.

The build and the mode/OTA machinery live in a **separate integrator repo** that consumes `libmk3`, `mixxx-mk3`, and `maschinepi-te` as git submodules and produces the flashable image. The existing Mixxx **git-based OTA** (in-place `git pull` updates, no reflash) must be preserved and generalized to both modes.

## Background: what the two systems actually are

Both are **stock Raspberry Pi OS Lite (arm64)** workloads that differ only in userspace services. Neither needs a custom kernel, and — critically — neither needs any boot-time (`config.txt`/kernel/dtoverlay) divergence.

### MusicPI (this repo)
- Built as a pi-gen image via `pi-tools/` / `scripts/gen-img.sh`.
- Runs headless: `maschinepi.service` (systemd) drives the MK3 via a C++ USB driver that renders directly to the screens.
- Realtime audio via PipeWire; RT tuning is all runtime (`sysctl` swappiness/dirty-ratios, RT priorities, `performance` CPU governor) — see `pi-tools/README.md`.

### MixxxDJ (`~/dev/mixxx-mk3`)
- **Not** an image — a provisioning script (`pi-setup/mk3-pi-setup.sh`) that apt-installs onto stock RPi OS Lite and enables a bundle of services.
- Runtime chain: **Xvfb** (virtual software X display, 960×544) → **Openbox** (fullscreen, no decorations) → **Mixxx (Qt6)** fullscreen. A C daemon **`mk3-screen-daemon`** captures the X framebuffer and mirrors it to the two MK3 screens. Mixxx reads the MK3 via its own HID mapping + `libmk3` (C). Python daemons add mouse/T9/overlay input.
- Audio: **PipeWire + WirePlumber** (user services, lingering enabled), `pipewire-jack`. Mixxx master out = "Maschine MK3 Analog Surround 4.0" (MK3 USB audio), cue/headphone = "Built-in Audio Stereo" (Pi 3.5mm jack), 48kHz.
- Extras: Tailscale, SMB/CIFS NAS music mount, MK3 boot splash, OTA update scripts.

### Shared vs. divergent

| Layer | Shared? |
|---|---|
| Kernel, `config.txt`, boot chain | **Shared** — identical (`dtparam=audio=on` covers the Pi jack; Xvfb needs no GPU/HDMI/KMS) |
| Audio stack (PipeWire/WirePlumber) | **Shared** — same components; only routing/quantum differ (runtime) |
| MK3 USB device (`17cc:1600`), udev | **Shared** — one device, claimed by whichever mode is active |
| App + UI stack | **Divergent** — headless C++ driver vs. Xvfb+Openbox+Qt+screen-daemon+Python; mutually exclusive at runtime |

Because Mixxx renders into **Xvfb**, it needs no HDMI/GPU/KMS — so there is **zero boot-time reason** to keep the systems on separate OSes.

## Decision: shared-base, not dual-boot

Install **both** bundles onto **one** RPi OS Lite rootfs and gate each behind a systemd target. Switching modes is a `systemctl isolate`, not a reboot.

### Rejected alternative: true dual-boot (`tryboot` + selector)
A 6-partition card with two isolated OS images and an MK3 boot-menu selector chainloading via the Pi firmware's `tryboot`/`autoboot.txt`. Rejected because:
- The two systems share kernel, `config.txt`, and audio stack — there is nothing to isolate at boot.
- The Mixxx side is a provisioning script, not an image; "fusing" is just running two provisioners into one rootfs, not merging two image pipelines.
- Dual-boot costs a bespoke MK3 bootloader, partition/`tryboot` plumbing, a duplicated base OS, doubled updates, and a full reboot per switch — for isolation we do not need.

Dual-boot remains a fallback only if hard hermetic isolation between the two OSes ever becomes a hard requirement (not currently the case).

### Rejected alternative: OverlayFS shared-RO base + per-mode overlay
Dedupes the base but adds real build complexity (apt-on-overlay, RO base upkeep) for a two-mode rig. YAGNI.

## Architecture

### Systemd targets
Two mutually exclusive targets, each `Conflicts=` the other so `isolate` cleanly tears down the previous mode.

- **`maschinepi.target`**
  - `Wants`: `maschinepi.service`, the PipeWire user stack (DAW audio profile).
  - Does **not** start Xvfb/Openbox/Mixxx/screen-daemon.
- **`mixxx.target`**
  - `Wants`: `xvfb.service`, `openbox.service`, `mixxx.service`, `mk3-screen-daemon.service`, `mk3-t9-daemon.service`, `mk3-mouse-daemon.service`, `mk3-overlay.service`, `mk3-bootsplash.service`, NAS mount, PipeWire user stack (DJ audio profile).
  - Does **not** start `maschinepi.service`.

The system default target is **`mode-selector.target`** (see below), which decides which mode target to isolate into.

### Boot flow (no reboot to switch)
1. Base boots to a minimal `mode-selector.target` after local filesystems are ready.
2. `mk3-mode-selector` (oneshot service) retries USB initialization until the MK3 is available; this deliberately accommodates cold controller startup.
3. Render the menu on the MK3 screens with the stored `default_mode` highlighted, then wait without a timeout.
4. On selection, release the MK3 and `systemctl isolate <target>`.
5. Runtime re-selection: a "switch mode" action available from within either app (and re-invocable by re-running the selector) isolates the other target — still no reboot.

### Mode selector UX (MK3)
The menu is drawn on every boot and has no auto-timeout.

- **4D encoder turn** → move highlight; **push** → activate highlighted mode.
- **D1–D8** → direct "activate mode N" keys (F1–F8 style). D1 = MusicPI, D2 = Mixxx; remaining slots reserved for future modes.
- **Set-as-default action** (e.g. hold-encoder) → writes `default_mode` to the config store.
- Optional **Shutdown** / **re-open-selector** actions.
- Keyboard arrows, number keys, Enter, and D provide a bench-testing fallback.

On a fresh card, storage preparation owns the MK3 first when available and shows
coarse but truthful milestones for partition resizing, both formats, starter
sample copying, and final sync. The Pi ACT LED simultaneously repeats three
short flashes. Storage preparation continues if no MK3 is attached; the selector
then waits for it normally.

**Visual language (base mockup provided 2026-07-21).** The selector/loader adopts the existing MusicPI boot-splash style (`pi-tools/mk3-boot-display.c`): dark background, single orange accent, monospace type, using both 480×272 screens:
- **Left screen** = identity: logo / waveform motif and a bottom **status line** (e.g. `Booting … | Initializing system | Starting audio engine : 3.0`).
- **Right screen** = progress: a `LOADING <MODE>` label, orange progress bar, and percentage.

**Decision: per-mode branding, no separate "station" identity.** The selector is invisible chrome that wears whichever mode's brand is relevant — it reuses the two splashes that already exist rather than inventing a third integrator brand. Applied:
- **Boot menu** → the left screen mirrors the **highlighted mode's** identity/brand (swapping as you scroll); the right screen shows the selectable mode list + progress once a mode is activating.
- The **update-available notification** lives in the left-screen status line (and/or a small badge), matching this style — never a foreign dialog.

Mockup asset should live in the integrator repo (e.g. `assets/`) alongside the per-mode splashes.

**Update-available notification (in the selector/loader).** The selector owns the MK3 at boot before either app starts, so it is the right place to surface OTA status — independent of X/mode:
- On boot the selector runs a lightweight `git fetch`/behind-count check per mode (cached/time-boxed so it never blocks the fast default-boot path; skip gracefully when offline).
- If an update is available it shows a **non-blocking notification** — e.g. a badge/line on the MK3 screen even during the invisible fast-path, and a menu entry when the Shift menu is open.
- From the menu, an **"Update now"** action runs that mode's `update` entrypoint (see OTA section) and then continues into the mode. Rendering/input use the selector's own MK3 backend, so this works headless too — replacing Mixxx's X/zenity-only prompt as the unified path.

### MK3 device ownership
Only one mode is ever active, so only one consumer claims the MK3 USB interfaces at a time:
- MusicPI mode → MusicPI's C++ driver owns HID (iface 4) + display (iface 5).
- Mixxx mode → Mixxx/`libmk3` + `mk3-screen-daemon` own them.
- The selector releases the MK3 before isolating a mode. No simultaneous-claim contention.

### Audio profiles
Both modes use the same PipeWire/WirePlumber install; each mode applies its own profile at activation:
- MusicPI: DAW quantum/latency + RT priorities + `performance` governor.
- Mixxx: JACK-API routing (master → MK3 USB audio, cue → Pi jack), 48kHz.
Profiles are applied by the target's units on isolate, and torn down by `Conflicts=` when switching away.

### Data isolation ("two homes")
**Decision: a single Linux user with two data dirs** (not a dedicated user per mode). Each system keeps its own state under that one home:
- Mixxx: `~/.mixxx` (config, DB, mappings, skin), `~/Music` + NAS mount.
- MusicPI: its `.mpi` project tree / app data dir.

Rationale: one user means one PipeWire instance / one `/run/user/UID` / one lingering user (which the Mixxx provisioner already assumes), and minimal `chown`/`User=`/runtime-dir patching in the provisioners and OTA scripts — keeping the systemd-target and OTA machinery (the design's trickiest area) boring. Isolation is logical (separate data dirs, no shared mutable state between modes), not enforced by filesystem permissions. A dedicated-user-per-mode model was considered and rejected: its hard privilege separation is a nice-to-have on a single-purpose rig but would add two user sessions, per-mode ownership handling, and more awkward `isolate` semantics to the central mechanism.

### Config store
A single small file (e.g. `/var/lib/mk3-mode/config`) holds:
- `default_mode` (target name).
- A slot table mapping menu slot → target name → display label, so adding a third mode is a table row, not code.
The selector reads it at boot and the "set default" action writes it.

## Delivery: integrator repo + submodules

Once this design is planned, the implementation lives in a **new dedicated integrator repo** (working name `mpi-station`), separate from both app repos. It owns the fused image build and the mode/OTA machinery, and pulls the app code in as **git submodules**:

- `libmk3` — the C MK3 library (shared USB HID/display/LED primitives).
- `mixxx-mk3` — the Mixxx provisioning + screen-daemon + mappings/skin.
- `maschinepi-te` — this repo (DAW app + `pi-tools`).

The integrator repo contains: the two systemd targets, `mode-selector.target`, the `mk3-mode-selector` binary, the fused-image build script, and the generalized OTA tooling. The app repos stay independently developable; the integrator bumps submodule refs to compose a release.

**Migration note:** the mode-switching + selector code being prototyped in `maschinepi-te` should be **migrated into the integrator repo** once planned — it is not long-term MusicPI-app code.

### libmk3 unification & cleanup (foundational — prerequisite)

The "one shared `libmk3` submodule" premise only works if there is genuinely one libmk3. Today there are two:

- **`maschinepi-te`** consumes libmk3 as a **git submodule** (`external/mk3` → `https://github.com/music-pi/libmk3.git`) — the canonical repo, and per the maintainer the **newest** version. A C++ app layer (`src/control/Mk3Controller`, `src/devices/Mk3Device`) and parity tests (`Mk3DisplayParityTests`, `Mk3HidMapParityTests`, `Mk3InputReportParityTests`) sit on top and stay in the app repo.
- **`mixxx-mk3`** carries a **stale vendored copy** of libmk3 in `external/mk3` (no `.gitmodules` — pasted source), consumed by its screen-daemon, `mk3_cli`, and Mixxx HID path.

**Unification work (do this first):**
1. Canonicalize on **`music-pi/libmk3`** at the DAW's newest ref as the single source of truth.
2. **Audit the drift** between Mixxx's vendored copy and canonical libmk3 — port any Mixxx-only fixes/workarounds that aren't upstream (e.g. the partial-display-rendering workaround `mk3_display_disable_partial_rendering`, any input/output-map deltas) **into** `music-pi/libmk3`, so nothing regresses when Mixxx switches over. The parity tests in the DAW are the reference for correct maps.
3. Convert `mixxx-mk3/external/mk3` from a vendored copy to a **submodule** of `music-pi/libmk3` (or have the integrator provide libmk3 and Mixxx build against it), removing the duplicate source.
4. The integrator repo then references libmk3 **once**; both modes and the `mk3-mode-selector` build against that single submodule.

This is a prerequisite, not deferred cleanup: the selector, both modes' MK3 access, and reproducible builds all depend on a single libmk3.

## OTA updates (no reflash)

The image is a **seed**, not the source of truth: it ships with on-device git checkouts (the integrator repo + its submodules) so both modes update in place via `git pull`, never requiring a reflash. This preserves and generalizes the mechanism Mixxx already has.

**Existing Mixxx OTA (to preserve):**
- `mk3-update.sh` — `git pull --ff-only origin master` on the on-device checkout, then re-copy mappings/skins, re-patch + reinstall systemd units, **rebuild `mk3-screen-daemon`/`mk3_cli` only if their source changed**, re-extract bootsplash frames, `daemon-reload`, restart Mixxx.
- `mk3-check-update.sh` — pre-boot prompt via `mixxx.service` `ExecStartPre`: fetches, and if behind shows a zenity dialog **on the MK3 left screen** (Xvfb + xdotool), PLAY/STOP mapped to Enter/Escape by a Python button reader, 30s auto-skip.

**Generalization for dual-mode:**
1. OTA pulls the **integrator** repo (advancing its pinned submodules together), then runs each mode's idempotent **re-provision** entrypoint: rebuild-if-changed, reinstall units/binary, restart its service. Mixxx already has such an entrypoint (`mk3-update.sh`); MusicPI needs an equivalent — it currently ships a pi-gen-baked binary with no OTA path, so an on-device build-or-fetch update path is **new required work**. (Per the pinned policy, components do not each track their own branch; the integrator bump is the unit of update.)
2. The pre-boot update prompt must work in **both** modes. Mixxx's version depends on Xvfb + zenity, which only exists in Mixxx mode. In MusicPI mode (headless, no X), the prompt must render via the C++ MK3 driver / `libmk3` instead. Factor the "check + prompt + apply" flow so the render/input backend is swappable per mode.
3. The `mode-selector` hosts the update check and **surfaces an "update available" notification** (it already owns the MK3 at boot and reads Shift), so the indicator + optional prompt appear before either mode's app starts, independent of X. This is the unified replacement for Mixxx's X/zenity-only `ExecStartPre` prompt. The check must be non-blocking on the fast default-boot path (time-boxed, offline-tolerant).

**Decision: submodule update policy = pinned refs bumped by integrator release.** Each submodule (`libmk3`, `mixxx-mk3`, `maschinepi-te`) is pinned to a specific commit; a release is composed by the integrator bumping those refs and tagging. On-device OTA therefore pulls the **integrator** repo (which advances the pinned submodules together), rather than each component tracking its own branch. Rationale: reproducible, known-good combinations across both modes — essential while libmk3 drift is being reconciled and so a Mixxx change can never silently pull an untested libmk3 under MusicPI. (Per-component branch tracking is rejected; a "track latest" dev override may be added later if needed, but is not the shipping default.)

## Build / packaging

Produce **one** fused RPi OS Lite image from the integrator repo:
1. Extend the existing MusicPI pi-gen stage (`pi-tools/`) as the base, OR run the MusicPI install into a stock RPi OS Lite rootfs.
2. Run the Mixxx provisioner (`mk3-pi-setup.sh`, adapted for non-interactive/chroot use: skip interactive Tailscale/SMB prompts, parameterize user/paths) into the same rootfs.
3. Place the on-device git checkouts (integrator repo + submodules) so OTA `git pull` works post-flash.
4. Install the new units: `maschinepi.target`, `mixxx.target`, `mode-selector.target`, `mk3-mode-selector.service`, and the `mk3-mode-selector` binary.
5. Set the system default target to `mode-selector.target`; do **not** auto-enable either app's own auto-start (the target owns start-up).
6. Reconcile shared components installed by both provisioners (PipeWire config, udev `99-mk3` rules, boot splash) so the last-writer is intentional, not accidental.

The `mk3-mode-selector` binary builds against the unified `libmk3` submodule (C) for MK3 render/input, plus evdev keyboard read, and issues `systemctl isolate`. Building on libmk3 directly (rather than MusicPI's JUCE C++ layer) keeps the selector small and mode-agnostic.

## Risks & validations

1. **Shared-component collisions.** Both provisioners touch PipeWire config, `99-mk3` udev rules, and boot splash. Validate that the fused image ends with one coherent set (test both modes' audio + MK3 access after a clean build).
2. **PipeWire model mismatch.** Mixxx enables PipeWire as a **user** service with lingering; MusicPI's tuning may assume system-level. Pick one model (user-level with lingering is the Mixxx assumption) and make both modes' profiles work under it.
3. **MK3 enumeration timing** — the selector must keep retrying through cold USB bring-up without delaying first-boot storage preparation indefinitely when the controller is absent.
4. **Clean teardown on isolate.** Switching from Mixxx must fully stop Xvfb/Openbox/Mixxx/screen-daemon and release the MK3 + audio device before MusicPI claims them (and vice-versa). Verify via `Conflicts=` + explicit device-release ordering.
5. **Image size / surface.** One rootfs now carries Qt/X/Mixxx/Python/Tailscale/Samba *and* JUCE/Tracktion. Acceptable (dormant services have no RT impact) but note the larger update surface.

## Testing

- Boot with a cold MK3 → selector waits for enumeration and renders the menu.
- Encoder + D1/D2 select each mode; "set default" persists the initial highlight across reboot.
- First boot → ACT LED and, when attached, MK3 screens report storage preparation; partitions receive equal shares of the card remainder.
- Switch MusicPI → Mixxx and back → audio routing correct each time (master on MK3, cue on Pi jack for Mixxx; DAW profile for MusicPI), MK3 owned by exactly one consumer.
- Verify no reboot occurs on switch and prior mode's services are fully stopped.

## Out of scope / deferred

- OverlayFS/dedup of the base rootfs.
- True dual-boot (`tryboot`) fallback — documented above, not built.
- More than two modes (the slot table supports it; no third mode planned yet).

## In scope but sequenced after core planning

- **Integrator repo migration** — stand up the `mpi-station` repo with the three submodules and move the mode-selector/target/OTA code into it. Prototyping may begin in `maschinepi-te`, but the code's home is the integrator repo.
- **MusicPI OTA path** — MusicPI ships a pi-gen-baked binary today with no in-place update; give it a Mixxx-equivalent `update` entrypoint (pull → rebuild/fetch → reinstall → restart) so both modes update without reflash.
- **X-independent update prompt** — refactor the pre-boot update check/prompt so its render+input backend is swappable, working headless (C++ driver / `libmk3`) as well as under Xvfb/zenity.

## Resolved defaults (from brainstorming)

- Selector always runs first and always displays the menu once the MK3 attaches.
- No auto-timeout.
- D1–D8 = direct mode-activate keys; D1 = MusicPI, D2 = Mixxx.
- Default is a persisted config value, editable from the menu.
