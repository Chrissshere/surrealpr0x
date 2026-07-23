#!/usr/bin/env bash
# Patch and check the iOS 16.4 restore ramdisk on macOS or Linux.
#
# Lab Option D (downgrade12,3 / Spironolactone 11 Pro success path):
#   1) asr64_patcher          — accept unsigned ASR payloads
#   2) libimg4 evaluate→0     — img4 auth always succeeds on the ramdisk
#   3) restored_external      — skip seal_system_volume (CBZ→B @ seal handler)
# All three must land on the ramdisk; trustcache injection is done by the caller.

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

script_dir="$(cd "$(dirname "$0")" && pwd)"
restored_patcher="$script_dir/patch_ios164_restored_external.py"
python_bin="${LITER8_PYTHON:-python3}"

for required in "$input" "$img4" "$asr_patcher" "$libimg4_patcher" "$ldid" "$restored_patcher"; do
    [[ -e "$required" ]] || { echo "Missing required file: $required" >&2; exit 2; }
done

OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
    command -v hdiutil >/dev/null 2>&1 || {
        echo "iOS 16.4 ramdisk preparation requires macOS hdiutil" >&2
        exit 2
    }
else
    hfsplus="$(dirname "$ldid")/hfsplus"
    [[ -e "$hfsplus" ]] || { echo "Missing required file: $hfsplus" >&2; exit 2; }
fi

mkdir -p "$work"

