# Releasing MPI-Station

This is the runbook for cutting a release of the MK3 dual-mode appliance. A
release is a **reproducible set of pinned submodules** plus a **hosted flashable
image** and its Raspberry Pi Imager `os_list`. Follow the phases in order;
each has a verification gate before the next.

The component repos are:

| Repo | Role | License |
|---|---|---|
| libmk3 | Shared MK3 driver | MIT |
| daw (MusicPI DAW) | MusicPI DAW | GPLv3 |
| mixxx-mk3 (MixxxDJ) | MixxxDJ integration | GPLv2-or-later |
| music-pi (this repo) | Integrator / image / update policy | GPLv3 |

## Versioning

- **mpi-station** carries the release tag: `vMAJOR.MINOR.PATCH` (beta uses a
  suffix, e.g. `v0.9.0-beta.2`).
- Component repos are tagged with their own version at the commit mpi-station
  pins. The release image is version-stamped:
  `mpi-station-vMAJOR.MINOR.PATCH[-PRERELEASE].img.xz`.
- A release is defined entirely by the submodule commit pins recorded in this
  repo at the tag. Current updates use the verified release image.

---

## Phase 0 — Pre-release finalization gate

- [ ] The finalization PR (licensing, README/AGENTS, funding, SPDX headers) is
      merged in every component repo.
- [ ] `.gitmodules` submodule URLs are **HTTPS** (`https://github.com/music-pi/...`)
      in this repo and in mixxx-mk3, so anonymous/CI clones can init them.
- [ ] `LICENSE` present in all four repos; copyright holder asserted.
- [ ] `.github/FUNDING.yml` has real handles (and GitHub Sponsors is enabled for
      the account, or the entries are removed).
- [ ] `image/os-list/icon.png` exists (≈40×40 PNG for the Imager list).
- [ ] Beta-blocker triage done: every hardening-plan finding is either fixed or
      recorded as a known issue for the release notes
      (`docs/superpowers/plans/` in maschinepi-te and mixxx-mk3).

## Phase 1 — Pin and verify components

- [ ] Bump each submodule to its intended release commit:
      ```bash
      git submodule update --remote --recursive
      # or per submodule: cd external/<name> && git checkout <tag/commit>
      ./scripts/check-submodules.sh
      ```
- [ ] Confirm a clean, from-scratch checkout builds (catches missing-file /
      submodule-URL problems before a device ever sees them):
      ```bash
      rm -rf /tmp/mpi-verify
      git -c url.https://github.com/.insteadOf=git@github.com: clone --recursive . /tmp/mpi-verify
      # build each component per its README; both must configure and compile
      ```
- [ ] Host-side integrator checks pass:
      ```bash
      ./tests/test-systemd-modes.sh
      ./tests/test-install-rootfs.sh
      ./tests/test-mode-selector.sh
      ```
- [ ] Tag each component repo at its pinned commit and push the tags.

## Phase 2 — Build the image

- [ ] Obtain a stock Raspberry Pi OS Lite **arm64** base image.
- [ ] Build with the documented public default (`mpi` / `musicpi`), or use a
      private password file for a non-public image:
      ```bash
      ./image/build-image.sh \
        --base /path/to/raspios-lite-arm64.img.xz \
        --mixxx-deb /path/to/mixxx-arm64.deb \
        --password-file /secure/path/release-password \
        --compress
      ```
- [ ] Rename the verified output for the release, for example
      `image/output/mpi-station-v0.9.0-beta.2.img.xz`.
- [ ] Sanity-inspect it: `./image/inspect-image.sh image/output/<img>`.

## Phase 3 — Hardware validation gate

Follow `docs/hardware-test.md` on a real Raspberry Pi 4 + MK3:

- [ ] Fresh flash boots; first-boot data-partition split and sample restore
      complete.
- [ ] The boot selector appears after the MK3 attaches; both **MixxxDJ** and
      **MusicPI** start and drive the MK3 (screens, pads, LEDs).
- [ ] Switching modes and rebooting works.
- [ ] Audio plays without xruns in a short soak on each mode.

Do not proceed to publish if this gate fails.

## Phase 4 — Host the image and generate the os_list

- [ ] Upload `mpi-station-v0.9.0-beta.2.img.xz` to the download host (GitHub Releases
      if < 2 GB, else Cloudflare R2 or archive.org — see the README hosting
      notes).
- [ ] Generate the release os_list + checksum:
      ```bash
      ./image/os-list/generate-os-list.sh \
        --image image/output/mpi-station-v0.9.0-beta.2.img.xz \
        --url   https://<host>/mpi-station-v0.9.0-beta.2.img.xz \
        --date  YYYY-MM-DD \
        --output image/os-list/mpi-station.release.json
      ```
- [ ] Host `mpi-station.release.json` at a **stable** URL.
- [ ] Verify the download: fetch the hosted image, check it against the emitted
      `.sha256`, and confirm `extract_sha256` matches.

## Phase 5 — Publish

- [ ] Confirm the four final repositories exist and are public:
      `music-pi/music-pi`, `music-pi/daw`, `music-pi/mixxx-mk3`, and
      `music-pi/libmk3`.
- [ ] Confirm local remotes and every submodule URL use the final organization
      URLs, and that a fresh anonymous recursive clone succeeds.
- [ ] Tag this repo: `git tag v0.9.0-beta.2 && git push origin v0.9.0-beta.2`.
- [ ] Create the GitHub Release here, attaching (or linking) the image and the
      `.sha256`, and including the os_list URL and release notes.
- [ ] Announce the Imager install path: **Choose OS → Use custom →** the
      `mpi-station.release.json` URL.

## Phase 6 — Post-release

- [ ] Independent install test: on a clean machine, add the os_list URL to
      Raspberry Pi Imager, flash, and boot — confirm the end-to-end user path.
- [ ] Record the exact submodule pins and image sha256 in the release notes so
      the build is reproducible.
- [ ] Open the next milestone; move any shipped known-issues into tracked work.

## Hotfix / rollback

- A release is the pinned set at a tag. To roll back, checksum-verify and flash
  the prior release image. OTA is not part of the current release candidate.
- For a hotfix, land the fix in the component repo, bump only that submodule
  pin, re-run Phases 1–5 with a new patch tag. Never hand-patch a device.
