# Report: how the A50 (Exynos 9610) Ubuntu Touch 26.04 / Halium 11 port is built, and what carries over to the SM-T510

Repo root: `/home/diego/dev/sm_t510_ubuntu_touch/src/a50-ubuntu-touch` (HEAD 462cc1b). Paths below are relative to it. The kernel repo `sadatdaniel/a50-halium` is not cloned locally, so I got the patch series from these docs rather than from the patch files.

## 1. Build pipeline

There are two paths, and releases do not use the upstream one.

**Upstream path (compile check only, never boot-tested on the device)**
- `build.sh` is 4 lines: it clones `gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools` into `build/` and runs `./build/build.sh "$@"`. It does not pin a commit; `docs/conventions.md` says they read it at `d5838d5`. Use `-k` to stop after boot.img.
- Build container (`docs/build-environment.md`): plain `ubuntu:22.04` with `sleep infinity`, plus these packages: git gnupg flex bison gperf build-essential zip bzr curl libc6-dev x11proto-core-dev libgl1-mesa-dev libxml2-utils xsltproc zlib1g-dev schedtool liblz4-tool bc lzop imagemagick libncurses5 rsync python3 python-is-python3 cpio xz-utils. No i386 multilib.
- Toolchain: Google prebuilt clang `android11-gsi` / `clang-r383902`. Getting the kernel to build hermetically with `LLVM=1` took 9 kernel commits (`docs/experiments/003-first-build.md`):
  - lld for host programs
  - LDLLD/LLVMNM definitions
  - drop `CONFIG_LLVM_POLLY`
  - vdso32 built with the integrated assembler
  - tzdev `.incbin` fixes for `O=` and ThinLTO builds
  - `__bad_copy_*` sentinels
  - setlocalversion trailing space
  - tfa9872 `-Werror`
- Other tool-path findings:
  - The tools' ramdisk is `github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64`.
  - `make-bootimage.sh` uses LineageOS `android_system_tools_mkbootimg` `lineage-20.0`.

**Release path (what actually ships)**
1. **Kernel:** built by a50-halium in its own Docker image with pinned Proton Clang 210521 and `SOURCE_DATE_EPOCH`:
   `build-kernel.sh --profile full --firmware /fw`
   then `make-boot-image.sh --port ubports --donor boot.img`. That script swaps only the kernel into a known-good donor boot.img (header plus Halium ramdisk) and patches only `kernel_size`/`ramdisk_size`. S-Boot ignores the header `id` digest.
2. `scripts/release/build-device-tarball.sh --boot boot.img` produces `device_a50.tar.xz`, containing `partitions/boot.img` and `system/` (= `overlay/system` taken from `git archive HEAD`, usrmerge layout). It refuses a boot.img larger than 57,671,680 bytes.
3. `scripts/release/build-rootfs-image.sh` collapses upstream's `prepare-fake-ota.sh` and `system-image-from-ota.sh`. It:
   - truncates to 6144M and runs `mkfs.ext4 -b 4096 -L ubuntu-touch`, loop-mounted as `.stage/system`;
   - unpacks, in order: the UT rootfs, the GSI, the device tarball, and a `version.tar.xz` (channel.ini);
   - renames `system.img` to `android-rootfs.img`, touches `.writable_image`;
   - runs `add-openstore-compat.sh` (co-installs libxml2.so.2 plus ICU74) and `configure-polkit-legacy.sh`;
   - with `--devel`, also runs `add-devel-access.sh`.

   Where the inputs come from:
   - **UT rootfs:** resolved live from `https://system-image.ubports.com/26.04-1.x/arm64/android9plus/daily/FP5/index.json`, taking the newest `/pool/rootfs-*.tar.xz`. The URL and sha are recorded in `out/rootfs-source.txt`.
   - **GSI:** pinned by `gsi.lock`:
     - `GSI_JOB=https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-11.0`
     - `GSI_BUILD=1542`, `GSI_DATE=2026-09-05`
     - artifact `halium_halium_arm64.tar.xz`, `GSI_SHA256=48ed0fd1…d2a3`
     - `GSI_ANDROID_ROOTFS_SHA256=e53c4d7f…`, `GSI_ANDROID_ROOTFS_BYTES=473772032`
   - They deviate from upstream in two ways: upstream's script doesn't know 26.04, and upstream picks the GSI by `bootimg_os_version` (12.0 here) where they pick it by `deviceinfo_halium_version`.
