#!/usr/bin/env bash
# Patch and check the iOS 16.4 restore ramdisk on macOS.

set -euo pipefail

if [[ $# -ne 7 ]]; then
    echo "Usage: $0 <input.im4p> <output.dmg> <work-dir> <img4> <asr-patcher> <libimg4-patcher> <ldid>" >&2
    exit 2
fi

input="$1"
output="$2"
work="$3"
img4="$4"
asr_patcher="$5"
libimg4_patcher="$6"
ldid="$7"

for required in "$input" "$img4" "$asr_patcher" "$libimg4_patcher" "$ldid"; do
    [[ -e "$required" ]] || { echo "Missing required file: $required" >&2; exit 2; }
done
command -v hdiutil >/dev/null 2>&1 || {
    echo "iOS 16.4 ramdisk preparation requires macOS hdiutil" >&2
    exit 2
}

mkdir -p "$work"
stage=$(mktemp -d "${TMPDIR:-/tmp}/surreal-ios164-ramdisk.XXXXXX")
mount_dir="$stage/mount"
mountable_image="$stage/ramdisk.dmg"
mounted=0

cleanup() {
    if [[ "$mounted" == 1 ]]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || \
            hdiutil detach -force "$mount_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$stage"
}
trap cleanup EXIT

"$img4" -i "$input" -o "$mountable_image"
mkdir "$mount_dir"
# Mount without preserving owners so the current user can write the image.
hdiutil attach -readwrite -nobrowse -owners off -mountpoint "$mount_dir" "$mountable_image" >/dev/null
mounted=1

asr_original="$work/asr.original"
asr_patched="$work/asr_patched"
lib_original="$work/libimg4.original"
lib_patched="$work/libimg4.patch"
asr_path="$mount_dir/usr/sbin/asr"
lib_path="$mount_dir/usr/lib/libimg4.dylib"

[[ -f "$asr_path" && -f "$lib_path" ]] || {
    echo "The mounted iOS 16.4 ramdisk does not contain the expected binaries" >&2
    exit 1
}

cp -p "$asr_path" "$asr_original"
"$asr_patcher" "$asr_original" "$asr_patched"
cmp -s "$asr_original" "$asr_patched" && {
    echo "asr patch produced no changes" >&2
    exit 1
}
"$ldid" -e "$asr_original" >"$stage/asr-entitlements.plist"
[[ -s "$stage/asr-entitlements.plist" ]] || {
    echo "Could not preserve asr entitlements" >&2
    exit 1
}
"$ldid" "-S$stage/asr-entitlements.plist" "$asr_patched"
cp -p "$asr_patched" "$asr_path"
chmod 755 "$asr_path"

cp -p "$lib_path" "$lib_original"
"$libimg4_patcher" "$lib_original" "$lib_patched"
cmp -s "$lib_original" "$lib_patched" && {
    echo "libimg4 patch produced no changes" >&2
    exit 1
}
"$ldid" -e "$lib_original" >"$stage/libimg4-entitlements.plist"
if [[ -s "$stage/libimg4-entitlements.plist" ]]; then
    "$ldid" "-S$stage/libimg4-entitlements.plist" "$lib_patched"
else
    # The stock libimg4 has no entitlements, so sign it before adding its hash.
    "$ldid" -S "$lib_patched"
fi
cp -p "$lib_patched" "$lib_path"
chmod 755 "$lib_path"

sync
hdiutil detach "$mount_dir" >/dev/null
mounted=0

# Mount the result again and compare the patched files.
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$mountable_image" >/dev/null
mounted=1
cmp -s "$asr_patched" "$mount_dir/usr/sbin/asr" || {
    echo "asr round-trip verification failed" >&2
    exit 1
}
cmp -s "$lib_patched" "$mount_dir/usr/lib/libimg4.dylib" || {
    echo "libimg4 round-trip verification failed" >&2
    exit 1
}
hdiutil detach "$mount_dir" >/dev/null
mounted=0

cp -p "$mountable_image" "$output"
cmp -s "$mountable_image" "$output" || {
    echo "ramdisk output copy verification failed" >&2
    exit 1
}

echo "iOS 16.4 restore ramdisk: patched and round-trip verified"
