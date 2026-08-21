# Beta-blocker triage

Classifies every finding from the two hardening plans against a **beta** bar
(testers, not GA). This drives Phase 0 of [RELEASING.md](../RELEASING.md) and the
release notes' known-issues section.

Source plans:
- `maschinepi-te` → `docs/superpowers/plans/2026-07-22-beta-rc-hardening.md`
- `mixxx-mk3` → `docs/superpowers/plans/2026-07-22-beta-rc-hardening.md`

**Bar for MUST-FIX (beta):** loss/corruption of user work, crashes on common
paths, or security exposure that ships on the device. Everything recoverable and
documentable can ship as a **KNOWN ISSUE**. Polish and future-proofing is
**POST-BETA**.

---

## MusicPI (mpi-te)

| Task | Finding | Sev | Verdict | Rationale |
|---|---|---|---|---|
| T1 | Non-atomic `.mpi` save; interrupted write destroys the project | crit | **MUST-FIX** | Data loss on SD-card-full/power-loss during long sessions — the worst beta experience. Non-negotiable. |
| T4/T5/T6 | Undo of load/slice silently corrupts round-robin/gain; some live edits push orphan undo transactions | crit (cluster) | **MUST-FIX** | Undo is a headline feature; silently reverting the *wrong* thing or corrupting a pad on a common action is unacceptable. The deep multi-layer RR edge can be staged, but the common-case undo must be correct. |
| T9 | Widgets cache raw Tracktion pointers → use-after-free on project load | crit | **MUST-FIX** | Crash on a happy path (loading a project) — testers do this constantly. |
| T3 | Arpeggiator reads `track_` unlocked on timer thread → race/UAF | high | **MUST-FIX** | Crash on a routine action (switch instrument slot / unplug while latched). Two-line fix. |
| T13a | yt-dlp args lack `--` terminator | low | **MUST-FIX (cheap)** | One-line security hardening; fold in. |
| T10 | Single global display-dirty flag → both panels repaint at 60 Hz | high (perf) | **RECOMMENDED** | Biggest recurring Pi CPU cost; affects "feel" and can contribute to glitches under UI load. Do if time; else known-issue. |
| T8 | Mixer/step knob edits bypass undo (non-uniform coverage) | high | **KNOWN ISSUE** | UX gap, not a crash or data loss. Document "undo doesn't yet cover mixer gain/pan/step-velocity." |
| T12 | Sample-index cache parsed synchronously at startup | med | **KNOWN ISSUE** | Slow first paint with a large library. Documentable. |
| T2 | Teardown ordering duplicated in dtor + shutdown | high | **POST-BETA** | Both copies are currently *correct* — this is future-regression prevention, not a live bug. |
| T7 | Enforce Raw contract with asserts | high | **POST-BETA** | Debug-only guardrail; do it alongside T4 if convenient. |
| T11 | `getPadsSnapshot` allocates per frame | med (perf) | **POST-BETA** | Minor per-frame churn. |
| T13b/c | argv-safe spawn, aligned capture buffer | low | **POST-BETA** | Latent/robustness only. |

## MixxxDJ (mixxx-mk3)

| Task | Finding | Sev | Verdict | Rationale |
|---|---|---|---|---|
| T1 | Clean checkout fails to configure (uncommitted CMake + untracked mk1) | crit | **MUST-FIX** | The release image is built from pinned commits; the build must succeed. Also Phase 1's clean-clone gate. |
| T2 | Overlay input double-dispatches into live decks | crit | **MUST-FIX** | In a DJ set, overlay button presses also firing sync/load on live decks is a show-stopper. Note this is real design work (needs a signaling channel) — if it can't land, **fallback: disable the settings overlay for beta**. |
| T3 | Any daemon touching LEDs blanks Mixxx's LEDs every session | high | **MUST-FIX (or mitigate)** | Dark deck/cue LEDs mid-set in a dark venue, every mouse-mode use — degrades core usability. If not fixed, document + tell testers to avoid mouse mode. |
| T7 | Boot-time unauthenticated git-pull → root RCE | crit (deprecated) | **MUST-VERIFY-ABSENT** | Owned by mpi-station now. Not fixed in-repo — instead **confirm the beta image does not install `mk3-check-update.sh` / `mk3-update.sh` or the boot `ExecStartPre`.** Gate this in the image build. |
| T4 | Screen daemon freezes on Xvfb restart | high | **RECOMMENDED** | X doesn't restart in normal appliance use; if it does, screens freeze until daemon restart. Cheap fix; else known-issue with a recovery note. |
| T5 | Stale `/tmp` flag wedges T9/mouse input after an overlay crash | high | **RECOMMENDED** | Cheap pid-stamp fix. Else known-issue: "if the controller stops responding, reboot." |
| T6 | Mouse daemon forks xdotool per HID report | med-high | **KNOWN ISSUE** | Only in mouse mode (not during beatmixing). Document; fix if time. |
| T8 | JS globals namespacing + skip identical frames | med | **POST-BETA** | Hygiene + perf; globals fix is cheap and can ride along. |

## MusicPI Station (mode selector)

| Task | Finding | Sev | Verdict | Rationale |
|---|---|---|---|---|
| S1 | Wi-Fi credential entry: reveal/hide, digit `1`, and distinct lowercase/uppercase/symbol layers | high | **FIXED; HARDWARE VERIFIED** | D7 hold-to-reveal remasks on release; pad 1 enters `1`; exact case and supported symbols render distinctly. Host regression tests pass and the flow connected successfully on the Raspberry Pi 4 + MK3 rig. |

---

## The beta gate (minimum must-fix set)

**MusicPI:** T1 (atomic save), T3 (arp race), T4/5/6 (undo correctness),
T9 (widget UAF), T13a (yt-dlp `--`).

**MixxxDJ:** T1 (clean build), T2 (overlay dispatch — or disable overlay),
T3 (LED blanking — or mitigate), T7 (verify RCE scripts absent from the image).

**MusicPI Station:** no remaining must-fix item from this triage; S1 is fixed and
hardware-verified.

**Strongly recommended if the schedule allows** (each downgrades to a documented
known-issue otherwise): mpi-te T10; mixxx-mk3 T4, T5.

## Known issues to document in the beta release notes

- MusicPI: undo does not yet cover mixer gain/pan/step-velocity (T8);
  slow first launch with very large sample libraries (T12).
- MixxxDJ (any of T4/T5/T6 not fixed): screens may freeze if the desktop
  session restarts — restart the screen daemon / reboot to recover; mouse mode
  is CPU-heavy and best avoided during a live set.

## Post-beta backlog (out of scope for this release)

- MusicPI: `SamplerInstrument` decomposition; song/arranger undo + ValueTree
  migration; teardown/Raw-contract hardening (T2, T7); snapshot/perf polish.
- MixxxDJ: a single HID/LED owner or the move to Mixxx's QML controller-screen
  system (which retires much of the daemon stack); HID protocol-table
  consolidation; extracting the in-tree mk1 driver to its own repo.