4. `scripts/release/make-installer-zip.sh` produces the zip. Details in §5.

## 2. Kernel config and patches

The A50 kernel is 4.14.194. Branch `ubuntu-touch-26.04` of `sadatdaniel/android_kernel_samsung_exynos9610_mint`, pinned base `bec0c2af…`.

**Defconfig recipe.** The vendor `build.sh` builds its defconfig from these parts, and `halium_a50_defconfig` is a `savedefconfig` of the result:
- `exynos9610-a50_core_defconfig`
- fragments `mint_partial-deknox-11`, `mint_mali-11`, `mint_variant_recovery`, `mint_root-none`
- the block appended by patch 0002
- Reference copy: `docs/experiments/002-halium_a50_defconfig.txt`.

**Big trap:** `ANDROID_MAJOR_VERSION=r` must be in the environment. Without it, 3 symbols vanish silently, including `USB_F_CONN_GADGET_NDOP` (`docs/kernel.md`, `docs/experiments/002-bare-make-config.md`).

**Halium-mandatory options** (guide's `halium.config`, carried by patch 0002's block):
- DEVTMPFS, FHANDLE, SYSVIPC
- IPC/NET/PID/USER/UTS namespaces, VT
- cgroups: MEMCG(+SWAP), BLK_CGROUP, CGROUP_SCHED/PIDS/FREEZER/DEVICE/CPUACCT/BPF
- SECCOMP
- the full netfilter/xt/NAT/MASQUERADE set for LXC networking; VETH, BRIDGE, TUN
- BLK_DEV_LOOP with MIN_COUNT=32
- `CONFIG_CMDLINE` including `systemd.unified_cgroup_hierarchy=0 cgroup_disable=pressure` (CMDLINE_EXTEND)
- Two warnings:
  - Do **not** enable `POSIX_MQUEUE`; it is reported to bootloop this device.
  - `FRAMEBUFFER_CONSOLE` must stay off; fbcon crashes against Samsung decon.

**Device-specific ("full" profile, nine patches):**
- `CONFIG_EXTRA_FIRMWARE` with 8 vendor blobs, e.g. ABOX `calliope_*.bin`. The DSP requests firmware at t=1.43 s but no filesystem exists until 2.08 s (`docs/experiments/007-abox-firmware-too-early.md`).
- Bluetooth: `CONFIG_BT` + `BT_HCIVHCI` + `RFKILL`, **plus restoring `hci_sock.c`**, which Samsung had commented out (`bt_sock_create` BUG_ON when bluebinder starts) — `docs/experiments/008-bluetooth-hci-sock.md`.
- Binder for Waydroid: `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"`, because there is no binderfs on 4.14.
- `decon-force-mask-layer` (fingerprint HBM).
- `fimc-is-sensor-open-race` and `fimc-is-clear-vctx-on-close` (camera panics).
- `abox-fixup-helper-dai-guard` (NULL-deref).
- Removing the ANDROID_MAJOR_VERSION Kconfig dependencies.
- `console=tty0` compiled into `CONFIG_CMDLINE`: S-Boot ignores the boot header cmdline and uses the DT bootargs.
- `docs/patches/0001-waitid-add-P_PIDFD-support.patch`: the Samsung tree had a half pidfd backport. glib 2.88 waitid(P_PIDFD) got EINVAL and lightdm crash-looped.

