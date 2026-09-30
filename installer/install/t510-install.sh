# Ubuntu Touch installer for the Samsung Galaxy Tab A 10.1 (2019), SM-T510.
# Sourced by update-binary; ui_print/abort/ZIP/TMP come from there.
# Writes exactly two things: the boot partition and /data/rootfs.img.

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
sum_of() { grep " \*\?$1\$" "$TMP/install/SHA256SUMS" | awk '{print $1}'; }
BOOT_SHA=$(sum_of boot.img)
ROOTFS_SHA=$(sum_of rootfs.img)
[ -n "$BOOT_SHA" ] && [ -n "$ROOTFS_SHA" ] || abort "SHA256SUMS is missing an entry"
while read -r line; do ui_print "  $line"; done < "$TMP/install/manifest.txt"
ui_print " "

mount /data >/dev/null 2>&1
grep -q " /data " /proc/mounts || abort "/data is not mounted.
   Wipe > Format Data (type 'yes') first; Samsung's /data is encrypted."
if [ -d /data/system/users ] || [ -e /data/system/packages.xml ]; then
    abort "/data still holds Android. Wipe > Format Data first."
fi
free_kb=$(df /data | tail -1 | awk '{print $4}')
need_kb=$(( $(grep '^rootfs_bytes=' "$TMP/install/manifest.txt" | cut -d= -f2) / 1024 ))
[ "$free_kb" -gt $((need_kb + 262144)) ] || abort "/data has ${free_kb}K free, need ${need_kb}K"

ui_print "Writing boot..."
unzip -o "$ZIP" install/boot.img -d "$TMP" >/dev/null 2>&1 || abort "no install/boot.img"
got=$(sha256sum "$TMP/install/boot.img" | awk '{print $1}')
[ "$got" = "$BOOT_SHA" ] || abort "boot.img in the zip is corrupt"
img_bytes=$(stat -c%s "$TMP/install/boot.img")
[ "$img_bytes" -le "$boot_bytes" ] || abort "boot.img ($img_bytes) is larger than the partition"
dd if="$TMP/install/boot.img" of="$BOOT_DEV" bs=1048576 >/dev/null 2>&1 || abort "dd to $BOOT_DEV failed"
sync
back=$(dd if="$BOOT_DEV" bs=512 count=$(( (img_bytes + 511) / 512 )) 2>/dev/null \
       | head -c "$img_bytes" | sha256sum | awk '{print $1}')
[ "$back" = "$BOOT_SHA" ] || abort "boot read-back does NOT match. DO NOT REBOOT; reflash boot."
ui_print "  boot verified"
rm -f "$TMP/install/boot.img"

ui_print " "
ui_print "Writing /data/rootfs.img (several minutes)..."
rm -f /data/rootfs.img
unzip -p "$ZIP" install/rootfs.img.gz | gzip -dc > /data/rootfs.img || abort "could not write /data/rootfs.img"
sync
ui_print "  hashing..."
back=$(sha256sum /data/rootfs.img | awk '{print $1}')
[ "$back" = "$ROOTFS_SHA" ] || abort "rootfs.img on /data does NOT match (full or failing /data?)"
ui_print "  rootfs verified"
: > /data/.force-ssh
sync
rm -rf "$TMP"

ui_print " "
ui_print "Done. Reboot > System. First boot takes a few minutes."
ui_print "Debug image: SSH on, root/phablet password 1234."
ui_print "  USB:  ssh phablet@10.15.19.82   or   adb shell"
ui_print "If it hangs at boot, plug USB and: telnet 192.168.2.15"
ui_print " "
