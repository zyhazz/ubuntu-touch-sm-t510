#!/bin/sh
# SM-T510: host side of the 64-bit audio bridge for PulseAudio (libhybris).
# 1) bind audio.hidl_compat over the 64-bit audio.primary.default.so stub
# 2) let the sphal namespace reach libaudiohal* in the default namespace
LD_CONF=/linkerconfig/ld.config.txt
WRAPPER=/android/system/lib64/hw/audio.hidl_compat.default.so
HAL=/android/vendor/lib64/hw/audio.primary.default.so
ANCHOR='namespace.sphal.link.default.shared_libs += libfdtrack.so'
LIBS='libaudiohal.so libaudiohal@5.0.so libaudiohal_deathhandler.so'
[ -e "$WRAPPER" ] || exit 0
i=0; while [ ! -s "$LD_CONF" ] && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
if [ -s "$LD_CONF" ] && ! grep -q libaudiohal.so "$LD_CONF" && grep -qF "$ANCHOR" "$LD_CONF"; then
    ins=""; for l in $LIBS; do ins="${ins}namespace.sphal.link.default.shared_libs += ${l}\n"; done
    tmp=$(mktemp)
    awk -v a="$ANCHOR" -v ins="$ins" '$0 == a { print; printf "%s", ins; next } { print }' "$LD_CONF" > "$tmp" && cat "$tmp" > "$LD_CONF"
    rm -f "$tmp"
fi
if [ "$(stat -c %s "$HAL")" != "$(stat -c %s "$WRAPPER")" ]; then
    mount --bind "$WRAPPER" "$HAL"
fi