**AppArmor** (`docs/experiments/019-apparmor-ladder.md`, handoffs 09–16). Took six builds (aa1–aa6):
- `SECURITY_APPARMOR=y` alone boots.
- Making it the default LSM panicked systemd-journald at 8.7 s. Cause: Samsung's `call_int_hook` macro overwrites RC with `security_integrity_current()` → fixed by `security-hook-default.patch`.
- Upstream 4.14 AppArmor socket-mediation patches did not compile, because Samsung made `sk_security` inline storage in `sock.h`. A compat rework was needed (aa6: DEFAULT_SECURITY=apparmor, HARDENED_USERCOPY=y).
- With AppArmor selected, Samsung's `vndservicemanager` aborts in `selinux_status_open()`. Fixed by LD_PRELOAD of Halium's `libselinux_stubs.so` via a container rc override.

**polkit:** 127 needs `SO_PEERPIDFD`, which this kernel lacks → setuid legacy helper (`docs/polkit-legacy.md`).

**Diagnostics warning:** don't trust `/proc/config.gz` or `lxc-checkconfig`. The vendor Makefile embeds the wrong config.

## 3. deviceinfo (`deviceinfo`)

Each value carries a [V]/[C]/[?] provenance comment.

| Field | Value |
|---|---|
| name / manufacturer / codename | "Galaxy A50" / Samsung / a50 |
| arch / kernel_arch | aarch64 / aarch64 (**must not be "arm64"**: it breaks the CROSS_COMPILE triples) |
| halium_version | 11 |
| ubuntu_touch_release | 26.04-1.x |
| kernel_source / branch | android_kernel_samsung_exynos9610_mint / ubuntu-touch-26.04 |
| kernel_defconfig | "halium_a50_defconfig halium.config" |
| kernel_cmdline | "androidboot.selinux=permissive loop.max_part=7" (ignored by S-Boot) |
| kernel_clang_compile / clang_branch | true / android11-gsi |
| kernel_llvm_compile | false (LLVM=1 is meaningless on 4.x; needs a build wrapper instead) |
| kernel_image_name | Image (DTB appended inside, no separate dtb) |
| bootimg_header_version | 1 |
| flash_pagesize | 2048 |
| flash_offset_base / kernel / ramdisk / second / tags | 0x0 / 0x10008000 / 0x0 / 0x0 / 0x10000100 |
| bootimg_board / os_version / os_patch_level | SRPRL05B007KU / 12.0 / 2022-09 |
| ramdisk_compression | gzip |
| system_partition_size | 6144M |
| rootfs_image_sector_size | 4096 |
| has_recovery_partition | false |

Deliberately unset:
- `bootimg_tailtype=SEAndroid`: the known-good image has zeros in its last 32 bytes.
- `bootimg_partition_size`: setting it adds an AVB footer via avbtool, which they avoid.
- `use_overlaystore`: it only shadows files that already exist, so the port's new files would be silently dropped.

## 4. Overlay (`overlay/system/`, mirrors /; see `overlay/README.md`)

**udev** (`usr/lib/udev/rules.d/`):
- `99-a50-binder.rules`: binder/hwbinder/vndbinder at 0666. Without it the greeter (uid 108) can't reach gralloc-mapper and lightdm loops.
- `99-a50-gnss.rules`: gnss_ipc as system:system 0660.
- `99-a50-fimc-scan-block.rules`: video* nodes root-only with `TAG-="uaccess"`, so the gst plugin scanner can't wedge fimc and block the freezer.

**Display:** they did not add any hwcomposer config.
- `etc/ubuntu-touch-session.d/android.conf`: GRID_UNIT_PX=21, QTWEBKIT_DPR=2.625.
- `etc/deviceinfo/devices/a50.yaml`: GridUnit, cutouts, orientations, and `OfonoPlugin: binder`.