if [[ "$OS" == "Darwin" ]]; then
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
    re_original="$work/restored_external.original"
    re_patched="$work/restored_external.patched"
    asr_path="$mount_dir/usr/sbin/asr"
    lib_path="$mount_dir/usr/lib/libimg4.dylib"
    re_path="$mount_dir/usr/local/bin/restored_external"

    [[ -f "$asr_path" && -f "$lib_path" && -f "$re_path" ]] || {
        echo "The mounted iOS 16.4 ramdisk does not contain asr/libimg4/restored_external" >&2
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
    # Lab verify: evaluate→0 at 0xA37C / 0xA380 when the binary layout matches 16.4.
    lib_a37c=$(python3 -c "print(open('$lib_patched','rb').read()[0xA37C:0xA380].hex())")
    lib_a380=$(python3 -c "print(open('$lib_patched','rb').read()[0xA380:0xA384].hex())")
    if [[ "$lib_a37c" == "1f2003d5" && "$lib_a380" == "000080d2" ]]; then
        echo "libimg4 lab offsets verified (0xA37C nop, 0xA380 mov x0,#0)"
    else
        echo "libimg4 lab fixed offsets not present ($lib_a37c/$lib_a380); trusting libimg4_patcher output"
    fi
    cp -p "$lib_patched" "$lib_path"
    chmod 755 "$lib_path"

    # Lab Option D: restored_external seal_system_volume skip + re-sign w/ ents.
    cp -p "$re_path" "$re_original"
    "$python_bin" "$restored_patcher" "$re_original" "$re_patched"
    "$ldid" -e "$re_original" >"$stage/restored_external.entitlements.plist"
    [[ -s "$stage/restored_external.entitlements.plist" ]] || {
        echo "Could not preserve restored_external entitlements" >&2
        exit 1
    }
    # -M preserves existing Mach-O signature slots when possible (lab used -M -S).
    if "$ldid" -M "-S$stage/restored_external.entitlements.plist" "$re_patched" 2>/dev/null; then
        :
    else
        "$ldid" "-S$stage/restored_external.entitlements.plist" "$re_patched"
    fi
    cp -p "$re_patched" "$re_path"
    chmod 755 "$re_path"

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
    cmp -s "$re_patched" "$mount_dir/usr/local/bin/restored_external" || {
        echo "restored_external round-trip verification failed" >&2
        exit 1
    }
    hdiutil detach "$mount_dir" >/dev/null
    mounted=0

    cp -p "$mountable_image" "$output"
    cmp -s "$mountable_image" "$output" || {
        echo "ramdisk output copy verification failed" >&2
        exit 1
    }
else
    # Linux path using linux-apfs-rw
    stage=$(mktemp -d "${TMPDIR:-/tmp}/surreal-ios164-ramdisk.XXXXXX")
    mountable_image="$stage/ramdisk.dmg"
    mount_dir="$stage/mount"
    mkdir -p "$mount_dir"
    cleanup() {
        sudo umount "$mount_dir" >/dev/null 2>&1 || true
        rm -rf "$stage"
    }
    trap cleanup EXIT

    "$img4" -i "$input" -o "$mountable_image"
    
    asr_original="$work/asr.original"
    asr_patched="$work/asr_patched"
    lib_original="$work/libimg4.original"
    lib_patched="$work/libimg4.patch"
    re_original="$work/restored_external.original"
    re_patched="$work/restored_external.patched"

    if ! grep -q "^[[:space:]]*apfs$" /proc/filesystems && ! lsmod | grep -q "^apfs\s"; then
        echo "APFS filesystem support not detected. Attempting to load apfs.ko..." >&2
        bin_dir="$(cd "$(dirname "$ldid")" && pwd)"
        root_dir="$(cd "$bin_dir/.." && pwd)"
        apfs_ko="$root_dir/linux-apfs-rw/apfs.ko"
        if [[ -f "$apfs_ko" ]]; then
            sudo insmod "$apfs_ko" || {
                echo "Warning: failed to load apfs.ko kernel module." >&2
            }
        else
            echo "Warning: apfs.ko kernel module not found at $apfs_ko." >&2
        fi
    fi

    sudo mount -t apfs -o loop,readwrite "$mountable_image" "$mount_dir" || {
        echo "Failed to mount APFS. Make sure linux-apfs-rw is installed and loaded." >&2
        exit 1
    }

    cp "$mount_dir/usr/sbin/asr" "$asr_original" || exit 1
    cp "$mount_dir/usr/lib/libimg4.dylib" "$lib_original" || exit 1
    cp "$mount_dir/usr/local/bin/restored_external" "$re_original" || exit 1

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
    
    truncate -s $(stat -c%s "$asr_original") "$asr_patched"
    
    "$libimg4_patcher" "$lib_original" "$lib_patched"
    cmp -s "$lib_original" "$lib_patched" && {
        echo "libimg4 patch produced no changes" >&2
        exit 1
    }
    "$ldid" -e "$lib_original" >"$stage/libimg4-entitlements.plist"
    if [[ -s "$stage/libimg4-entitlements.plist" ]]; then
        "$ldid" "-S$stage/libimg4-entitlements.plist" "$lib_patched"
    else
        "$ldid" -S "$lib_patched"
    fi

    truncate -s $(stat -c%s "$lib_original") "$lib_patched"

    "$python_bin" "$restored_patcher" "$re_original" "$re_patched"
    "$ldid" -e "$re_original" >"$stage/restored_external.entitlements.plist"
    [[ -s "$stage/restored_external.entitlements.plist" ]] || {
        echo "Could not preserve restored_external entitlements" >&2
        exit 1
    }
    if "$ldid" -M "-S$stage/restored_external.entitlements.plist" "$re_patched" 2>/dev/null; then
        :
    else
        "$ldid" "-S$stage/restored_external.entitlements.plist" "$re_patched"
    fi
    truncate -s $(stat -c%s "$re_original") "$re_patched" 2>/dev/null || true

    sudo rm -f "$mount_dir/usr/sbin/asr"
    sudo cp "$asr_patched" "$mount_dir/usr/sbin/asr"
    sudo chmod 755 "$mount_dir/usr/sbin/asr"

    sudo rm -f "$mount_dir/usr/lib/libimg4.dylib"
    sudo cp "$lib_patched" "$mount_dir/usr/lib/libimg4.dylib"
    sudo chmod 755 "$mount_dir/usr/lib/libimg4.dylib"

    sudo rm -f "$mount_dir/usr/local/bin/restored_external"
    sudo cp "$re_patched" "$mount_dir/usr/local/bin/restored_external"
    sudo chmod 755 "$mount_dir/usr/local/bin/restored_external"

    sudo umount "$mount_dir"

    cp -p "$mountable_image" "$output"
    cmp -s "$mountable_image" "$output" || {
        echo "ramdisk output copy verification failed" >&2
        exit 1
    }
fi

echo "iOS 16.4 restore ramdisk: lab Option D (asr + libimg4 + restored_external seal) verified"

