#!/bin/sh
# SM-T510: generate container override files before the Android container
# starts, and hook t510-mount-hooks.sh into LXC's mount hook.
H=/var/lib/lxc/android
S=/android/system
src="$S/etc/init/init.disabled.rc"
if [ -r "$src" ]; then
    awk '
        /^service / { suppress = 0 }
        /^service vendor\.audio-hal(-2-0)? / { suppress = 1 }
        suppress { print "# t510: audio HIDL re-enabled: " $0; next }
        { print }
    ' "$src" > "$H/init.disabled.rc.audiofix.tmp" && \
        mv "$H/init.disabled.rc.audiofix.tmp" "$H/init.disabled.rc.audiofix"
fi
if ! grep -q t510-mount-hooks.sh "$H/mount.sh"; then
    printf '\n# SM-T510 port\n[ -x %s/t510-mount-hooks.sh ] && . %s/t510-mount-hooks.sh\n' "$H" "$H" >> "$H/mount.sh"
fi