**Container hooks:**
- `var/lib/lxc/android/a50-mount-hooks.sh` does binds inside the container namespace. It disables:
  - `watchdogd`: it opens /dev/watchdog, spins holding `misc_mtx`, and freezes every misc device including mali0.
  - vendor `init.exynos9610.usb.rc`: the conn_gadget double `misc_register` corrupts `misc_list`. This was the root cause of the "mali0 open hangs" display blocker.
  - `emservice.rc` and `cass.rc`.
- The same hooks also:
  - re-enable the audio HALs that the GSI's `init.disabled.rc` disables;
  - bind a patched `mixer_paths.xml`;
  - apply the vndservicemanager SELinux stub preload.
- `usr/local/bin/a50-container-prepare.sh` (+ service) generates these files before `lxc-android-config.service` starts.

**Audio:**
- `a50-audio-hidl-compat.sh`/.service: binds the **64-bit** `audio.hidl_compat.default.so` over `/vendor/lib64/hw/audio.primary.default.so` host-side, and rewrites `/linkerconfig/ld.config.txt` on every boot (adds libaudiohal* to the sphal→default link). Without it PulseAudio loads a 12 KB stub.
- `a50-gen-mixer-paths.py`: the speaker is routed off RDMA7, which the ABOX firmware NACKs.
- `a50-audio-speaker-route.sh`: pins the default sink off the unusable low-latency output.

**Telephony:** `etc/ofono/binder.conf` sets slots, `radioInterface=1.4`, and `signalStrengthRange=-120,-75`.

**USB:** `etc/default/usb-moded.d/device-specific-config.conf` sets `USB_MODED_HW_ADAPTATION_ARGS="-f"`, because there is no cable detection.

**GPS:** `a50-gnss-unblock.sh` sets `service.bootanim.exit`, which gpsd waits on forever.

**Other:**
- Waydroid: user unit `usr/lib/systemd/user/waydroid-session.service`, a launcher wrapper, and a nocamera drop-in.
- `usr/libexec/netplan/configure` shim for the hotspot.
- `device-hacks` → `a50-device-setup.sh`: unmasks sensorfwd, patches `touch.pa`, fixes the datetime indicator.
- **Wi-Fi and sensors needed no overlay files.** Wi-Fi is the SCSC wlbt driver; the interface is `swlan0`.

**Ramdisk:** `ramdisk-overlay/` is essentially the unmodified upstream init. The README lists 4 fixes from Droidian that were never needed or ported: mknod `/dev/kmsg`, skip `/proc`/`/sys` moves, force `BOOT_MODE=halium` (charger mode), and a `/dev/sda32` fallback.

## 5. Installer

- `installer/META-INF/com/google/android/update-binary` is a shell script that sources `installer/install/a50-install.sh`.
- The installer:
  - finds `boot` and `userdata` by name and requires the boot partition to be exactly 57,671,680 bytes;
  - checks `SHA256SUMS` and `manifest.txt`;
  - requires /data to be mounted, unencrypted (Format Data), and not holding an Android install;
  - dd's boot.img, **reads it back and hashes it**;
  - streams `rootfs.img.gz` → `/data/rootfs.img` and hashes it;
  - for devel builds, writes `/data/.force-ssh`.
- It never touches vendor, system, efs, modem or recovery. TWRP is required because Samsung has no fastboot.
- The Halium initramfs loop-mounts `/data/rootfs.img` as root; the telnet debug shell is at 192.168.2.15.
- Status docs note the port is still "pre-finalization": the rootfs is not on `system` (5300 MiB there, content ~4.1 GB).

## 6. Biggest problems and fixes

