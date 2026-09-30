# Ubuntu Touch installer for the Samsung Galaxy Tab A 10.1 (2019), SM-T510.
# Sourced by update-binary; ui_print/abort/ZIP/TMP come from there.
# Writes the boot partition, /data/rootfs.img and /data/android-rootfs.img.

ui_print " "
ui_print "=============================================="
ui_print " Ubuntu Touch 24.04 - Galaxy Tab A 10.1 SM-T510"
ui_print "=============================================="
ui_print " "

find_part() {
    for base in /dev/block/by-name /dev/block/platform/*/by-name; do
        [ -e "$base/$1" ] && { readlink -f "$base/$1"; return 0; }
    done
    return 1
}

device=$(getprop ro.product.device)
model=$(getprop ro.product.model)
case "$device:$model" in
    gta3xl*|*T510*) ;;
    *) abort "this is '$device' ($model), not an SM-T510 (gta3xlwifi)" ;;
esac

BOOT_DEV=$(find_part boot) || abort "no boot partition found"
boot_bytes=$(( $(cat "/sys/class/block/$(basename "$BOOT_DEV")/size") * 512 ))
ui_print "boot      $BOOT_DEV ($boot_bytes bytes)"

unzip -o "$ZIP" install/SHA256SUMS install/manifest.txt -d "$TMP" >/dev/null 2>&1
[ -f "$TMP/install/SHA256SUMS" ] || abort "this zip has no SHA256SUMS"
# Only plain sh builtins here: TWRP's grep/awk are minimal.
sum_of() {
    while read -r h f; do
        [ "$f" = "$1" ] || [ "$f" = "*$1" ] && { echo "$h"; return 0; }
    done < "$TMP/install/SHA256SUMS"
}
first_field() { read -r x _ ; echo "$x"; }
manifest_get() {
    while IFS='=' read -r k v; do [ "$k" = "$1" ] && { echo "$v"; return 0; }; done < "$TMP/install/manifest.txt"
}
BOOT_SHA=$(sum_of boot.img)
ROOTFS_SHA=$(sum_of rootfs.img)
ANDROID_SHA=$(sum_of android-rootfs.img)
[ -n "$BOOT_SHA" ] && [ -n "$ROOTFS_SHA" ] && [ -n "$ANDROID_SHA" ] || abort "SHA256SUMS is missing an entry"
while read -r line; do ui_print "  $line"; done < "$TMP/install/manifest.txt"
VARIANT=$(manifest_get variant)
ui_print " "

mount /data >/dev/null 2>&1
grep -q " /data " /proc/mounts || abort "/data is not mounted.
   Wipe > Format Data (type 'yes') first; Samsung's /data is encrypted."
if [ -d /data/system/users ] || [ -e /data/system/packages.xml ]; then
    abort "/data still holds Android. Wipe > Format Data first."
fi
set -- $(df -k /data | tail -1)
free_kb=$4
need_kb=$(( ($(manifest_get rootfs_bytes) + $(manifest_get android_rootfs_bytes)) / 1024 ))
[ "$free_kb" -gt $((need_kb + 262144)) ] || abort "/data has ${free_kb}K free, need ${need_kb}K"

ui_print "Writing boot..."
unzip -o "$ZIP" install/boot.img -d "$TMP" >/dev/null 2>&1 || abort "no install/boot.img"
got=$(sha256sum "$TMP/install/boot.img" | first_field)
[ "$got" = "$BOOT_SHA" ] || abort "boot.img in the zip is corrupt"
img_bytes=$(wc -c < "$TMP/install/boot.img")
[ "$img_bytes" -le "$boot_bytes" ] || abort "boot.img ($img_bytes) is larger than the partition"
dd if="$TMP/install/boot.img" of="$BOOT_DEV" bs=1048576 >/dev/null 2>&1 || abort "dd to $BOOT_DEV failed"
sync
back=$(dd if="$BOOT_DEV" bs=512 count=$(( (img_bytes + 511) / 512 )) 2>/dev/null \
       | head -c "$img_bytes" | sha256sum | first_field)
[ "$back" = "$BOOT_SHA" ] || abort "boot read-back does NOT match. DO NOT REBOOT; reflash boot."
ui_print "  boot verified"
rm -f "$TMP/install/boot.img"

ui_print " "
ui_print "Writing /data/rootfs.img (several minutes)..."
rm -f /data/rootfs.img
unzip -p "$ZIP" install/rootfs.img.gz | gzip -dc > /data/rootfs.img || abort "could not write /data/rootfs.img"
sync
ui_print "  hashing..."
back=$(sha256sum /data/rootfs.img | first_field)
[ "$back" = "$ROOTFS_SHA" ] || abort "rootfs.img on /data does NOT match (full or failing /data?)"
ui_print "  rootfs verified"

ui_print " "
ui_print "Writing /data/android-rootfs.img (Halium GSI)..."
rm -f /data/android-rootfs.img
unzip -p "$ZIP" install/android-rootfs.img.gz | gzip -dc > /data/android-rootfs.img || abort "could not write /data/android-rootfs.img"
sync
back=$(sha256sum /data/android-rootfs.img | first_field)
[ "$back" = "$ANDROID_SHA" ] || abort "android-rootfs.img on /data does NOT match"
ui_print "  android-rootfs verified"
[ "$VARIANT" = devel ] && : > /data/.force-ssh
sync
rm -rf "$TMP"

ui_print " "
ui_print "Done. Reboot > System. First boot takes a few minutes."
if [ "$VARIANT" = devel ]; then
    ui_print "DEBUG image: SSH on, root/phablet password 1234."
    ui_print "  USB:  ssh phablet@10.15.19.82   or   adb shell"
fi
ui_print "If it hangs at boot, plug USB and: telnet 192.168.2.15"
ui_print " "
