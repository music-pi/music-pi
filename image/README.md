# image/ — fused Raspberry Pi OS Lite image build (Phase 2b)

Produces one flashable image with both stacks installed and gated behind the
systemd mode targets. Phase 2b chose the supported MusicPI official-image
injection approach: supply a stock Raspberry Pi OS Lite arm64 image and perform
all compilation, package installation, and provisioning on the host.

```bash
./image/build-image.sh --base /path/to/raspios-lite-arm64.img.xz --mixxx-deb /path/to/mixxx-arm64.deb --compress
```

`--mixxx-deb` is required and must point to the verified ARM64 Mixxx release package; binary packages are release assets, not source-repository content.

The mount/injection step runs in the existing `pi-gen:latest` helper container,
so host sudo is not required. The root filesystem receives 2048 MiB of build
headroom. Two small labeled ext4 bootstrap partitions are appended:

- `MIXXX_LIBRARY`, mounted at `/home/mpi/Music`.
- `MPI_SAMPLES`, mounted at
  `/home/mpi/maschinepi/samples` and preloaded with the pinned sample set.

On the first boot, before either filesystem mounts, the image divides every
remaining sector on the physical card equally between these two partitions,
recreates them, and restores the bundled samples from the rootfs seed. This
step is local filesystem setup only: it performs no compilation, package
download, or application provisioning. `--data-bootstrap-mb` controls only the
small pre-boot image partitions, not their final on-card sizes.
MusicPI, the Mixxx screen tools, and the selector are cross-compiled on the
host. Runtime packages and the pinned Mixxx ARM64 package are installed into the
mounted rootfs under QEMU. No compilation, package download, or provisioning is
performed by the Pi. Pass
`--maschinepi-binary /path/to/arm64/maschinepi` to reuse an existing ARM64
artifact.

The injected test login is `mpi` / `musicpi` unless `--password-file` is supplied.
Change it before putting the device on an untrusted network.

The build must reconcile shared components needed by both application stacks,
including PipeWire configuration, `99-mk3` udev rules, and the boot splash, so
the last writer is intentional.

See `docs/hardware-test.md`.
