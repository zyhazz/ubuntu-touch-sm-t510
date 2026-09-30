# Porting notes — SM-T510 (Exynos 7904) to Ubuntu Touch 24.04 / Halium 11

What broke, in the order it was hit, how it was diagnosed and how it was fixed.
Most of it applies to any Samsung Exynos device of the 2019–2020 generation
(4.4/4.14 kernels, S-Boot, system-as-root, Android 11 vendor).

## The 32-bit vendor

The stock kernel is already arm64 (4.4.177, `CONFIG_COMPAT=y`), only the
Android userspace is 32-bit (`TARGET_ARCH := arm`, binder64). Ubuntu Touch
20.04+ and the Halium GSIs from 10 onwards are arm64 only.

Anything that crosses a process boundary does not care: HIDL services talk
over hwbinder, and a 32-bit `composer`, `allocator`, `audio`, `camera.provider`
serves a 64-bit client fine. The problem is what a 64-bit process loads
*in-process* through libhybris: `libGLES_mali.so`, `gralloc.exynos7904.so`,
`android.hardware.graphics.mapper@2.0-impl.so`, the audio HAL.

The Galaxy A30 (SM-A305GT) uses the same Exynos 7904 with an arm64 userspace,
and its Android 11 `libGLES_mali.so` is the same `r26p0-01eac0` build as the
T510's 32-bit one. `scripts/make-hybrid-vendor.sh` copies the T510 vendor
image, grows it and adds the A30 `/vendor/lib64` with SELinux labels
preserved. The result lives at `/var/lib/lxc/android/vendor.img`;
`mount-android-partitions` prefers `vendor.img` there over the vendor
partition, so the partition is never touched.

## Kernel

Base: gta3xlwifi-dev `main` (4.4.302, Mali r26p0 like the blobs). The
`testing` branch is 4.4.177 with Mali r19p0 — wrong for these blobs.

| Symptom | Cause | Fix |
|---|---|---|
| `prepare3: srctree is not clean`, empty `arch/arm64/include/generated` | upstream tracks `.config`, `include/config`, generated asm headers and host binaries; with `O=` they shadow the build via VPATH | `kernel/remove-generated.txt`, removed by `prepare-kernel.sh` |
| `init/uh.elf: file not found` | `.incbin` with srctree-relative paths | `KBUILD_AFLAGS += -Wa,-I$(srctree)` |
| `"ANDROID_VERSION" is not defined [-Werror=undef]` | only passed to dtc | define it in `KBUILD_CFLAGS` |
| `implicit declaration of rkp_set_mnt_flags` | overlayfs + RKP never built together by Samsung | declare it like `fs/pnode.c` does |
| `sched_rt_entity has no member my_q` | Samsung sched code needs it | keep `CONFIG_RT_GROUP_SCHED=y` |
| Stuck on the Samsung logo, initramfs never runs | S-Boot appends `skip_initramfs` (system-as-root) to the DT bootargs | make `skip_initramfs` a no-op |
| `run-init: opening console: No such device` | S-Boot passes `console=ram`; no such console driver, so `/dev/console` has no device | ignore `console=ram`, add `console=tty0` to `CONFIG_CMDLINE` |
| Panic in `strcmp` from `config_usb_cfg_link` (bootloop right after systemd starts) | usb-moded links functions before writing the config's `configuration` string; Samsung code strcmp()s NULL | treat a NULL/unnamed config as a generic (GSI) configfs user |
| `Config c/1 of g1 needs at least one function`, `failed to start g1: -22` | same code parked functions for Samsung's framework mode | only `"Conf 1"` means Samsung framework |
| Initramfs: `Couldn't find data partition`, udev hangs 120 s | eMMC command queueing left a userdata read in flight forever | CMDQ off by default, `dw_mmc.cmdq=1` re-enables |
| `lxc-start: Failed to bind mount /dev/pts/ptmx` | 4.4 needs it explicitly | `CONFIG_DEVPTS_MULTIPLE_INSTANCES=y` |
| Oops at `0x96` in `mmc_rpmb_access` as soon as the TEE starts | `blkdev_get_by_path()` returns `ERR_PTR(-ENOENT)` (host `/dev` has no `/dev/block/mmcblk0rpmb`), code checked NULL | try `/dev/mmcblk0rpmb`, handle ERR_PTR |
| `abox has been disabled`, audio HAL `cannot prepare channel: EBUSY` | ABOX asks for `calliope_sram.bin` at ~1.4 s, before any rootfs | `CONFIG_EXTRA_FIRMWARE` with calliope_{s,d}ram.bin and Tfa9896.cnt |
| Oops in `regcache_cache_only` from `abox_enable` (charger boots) | with built-in firmware the async completion runs before the regmap exists | request the firmware after regmap/runtime PM setup |

