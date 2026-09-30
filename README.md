# Ubuntu Touch for the Samsung Galaxy Tab A 10.1 (2019) — SM-T510

**SM-T510 · codename `gta3xlwifi` · Exynos 7904 · Ubuntu Touch 24.04-2.x · Halium 11**

A community port. Not endorsed by, affiliated with, or supported by the UBports
Foundation or by Samsung. *Leia em português: [README.pt-BR.md](README.pt-BR.md).*

Built the way the [Galaxy A50 port](https://github.com/sadatdaniel/a50-ubuntu-touch)
is built — standalone kernel + Halium 11 GSI + Ubuntu Touch rootfs, installed
from TWRP — with one twist: the SM-T510 ships a **32-bit Android userspace**
(armeabi-v7a vendor on an arm64 kernel, 2 GB RAM), while Ubuntu Touch 20.04+ is
arm64 only. The port runs the stock 32-bit vendor HAL services unchanged and
adds a `/vendor/lib64` taken from the **Galaxy A30 (SM-A305GT)**, which has the
same SoC and the very same Mali-G71 r26p0 driver, for everything a 64-bit
process has to load in-process (EGL/GLES, gralloc, mapper).

## What works

| | Status |
|---|---|
| Boot to Lomiri, first-run wizard, touch | ✅ |
| Display, GPU (Mali-G71, hwcomposer 2) | ✅ |
| Auto-rotation (accelerometer) | ✅ |
| Wi-Fi | ✅ |
| Audio: speaker | ✅ (48 kHz, via the audio HIDL bridge) |
| Microphone | ✅ |
| Camera | ❌ HAL opens, the camera app crashes starting the preview |
| Suspend (deep sleep) | ❌ never suspends; the device stays awake with the screen off |
| Off-mode charging | ⚠️ charger UI shows, but the power key does not boot the system while plugged in (unplug, then hold power) |
| Bluetooth, GPS, sensors other than rotation | untested |
| Waydroid | untested (kernel has the binder nodes) |

## Installing

Everything on the tablet is erased. The bootloader must already be unlocked
(Developer options → OEM unlocking, then the Download-mode long-press
Volume Up prompt).

1. **Stock Android 11.** Flash `T510XXS5CVL1` with Odin: BL, AP and
   `CSC_OMC_*` (not `HOME_CSC`). `scripts/extract-firmware.sh` downloads it, or
   use Bifrost/SamFw. Boot it once, connect to the internet, check that OEM
   unlocking is still on and greyed out.
2. **TWRP.** Flash `twrp-3.7.0_11-0-T510XXU5CWA1-20230330.tar.md5` (Magendanz,
   includes a disabled vbmeta) as AP with *Auto Reboot* off, then boot straight
   into recovery with Power + Volume Up.
3. **Format data.** TWRP → Wipe → Format Data → `yes`.
4. **Install** `ubuntu-touch-sm-t510-24.04-*.zip` (build it, see below) from
   TWRP → Install. It writes the boot partition, `/data/rootfs.img` and
   `/data/android-rootfs.img` and verifies all three by SHA-256.
5. Reboot → System. The first boot takes a few minutes.

Release zips are not published here: they contain Samsung's proprietary vendor
libraries and DSP firmware. Build your own from official firmware.

## Building

Linux (tested on WSL2 Ubuntu 24.04) with Docker, ~40 GB free.

```sh
docker build -t t510-build docker/
scripts/fetch-deps.sh          # toolchain, mkbootimg, samloader-rs, UT rootfs, GSI, TWRP
scripts/extract-firmware.sh    # T510 (Odin files + vendor) and A30 firmware
scripts/prepare-kernel.sh      # community kernel @ pinned commit + kernel/patches
scripts/build-kernel.sh        # out/kernel (AOSP GCC 4.9)
scripts/make-boot.sh           # out/halium-boot.img (must fit the 32 MiB boot partition)
scripts/make-hybrid-vendor.sh  # out/vendor.img: T510 vendor + A30 lib64
scripts/build-rootfs.sh        # out/rootfs.img, out/android-rootfs.img
scripts/make-installer-zip.sh  # out/ubuntu-touch-sm-t510-24.04-*.zip
```

`T510_DEVEL=1 scripts/build-rootfs.sh` and the same variable for
`make-installer-zip.sh` produce a debug image: SSH on with password login
(`1234`, change with `T510_DEVEL_PASSWORD`), `keys/t510_ed25519.pub` authorized
for root, adb without host-key verification. Useful while porting, unsafe to
carry around.

## Layout

| Path | What |
|---|---|
| `kernel/patches/` | 11 patches on top of [gta3xlwifi-dev/android_kernel_gta3xlwifi](https://github.com/gta3xlwifi-dev/android_kernel_gta3xlwifi) `main` (4.4.302); `arch/arm64/configs/halium.config` is added by one of them |
| `kernel/remove-generated.txt` | build artifacts that upstream tracks in git and that break `O=` builds |
| `overlay/system/` | files copied into the Ubuntu Touch rootfs |
| `installer/` | the TWRP installer (`update-binary` + `t510-install.sh`) |
| `scripts/` | build pipeline |
| `debug/` | helpers used while porting: `tsh` (Halium initramfs telnet), `ush` (SSH), `sigbus_trace.c` (LD_PRELOAD SIGBUS/SIGSEGV tracer) |
| `docs/porting-notes.md` | **every problem hit and how it was fixed** — read this if you port another Samsung Exynos device |

## Credits

- [sadatdaniel/a50-ubuntu-touch](https://github.com/sadatdaniel/a50-ubuntu-touch) — the method, and the audio bridge approach
- [gta3xlwifi-dev](https://github.com/gta3xlwifi-dev) — the 4.4.302 kernel and the device tree
- Magendanz — TWRP for the SM-T510
- UBports, Halium — Ubuntu Touch, the GSI, the initramfs and the build tools
- [topjohnwu/samloader-rs](https://github.com/topjohnwu/samloader-rs) — firmware downloads

## License

Scripts, installer and overlay: GPL-3.0-or-later (see [LICENSE](LICENSE)).
The kernel patches are derived from the Linux kernel and are GPL-2.0.