1. **Display hang / mali0 open blocked:** conn_gadget double-registration plus watchdogd holding `misc_mtx` → container rc binds. Then hwbinder at 0600 → udev rule (`docs/experiments/006-what-we-missed.md`).
2. **lightdm crash loop:** the waitid P_PIDFD kernel patch.
3. **Audio:** ABOX firmware requested too early → EXTRA_FIRMWARE. The GSI disables the audio HAL. The **Samsung audio HAL is 32-bit only** → hidl_compat bridge plus the linkerconfig hack (§26 of experiment 007). Mixer-path rewrite.
4. **Bluetooth:** vendor-removed hci_sock → kernel panic.
5. **AppArmor:** Samsung LSM macro and sock.h changes; vndservicemanager `selinux_status_open` abort.
6. **Bare-make kernel:** ANDROID_MAJOR_VERSION; the vendor build.sh fragment recipe; Proton vs Google clang (still not boot-tested).
7. **S-Boot:** ignores the cmdline, needs no SEAndroid/AVB footer, and rebooting to recovery from Linux is unreliable.
8. **Suspend is still broken:** ABOX PM notifier, wlbt, and fimc corruption (experiments 017, 018, 021, 022, 025).
9. **Still open:** the camera app (qtubuntu-camera API mismatch) and fingerprint.
10. **Rootfs size:** 3584M is too small; 6144M is needed.
11. **Rule they learned the hard way:** `lxc-attach -n android -- logcat` is the only place HAL errors appear.

## 7. What implies a 64-bit userspace/vendor requirement (important for the SM-T510)

- The Halium 11 GSI (`generic_arm64/halium_halium_arm64.tar.xz`) and the UT rootfs (`arm64/android9plus`) are both arm64. libhybris on the host loads **`/vendor/lib64`** HALs, and the linker namespaces are 64-bit (`/android/system/lib64`).
- Even the A50, which has a 64-bit vendor, needed a bridge for its one 32-bit-only HAL (audio): the 32-bit HIDL service over hwbinder plus the 64-bit `hidl_compat` wrapper. A **purely 32-bit T510 vendor would lack every `/vendor/lib64` HAL**, including gralloc/hwcomposer/Mali `libGLES_mali.so`, which Mir and Lomiri load in-process. That is why borrowing an arm64 vendor from the A30 makes sense.
- The Waydroid `HALIUM_11` vendor image is arm64 too.
- For the A30 vendor blobs on the T510, expect to redo A50-style fixes:
  - the Mali-G71 blob must match the T510 kernel's Mali driver version (A50 used the `mint_mali-11` fragment);
  - ABOX/SCSC firmware must match the kernel drivers;
  - vendor init rc differences (watchdogd, usb rc, emservice/cass);
  - `mixer_paths`;
  - `vndservicemanager` SELinux stubs.
- Kernel 4.4 specifics:
  - no binderfs, so anbox binder devices must be compiled in;
  - the pidfd backport is likely absent. Check what glib does, since it probes pidfd first; polkit will certainly need the legacy helper;
  - the AppArmor backport must be a 4.4 series, not 4.14.
- With 2 GB of RAM, note the A50 already hit ~1.6 GB available with swap in use, and Waydroid adds ~2 GB to userdata.

## Key files

- `README.md`, `REPRODUCE.md`, `build.sh`, `gsi.lock`, `deviceinfo`
- `docs/kernel.md`, `docs/build-environment.md`, `docs/conventions.md`, `docs/plan.md`, `docs/status.md`, `docs/RELEASING.md`
- `docs/experiments/002-bare-make-config.md`, `003-first-build.md`, `006-what-we-missed.md`, `007-abox-firmware-too-early.md`, `008-bluetooth-hci-sock.md`, `013-waydroid.md`, `019-apparmor-ladder.md`
- `docs/patches/0001-waitid-add-P_PIDFD-support.patch`
- `scripts/release/{build-device-tarball.sh,build-rootfs-image.sh,make-installer-zip.sh,add-devel-access.sh,configure-polkit-legacy.sh,add-openstore-compat.sh}`
- `installer/install/a50-install.sh`
- `overlay/system/var/lib/lxc/android/a50-mount-hooks.sh`
- `overlay/system/usr/local/bin/{a50-container-prepare.sh,a50-audio-hidl-compat.sh}`
- `overlay/README.md`, `ramdisk-overlay/README.md`
- `docs/SESSION-HANDOFF-08.md` through `-16.md` (AppArmor/SELinux stubs)