# systemd/ — mode targets and selector service (Phase 3)

The implemented integrator-owned units make the two modes mutually exclusive
and boot the selector first:

- `maschinepi.target` — pulls in the MusicPI DAW stack; `Conflicts=mixxx.target`.
- `mixxx.target` — pulls in Xvfb/Openbox/Mixxx/screen-daemon; `Conflicts=maschinepi.target`.
- `mode-selector.target` — the default boot target; starts `mk3-mode-selector.service`.
- `mk3-mode-selector.service` — opens the on-device menu on every boot and waits
  without a timeout for a cold MK3 to enumerate. It also starts NetworkManager
  so the selector can scan and save system-wide Wi-Fi profiles before a mode is
  launched.

Switching is `systemctl isolate <target>` — no reboot. The system default is
`mode-selector.target`; neither app's own auto-start is enabled (the target owns
start-up). Clean teardown on `isolate` (release MK3 + audio before the other mode
claims them) is validated here via `Conflicts=` and explicit ordering.

Every mode-owned service has `PartOf=` its target. This is essential: stopping a
target on `isolate` then stops its complete service stack and releases MK3/audio.

For SSH testing on the Pi:

```bash
sudo mpi-mode-switch mixxx
sudo mpi-mode-switch maschinepi
sudo mpi-mode-switch selector
sudo mpi-mode-switch --set-default mixxx
```

See `docs/hardware-test.md`.