Boot image: header v1, 2 KiB pages, kernel at 0x10008000, **32 MiB boot
partition**. With the audio firmware built in, the kernel plus a gzip initrd
no longer fits; the Halium initrd is recompressed with xz.

Reading crashes: `/proc/last_kmsg` survives a warm reset; pull it from TWRP
with adb right after a panic. `/proc/reset_reason` says `KPON` after a kernel
panic.

## Halium / Ubuntu Touch integration

| Symptom | Cause | Fix |
|---|---|---|
| `mount-android-partitions`: `/android/vendor: mount point is a symbolic link to nowhere` | with `/data/rootfs.img` the initramfs uses the "halium" layout and loop-mounts **`/data/android-rootfs.img`**; with the GSI only inside the rootfs, it falls back and leaves a broken symlink | the installer writes the GSI to `/data/android-rootfs.img` too |
| Android container shuts itself down 7 s after start (`reboot,boringssl-self-check-failed`) | vendor rc runs `boringssl_self_test64` once the ABI list has arm64; the T510 vendor has no 64-bit binary | take `boringssl_self_test64` (and `snap_utility_64`) from the A30 |
| usb-moded: `mkdir configs/c.1: Device or resource busy` | the container's `init.exynos7904.usb.rc` builds Samsung's gadget (`configs/b.1`) on the shared configfs first | ship that rc empty |
| Lomiri dies at start with `buffer allocation failed`; the root-owned system compositor works | Exynos gralloc allocates through **ION inside the client process**; `/dev/ion` is 0600 root | udev: `ion` and `sw_sync` 0666 |
| Tablet powers off ~30 s into boot | `systemd-logind: Power key pressed short. Powering off...` before repowerd takes the key | `HandlePowerKey=ignore` |
| SSH password login refused on the debug image | `lxc-android-config` ships `50-*.conf` with `PasswordAuthentication no`, sshd keeps the first value | name the debug drop-in `00-*` |
| `/usr` read-only | the rootfs is mounted ro at runtime | `mount -o remount,rw /` for experiments; anything the container needs is generated at image build time |

## Audio

Four layers, all needed:

1. The Halium GSI's `init.disabled.rc` points the audio HIDL services at
   `*_DISABLED` binaries. A copy with those services commented out is bind
   mounted in the container from LXC's mount hook (`t510-mount-hooks.sh`).
2. Samsung's `audio.primary.exynos7904.so` is 32-bit only (the A30 does not
   have a 64-bit one either). PulseAudio loads Android's 64-bit
   `audio.hidl_compat.default.so` instead, bound over the 64-bit
   `audio.primary.default.so` stub, and `ld.config.txt`'s sphal namespace is
   allowed to reach `libaudiohal*` (`t510-audio-hidl-compat.sh`). The Ubuntu
   Touch unit sets `HYBRIS_USE_VENDOR_NAMESPACE=1`, which hides the system
   `libaudiohal` from the bridge; unset it.
3. PulseAudio's API 30 droid module calls `create_audio_patch()` without
   checking the device version. `audio.hidl_compat` reports
   `AUDIO_DEVICE_API_VERSION_2_0`, allocates its device with `new` and never
   sets that pointer, so PulseAudio jumps into heap garbage (SIGBUS at an
   "address" that is ASCII text). Found with `debug/sigbus_trace.c`: the caller
   was `libdroid-util-30.so`, `ldr x6, [x0, #272]; blr x6`, and offset 272 of
   `audio_hw_device` is `create_audio_patch`. The **API 28 module**
   (`module-droid-card-28`) honours the version and routes without patches.
4. `rate=48000` (the ABOX DSP's rate; 44.1 kHz hissed) and
   `set-default-sink sink.primary-out` (`sink.fast` is the low-latency output
   and underruns on long streams: noise in the browser).

## Open

- **Suspend.** `echo mem > /sys/power/state` is refused while the display and
  Wi-Fi hold wakeup sources, and nothing in Ubuntu Touch ever suspends this
  device. In off-mode charging the Android charger does suspend it, and the
  power key never wakes it. Resume is the thing to debug next.
- **Camera.** The provider and `minimediaservice` open the camera; the app
  asks for flash `auto` (no flash on this device), gets no valid picture size
  and crashes (SIGSEGV) when the HAL reports error 0 at preview start.
- The journal is not written in charger mode (read-only root); log to the
  journal via `systemd-cat` and note that only the first seconds survive.
