#!/bin/bash
CURRENT_VERSION="v2.0 beta 29"
UPDATE_REPOSITORY_URL="https://github.com/Chrissshere/surrealpr0x"
UPDATE_BRANCH="ios164-beta"

if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Do not run this script with sudo or as root."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

clear

IPSW_PATH=""
IPSW_PATH_LATEST=""
SHSH_PATH=""
dfu_instructions=""
restorefiles_remake=""
VERSION=""
BUILD=""
VERSION_LATEST=""
IOS164_BUILD_DEVICE=""
IOS164_IMG4=""
IOS164_TARGET_IDENTITY=""
IOS164_BASE_IDENTITY=""
IOS164_TARGET_VERSION=""
IOS164_TARGET_BUILD=""
IOS164_BASE_VERSION=""
IOS164_BASE_BUILD="23F84"
IOS164_TARGET_KERNEL=""
IOS164_BASE_KERNEL=""
IOS164_TARGET_OS=""
IOS164_BASE_OS=""
IOS164_TARGET_RAMDISK=""
IOS164_BASE_RAMDISK=""
IOS164_TARGET_TRUSTCACHE=""
IOS164_BASE_TRUSTCACHE=""
IOS164_TARGET_IBSS=""
IOS164_BASE_IBSS=""
IOS164_TARGET_IBEC=""
IOS164_BASE_IBEC=""
if [[ "${1:-}" == "ios164-build" && "${2:-}" == iPhone* ]]; then
    IOS164_BUILD_DEVICE="$2"
fi

set -euo pipefail

error_handler() {
    local exit_code=$?
    local failed_command="$BASH_COMMAND"
    local line_number="${BASH_LINENO[0]}"
    local script_file="${BASH_SOURCE[1]:-$0}"

    {
        echo "[!] surrealra1n has crashed due to an issue"
        echo "[!] Exit code: $exit_code"
        echo "[!] Script: $script_file"
        echo "[!] Line: $line_number"
        echo "[!] Failed command: $failed_command"
        echo
        echo "[!] It is recommended to report this issue here:"
        echo "    https://github.com/pwnerblu/surrealra1n/issues"
        echo "Here's the recommended way to report this:"
        echo "Title should be a brief and clear summary of the issue you are trying to report"
        echo "Issue description should mention all relevant details to such issue if possible, and also a full terminal log attached."
        echo "[!] Issues THAT DO NOT CONTAIN PROPER LOGS, DETAILS, OR ANYTHING RELEVANT, WILL BE CLOSED AS INVALID."
        echo 
        echo "[!] To attach this log into your issue, do the following:"
        if [[ $dist == 3 || $dist == 4 ]]; then
            echo "Cmd + A -> Cmd + C, then paste the entire log into your issue you're opening"
        else
            echo "Ctrl + Shift + A -> Ctrl + Shift + C, then paste the entire log into the issue you're opening"
        fi
    } 

    exit "$exit_code"
}

trap 'error_handler $LINENO' ERR

echo "Your surrealra1n version: $CURRENT_VERSION"
if [[ "${1:-}" == "ios164-build" ]]; then
    # Do not use sudo or clear temporary files before validation.
    echo "iOS 16.4 build-only mode: no sudo and no device changes."
else
    # Request sudo for the legacy interactive workflow.
    echo "Enter your user password when prompted to"
    sudo -v || exit 1

    sudo rm -rf "tmp"
    sudo rm -rf "tmp1"
    sudo rm -rf "tmp2"
    sudo rm -rf "work"
fi

dist=0

JAILBREAK=0

DISTRO="Unsupported"
ARCH="$(uname -m)"

macos_binary_matches_host(){
    local helper helper_archs

    [[ -f "$1" ]] || return 0
    helper="$1"
    if command -v lipo >/dev/null 2>&1; then
        helper_archs=$(lipo -archs "$helper" 2>/dev/null || true)
    else
        helper_archs=$(file -b "$helper" 2>/dev/null || true)
    fi
    [[ " $helper_archs " == *" $ARCH "* ]]
}

macos_helpers_match_host(){
    local helper

    [[ $dist == 4 ]] || return 0
    for helper in \
        tools/img4-ios164 \
        bin/img4 \
        bin/kerneldiff \
        bin/iBootPatch \
        bin/iBootpatch2 \
        bin/Kernel64Patcher3 \
        bin/asr64_patcher \
        bin/libimg4_patcher \
        bin/ldid \
        bin/trustcache \
        futurerestore/futurerestore; do
        macos_binary_matches_host "$helper" || return 1
    done
}

# macOS detection
if [[ "$(uname)" == "Darwin" ]]; then
    DISTRO="macOS"
    if [[ "$ARCH" == "arm64" ]]; then
        echo "You are running surrealra1n on an Apple Silicon Mac."
        dist=3
        echo
    elif [[ "$ARCH" == "x86_64" ]]; then
        echo "You are running surrealra1n on Intel macOS."
        dist=4
        echo
    fi
# Linux detection
elif [[ -r /etc/os-release ]]; then
    . /etc/os-release

    if [[ "$ID" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
        DISTRO="Arch"
        dist=2
    elif [[ "$ID" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
        DISTRO="Debian"
        dist=1
        read -n 1 -s -r -p "Press any key to continue"
    elif [[ "$ID" == "fedora" || "${ID_LIKE:-}" == *fedora* || "${ID_LIKE:-}" == *rhel* ]]; then
        DISTRO="Fedora"
        dist=5
        read -n 1 -s -r -p "Press any key to continue"
    # generic Linux fallback
    elif command -v apt-get &>/dev/null; then
        DISTRO="Debian"
        dist=1
        echo "Unrecognized distro; treating as Debian-based (apt-get detected)."
        read -n 1 -s -r -p "Press any key to continue"
    elif command -v pacman &>/dev/null; then
        DISTRO="Arch"
        dist=2
        echo "Unrecognized distro; treating as Arch-based (pacman detected)."
    elif command -v dnf &>/dev/null; then
        DISTRO="Fedora"
        dist=5
        echo "Unrecognized distro; treating as Fedora-based (dnf detected)."
        read -n 1 -s -r -p "Press any key to continue"
    elif command -v zypper &>/dev/null; then
        DISTRO="Fedora"
        dist=5
        echo "Unrecognized distro; treating as Fedora-based (zypper detected, using dnf flow)."
        read -n 1 -s -r -p "Press any key to continue"
    fi
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    # prevent finder from annoying you
    killall -STOP AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater 2>/dev/null
fi

# Run macOS version check only if you're on macOS, should fix Linux
if [[ $dist == 3 || $dist == 4 ]]; then
    macmodel=$(sysctl -n hw.model) 

    # Outdated macOS ver check
    macos_ver=$(sw_vers -productVersion) 
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    if [[ "$(printf '%s\n' "10.15" "$macos_ver" | sort -V | head -n1)" == "10.15" ]]; then
        echo "Your macOS version $macos_ver is supported."
    else
        echo "surrealra1n only supports macOS 10.15 and later."
        exit 1
    fi
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    # Check for Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        echo "Xcode Command Line Tools are not installed. Installing..."
        xcode-select --install
        echo "Please re-run surrealra1n after the installation completes."
        exit 1
    else
        echo "Xcode Command Line Tools are installed."
    fi

    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        echo "[!] Homebrew is not installed. You will need to install Homebrew from https://brew.sh"
        exit 1
    else
        echo "Homebrew is installed."
    fi

    # Check for missing brew dependencies
    BREW_DEPS=("libimobiledevice" "libirecovery" "binutils")
    for dep in "${BREW_DEPS[@]}"; do
        if ! brew list "$dep" &>/dev/null; then
            echo "[$dep] is not installed. Installing..."
            brew install "$dep"
        else
            echo "[$dep] is installed."
        fi
    done
fi

# Check for Rosetta 2 (Apple Silicon only)
if [[ $dist == 3 ]]; then
    if ! /usr/bin/pgrep -q oahd; then
        echo "Rosetta 2 is not installed. Installing..."
        softwareupdate --install-rosetta --agree-to-license
    else
        echo "Rosetta 2 is installed."
    fi
fi

# Unsupported check
if [[ "$DISTRO" == "Unsupported" ]]; then
    echo "Unsupported Linux distribution."
    echo "Could not detect a compatible package manager (apt-get, pacman, dnf, or zypper)."
    echo "This script only supports Debian-based, Arch-based, Fedora-based and macOS systems."
    exit 1
fi

echo "Detected distro family: $DISTRO"

if [[ $dist == 3 || $dist == 4 ]]; then
    zenity="./bin/zenity"
else
    zenity="zenity"
fi

pick_file() {
    local p
    p=$($zenity --file-selection --title="$1" 2>/dev/null)
    if [[ -z "$p" ]]; then
        read -e -r -p "$1 - enter absolute path (blank to cancel): " p </dev/tty
    fi
    echo "$p"
}


# Dependency check
echo "Checking for required dependencies..."

if [[ $dist == 1 ]]; then
    DEPENDENCIES=(libusb-1.0-0-dev libusbmuxd-tools libimobiledevice-utils usbmuxd zenity git curl make gcc python3-pip python3-usb)
    MISSING_PACKAGES=()

    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "Missing packages detected: ${MISSING_PACKAGES[*]}"
        echo "Installing missing dependencies..."
        sudo apt update || true # issue workarounds
        sudo apt install -y "${MISSING_PACKAGES[@]}" || true # issue workarounds
    else
        echo "All dependencies are installed." 
    fi
elif [[ $dist == 2 ]]; then
    DEPENDENCIES=(libusb libusbmuxd libimobiledevice usbmuxd zenity git curl make gcc base-devel python-pip)
    MISSING_PACKAGES=()


    for pkg in "${DEPENDENCIES[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "Missing packages detected: ${MISSING_PACKAGES[*]}"
        echo "Installing missing dependencies..."
        sudo pacman -Syu --needed "${MISSING_PACKAGES[@]}"
    else
        echo "All dependencies are already installed."
    fi
elif [[ $dist == 5 ]]; then
    # Fedora/RHEL: the PyUSB package is python3-pyusb (not python3-usb).
    DEPENDENCIES=(libusb1-devel usbmuxd libimobiledevice-utils zenity git curl make gcc python3-pip python3-pyusb)
    MISSING_PACKAGES=()

    for pkg in "${DEPENDENCIES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "Missing packages detected: ${MISSING_PACKAGES[*]}"
        echo "Installing missing dependencies..."
        sudo dnf install -y "${MISSING_PACKAGES[@]}"
    else
        echo "All dependencies are already installed."
    fi
elif [[ "$DISTRO" == "unknown" ]]; then
    echo "Unsupported Linux distribution."
    echo "This script only supports Debian-based, Arch-based, Fedora-based and macOS systems."
    exit 1
fi

#
stat_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"     # Linux (GNU)
    else
        stat -f %z "$1"     # macOS / BSD
    fi
}

find_dmg() {
    dir="$1"          # directory to search
    mode="$2"         # smallest | largest
    max_size="${3:-}"     # optional (bytes)

    find "$dir" -type f -name '*.dmg' ! -name '._*' -print |
    while IFS= read -r f; do
        size=$(stat_size "$f") || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf '%s %s\n' "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

find_dmg_arm64e() {
    dir="$1"          # directory to search
    mode="$2"         # smallest | largest
    max_size="${3:-}"     # optional (bytes)

    find "$dir" -type f -name '*.dmg*' ! -name '._*' -print |
    while IFS= read -r f; do
        size=$(stat_size "$f") || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf '%s %s\n' "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

# boot file error handling improvements

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "[!] Required file missing: $1"
        exit 1
    fi
}

require_dir() {
    if [[ ! -d "$1" ]]; then
        echo "[!] Required directory missing: $1"
        exit 1
    fi
}

#

if [[ "${1:-}" == "ios164-build" ]]; then
    echo "Skipping update prompt in build-only mode."
else
    echo "Checking for updates..."
    mkdir -p update
    rm -rf update/latest.txt
    LATEST_VERSION=""
    RELEASE_NOTES=""
    if curl -fsSL --retry 2 -o update/latest.txt "$UPDATE_REPOSITORY_URL/raw/refs/heads/$UPDATE_BRANCH/update/latest.txt?cachebust=$(date +%s)"; then
        LATEST_VERSION=$(head -n 1 "update/latest.txt" | tr -d '\r\n')
        RELEASE_NOTES=$(awk '/^RELEASE NOTES:/{flag=1; next} flag' "update/latest.txt")
    fi

    if [[ -z "$LATEST_VERSION" ]]; then
        echo "Could not read update information. Continuing without an update check."
    elif [[ "$LATEST_VERSION" != "$CURRENT_VERSION" ]]; then
        CURRENT_BETA=""
        LATEST_BETA=""
        if [[ "$CURRENT_VERSION" =~ [[:space:]]beta[[:space:]]+([0-9]+) ]]; then
            CURRENT_BETA="${BASH_REMATCH[1]}"
        fi
        if [[ "$LATEST_VERSION" =~ [[:space:]]beta[[:space:]]+([0-9]+) ]]; then
            LATEST_BETA="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$CURRENT_BETA" && -n "$LATEST_BETA" ]] && (( 10#$LATEST_BETA <= 10#$CURRENT_BETA )); then
            echo "Ignoring stale beta update marker: $LATEST_VERSION"
        else
            echo "A new version of surrealra1n is available: $LATEST_VERSION"
            echo "RELEASE NOTES:"
            echo "$RELEASE_NOTES"
            echo ""
            echo "It is strongly recommended to update to get the latest features + bug fixes."
            read -p "Would you like to update now? (y/n): " update
            if [[ $update == y || $update == Y ]]; then
                rm -rf "updatefiles"
                mkdir updatefiles
                rm -rf "updatefiles/repo"
                git clone --branch "$UPDATE_BRANCH" "$UPDATE_REPOSITORY_URL" updatefiles/repo --recursive
                if [[ ! -d updatefiles/repo ]]; then
                    echo "Failed to clone repository."
                    exit 1
                fi
                rm -rf "surrealra1n.old"
                mkdir -p surrealra1n.old # make folder to back up old surrealra1n installation
                echo "$CURRENT_VERSION" > surrealra1n.old/oldversion.txt
                echo "Backing up your current surrealra1n installation..."
                mv -v bin surrealra1n.old/
                mv -v futurerestore surrealra1n.old/
                mv -v keys surrealra1n.old/
                mv -v surrealra1n.sh surrealra1n.old/
                rm -rf "bin"
                rm -rf "futurerestore"
                rm -rf "keys"
                echo "Copying new files..."
                cp -av updatefiles/repo/. ./
                chmod +x surrealra1n.sh

                rm -rf "updatefiles"
                echo "surrealra1n has been updated! Please run the script again"
                exit 0
            else
                echo "You have declined the update. Continuing with the current version."
                read -p "Press enter to continue"
            fi
        fi
    else
        echo "surrealra1n is up to date."
        sleep 1
    fi
fi

echo "Checking for existing binaries..."

#!/bin/bash

MACOS_HELPERS_NEED_REBUILD=0
if [[ $dist == 3 || $dist == 4 ]] && ! macos_helpers_match_host; then
    MACOS_HELPERS_NEED_REBUILD=1
    echo "Some macOS helpers were built for another CPU. Rebuilding them for $ARCH."
fi

# Check if all required binaries exist
if [[ -f "./bin/img4" && \
      -f "./bin/img4tool" && \
      -f "./bin/irecovery" && \
      -f "./bin/kairos" && \
      -f "./bin/kerneldiff" && \
      -f "./bin/KPlooshFinder" && \
      -f "./bin/gaster" && \
      -f "./bin/Kernel64Patcher" && \
      -f "./bin/Kernel64Patcher2" && \
      -f "./bin/dmg" && \
      -f "./bin/pzb" && \
      -f "./bin/zenity" && \
      -f "./bin/iBoot64Patcher" && \
      -f "./bin/iBootPatch" && \
      -f "./bin/iBootpatch2" && \
      -f "./bin/asr64_patcher" && \
      -f "./bin/libimg4_patcher" && \
      -f "./bin/Kernel64Patcher3" && \
      -f "./bin/trustcache" && \
      -f "./bin/ipx_restored_patcher" && \
      -f "./bin/restored_external64_patcher" && \
      -f "./bin/restoredpatcher" && \
      -f "./bin/hfsplus" && \
      -f "./bin/tsschecker" && \
      -f "./bin/ipatcher" && \
      -f "./bin/iproxy" && \
      -f "./bin/dtree_patcher" && \
      -f "./bin/sshpass" && \
      -f "./bin/dsc64patcher" && \
      -f "./bin/idevicerestore" && \
      -f "./bin/ldid" && \
      -f "./activate.sh" && \
      -f "./backup.sh" && \
      -f "./futurerestore/futurerestore" && \
      $MACOS_HELPERS_NEED_REBUILD -eq 0 ]]; then
    echo "Found necessary binaries."
elif [[ $dist == 3 ]]; then
    echo "Binaries do not exist"
    echo "Downloading binaries..."

    mkdir -p bin futurerestore

    curl -L -o bin/img4 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4
    curl -L -o bin/img4tool https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4tool
    curl -L -o bin/pzb https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/pzb
    curl -L -o bin/KPlooshFinder https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/KPlooshFinder
    curl -L -o bin/dsc64patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dsc64patcher
    curl -L -o bin/kerneldiff https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kerneldiff
    curl -L -o bin/dtree_patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dtree_patcher
    curl -L -o bin/irecovery https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/irecovery
    curl -L -o bin/iBoot64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/iBoot64Patcher
    curl -L -o bin/Kernel64Patcher2 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/Kernel64Patcher
    curl -L -o bin/hfsplus https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus
    curl -L -o bin/zenity https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/zenity
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/fd2e870d832ea59c31a54377370ad469f70e6499/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    # from spironolactone oops
    curl -L -o bin/trustcache https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/trustcache
    curl -L -o bin/iBoot64Patcher2 https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/iBoot64Patcher_cryptic
    # sshpass
    curl -L -o bin/sshpass https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/sshpass
    curl -L -o bin/iproxy https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iproxy
    curl -L -o bin/dmg https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dmg
    curl -L -o bin/ipatcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iPatcher
    # install additional restored_external patcher (iPhone X only)
    curl -L -o bin/ipx_restored_patcher https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/arm64/ipx_restored_patcher
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/991a74e2bbbdebdb1dd2d49d82f0829e7553f02f/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    curl -L -o bin/Kernel64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/Kernel64Patcher
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    git clone https://github.com/pwnerblu/Kernel64Patcher --recursive
    cd Kernel64Patcher
    make
    cp Kernel64Patcher ../bin/Kernel64Patcher3
    cd ..
    rm -rf "Kernel64Patcher"
    git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
    cd iBootpatch2
    make
    cp iBootpatch2 ../bin/iBootpatch2
    cd ..
    rm -rf "iBootpatch2"
    # done!
    curl -L -o bin/gaster https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/gaster
    curl -L -o bin/tsschecker https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/tsschecker
    curl -L -o bin/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64
    curl -L -o bin/kairos https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    curl -L -o futurerestore/futurerestore.zip https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-macOS-RELEASE-main.zip
    # fetch idevicerestore for 7.0-9.3.5 restores 
    curl -L -o bin/idevicerestore https://github.com/NyanSatan/SundanceInH2A/raw/refs/heads/master/executables/Darwin/idevicerestore
    # libs
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-macOS-v2.0.0-Build_329-RELEASE.tar.xz
    if [[ -d futurerestore-macOS-v2.0.0-Build_329-RELEASE ]]; then
        cp futurerestore-macOS-v2.0.0-Build_329-RELEASE/* .
    fi
    chmod +x futurerestore
    [[ -x futurerestore ]] || { echo "futurerestore was not extracted successfully"; exit 1; }
    rm -rf *.tar.xz
    rm -rf *.sh
    rm -rf *.zip
    rm -rf "futurerestore-macOS-v2.0.0-Build_329-RELEASE" 
    cd ..
    xattr -c bin/*
    xattr -c futurerestore/futurerestore
elif [[ $dist == 4 ]]; then
    echo "Binaries do not exist"
    echo "Downloading binaries..."

    mkdir -p bin futurerestore

    curl -L -o bin/img4 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4
    curl -L -o bin/img4tool https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4tool
    curl -L -o bin/pzb https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/pzb
    curl -L -o bin/KPlooshFinder https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/KPlooshFinder
    curl -L -o bin/dsc64patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dsc64patcher
    curl -L -o bin/kerneldiff https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kerneldiff
    curl -L -o bin/dtree_patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dtree_patcher
    curl -L -o bin/irecovery https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/irecovery
    curl -L -o bin/iBoot64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/iBoot64Patcher
    curl -L -o bin/Kernel64Patcher2 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/Kernel64Patcher
    curl -L -o bin/hfsplus https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus
    curl -L -o bin/zenity https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/zenity
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/fd2e870d832ea59c31a54377370ad469f70e6499/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    # from spironolactone oops
    curl -L -o bin/trustcache https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/trustcache
    curl -L -o bin/iBoot64Patcher2 https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/iBoot64Patcher_cryptic
    # sshpass
    curl -L -o bin/sshpass https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/sshpass
    curl -L -o bin/iproxy https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iproxy
    curl -L -o bin/dmg https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dmg
    curl -L -o bin/ipatcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iPatcher
    # install additional restored_external patcher (iPhone X only)
    curl -L -o bin/ipx_restored_patcher https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/ipx_restored_patcher
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/991a74e2bbbdebdb1dd2d49d82f0829e7553f02f/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    curl -L -o bin/Kernel64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/Kernel64Patcher
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    git clone https://github.com/pwnerblu/Kernel64Patcher --recursive
    cd Kernel64Patcher
    make
    cp Kernel64Patcher ../bin/Kernel64Patcher3
    cd ..
    rm -rf "Kernel64Patcher"
    git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
    cd iBootpatch2
    make
    cp iBootpatch2 ../bin/iBootpatch2
    cd ..
    rm -rf "iBootpatch2"
    # done!
    curl -L -o bin/gaster https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/gaster
    curl -L -o bin/tsschecker https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/tsschecker
    curl -L -o bin/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_x86_64
    curl -L -o bin/kairos https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    curl -L -o futurerestore/futurerestore.zip https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-macOS-RELEASE-main.zip
    # fetch idevicerestore for 7.0-9.3.5 restores 
    curl -L -o bin/idevicerestore https://github.com/NyanSatan/SundanceInH2A/raw/refs/heads/master/executables/Darwin/idevicerestore
    # libs
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-macOS-v2.0.0-Build_329-RELEASE.tar.xz
    if [[ -d futurerestore-macOS-v2.0.0-Build_329-RELEASE ]]; then
        cp futurerestore-macOS-v2.0.0-Build_329-RELEASE/* .
    fi
    chmod +x futurerestore
    [[ -x futurerestore ]] || { echo "futurerestore was not extracted successfully"; exit 1; }
    rm -rf *.tar.xz
    rm -rf *.sh
    rm -rf *.zip
    rm -rf "futurerestore-macOS-v2.0.0-Build_329-RELEASE" 
    cd ..
    xattr -c bin/*
    xattr -c futurerestore/futurerestore
else
    echo "Binaries do not exist"
    echo "Downloading binaries..."

    mkdir -p bin futurerestore

    curl -L -o bin/img4 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/img4
    curl -L -o bin/img4tool https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/img4tool
    curl -L -o bin/KPlooshFinder https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/KPlooshFinder
    curl -L -o bin/pzb https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/pzb
    curl -L -o bin/dsc64patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dsc64patcher
    curl -L -o bin/kerneldiff https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/kerneldiff
    curl -L -o bin/dtree_patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dtree_patcher
    curl -L -o bin/irecovery https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/irecovery
    curl -L -o bin/iBoot64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Linux/iBoot64Patcher
    curl -L -o bin/Kernel64Patcher2 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/Kernel64Patcher
    curl -L -o bin/hfsplus https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/hfsplus
    # sshpass
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/fd2e870d832ea59c31a54377370ad469f70e6499/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    curl -L -o bin/trustcache https://github.com/CRKatri/trustcache/releases/download/v2.0/trustcache_linux_x86_64
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    git clone https://github.com/pwnerblu/Kernel64Patcher --recursive
    cd Kernel64Patcher
    make
    cp Kernel64Patcher ../bin/Kernel64Patcher3
    cd ..
    rm -rf "Kernel64Patcher"
    git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
    cd iBootpatch2
    make
    cp iBootpatch2 ../bin/iBootpatch2
    cd ..
    rm -rf "iBootpatch2"
    curl -L -o bin/iBoot64Patcher2 https://github.com/appleiPodTouch4/spironolactone/raw/refs/heads/main/Linux/x86_64/iBoot64patcher_cryptic
    curl -L -o bin/sshpass https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/sshpass
    curl -L -o bin/iproxy https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/iproxy
    curl -L -o bin/zenity https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/zenity
    curl -L -o bin/dmg https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dmg
    curl -L -o bin/ipatcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/ipatcher
    # install additional restored_external patcher (iPhone X only)
    curl -L -o bin/ipx_restored_patcher https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/ipx_restored_patcher
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/991a74e2bbbdebdb1dd2d49d82f0829e7553f02f/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    curl -L -o bin/Kernel64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Linux/Kernel64Patcher
    curl -L -o bin/gaster https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/gaster
    curl -L -o bin/tsschecker https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/tsschecker
    curl -L -o bin/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64
    curl -L -o bin/kairos https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/kairos
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    curl -L -o futurerestore/futurerestore.zip https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-Linux-x86_64-RELEASE-main.zip
    # fetch idevicerestore for 7.0-9.3.5 restores 
    curl -L -o bin/idevicerestore https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/idevicerestore2
    # libs
    rm -rf "lib"
    mkdir lib
    curl -L -o lib/libcrypto.so.35 https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/lib/libcrypto.so.35
    curl -L -o lib/libssl.so.35 https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/lib/libssl.so.35
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE.tar.xz
    if [[ -d futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE ]]; then
        cp futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE/* .
    fi
    chmod +x linux_fix.sh || true
    sudo ./linux_fix.sh || true
    rm -rf linux_fix.sh || true
    chmod +x futurerestore
    [[ -x futurerestore ]] || { echo "futurerestore was not extracted successfully"; exit 1; }
    rm -rf *.tar.xz || true
    rm -rf *.sh || true
    rm -rf *.zip || true
    rm -rf "futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE" 
    cd ..
fi

echo "Checking for dependencies that are required for usbliter8ctl, assuming Python3 is on your system"
# Use a local virtual environment so pyusb works on macOS.
LITER8_PYTHON="python3"
if [[ -x "$SCRIPT_DIR/.venv/bin/python" ]]; then
    LITER8_PYTHON="$SCRIPT_DIR/.venv/bin/python"
elif [[ -x "./.venv/bin/python" ]]; then
    LITER8_PYTHON="./.venv/bin/python"
fi
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    libusb_prefix="$(brew --prefix libusb 2>/dev/null || true)"
    if [[ -f "$libusb_prefix/lib/libusb-1.0.dylib" ]]; then
        export DYLD_FALLBACK_LIBRARY_PATH="$libusb_prefix/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
    fi
fi
if ! "$LITER8_PYTHON" -c 'from usb.backend import libusb1; raise SystemExit(libusb1.get_backend() is None)' 2>/dev/null; then
    echo "pyusb missing for: $LITER8_PYTHON"
    echo "Creating local .venv and installing pyusb..."
    if command -v python3 >/dev/null 2>&1; then
        python3 -m venv "$SCRIPT_DIR/.venv" 2>/dev/null || true
        if [[ -x "$SCRIPT_DIR/.venv/bin/pip" ]]; then
            "$SCRIPT_DIR/.venv/bin/pip" install -q pyusb || true
            LITER8_PYTHON="$SCRIPT_DIR/.venv/bin/python"
        fi
    fi
fi
if "$LITER8_PYTHON" -c 'from usb.backend import libusb1; raise SystemExit(libusb1.get_backend() is None)' 2>/dev/null; then
    echo "pyusb: ok ($LITER8_PYTHON)"
else
    echo "WARNING: pyusb or its libusb backend is unavailable. liter8ctl cannot boot iBSS."
    echo "Fix: install pyusb in .venv and install libusb with your package manager."
fi

if [[ -n "$IOS164_BUILD_DEVICE" ]]; then
    # An explicit build target does not need a connected phone.
    IDENTIFIER="$IOS164_BUILD_DEVICE"
    MODE="Build-only"
    ECID="not-required"
    SERIAL="not-required"
    DEVICE_VERSION="not-required"
else
IDEVICE_INFO=$(ideviceinfo 2>&1) || true
IDEVICE_STATUS=$?
if [[ $IDEVICE_STATUS -eq 0 && "$IDEVICE_INFO" != *"No device found!"* && "$IDEVICE_INFO" != *"ERROR:"* ]]; then
    IDENTIFIER=$(echo "$IDEVICE_INFO" | grep "^ProductType:" | cut -d ':' -f2 | xargs)
    ECID=$(echo "$IDEVICE_INFO" | grep "^UniqueChipID:" | cut -d ':' -f2 | xargs)
    SERIAL=$(echo "$IDEVICE_INFO" | grep "^SerialNumber:" | cut -d ':' -f2 | xargs)
    DEVICE_VERSION=$(echo "$IDEVICE_INFO" | grep "^ProductVersion:" | cut -d ':' -f2 | xargs)
    MODE="Normal"
elif [[ $IDEVICE_STATUS -ne 0 && "$IDEVICE_INFO" != *"No device found!"* ]] || [[ "$IDEVICE_INFO" == *"ERROR:"* && "$IDEVICE_INFO" != *"No device found!"* ]]; then
    # ideviceinfo ran but failed for another reason, try -s
    IDEVICE_INFO=$(ideviceinfo -s 2>&1) || true
    IDEVICE_STATUS=$?
    if [[ $IDEVICE_STATUS -eq 0 && "$IDEVICE_INFO" != *"No device found!"* ]]; then
        IDENTIFIER=$(echo "$IDEVICE_INFO" | grep "^ProductType:" | cut -d ':' -f2 | xargs)
        ECID=$(echo "$IDEVICE_INFO" | grep "^UniqueChipID:" | cut -d ':' -f2 | xargs)
        DEVICE_VERSION=$(echo "$IDEVICE_INFO" | grep "^ProductVersion:" | cut -d ':' -f2 | xargs)
        SERIAL="none"
        MODE="Normal"
    else
        echo "ideviceinfo failed after two attempts."
        exit 1
    fi
else
    echo "[*] Device is not in normal mode. Trying recovery/DFU mode..."
    # Try irecovery
    IRECOVERY_INFO=$(./bin/irecovery -q 2>/dev/null) || true
    if [[ -n "$IRECOVERY_INFO" ]]; then
        echo "[*] Device is in Recovery or DFU mode."
        IDENTIFIER=$(echo "$IRECOVERY_INFO" | grep "^PRODUCT:" | cut -d ':' -f2 | xargs)
        ECID=$(echo "$IRECOVERY_INFO" | grep "^ECID:" | cut -d ':' -f2 | xargs)
        MODE=$(echo "$IRECOVERY_INFO" | grep "^MODE:" | cut -d ':' -f2 | xargs)
        echo "[+] Device Identifier: $IDENTIFIER"
        echo "[+] ECID: $ECID"
    else
        echo "[!] No device detected in normal or recovery mode."
        IDENTIFIER="NONE"
        MODE="None"
        ECID="None"
        REFER2=""
        BOARDID2=""
        REFER=""
        BOARDID=""
        NAME="No device"
    fi
fi
fi

if [[ -d "seprmvr64boot" ]]; then
    mkdir -p boot
    mv -v seprmvr64boot/* boot/
    rm -rf "seprmvr64boot"
fi

# The build command can use an explicit target without a connected phone.
if [[ -n "$IOS164_BUILD_DEVICE" ]]; then
    IDENTIFIER="$IOS164_BUILD_DEVICE"
    MODE="Build-only"
    ECID="not-required"
fi

if [[ $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 ]]; then
    echo "iPad mini 3 is not supported yet"
    exit 1
fi

KEY_FILE="keys/$IDENTIFIER.txt"

# BB update determine check

if [[ $IDENTIFIER == iPhone* || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,5 || $IDENTIFIER == iPad4,6 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPad5,4 || $IDENTIFIER == iPad11,2 ]]; then
    updatebb_flag="--latest-baseband"
elif [[ $IDENTIFIER == iPod* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad11,1 ]]; then
    updatebb_flag="--no-baseband"
fi

# changes to device detection stuff

if [[ $IDENTIFIER == iPhone12* ]]; then
    PMP="t8030pmp.im4p"
fi

if [[ $IDENTIFIER == iPhone6* ]]; then
    REFER="iphone6"
    REFER2="iphone6"
elif [[ $IDENTIFIER == iPhone7* ]]; then
    REFER="iphone7"
elif [[ $IDENTIFIER == iPod7* ]]; then
    REFER="n102"
    REFER2="n102"
    BOARDID="n102ap"
    BOARDID2="n102"
    NAME="iPod touch 6 ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone11,8 ]]; then
    REFER="iphone11b"
    REFER2="n841"
    BOARDID="n841ap"
    BOARDID2="n841"
    NAME="iPhone XR ($BOARDID)"
    AOP14="aopfw-iphone11baop.im4p"
    AOP="aopfw-iphone11baop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-n84.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="N841_CallanFirmware.im4p"
    HAPTICASSET="N841_HapticAssets.im4p"
    MTFW="N841_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11b.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPad11,1 ]]; then
    REFER="ipad11"
    REFER2="j210"
    BOARDID="j210ap"
    BOARDID2="j210"
    NAME="iPad mini (5th generation, Wi-Fi only) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J210_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPad11,2 ]]; then
    REFER="ipad11"
    REFER2="j210"
    BOARDID="j211ap"
    BOARDID2="j210"
    NAME="iPad mini (5th generation, Cellular) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J211_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPhone11,2 ]]; then
    REFER="iphone11"
    REFER2="d321"
    BOARDID="d321ap"
    BOARDID2="d321"
    NAME="iPhone XS ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D321_CallanFirmware.im4p"
    HAPTICASSET="D321_HapticAssets.im4p"
    MTFW="D321_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone11,4 ]]; then
    REFER="iphone11"
    REFER2="d331"
    BOARDID="d331ap"
    BOARDID2="d331"
    NAME="iPhone XS Max ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D331_CallanFirmware.im4p"
    HAPTICASSET="D331_HapticAssets.im4p"
    MTFW="D331_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone11,6 ]]; then
    REFER="iphone11"
    REFER2="d331p"
    BOARDID="d331pap"
    BOARDID2="d331p"
    NAME="iPhone XS Max ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D331p_CallanFirmware.im4p"
    HAPTICASSET="D331p_HapticAssets.im4p"
    MTFW="D331p_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone12,1 ]]; then
    REFER="iphone12b"
    REFER2="n104"
    BOARDID="n104ap"
    BOARDID2="n104"
    NAME="iPhone 11 ($BOARDID)"
    AOP14="aopfw-iphone12baop.im4p"
    AOP="aopfw-iphone12baop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-n104.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="N104_AudioCodecFirmware.im4p"
    HAPTICASSET="N104_HapticAssets.im4p"
    MTFW="N104_Multitouch.im4p"
    LEAPHAPTIC="N104_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12b.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,3 ]]; then
    REFER="iphone12"
    REFER2="d421"
    BOARDID="d421ap"
    BOARDID2="d421"
    NAME="iPhone 11 Pro ($BOARDID)"
    AOP14="aopfw-iphone12aop.im4p"
    AOP="aopfw-iphone12aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d4x.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="D421_AudioCodecFirmware.im4p"
    HAPTICASSET="D421_HapticAssets.im4p"
    MTFW="D421_Multitouch.im4p"
    LEAPHAPTIC="D421_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,5 ]]; then
    REFER="iphone12"
    REFER2="d431"
    BOARDID="d431ap"
    BOARDID2="d431"
    NAME="iPhone 11 Pro Max ($BOARDID)"
    AOP14="aopfw-iphone12aop.im4p"
    AOP="aopfw-iphone12aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d4x.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="D431_AudioCodecFirmware.im4p"
    HAPTICASSET="D431_HapticAssets.im4p"
    MTFW="D431_Multitouch.im4p"
    LEAPHAPTIC="D431_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,8 ]]; then
    REFER="iphone12c"
    REFER2="d79"
    BOARDID="d79ap"
    BOARDID2="d79"
    NAME="iPhone SE 2nd generation ($BOARDID)"
    AOP14="aopfw-iphone12caop.im4p"
    AOP="aopfw-iphone12caop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    IOFW13="SmartIOFirmwareT8030.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d79.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    AVE13="AppleAVE2FW.im4p"
    CALLAN="D79_AudioCodecFirmware.im4p"
    MTFW="D79_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone12c.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 || $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    REFER="iphone10"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    REFER="iphone10b"
elif [[ $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 ]]; then
    REFER="ipad4"
    REFER2="ipad4"
elif [[ $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 || $IDENTIFIER == iPad4,6 ]]; then
    REFER="ipad4b"
    REFER2="ipad4b"
elif [[ $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 ]]; then
    REFER="ipad4bm"
    REFER2="ipad4bm"
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]]; then
    REFER="ipad5"
    REFER2="ipad5"
elif [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]]; then
    REFER="ipad5b"
    REFER2="ipad5b"
else
    echo "Unsupported device"
    exit 1
fi

if [[ $IDENTIFIER == iPhone6,1 ]]; then
    BOARDID="n51ap"
    BOARDID2="n51"
    NAME="iPhone 5S (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone6,2 ]]; then
    BOARDID="n53ap"
    BOARDID2="n53"
    NAME="iPhone 5S (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone7,2 ]]; then
    BOARDID="n61ap"
    BOARDID2="n61"
    REFER2="$BOARDID2"
    NAME="iPhone 6 ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone7,1 ]]; then
    BOARDID="n56ap"
    BOARDID2="n56"
    REFER2="$BOARDID2"
    NAME="iPhone 6 Plus ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,1 ]]; then
    BOARDID="d20ap"
    BOARDID2="d20"
    REFER2="$BOARDID2"
    NAME="iPhone 8 (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,4 ]]; then
    BOARDID="d201ap"
    BOARDID2="d20"
    REFER2="$BOARDID2"
    NAME="iPhone 8 (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,2 ]]; then
    BOARDID="d21ap"
    BOARDID2="d21"
    REFER2="$BOARDID2"
    NAME="iPhone 8 Plus (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,5 ]]; then
    BOARDID="d211ap"
    BOARDID2="d21"
    REFER2="$BOARDID2"
    NAME="iPhone 8 Plus (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,3 ]]; then
    BOARDID="d22ap"
    BOARDID2="d22"
    REFER2="$BOARDID2"
    NAME="iPhone X (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,6 ]]; then
    BOARDID="d221ap"
    BOARDID2="d22"
    REFER2="$BOARDID2"
    NAME="iPhone X (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,1 ]]; then
    BOARDID="j71ap"
    BOARDID2="j71"
    NAME="iPad Air (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,2 ]]; then
    BOARDID="j72ap"
    BOARDID2="j72"
    NAME="iPad Air (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,3 ]]; then
    BOARDID="j73ap"
    BOARDID2="j73"
    NAME="iPad Air (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,4 ]]; then
    BOARDID="j85ap"
    BOARDID2="j85"
    NAME="iPad mini 2 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,5 ]]; then
    BOARDID="j86ap"
    BOARDID2="j86"
    NAME="iPad mini 2 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,6 ]]; then
    BOARDID="j87ap"
    BOARDID2="j87"
    NAME="iPad mini 2 (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,7 ]]; then
    BOARDID="j85map"
    BOARDID2="j85m"
    NAME="iPad mini 3 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,8 ]]; then
    BOARDID="j86map"
    BOARDID2="j86m"
    NAME="iPad mini 3 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,9 ]]; then
    BOARDID="j87map"
    BOARDID2="j87m"
    NAME="iPad mini 3 (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,1 ]]; then
    BOARDID="j96ap"
    BOARDID2="j96"
    NAME="iPad mini 4 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,2 ]]; then
    BOARDID="j97ap"
    BOARDID2="j97"
    NAME="iPad mini 4 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,3 ]]; then
    BOARDID="j81ap"
    BOARDID2="j81"
    NAME="iPad Air 2 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,4 ]]; then
    BOARDID="j82ap"
    BOARDID2="j82"
    NAME="iPad Air 2 (Cellular, $BOARDID) - $IDENTIFIER"
fi

if [[ $IDENTIFIER == iPad5* ]]; then
    LATEST_VERSION="15.8.8"
elif [[ $IDENTIFIER == iPhone10* ]]; then
    LATEST_VERSION="16.7.16"
elif [[ $IDENTIFIER == iPhone11* ]]; then
    LATEST_VERSION="18.7.9"
elif [[ $IDENTIFIER == iPhone12* ]]; then
    LATEST_VERSION="26.5.2"
elif [[ $IDENTIFIER == iPad11* ]]; then
    LATEST_VERSION="26.5.2"
else
    LATEST_VERSION="12.5.8"
fi

IBSS="iBSS.$REFER2.RELEASE.im4p"
IBEC="iBEC.$REFER2.RELEASE.im4p"
LLB="LLB.$REFER2.RELEASE.im4p"
IBOOT="iBoot.$REFER2.RELEASE.im4p"
LLB10="LLB.$BOARDID2.RELEASE.im4p"
IBOOT10="iBoot.$BOARDID2.RELEASE.im4p"
DEVICETREE="DeviceTree.$BOARDID.im4p"
ALLFLASH="all_flash.$BOARDID.production"
KERNEL="kernelcache.release.$REFER"
IBSS10="iBSS.$BOARDID2.RELEASE.im4p"
IBEC10="iBEC.$BOARDID2.RELEASE.im4p"
IBSS7="iBSS.$BOARDID.RELEASE.im4p"
IBEC7="iBEC.$BOARDID.RELEASE.im4p"
KERNEL10="kernelcache.release.$BOARDID2"

INFO_TEXT="surrealra1n - $CURRENT_VERSION
Tether Downgrader for some checkm8 64bit devices, iOS 7.0 - 15.8.5
This build is an early beta. Use at your own risk, and expect bugs.

Uses latest SHSH blobs (for tethered downgrades)
iSuns9 fork of asr64_patcher is used for patching ASR
Huge thanks to bodyc1m for iPod touch 6 support, including the Arch Linux/Fedora port they did.
Huge thanks to Mineek for seprmvr64.

Device: $NAME
ECID: $ECID

Device is in $MODE mode."

# iPhone 11 Pro support is still experimental.
if [[ $IDENTIFIER == iPhone12,3 && "${1:-}" != "ios164-build" ]]; then
    echo
    echo "================================================================"
    echo " WARNING: iPhone 11 Pro (iPhone12,3) is EXPERIMENTAL"
    echo "================================================================"
    echo " Expected “least unlikely” range: iOS 15.4 – 15.6.1"
    echo " 15.0 can be forced if keys exist (Rose gate) — still experimental"
    echo " Requires: usbliter8 + Pi Pico (or equivalent) to pwn A13"
    echo " Success is uncommon; bricks / restore loops are possible."
    echo " Keys in tree: 15.0 + 15.4 / 15.4.1 / 15.5 / 15.6 / 15.6.1"
    echo "================================================================"
    read -p "Continue anyway at your own risk? (y/N): " iphone12_3_confirm
    if [[ $iphone12_3_confirm != y && $iphone12_3_confirm != Y ]]; then
        echo "Aborted. Use another device or wait for upstream support."
        exit 1
    fi
    echo "Proceeding with iPhone 11 Pro experimental path..."
    echo
fi

misc_utils(){

clear
echo "$INFO_TEXT"
echo ""
echo "Options:"
echo ""
echo "1. Reinstall surrealra1n"
echo "2. Clear all created boot files and restore files"
if [[ -d "surrealra1n.old" ]]; then
    echo "3. Go back to previous version of surrealra1n"
    echo "4. Back"
else
    echo "3. Back"
fi
if [[ -d "surrealra1n.old" ]]; then
    read -p "Please input an option (1-4): " misc_utils_options
else
    read -p "Please input an option (1-3): " misc_utils_options
fi
if [[ $misc_utils_options == 1 ]]; then
    echo "WARNING: All of your boot files, and other things will be deleted (if any files are in the surrealra1n directory, they will be erased), and surrealra1n will be fresh installed."
    read -p "Are you sure you want to reinstall surrealra1n? (y/N): " surrealra1n_reinstall
    if [[ $surrealra1n_reinstall == Y || $surrealra1n_reinstall == y ]]; then
        sudo rm -rf ./*
        git clone --branch development https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "Failed to clone repository. You will need to fetch surrealra1n from releases on GitHub"
            exit 1
        fi
        echo "Copying new files..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh

        rm -rf "repo"
        echo "surrealra1n has been reinstalled! Please run the script again"
        exit 0
    else
        echo "surrealra1n reinstall has been canceled."
        misc_utils
    fi
elif [[ $misc_utils_options == 2 ]]; then
    echo "WARNING: All of your boot files and restore files will be deleted. You will need to re-create them afterwards if you proceed."
    echo "This may be useful if you want more disk space."
    read -p "Are you sure you want to clear these files? (y/N): " clear_files    
    if [[ $clear_files == y || $clear_files == Y ]]; then
        sudo rm -rf "boot"
        sudo rm -rf "restorefiles"
        sudo rm -rf "noseprestore"
    else
        echo "Clearing boot files/restore files has been canceled"
        misc_utils
    fi
elif [[ $misc_utils_options == 3 ]] && [[ -d "surrealra1n.old" ]]; then
    old_version=$(cat surrealra1n.old/oldversion.txt)
    if [[ "$old_version" == *beta* ]]; then
        echo "Rollback feature is not supported if you update from a beta."
        rm -rf "surrealra1n.old"
        sleep 4
        misc_utils
        return
    fi
    echo "WARNING: This will restore surrealra1n to the previous version backed up in surrealra1n.old."
    echo "Any new features from this surrealra1n release may not exist in the previous version"
    read -p "Are you sure you want to go back to the previous version? (y/N): " rollback_confirm
    if [[ $rollback_confirm == Y || $rollback_confirm == y ]]; then
        rm -rf "bin"
        rm -rf "futurerestore"
        rm -rf "keys"
        rm -rf surrealra1n.sh
        cp -av surrealra1n.old/. ./
        chmod +x surrealra1n.sh
        rm -rf "surrealra1n.old"
        echo "surrealra1n has been restored to the previous version! Please run the script again."
        echo "You can upgrade to the latest version at any time later if you want to be on latest again."
        exit 0
    else
        echo "Rollback has been canceled."
        misc_utils
    fi
elif [[ $misc_utils_options == 3 ]] || [[ $misc_utils_options == 4 ]]; then
    main_menu
else
    echo "Invalid option. Exiting."
    exit 1
fi

}

pwn_device(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4* ]] && [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
    echo "A7 devices may have issues pwning on Linux"
    echo "If you have a MacBook, use surrealra1n on that instead"
    echo "You may choose to continue attempting to pwn with Linux"
    read -p "Press enter to continue"
fi

echo "Checking if this device is in pwned DFU already"
irecovery_output=$(./bin/irecovery -q)
if echo "$irecovery_output" | grep -q "PWND"; then
    echo "Device is pwned!"
    if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
        echo "Skipping gaster reset"
    else
        ./bin/gaster reset
    fi
    return
elif [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    echo "Proceed to do the following:"
    echo "A12/A13 tether downgrades are for advanced users only. If you don't know what you're doing, DO not proceed"
    echo "Disconnect your device from the computer, then connect it to your Pi Pico"
    echo "Make sure your Pi Pico has the custom firmware required to pwn the device with usbliter8."
    read -p "Press enter to continue once device is pwned successfully AND reconnected to the computer"
else
    echo "Device is not pwned yet, attempting to pwn"
    ./bin/gaster pwn 
    ./bin/gaster reset
    if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
        ./bin/irecovery -f surrealra1n.sh
        ./bin/gaster reset
    fi
fi

echo "Checking if this device has pwned successfully"
irecovery_output=$(./bin/irecovery -q)
if echo "$irecovery_output" | grep -q "PWND"; then
    echo "Device is pwned!"
else
    echo "Device has not pwned successfully"
    exit 1
fi

}

dfu_helper(){

if [[ $MODE == Normal || $MODE == Recovery ]]; then
    echo "You need to put your device into DFU mode."
    read -p "Would you like instructions on how to do this? (y/n): " dfu_instructions
    if [[ $dfu_instructions == y || $dfu_instructions == Y ]]; then
        echo "Instructions will begin in:"
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Hold power + home buttons." 
        echo "10" && sleep 1 && echo "9" && sleep 1 && echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Release the power button now, but keep holding home button."
        echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    else
        echo "Put your device into DFU mode now"
    fi
fi

echo "Checking for DFU devices"
if [[ $dfu_instructions == Y || $dfu_instructions == y ]]; then
    MODE=$(./bin/irecovery -q | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
    if [[ $MODE == DFU ]]; then
        echo "The device has entered DFU successfully!"
    else
        echo "Device has not entered DFU mode successfully"
        exit 1
    fi
else
    while true; do
      MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
      if [ "$MODE" = "DFU" ]; then
        echo "Device is now in DFU mode!"
        break
      fi

      sleep 1
    done
fi

}

switch_to_main(){

echo "Fetching latest stable version info..."
curl -L -o update/latest_main.txt https://github.com/pwnerblu/surrealra1n/raw/refs/heads/main/update/latest.txt
MAIN_VERSION=$(head -n 1 "update/latest_main.txt" | tr -d '\r\n')

CURRENT_CLEAN=$(echo "$CURRENT_VERSION" | sed 's/ beta//g' | sed 's/ .*//g' | tr -d 'v')
MAIN_CLEAN=$(echo "$MAIN_VERSION" | sed 's/ beta//g' | sed 's/ .*//g' | tr -d 'v')

CURRENT_MAJOR=$(echo "$CURRENT_CLEAN" | cut -d'.' -f1)
CURRENT_MINOR=$(echo "$CURRENT_CLEAN" | cut -d'.' -f2)
CURRENT_PATCH=$(echo "$CURRENT_CLEAN" | cut -d'.' -f3)
CURRENT_PATCH=${CURRENT_PATCH:-0}

MAIN_MAJOR=$(echo "$MAIN_CLEAN" | cut -d'.' -f1)
MAIN_MINOR=$(echo "$MAIN_CLEAN" | cut -d'.' -f2)
MAIN_PATCH=$(echo "$MAIN_CLEAN" | cut -d'.' -f3)
MAIN_PATCH=${MAIN_PATCH:-0}

echo "Current version: $CURRENT_VERSION"
echo "Latest stable version: $MAIN_VERSION"
echo ""

if [[ "$CURRENT_MAJOR" == "$MAIN_MAJOR" && "$CURRENT_MINOR" == "$MAIN_MINOR" && "$CURRENT_PATCH" == "$MAIN_PATCH" ]]; then
    echo "You are already on the stable equivalent of your current version ($MAIN_VERSION)."
    echo "No action needed."
    read -p "Press enter to go back"
    main_menu
    return
fi

if [[ "$CURRENT_MAJOR" -gt "$MAIN_MAJOR" ]] || \
   [[ "$CURRENT_MAJOR" -eq "$MAIN_MAJOR" && "$CURRENT_MINOR" -gt "$MAIN_MINOR" ]]; then
    echo "WARNING: You are currently on $CURRENT_VERSION (development branch)."
    echo "The latest stable version is $MAIN_VERSION (main branch)."
    echo "Since your development version is newer than stable, switching will require a clean reinstall."
    echo "This means ALL boot files, restore files, and binaries will be deleted."
    echo ""
    read -p "Are you sure you want to switch to stable? (y/N): " switch_confirm
    if [[ $switch_confirm == Y || $switch_confirm == y ]]; then
        sudo rm -rf ./*
        git clone --branch main https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "Failed to clone repository."
            exit 1
        fi
        echo "Copying new files..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh
        rm -rf "repo"
        echo "surrealra1n has been switched to stable $MAIN_VERSION! Please run the script again."
        exit 0
    else
        echo "Switch to stable has been canceled."
        main_menu
    fi
else
    echo "You are on $CURRENT_VERSION (development branch)."
    echo "Latest stable version is $MAIN_VERSION (main branch)."
    echo "This will upgrade you to stable without wiping your boot/restore files."
    echo ""
    read -p "Would you like to switch to stable? (y/N): " switch_confirm
    if [[ $switch_confirm == Y || $switch_confirm == y ]]; then
        rm -rf "surrealra1n.old"
        mkdir -p surrealra1n.old
        echo "Backing up your current surrealra1n installation..."
        echo "$CURRENT_VERSION" > surrealra1n.old/oldversion.txt
        mv -v bin surrealra1n.old/
        mv -v futurerestore surrealra1n.old/
        mv -v keys surrealra1n.old/
        mv -v surrealra1n.sh surrealra1n.old/
        git clone --branch main https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "Failed to clone repository."
            exit 1
        fi
        echo "Copying new files..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh
        rm -rf "repo"
        echo "surrealra1n has been switched to stable $MAIN_VERSION! Please run the script again."
        exit 0
    else
        echo "Switch to stable has been canceled."
        main_menu
    fi
fi

}

dfu_helper_a11(){

if [[ $MODE == Normal || $MODE == Recovery ]]; then
    echo "You need to put your device into DFU mode."
    read -p "Would you like instructions on how to do this? (y/n): " dfu_instructions
    if [[ $dfu_instructions == y || $dfu_instructions == Y ]] && [[ $MODE == Recovery ]]; then
        echo "Instructions will begin in:"
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Hold volume down + power buttons." 
        echo "4" && sleep 1 && echo "3" && sleep 1 && ./bin/irecovery -n && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Release the power button now, but keep holding volume down button."
        echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    elif [[ $dfu_instructions == y || $dfu_instructions == Y ]] && [[ $MODE == Normal ]]; then
        echo "Put your device into recovery mode, then continue"
        read -p "Press enter to continue once Device is in Recovery"
        echo "Instructions will begin in:"
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Hold volume down + power buttons." 
        echo "4" && sleep 1 && echo "3" && sleep 1 && ./bin/irecovery -n && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "Release the power button now, but keep holding volume down button."
        echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    else
        echo "Put your device into DFU mode now"
    fi
fi

echo "Checking for DFU devices"
if [[ $dfu_instructions == Y || $dfu_instructions == y ]]; then
    MODE=$(./bin/irecovery -q | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
    if [[ $MODE == DFU ]]; then
        echo "The device has entered DFU successfully!"
    else
        echo "Device has not entered DFU mode successfully"
        exit 1
    fi
else
    while true; do
      MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
      if [ "$MODE" = "DFU" ]; then
        echo "Device is now in DFU mode!"
        break
      fi

      sleep 1
    done
fi

}

reset_restore_vars() {
    IPSW_PATH=""
    IPSW_PATH_LATEST=""
    SHSH_PATH=""
    VERSION=""
    BUILD=""
    VERSION_LATEST=""
}

sep_checker(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPod7* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.0* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP is incompatible. Restore cannot continue"
    exit 1
fi
if [[ $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.1* ]]; then
    echo "SEP is compatible but Touch ID will break"
    read -p "Press enter to continue"
fi
if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 10.1* || $VERSION == 10.2* || $VERSION == 10.3* ]]; then
    echo "SEP is compatible but Touch ID will break, device may take 3-5 minutes to boot, and may hang during Setup"
    read -p "Press enter to continue"
fi
if [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.* ]]; then
    echo "SEP is compatible but Touch ID will break, device may take 3-5 minutes to boot, and may hang for 30 seconds when it reaches the Touch ID part of Setup. Deep sleep issues are also very likely"
fi
if [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 11.3* || $VERSION == 11.4* || $VERSION == 12.* ]]; then
    echo "SEP is compatible but Touch ID will break"
    read -p "Press enter to continue"
fi
if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.* || $VERSION == 11.* || $VERSION == 12.* ]]; then
    echo "SEP is incompatible. Restore cannot continue"
    exit 1
fi
if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.3* || $VERSION == 14.4* || $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* || $VERSION == 15.* ]]; then
    echo "SEP is partially incompatible"
    echo "Device will be unable to activate after the restore."
    echo "And potentially other broken features"
    read -p "Press enter to continue"
fi
if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 11.* || $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.0* || $VERSION == 14.1* || $VERSION == 14.2* ]]; then
    echo "SEP is incompatible. Restore cannot continue"
    exit 1
fi

}

download_tvos_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.j42d.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
sep_ipsw="https://secure-appldnld.apple.com/tvos10.2.2/091-23452-20170720-5D53229C-6A56-11E7-8577-8B2C4A4DD6D5/AppleTV5,3_10.2.2_14W756_Restore.ipsw"
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/pwnerblu/cursed-sep-resources/raw/refs/heads/main/BuildManifest-$IDENTIFIER.plist
sudo ./bin/pzb -g Firmware/all_flash/sep-firmware.j42d.RELEASE.im4p $sep_ipsw
sudo mv -v sep-firmware.j42d.RELEASE.im4p $sep_path

}

download_iphone6_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.n61.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
sep_ipsw="https://updates.cdn-apple.com/2026WinterFCS/fullrestores/047-28352/B80B4A86-C206-4C4F-8D35-65579694AEE9/iPhone_4.7_12.5.8_16H88_Restore.ipsw"
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/pwnerblu/cursed-sep-resources/raw/refs/heads/main/BuildManifest-$IDENTIFIER-12.5.8.plist
sudo ./bin/pzb -g Firmware/all_flash/sep-firmware.n61.RELEASE.im4p $sep_ipsw
sudo mv -v sep-firmware.n61.RELEASE.im4p $sep_path

}

download_1033_ota_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.$BOARDID2.RELEASE.im4p"
sep_name="sep-firmware.$BOARDID2.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
if [[ $IDENTIFIER == iPhone6* ]]; then
    sep_ipsw="http://appldnld.apple.com/ios10.3.3/091-23133-20170719-CA8E78E6-6977-11E7-968B-2B9100BA0AE3/iPhone_4.0_64bit_10.3.3_14G60_Restore.ipsw"
elif [[ $IDENTIFIER == iPad4* ]]; then
    sep_ipsw="http://appldnld.apple.com/ios10.3.3/091-23378-20170719-CA983C78-6977-11E7-8922-3D9100BA0AE3/iPad_64bit_10.3.3_14G60_Restore.ipsw"
fi
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/manifest/BuildManifest_${IDENTIFIER}_10.3.3.plist
sudo ./bin/pzb -g Firmware/all_flash/$sep_name $sep_ipsw
sudo mv -v $sep_name $sep_path

}

prepatch_ibssibec_fr(){

sudo mkdir -p /tmp/futurerestore
mkdir -p work
./bin/img4tool -s "$SHSH_PATH" -e -m "$IDENTIFIER-im4m"
im4m="$IDENTIFIER-im4m"
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
if [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87486/23310DA1-A434-4192-87BC-31429FD2D625/iPhone_4.7_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87451/EE6AEB4B-1BF7-4FBF-9D29-A8C7B970B495/iPhone_5.5_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87865/458334F5-D8E1-498A-A9FD-08BBD20FE007/iPhone10,3,iPhone10,6_14.3_18C66_Restore.ipsw"
fi
if [[ $VERSION == 10.3* || $VERSION == 11.* || $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* || $VERSION == 16.* ]]; then
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC" -d work
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0 ]]; then # just for 14.0 beta 4 restore
        cd work
        sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
        sudo ../bin/pzb -g Firmware/dfu/$IBEC $ipsw_url
        cd ..
    fi
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched
    if [[ $IDENTIFIER == iPhone10* ]]; then
        ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched -n
    fi
    ./bin/iBoot64Patcher work/iBEC.raw work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" -n
    sudo ./bin/img4 -i work/iBSS.patched -o /tmp/futurerestore/ibss.$BOARDID.$BUILD.patched.img4 -A -T ibss -M $im4m
    sudo ./bin/img4 -i work/iBEC.patched -o /tmp/futurerestore/ibec.$BOARDID.$BUILD.patched.img4 -A -T ibec -M $im4m
else
    # 10.3 iBSS/iBEC workaround
    IBSS_KEY=$(grep "ibss-10.3:" "$KEY_FILE" | cut -d':' -f2 | xargs)
    IBEC_KEY=$(grep "ibec-10.3:" "$KEY_FILE" | cut -d':' -f2 | xargs)
    if [[ $IDENTIFIER == iPhone6* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02949-20170327-7584B286-0D86-11E7-A4FA-7ECE122AC769/iPhone_4.0_64bit_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone7,2 ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02962-20170327-7584E8B4-0D86-11E7-B580-8CCE122AC769/iPhone_4.7_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone7,1 ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02950-20170327-75843ACC-0D86-11E7-ACCC-80CE122AC769/iPhone_5.5_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad4* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02965-20170327-758BACE4-0D86-11E7-9129-8ECE122AC769/iPad_64bit_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad5* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02967-20170327-758827FE-0D86-11E7-9B30-90CE122AC769/iPad_64bit_TouchID_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPod7* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02958-20170327-75869E66-0D86-11E7-BF4D-88CE122AC769/iPodtouch_10.3_14E277_Restore.ipsw"
    fi
    sudo ./bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
    sudo ./bin/pzb -g Firmware/dfu/$IBEC $ipsw_url
    sudo mv -v $IBSS work/
    sudo mv -v $IBEC work/
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched
    ./bin/iBoot64Patcher work/iBEC.raw work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" -n
    sudo ./bin/img4 -i work/iBSS.patched -o /tmp/futurerestore/ibss.$BOARDID.$BUILD.patched.img4 -A -T ibss -M $im4m
    sudo ./bin/img4 -i work/iBEC.patched -o /tmp/futurerestore/ibec.$BOARDID.$BUILD.patched.img4 -A -T ibec -M $im4m
fi

}

det_rsep_flag(){

if [[ $VERSION == 16.* || $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 || $IDENTIFIER == iPhone12* ]]; then
    rsep_flag=""
else
    rsep_flag="--no-rsep"
fi

}

restore_with_blobs(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "No IPSW selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW does not exist: $IPSW_PATH"
    exit 1
fi
if [[ -z "$SHSH_PATH" ]]; then
    echo "No SHSH blob selected. Aborting."
    exit 1
fi
if [[ ! -f "$SHSH_PATH" ]]; then
    echo "SHSH blob does not exist: $SHSH_PATH"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    echo "iPhone X is not supported yet."
    echo "Legacy iOS Kit *does* support iPhone X restores with blobs though"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi

pwn_device
det_rsep_flag

sleep 5

if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]] && [[ $VERSION == 10.* ]]; then
    download_tvos_sep
    if [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.3* ]]; then
        unzip -j "$IPSW_PATH" "$KERNEL" -d work
        ./bin/img4 -i work/$KERNEL -o work/kernel.raw
        ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
        ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
        ./bin/img4 -i work/$KERNEL -o work/kernel.im4p -T rkrn -P work/kernel.diff -J || true
        prepatch_ibssibec_fr
        while true; do
            set +e
            sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
                ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
                --sep $sep_path --sep-manifest $manifest_path \
                --custom-latest $LATEST_VERSION \
                $updatebb_flag $rsep_flag --rkrn work/kernel.im4p $IPSW_PATH
            EXIT_CODE=$?
            set -e
            if [[ $EXIT_CODE -eq 139 ]]; then
                echo "futurerestore segfaulted (exit 139), retrying..."
                sleep 2
            else
                break
            fi
        done
        if [[ $EXIT_CODE -eq 0 ]]; then
            echo "Restore has completed! Read above if there are any errors"
            exit 0
        else
            echo "futurerestore failed with exit code $EXIT_CODE"
            exit 1
        fi
    fi
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad4* || $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.* ]]; then
    download_1033_ota_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    download_iphone6_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
else
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --latest-sep \
            --custom-latest $LATEST_VERSION \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
fi

echo "Restore has completed! Read above if there is any errors"
exit 0

}

restore_untethered_opts(){

clear 
echo "$INFO_TEXT"
echo ""
echo "Options:"
echo ""
echo "1. Select Target IPSW"
echo "2. Select SHSH"
echo "3. Start Restore"
echo "4. Back"
read -p "Please input an option (1-4): " untether_options
if [[ $untether_options == 1 ]]; then
    IPSW_PATH=$(pick_file "Select an IPSW file")
    if [[ -z "$IPSW_PATH" ]]; then
        echo "No IPSW selected. Aborting."
        exit 1
    fi
    unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
    BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    restore_untethered_opts
elif [[ $untether_options == 2 ]]; then
    SHSH_PATH=$(pick_file "Select an SHSH2 file")
    if [[ -z "$SHSH_PATH" ]]; then
        echo "No SHSH blob selected. Aborting."
        exit 1
    fi
    echo "An SHSH blob is selected. Please ensure this blob is valid for iOS $VERSION, otherwise the restore will likely fail"
    read -p "Press enter to continue"
    restore_untethered_opts
elif [[ $untether_options == 3 ]]; then
    sep_checker
    restore_with_blobs
elif [[ $untether_options == 4 ]]; then
    reset_restore_vars
    restore_utils
else
    echo "Invalid option. Exiting."
    exit 1
fi

}

make_custom_ipsw_ios16(){

mkdir -p restorefiles
mkdir -p restorefiles/$IDENTIFIER
mkdir -p restorefiles/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
find tmp1/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec rm -f {} +
find tmp2/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec cp {} tmp1/Firmware/all_flash/ \;
# because no AOP validation patch for iOS 16, fallback to latest AOP
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    mv tmp2/Firmware/AOP/aopfw-iphone10baop.im4p tmp1/Firmware/AOP/aopfw-iphone10baop.im4p
else
    mv tmp2/Firmware/AOP/aopfw-iphone10aop.im4p tmp1/Firmware/AOP/aopfw-iphone10aop.im4p
fi
./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -e -o -h
./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
cd tmp1
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
mkdir -p work
cd work 
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65861/0A0400A0-2174-4D49-91B7-43FC9DE24272/iPhone10,3,iPhone10,6_16.0_20A362_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65568/0851247C-1B06-4CD4-B3C2-5A94026970B7/iPhone_5.5_P3_16.0_20A362_Restore.ipsw"
else
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65931/BD2515B7-7802-4EB4-9377-98E3238EA5A8/iPhone_4.7_P3_16.0_20A362_Restore.ipsw"
fi
sudo ../bin/pzb -g 098-08863-001.dmg $url_ios16
sudo ../bin/pzb -g $KERNEL $url_ios16
cd ..
restore_ramdisk_dmg=$(find_dmg work smallest)
./bin/img4 -i work/$KERNEL -o work/kernel.raw
./bin/KPlooshFinder work/kernel.raw work/kernel.patched
./bin/kerneldiff work/kernel.raw work/kernel.patched work/kernel.diff
./bin/img4 -i work/$KERNEL -o $restoredir/kernel.im4p -T rkrn -P work/kernel.diff -J || true
# rdsk prep
./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
./bin/asr64_patcher work/asr work/asr_patched
./bin/ldid -e work/asr > work/ents.plist
./bin/ldid -Swork/ents.plist work/asr_patched
./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
./bin/ldid -Swork/ents.plist work/libimg4.patch
./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
# pack rdsk into im4p
./bin/img4 -i work/ramdisk.raw -o $restoredir/ramdisk.im4p -A -T rdsk
# Wrap up
rm -rf "tmp1"
rm -rf "work"

}

make_custom_ipsw(){

mkdir -p restorefiles
mkdir -p restorefiles/$IDENTIFIER
mkdir -p restorefiles/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
if [[ $VERSION == 10.1* || $VERSION == 10.2* ]]; then
    cp tmp2/Firmware/all_flash/$LLB tmp1/Firmware/all_flash/$ALLFLASH/$LLB10
    cp tmp2/Firmware/all_flash/$IBOOT tmp1/Firmware/all_flash/$ALLFLASH/$IBOOT10
elif [[ $VERSION == 10.3* ]]; then
    cp tmp2/Firmware/all_flash/$LLB tmp1/Firmware/all_flash/$LLB
    cp tmp2/Firmware/all_flash/$IBOOT tmp1/Firmware/all_flash/$IBOOT
else
    find tmp1/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec rm -f {} +
    find tmp2/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec cp {} tmp1/Firmware/all_flash/ \;
fi
if [[ $VERSION == 14.* ]] && [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
    ./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -b
    ./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
elif [[ $VERSION == 15.* ]] && [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
    ./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -e -o -r -b15
    ./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
fi
cd tmp1
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
mkdir -p work
restore_ramdisk_dmg=$(find_dmg tmp1 smallest)
update_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
if [[ $VERSION == 10.2* || $VERSION == 10.1* ]]; then
    cp -v tmp1/$KERNEL10 work/kernel.im4p
else
    cp -v tmp1/$KERNEL work/kernel.im4p
fi
./bin/img4 -i work/kernel.im4p -o work/kernel.raw
./bin/KPlooshFinder work/kernel.raw work/kernel.patched
if [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    mv -v work/kernel.patched work/kernel.patch
    ./bin/Kernel64Patcher2 work/kernel.patch work/kernel.patched -u 11 --skip-sks --skip-acm --skip-amfi
fi
./bin/kerneldiff work/kernel.raw work/kernel.patched work/kernel.diff
./bin/img4 -i work/kernel.im4p -o $restoredir/kernel.im4p -T rkrn -P work/kernel.diff -J || true
# rdsk prep
./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
if [[ $VERSION == 10.* ]]; then
    ./bin/hfsplus work/ramdisk.raw grow 60000000
fi
./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
./bin/asr64_patcher work/asr work/asr_patched
./bin/ldid -e work/asr > work/ents.plist
./bin/ldid -Swork/ents.plist work/asr_patched
./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
    ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
    ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
fi
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then # do some ipx patching
    ./bin/hfsplus work/ramdisk.raw extract usr/local/bin/restored_external work/restored_external
    ./bin/ipx_restored_patcher work/restored_external work/restored_patch # use restored patcher by Mineek
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/restored_external
    ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/restored_external
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/restored_external
fi
# pack rdsk into im4p
./bin/img4 -i work/ramdisk.raw -o $restoredir/ramdisk.im4p -A -T rdsk
if [[ $IDENTIFIER == iPhone10* ]]; then
    # do update ramdisk stuff so 14.0b4 to 14.3-15.6.1 update install is possible
    ./bin/img4 -i $update_ramdisk_dmg -o work/ramdisk.raw
    ./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
    ./bin/asr64_patcher work/asr work/asr_patched
    ./bin/ldid -e work/asr > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/asr_patched
    ./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
    ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
    ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
    if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then # do some ipx patching
        ./bin/hfsplus work/ramdisk.raw extract usr/local/bin/restored_update work/restored_external
        ./bin/ipx_restored_patcher work/restored_external work/restored_patch # use restored patcher by Mineek
        ./bin/ldid -e work/restored_external > work/ents.plist
        ./bin/ldid -Swork/ents.plist work/restored_patch
        ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/restored_update
        ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/restored_update
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/restored_update
    fi
    # pack rdsk into im4p
    ./bin/img4 -i work/ramdisk.raw -o $restoredir/updateramdisk.im4p -A -T rdsk
fi
# Wrap up
rm -rf "tmp1"
rm -rf "work"

}

validate_ios164_archive_component(){

    local custom_ipsw="$1"
    local reference_ipsw="$2"
    local member="$3"
    local label="$4"
    local check_dir

    [[ -f "$custom_ipsw" && -f "$reference_ipsw" ]] || {
        echo "FATAL: cannot validate the iOS 16.4 archive $label."
        return 1
    }

    check_dir=$(mktemp -d "${TMPDIR:-/tmp}/surrealra1n-ios164-ibec.XXXXXX") || {
        echo "FATAL: cannot create the iOS 16.4 archive validation directory."
        return 1
    }

    if ! unzip -p "$reference_ipsw" "$member" > "$check_dir/reference.im4p" ||
       ! unzip -p "$custom_ipsw" "$member" > "$check_dir/custom.im4p" ||
       [[ ! -s "$check_dir/reference.im4p" || ! -s "$check_dir/custom.im4p" ]]; then
        rm -rf "$check_dir"
        echo "FATAL: could not extract the iOS 16.4 archive $label."
        return 1
    fi

    if ! cmp -s "$check_dir/reference.im4p" "$check_dir/custom.im4p"; then
        rm -rf "$check_dir"
        echo "FATAL: iOS 16.4 custom IPSW $label differs from the stock target component."
        return 1
    fi

    rm -rf "$check_dir"
    echo "iOS 16.4 archive $label matches the stock target IPSW component."
}

validate_ios164_archive_boot_components(){

    local custom_ipsw="$1"
    # Second arg is kept for callers; Odysseus path validates against the 16.4 target IPSW.
    local _unused_base_ipsw="${2:-}"
    # Optional explicit dir for Odysseus sidecars (ramdisk.im4p, etc.). Required when
    # custom.ipsw is still in cwd as "custom.ipsw" during the build (dirname == ".").
    local artifact_dir="${3:-}"
    local reference_ipsw="${IPSW_PATH:-}"
    local ibss_member="${IOS164_TARGET_IBSS:-Firmware/dfu/$IBSS}"
    local ibec_member="${IOS164_TARGET_IBEC:-Firmware/dfu/$IBEC}"

    [[ -f "$reference_ipsw" ]] || {
        echo "FATAL: missing iOS 16.4 target IPSW for archive validation."
        return 1
    }

    if [[ -z "$artifact_dir" ]]; then
        if [[ -n "${restoredir:-}" && -d "${restoredir:-}" ]]; then
            artifact_dir="$restoredir"
        else
            artifact_dir=$(dirname "$custom_ipsw")
        fi
    fi
    # Never treat bare cwd as the artifact dir when we know restoredir.
    if [[ "$artifact_dir" == "." && -n "${restoredir:-}" && -d "$restoredir" ]]; then
        artifact_dir="$restoredir"
    fi

    validate_ios164_archive_component "$custom_ipsw" "$reference_ipsw" "$ibss_member" iBSS || return 1
    validate_ios164_archive_component "$custom_ipsw" "$reference_ipsw" "$ibec_member" iBEC || return 1
    validate_ios164_archive_kernel_entries "$custom_ipsw" || return 1
    validate_ios164_odysseus_artifacts "$artifact_dir"
}

validate_ios164_odysseus_artifacts(){

    local restoredir="$1"
    local missing=0

    for f in ramdisk.im4p kernel.im4p ibss.patched.bin ibec.patched.bin; do
        if [[ ! -s "$restoredir/$f" ]]; then
            echo "FATAL: missing iOS 16.4 Odysseus artifact: $restoredir/$f"
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || return 1
    echo "iOS 16.4 Odysseus artifacts (rdsk/rkrn/iBSS/iBEC) are present."
}

validate_ios164_archive_kernel_entries(){

    local custom_ipsw="$1"
    local python_bin="${LITER8_PYTHON:-python3}"

    [[ -n "$IOS164_TARGET_IDENTITY" && -n "$BOARDID" && -n "$KERNEL" ]] || {
        echo "FATAL: missing iOS 16.4 manifest state for archive validation."
        return 1
    }

    "$python_bin" - "$custom_ipsw" "$IOS164_TARGET_IDENTITY" "$BOARDID" "$KERNEL" <<'PY'
import plistlib
import sys
import zipfile


def fail(message: str) -> None:
    print(f"FATAL: {message}")
    raise SystemExit(1)


archive_path, identity_index, board, expected_kernel = sys.argv[1:]
try:
    with zipfile.ZipFile(archive_path) as archive:
        manifest = plistlib.loads(archive.read("BuildManifest.plist"))
        if str(manifest.get("ProductVersion", "")) != "16.4":
            fail(
                "iOS 16.4 archive ProductVersion is "
                f"{manifest.get('ProductVersion')!r}, expected 16.4 "
                "(hybrid base IPSWs cannot enter restore mode on this path)"
            )
        if str(manifest.get("ProductBuildVersion", "")) != "20E247":
            fail(
                "iOS 16.4 archive ProductBuildVersion is "
                f"{manifest.get('ProductBuildVersion')!r}, expected 20E247"
            )
        identity = manifest["BuildIdentities"][int(identity_index)]
        info = identity["Info"]
        if info.get("DeviceClass") != board or info.get("RestoreBehavior") != "Erase":
            fail("iOS 16.4 archive identity does not match the selected board")
        path = identity["Manifest"]["KernelCache"]["Info"]["Path"]
        if path != expected_kernel:
            fail(f"iOS 16.4 archive KernelCache path is unexpected: {path}")
        entry = archive.getinfo(path)
        if entry.is_dir() or entry.file_size == 0:
            fail(f"iOS 16.4 archive KernelCache is empty: {path}")
        # RestoreKernelCache usually aliases KernelCache on 16.4; accept either.
        try:
            rpath = identity["Manifest"]["RestoreKernelCache"]["Info"]["Path"]
            rentry = archive.getinfo(rpath)
            if rentry.is_dir() or rentry.file_size == 0:
                fail(f"iOS 16.4 archive RestoreKernelCache is empty: {rpath}")
        except KeyError:
            pass
except (IndexError, KeyError, TypeError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
    fail(f"cannot validate iOS 16.4 archive kernel paths: {exc}")

print("iOS 16.4 archive is target-based (16.4/20E247) with valid kernel paths.")
PY
}

# usbliter8ctl is shipped in-tree (upstream GitHub repo was removed / 404s).
# Prefer tools/liter8ctl; keep a working copy at bin/liter8ctl for callers.
ensure_liter8ctl(){
    local want_hash="30f0cccee9ac359ac0bee11e165f8bd3f23849c913f4b5a8c4fc0ee3be7377b3"
    local bundled="$SCRIPT_DIR/tools/liter8ctl"
    local dest="$SCRIPT_DIR/bin/liter8ctl"
    local got_hash=""

    mkdir -p "$SCRIPT_DIR/bin"
    if [[ -s "$bundled" ]]; then
        cp "$bundled" "$dest"
    elif [[ -s "$dest" ]]; then
        echo "Using existing bin/liter8ctl (bundled tools/liter8ctl missing)."
    else
        echo "FATAL: bundled liter8ctl is missing."
        echo "Expected: $bundled"
        echo "The old prdgmshift/usbliter8 GitHub download is gone (404)."
        return 1
    fi
    chmod +x "$dest" 2>/dev/null || true

    if command -v shasum >/dev/null 2>&1; then
        got_hash=$(shasum -a 256 "$dest" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
        got_hash=$(sha256sum "$dest" | awk '{print $1}')
    else
        echo "WARNING: no sha256 tool; skipping liter8ctl checksum verify."
        return 0
    fi
    if [[ "$got_hash" != "$want_hash" ]]; then
        echo "FATAL: liter8ctl checksum mismatch."
        echo "  got:  $got_hash"
        echo "  want: $want_hash"
        return 1
    fi
    return 0
}

ensure_ios164_futurerestore(){

    local stock_bin="$SCRIPT_DIR/futurerestore/futurerestore"
    local fr_bin="$SCRIPT_DIR/futurerestore/futurerestore-usbliter8"
    local patcher="$SCRIPT_DIR/tools/patch_futurerestore_usbliter8.py"
    local python_bin="${LITER8_PYTHON:-python3}"
    local patch_word host_arch host_os

    [[ -x "$SCRIPT_DIR/.venv/bin/python" ]] && python_bin="$SCRIPT_DIR/.venv/bin/python"
    host_os=$(uname -s)
    host_arch=$(uname -m)

    [[ -x "$stock_bin" ]] || {
        echo "FATAL: stock futurerestore is missing at $stock_bin"
        echo "Run surrealra1n once so it can download Build 329, then retry."
        return 1
    }

    # Linux: macOS arm64 byte patches do not apply to the Linux x86_64 binary.
    # Use stock Build 329 under the usbliter8 name so the Odysseus argv stays shared.
    if [[ "$host_os" != "Darwin" ]]; then
        echo "Linux: using stock futurerestore Build 329 for the iOS 16.4 path."
        echo "Note: the macOS usbliter8 patch set is arm64-only; Linux keeps stock FR for now."
        if [[ ! -x "$fr_bin" || "$stock_bin" -nt "$fr_bin" ]]; then
            cp "$stock_bin" "$fr_bin" || {
                echo "FATAL: could not install futurerestore-usbliter8 from stock."
                return 1
            }
            chmod +x "$fr_bin" || true
        fi
        if ! "$fr_bin" -h >/dev/null 2>&1; then
            echo "FATAL: futurerestore cannot run on this Linux host: $fr_bin"
            return 1
        fi
        return 0
    fi

    if [[ "$host_arch" != "arm64" ]]; then
        echo "FATAL: on macOS, the iOS 16.4 Odysseus restore path requires Apple Silicon."
        echo "Stock futurerestore cannot take over from liter8 Recovery with --no-ibss,"
        echo "and the usbliter8 FR patch set is arm64-only (Build 329)."
        return 1
    fi
    [[ -f "$patcher" ]] || {
        echo "FATAL: missing $patcher"
        return 1
    }

    # Rebuild when missing or when the stock binary is newer than the patched one.
    if [[ ! -x "$fr_bin" || "$stock_bin" -nt "$fr_bin" ]]; then
        echo "Building usbliter8-patched futurerestore from stock Build 329..."
        "$python_bin" "$patcher" "$stock_bin" "$fr_bin" || {
            echo "FATAL: could not patch futurerestore for the iOS 16.4 path."
            return 1
        }
    fi

    if ! "$fr_bin" -h >/dev/null 2>&1; then
        echo "FATAL: patched futurerestore cannot run on this Mac: $fr_bin"
        return 1
    fi
    # v12 recovery + --use-pwndfu + --no-ibss fallthrough (NOP at 0xC2A0).
    patch_word=$(xxd -p -s 0xC2A0 -l 4 "$fr_bin" 2>/dev/null | tr -d '\n' || true)
    if [[ "$patch_word" != "1f2003d5" ]]; then
        echo "Rebuilding usbliter8 futurerestore (patch marker mismatch: 0xC2A0=$patch_word)..."
        "$python_bin" "$patcher" "$stock_bin" "$fr_bin" || {
            echo "FATAL: $fr_bin is not the usbliter8-patched build (0xC2A0=$patch_word)."
            return 1
        }
        patch_word=$(xxd -p -s 0xC2A0 -l 4 "$fr_bin" 2>/dev/null | tr -d '\n' || true)
        [[ "$patch_word" == "1f2003d5" ]] || {
            echo "FATAL: patched futurerestore still missing v12 marker at 0xC2A0."
            return 1
        }
    fi
    echo "Using usbliter8-patched futurerestore for the iOS 16.4 Odysseus path."
}

# Pre-seed futurerestore's TMPDIR cache from the local base IPSW so Cryptex1 /
# SEP / Rose are not re-downloaded via flaky libfragmentzip (LFZP 487 mid-file).
# FR Build 329 looks for fixed basenames under $TMPDIR/futurerestore/.
seed_ios164_futurerestore_cache(){

    local base_ipsw="$1"
    local fr_cache="$2"
    local python_bin="${LITER8_PYTHON:-python3}"
    local cache_dir board_class

    [[ -f "$base_ipsw" ]] || {
        echo "WARNING: cannot seed FR cache — missing base IPSW: $base_ipsw"
        return 1
    }
    [[ -x "$SCRIPT_DIR/.venv/bin/python" ]] && python_bin="$SCRIPT_DIR/.venv/bin/python"
    board_class="$BOARDID"
    cache_dir="$fr_cache/futurerestore"
    mkdir -p "$cache_dir"

    echo "Seeding futurerestore cache from base IPSW (avoids CDN Cryptex/SEP pzb downloads)..."
    if ! "$python_bin" - "$base_ipsw" "$cache_dir" "$board_class" <<'PY'
import plistlib
import shutil
import sys
import zipfile
from pathlib import Path

ipsw, cache_dir, board = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
cache_dir.mkdir(parents=True, exist_ok=True)

# futurerestore Build 329 cache basenames (see "Checking for cached Cryptex1...")
CRYPTEX_MAP = {
    "Cryptex1,SystemOS": "cryptex1SysOS.dmg",
    "Cryptex1,SystemVolume": "cryptex1SysVOL.dmg.root_hash",
    "Cryptex1,SystemTrustCache": "cryptex1SysTC.dmg.trustcache",
    "Cryptex1,AppOS": "cryptex1AppOS.dmg",
    "Cryptex1,AppVolume": "cryptex1AppVOL.dmg.root_hash",
    "Cryptex1,AppTrustCache": "cryptex1AppTC.dmg.trustcache",
}

with zipfile.ZipFile(ipsw) as zf:
    manifest = plistlib.loads(zf.read("BuildManifest.plist"))
    identity = None
    for bi in manifest.get("BuildIdentities", []):
        info = bi.get("Info", {})
        if (
            info.get("DeviceClass") == board
            and info.get("RestoreBehavior") == "Erase"
        ):
            identity = bi
            break
    if identity is None:
        # Fall back to first Erase identity if board match is missing.
        for bi in manifest.get("BuildIdentities", []):
            if bi.get("Info", {}).get("RestoreBehavior") == "Erase":
                identity = bi
                break
    if identity is None:
        raise SystemExit("no Erase identity in base IPSW BuildManifest")

    man = identity["Manifest"]
    seeded = []
    missing = []

    def copy_member(member: str, dest_name: str) -> None:
        dest = cache_dir / dest_name
        if dest.is_file() and dest.stat().st_size > 0:
            # Keep a complete prior seed.
            if dest.stat().st_size == zf.getinfo(member).file_size:
                seeded.append(f"{dest_name} (cached)")
                return
        with zf.open(member) as src, open(dest, "wb") as out:
            shutil.copyfileobj(src, out, length=1024 * 1024)
        if not dest.is_file() or dest.stat().st_size == 0:
            raise SystemExit(f"failed to seed {dest_name} from {member}")
        seeded.append(f"{dest_name} <- {member} ({dest.stat().st_size} bytes)")

    for component, dest_name in CRYPTEX_MAP.items():
        try:
            path = man[component]["Info"]["Path"]
        except KeyError:
            missing.append(component)
            continue
        # SystemOS may be .dmg.aea in modern IPSWs; FR still caches as .dmg.
        copy_member(path, dest_name)

    # Optional: SEP / RestoreSEP so --latest-sep can skip the small download too.
    for component, dest_name in (
        ("RestoreSEP", "sep.im4p"),
        ("SEP", "sep.im4p"),
    ):
        if (cache_dir / "sep.im4p").is_file() and (cache_dir / "sep.im4p").stat().st_size > 0:
            break
        try:
            path = man[component]["Info"]["Path"]
        except KeyError:
            continue
        try:
            copy_member(path, dest_name)
            break
        except KeyError:
            continue

    for line in seeded:
        print(f"  seeded: {line}")
    if missing:
        print("  missing components (FR may still CDN-fetch): " + ", ".join(missing))
    required = [
        "cryptex1SysOS.dmg",
        "cryptex1SysVOL.dmg.root_hash",
        "cryptex1SysTC.dmg.trustcache",
        "cryptex1AppOS.dmg",
        "cryptex1AppVOL.dmg.root_hash",
        "cryptex1AppTC.dmg.trustcache",
    ]
    bad = [n for n in required if not (cache_dir / n).is_file() or (cache_dir / n).stat().st_size == 0]
    if bad:
        raise SystemExit("incomplete cryptex seed: " + ", ".join(bad))
    print("Cryptex1 cache seed complete.")
PY
    then
        echo "WARNING: could not seed FR cache from base IPSW; FR will try CDN pzb downloads."
        return 1
    fi
    # Drop incomplete partials that LFZP may have left from a prior failed attempt.
    # Only touch zero-byte cryptex stubs; complete seeds are kept.
    local f
    for f in "$cache_dir"/cryptex1*.dmg "$cache_dir"/cryptex1*.root_hash "$cache_dir"/cryptex1*.trustcache; do
        [[ -e "$f" ]] || continue
        if [[ ! -s "$f" ]]; then
            echo "Removing empty cache stub: $f"
            rm -f "$f"
        fi
    done
    return 0
}

purge_ios164_partial_cryptex_cache(){

    local fr_cache="$1"
    local cache_dir="$fr_cache/futurerestore"
    [[ -d "$cache_dir" ]] || return 0
    # LFZP 487 mid-download can leave a truncated cryptex1SysOS.dmg that FR then
    # treats as "cached" and never re-fetches cleanly. Always wipe cryptex on
    # download-related failures so the next attempt re-seeds from the IPSW.
    echo "Purging Cryptex1 entries from FR cache after download failure..."
    rm -f \
        "$cache_dir"/cryptex1SysOS.dmg \
        "$cache_dir"/cryptex1SysVOL.dmg.root_hash \
        "$cache_dir"/cryptex1SysTC.dmg.trustcache \
        "$cache_dir"/cryptex1AppOS.dmg \
        "$cache_dir"/cryptex1AppVOL.dmg.root_hash \
        "$cache_dir"/cryptex1AppTC.dmg.trustcache \
        "$cache_dir"/cryptex1SysOS.dmg.* \
        "$cache_dir"/cryptex1AppOS.dmg.* 2>/dev/null || true
}

stage_ios164_futurerestore_iboot(){

    local restoredir="$1"
    local shsh_path="$2"
    local board="$BOARDID"
    local build="20E247"
    local stage_dir="/tmp/futurerestore"
    local im4m_path img4tool_bin
    local python_bin="${LITER8_PYTHON:-python3}"
    local ibss_bin="$restoredir/ibss.patched.bin"
    local ibec_bin="$restoredir/ibec.patched.bin"
    local ibss_img4="$stage_dir/ibss.${board}.${build}.patched.img4"
    local ibec_img4="$stage_dir/ibec.${board}.${build}.patched.img4"
    [[ -x "$SCRIPT_DIR/.venv/bin/python" ]] && python_bin="$SCRIPT_DIR/.venv/bin/python"

    [[ -s "$ibss_bin" && -s "$ibec_bin" && -s "$shsh_path" ]] || {
        echo "FATAL: cannot stage iOS 16.4 iBSS/iBEC for futurerestore."
        return 1
    }

    img4tool_bin="$SCRIPT_DIR/bin/img4tool"
    [[ -x "$img4tool_bin" ]] || {
        echo "FATAL: missing img4tool for iOS 16.4 iBoot staging."
        return 1
    }

    mkdir -p "$stage_dir"
    im4m_path=$(mktemp "${TMPDIR:-/tmp}/surreal-ios164-im4m.XXXXXX")
    # Extract IM4M from the live SHSH for personalizing the staged bootloaders.
    if ! "$img4tool_bin" -e -s "$shsh_path" -m "$im4m_path" >/dev/null 2>&1; then
        # Fallback: some builds store ApImg4Ticket as the IM4M payload.
        if ! "$python_bin" - "$shsh_path" "$im4m_path" <<'PY'
import plistlib, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    blob = plistlib.load(f)
ticket = blob.get("ApImg4Ticket") or blob.get("APTicket")
if not ticket:
    raise SystemExit("no ApImg4Ticket in shsh")
open(dst, "wb").write(ticket)
PY
        then
            rm -f "$im4m_path"
            echo "FATAL: could not extract IM4M from SHSH for iBoot staging."
            return 1
        fi
    fi
    [[ -s "$im4m_path" ]] || {
        rm -f "$im4m_path"
        echo "FATAL: extracted IM4M is empty."
        return 1
    }

    local tmp_im4p tag src_bin dst_img4
    for tag in ibss ibec; do
        if [[ $tag == ibss ]]; then
            src_bin="$ibss_bin"
            dst_img4="$ibss_img4"
        else
            src_bin="$ibec_bin"
            dst_img4="$ibec_img4"
        fi
        tmp_im4p="${dst_img4%.img4}.im4p"
        if ! "$img4tool_bin" -c "$tmp_im4p" -t "$tag" "$src_bin" >/dev/null; then
            rm -f "$im4m_path"
            echo "FATAL: img4tool failed creating $tag im4p"
            return 1
        fi
        if ! "$img4tool_bin" -c "$dst_img4" -p "$tmp_im4p" -m "$im4m_path" >/dev/null; then
            rm -f "$im4m_path"
            echo "FATAL: img4tool failed wrapping $tag img4"
            return 1
        fi
        if [[ ! -s "$dst_img4" ]]; then
            rm -f "$im4m_path"
            echo "FATAL: staged $tag img4 is empty"
            return 1
        fi
        echo "Staged $tag for futurerestore: $dst_img4"
    done
    rm -f "$im4m_path"
}

make_custom_ipsw_ios164(){

    # Target-based custom IPSW + Odysseus sidecars (rdsk/rkrn + patched iBSS/iBEC).
    # Hybrid base (26.x) archives leave ProductVersion 26.x and stock base iBEC in
    # the restore path, which fails Recovery→Restore with "Unable to place device
    # into restore mode". The proven A13 path uses the 16.4 IPSW, external --rdsk
    # / --rkrn, --use-pwndfu --no-ibss --skip-blob, and a usbliter8-patched FR.

    local python_bin="${LITER8_PYTHON:-python3}"
    local ibss_key ibec_key
    local target_ramdisk_rel target_trustcache_rel
    local restore_ramdisk_dmg target_trustcache_path

    if [[ -z "${IOS164_TARGET_IDENTITY:-}" ]]; then
        prepare_ios164_build_inputs "$IPSW_PATH" "$IPSW_PATH_LATEST"
    fi

    ibss_key=$(grep '^ibss-16.4:' "$KEY_FILE" | cut -d':' -f2 | xargs)
    ibec_key=$(grep '^ibec-16.4:' "$KEY_FILE" | cut -d':' -f2 | xargs)
    [[ "$ibss_key" =~ ^[0-9A-Fa-f]{96}$ ]] || {
        echo "FATAL: missing iBSS 16.4 key in $KEY_FILE"
        exit 1
    }
    [[ "$ibec_key" =~ ^[0-9A-Fa-f]{96}$ ]] || {
        echo "FATAL: missing iBEC 16.4 key in $KEY_FILE"
        exit 1
    }
    [[ -f "$SCRIPT_DIR/tools/patch_iboot_semantic.py" && -f "$SCRIPT_DIR/tools/iboot_patchfinder.py" ]] || {
        echo "FATAL: missing tools/patch_iboot_semantic.py or tools/iboot_patchfinder.py"
        exit 1
    }

    mkdir -p restorefiles "$restoredir" boot "boot/$IDENTIFIER" "boot/$IDENTIFIER/$VERSION" work
    rm -rf tmp1 tmp2
    echo "Extracting iOS 16.4 target IPSW..."
    unzip -q "$IPSW_PATH" -d tmp1
    echo "Extracting signed base IPSW (carrier reference only)..."
    unzip -q "$IPSW_PATH_LATEST" -d tmp2
    chmod -R u+w tmp1 tmp2

    target_ramdisk_rel="$IOS164_TARGET_RAMDISK"
    target_trustcache_rel="$IOS164_TARGET_TRUSTCACHE"
    restore_ramdisk_dmg="tmp1/$target_ramdisk_rel"
    target_trustcache_path="tmp1/$target_trustcache_rel"
    [[ -s "tmp1/$IOS164_TARGET_KERNEL" && -s "$restore_ramdisk_dmg" && -s "$target_trustcache_path" ]] || {
        echo "FATAL: iOS 16.4 target components missing after extract"
        exit 1
    }
    [[ -s "tmp1/Firmware/dfu/$IBSS" && -s "tmp1/Firmware/dfu/$IBEC" ]] || {
        echo "FATAL: iOS 16.4 target iBSS/iBEC missing after extract"
        exit 1
    }

    echo "Patching iOS 16.4 iBSS (liter8 handoff) and iBEC (restore entry)..."
    "$IOS164_IMG4" -i "tmp1/Firmware/dfu/$IBSS" -o work/iBSS.raw -k "$ibss_key"
    "$IOS164_IMG4" -i "tmp1/Firmware/dfu/$IBEC" -o work/iBEC.raw -k "$ibec_key"
    "$python_bin" "$SCRIPT_DIR/tools/patch_iboot_semantic.py" \
        work/iBSS.raw work/iBSS.patch \
        --mode ibss --patchfinder "$SCRIPT_DIR/tools/iboot_patchfinder.py"
    "$python_bin" "$SCRIPT_DIR/tools/patch_iboot_semantic.py" \
        work/iBEC.raw work/iBEC.patch \
        --mode ibec --patchfinder "$SCRIPT_DIR/tools/iboot_patchfinder.py"
    # liter8 restore handoff uses the semantic iBSS patch; local-boot packaging is best-effort.
    cp work/iBSS.patch "boot/$IDENTIFIER/iBSS.patch"
    cp work/iBSS.patch "boot/$IDENTIFIER/$VERSION/iBSS.patch"
    cp work/iBSS.patch "$restoredir/ibss.patched.bin"
    cp work/iBEC.patch "$restoredir/ibec.patched.bin"
    if ./bin/iBootpatch2 work/iBSS.patch "boot/$IDENTIFIER/$VERSION/iBSS.boot" 2>/dev/null; then
        :
    else
        cp work/iBSS.patch "boot/$IDENTIFIER/$VERSION/iBSS.boot"
    fi
    echo "iOS 16.4: leaving stock target iBSS/iBEC inside custom.ipsw (Odysseus uses staged patched copies)."

    echo "Patching iOS 16.4 kernel (NAND krnl only)..."
    "$IOS164_IMG4" -i "tmp1/$IOS164_TARGET_KERNEL" -o work/kernel.raw
    "$python_bin" ./bin/patch_ios164_kernel.py \
        work/kernel.raw work/kernelboot.patch \
        --kernel64-patcher ./bin/Kernel64Patcher3
    ./bin/kerneldiff work/kernel.raw work/kernelboot.patch work/kernelboot.diff
    # NAND KernelCache: full 16.4 patch set (for post-restore tether boot experiments).
    "$IOS164_IMG4" -i "tmp1/$IOS164_TARGET_KERNEL" -o work/kernel.krnl.im4p \
        -T krnl -J -P work/kernelboot.diff
    # --rkrn restore entry: STOCK 16.4 kernel retagged rkrn (lab Boot-Bar style).
    # Heavy AMFI patches here made restore mode fall back logo→Recovery (30MB custom rkrn).
    "$IOS164_IMG4" -i "tmp1/$IOS164_TARGET_KERNEL" -o work/kernel.rkrn.im4p -T rkrn -J
    [[ -s work/kernel.krnl.im4p && -s work/kernel.rkrn.im4p ]] || {
        echo "FATAL: failed to repack iOS 16.4 kernels"
        exit 1
    }
    cp work/kernel.krnl.im4p "tmp1/$IOS164_TARGET_KERNEL"
    cp work/kernel.rkrn.im4p "$restoredir/kernel.im4p"
    echo "iOS 16.4: --rkrn is stock kernel (lab restore-entry); IPSW KernelCache is patched."

    echo "Patching iOS 16.4 restore ramdisk (lab Option D: asr + libimg4 + restored_external seal)..."
    ./bin/patch_ios164_ramdisk.sh \
        "$restore_ramdisk_dmg" work/ramdisk.raw work \
        "$IOS164_IMG4" ./bin/asr64_patcher ./bin/libimg4_patcher ./bin/ldid
    [[ -s work/asr_patched && -s work/libimg4.patch && -s work/restored_external.patched ]] || {
        echo "FATAL: iOS 16.4 lab trust-cache inputs are missing (asr/libimg4/restored_external)"
        exit 1
    }
    "$IOS164_IMG4" -i "$target_trustcache_path" -o work/trustcache.raw || exit 1
    cp work/trustcache.raw work/trustcache.stock.raw
    # Lab: inject CDHashes for every re-signed ramdisk binary AMFI will execute.
    ./bin/trustcache append work/trustcache.raw work/asr_patched || exit 1
    ./bin/trustcache append work/trustcache.raw work/libimg4.patch || exit 1
    ./bin/trustcache append work/trustcache.raw work/restored_external.patched || exit 1
    "$IOS164_IMG4" -i work/trustcache.raw -o "$target_trustcache_path" -A -T rtsc || exit 1
    [[ -s work/trustcache.raw && -s "$target_trustcache_path" ]] &&
    ! cmp -s work/trustcache.stock.raw work/trustcache.raw || {
        echo "FATAL: iOS 16.4 RestoreTrustCache injection failed"
        exit 1
    }
    stock_tc_size=$(wc -c < work/trustcache.stock.raw | tr -d ' ')
    new_tc_size=$(wc -c < work/trustcache.raw | tr -d ' ')
    echo "RestoreTrustCache grew ${stock_tc_size} → ${new_tc_size} bytes (lab CDHash inject)"
    "$IOS164_IMG4" -i work/ramdisk.raw -o "$restore_ramdisk_dmg" -A -T rdsk
    cp "$restore_ramdisk_dmg" "$restoredir/ramdisk.im4p"
    # Keep lab sidecars next to the bundle for offline inspection.
    cp work/restored_external.patched "$restoredir/restored_external.patched" 2>/dev/null || true
    cp work/asr_patched "$restoredir/asr_patched" 2>/dev/null || true
    cp work/libimg4.patch "$restoredir/libimg4.patch" 2>/dev/null || true

    echo "Packing target-based custom.ipsw (ProductVersion 16.4)..."
    (
        cd tmp1
        zip -0 -r ../custom.ipsw ./*
    )
    validate_ios164_archive_boot_components custom.ipsw "$IPSW_PATH_LATEST" "$restoredir" || {
        rm -f custom.ipsw
        rm -rf tmp1 tmp2 work
        exit 1
    }
    mv -v custom.ipsw "$restoredir/custom.ipsw"
    rm -rf tmp1 tmp2 work
    echo "iOS 16.4 Odysseus bundle ready in $restoredir"
    ls -la "$restoredir"
}

make_custom_ipsw_a12_ios14(){

if [[ $VERSION == 16.4 ]]; then
    make_custom_ipsw_ios164
    return
fi

local ios164_base_ibec_path=""

if [[ $VERSION == 16.4 && -z "${IOS164_TARGET_IDENTITY:-}" ]]; then
    prepare_ios164_build_inputs "$IPSW_PATH" "$IPSW_PATH_LATEST"
fi

IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
mkdir -p restorefiles
mkdir -p restorefiles/$IDENTIFIER
mkdir -p restorefiles/$IDENTIFIER/$VERSION
mkdir -p boot
mkdir -p boot/$IDENTIFIER
mkdir -p boot/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
if [[ -n "$IOS164_BUILD_DEVICE" ]]; then
    # Make the temporary base tree writable.
    chmod -R u+w tmp2
fi
mkdir -p work
if [[ $VERSION == 16.4 ]]; then
    ios164_base_ibec_path="tmp2/$IOS164_BASE_IBEC"
    [[ -s "$ios164_base_ibec_path" ]] || {
        echo "FATAL: missing base iBEC component: $ios164_base_ibec_path"
        exit 1
    }
fi
# iBSS patching of course because yes
    if [[ $VERSION == 14.0 ]] && [[ $BUILD != 18A373 ]]; then
    if [[ $IDENTIFIER == iPhone11,8 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46828/6A00C15C-8AEB-490E-A468-04E28C68E7C9/iPhone11,8,iPhone12,1_14.0_18A373_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46850/8A4DA7D0-40E1-4079-A159-5B0983102B66/iPhone11,2,iPhone11,4,iPhone11,6,iPhone12,3,iPhone12,5_14.0_18A373_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad11,1 || $IDENTIFIER == iPad11,2 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46551/EFCA25AF-50BE-4712-A9C2-1E760AD99B82/iPad_Spring_2019_14.0_18A373_Restore.ipsw"
    fi
    cd work 
    sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
    cd ..
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch 
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
elif [[ $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* ]]; then
    if [[ $IDENTIFIER == iPhone11,8 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22451/5C8BBEE0-8471-4801-8D85-54D33DEDA50D/iPhone11,8,iPhone12,1_14.4.2_18D70_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22729/77571761-8A7F-4F67-BB19-12D9BC82405B/iPhone11,2,iPhone11,4,iPhone11,6,iPhone12,3,iPhone12,5_14.4.2_18D70_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad11,1 || $IDENTIFIER == iPad11,2 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22329/CF450435-1EDC-4212-A768-D666A1677EC5/iPad_Spring_2019_14.4.2_18D70_Restore.ipsw"
    fi
    cd work 
    sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
    cd ..
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch 
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
    elif [[ $VERSION == 15.* || $VERSION == 16.4 ]]; then
        ./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
        ./bin/iBootPatch work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
        ./bin/iBootPatch work/iBSS.raw work/iBSS.patchboot
        if [[ $VERSION == 16.4 ]]; then
            cp boot/$IDENTIFIER/iBSS.patch boot/$IDENTIFIER/$VERSION/iBSS.patch
            [[ -s boot/$IDENTIFIER/iBSS.patch && -s work/iBSS.patchboot ]] || {
                echo "iOS 16.4 iBSS patch output is missing"
                exit 1
            }
            [[ -s boot/$IDENTIFIER/$VERSION/iBSS.patch ]] || {
                echo "iOS 16.4 versioned iBSS patch output is missing"
                exit 1
            }
            cmp -s work/iBSS.raw boot/$IDENTIFIER/iBSS.patch && {
                echo "iOS 16.4 iBSS patch made no changes"
                exit 1
            }
            cmp -s boot/$IDENTIFIER/iBSS.patch boot/$IDENTIFIER/$VERSION/iBSS.patch || {
                echo "iOS 16.4 versioned iBSS patch does not match the build output"
                exit 1
            }
            cmp -s work/iBSS.raw work/iBSS.patchboot && {
                echo "iOS 16.4 local boot iBSS patch made no changes"
                exit 1
            }
        fi
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    if [[ $VERSION == 16.4 ]]; then
        echo "iOS 16.4: keeping the signed base iBEC unchanged."
    else
        ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
    fi
else
    ./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
fi
#
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]] && [[ $BUILD != 18A5342e ]]; then
    # update rd stuff
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
    restored="restored_update"
elif [[ $IDENTIFIER == iPhone12,8 ]] && [[ $VERSION == 15.* ]]; then
    # update rd stuff
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
    restored="restored_update"
else
    restore_ramdisk_dmg=$(find_dmg tmp1 smallest)
    restored="restored_external"
fi
if [[ $LATEST_VERSION == 18.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 179000000)
elif [[ $LATEST_VERSION == 26.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 232784000)
fi
fs_dmg_18=$(find_dmg_arm64e tmp2 largest)
fs_dmg=$(find_dmg tmp1 largest)
fs_dmg_name=${fs_dmg##*/}
fs_dmg_18_name=${fs_dmg_18##*/}
ramdisk_dmg_name_18=${restore_ramdisk_dmg_18##*/}
ramdisk_dmg_name=${restore_ramdisk_dmg##*/}
if [[ $IDENTIFIER == iPhone12,8 || $IDENTIFIER == iPhone12,1 || $IDENTIFIER == iPhone11,8 || $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPad11,1 ]]; then
    IDENTITY="0"
elif [[ $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone12,5 || $IDENTIFIER == iPad11,2 ]]; then
    IDENTITY="1"
elif [[ $IDENTIFIER == iPhone11,6 ]]; then
    IDENTITY="2"
fi

if [[ $VERSION == 16.4 ]]; then
    IDENTITY="$IOS164_BASE_IDENTITY"
    fs_dmg="tmp1/$IOS164_TARGET_OS"
    fs_dmg_18="tmp2/$IOS164_BASE_OS"
    fs_dmg_name=${fs_dmg##*/}
    fs_dmg_18_name=${fs_dmg_18##*/}
    target_ramdisk_rel="$IOS164_TARGET_RAMDISK"
    target_trustcache_rel="$IOS164_TARGET_TRUSTCACHE"
    base_ramdisk_rel="$IOS164_BASE_RAMDISK"
    base_trustcache_rel="$IOS164_BASE_TRUSTCACHE"
    restore_ramdisk_dmg="tmp1/$target_ramdisk_rel"
    restore_ramdisk_dmg_18="tmp2/$base_ramdisk_rel"
    target_trustcache_path="tmp1/$target_trustcache_rel"
    base_trustcache_path="tmp2/$base_trustcache_rel"
    [[ -f "$fs_dmg" && -f "$fs_dmg_18" && -f "$restore_ramdisk_dmg" && -f "$restore_ramdisk_dmg_18" &&
       -f "$target_trustcache_path" && -f "$base_trustcache_path" ]] || {
        echo "FATAL: iOS 16.4 manifest paths are absent from an extracted IPSW"
        exit 1
    }
    ramdisk_dmg_name=${restore_ramdisk_dmg##*/}
    ramdisk_dmg_name_18=${restore_ramdisk_dmg_18##*/}
fi
manifest_python=(sudo python3)
[[ -n "$IOS164_BUILD_DEVICE" ]] && manifest_python=(python3)
KERNEL2="$KERNEL2" IDENTITY="$IDENTITY" "${manifest_python[@]}" <<'PY'
import os
import plistlib

with open("tmp2/BuildManifest.plist", "rb") as f:
    plist = plistlib.load(f)

identity = int(os.environ["IDENTITY"])

plist["BuildIdentities"][identity]["Manifest"]["KernelCache"]["Info"]["Path"] = os.environ["KERNEL2"]

with open("tmp2/BuildManifest.plist", "wb") as f:
    plistlib.dump(plist, f)
PY
cp -v tmp1/Firmware/AOP/$AOP14 tmp2/Firmware/AOP/$AOP
cp -v tmp1/Firmware/agx/$GFX tmp2/Firmware/agx/$GFX
cp -v tmp1/Firmware/ane/$ANE tmp2/Firmware/ane/$ANE
cp -v tmp1/Firmware/isp_bni/$ISP tmp2/Firmware/isp_bni/$ISP
if [[ $IDENTIFIER == iPhone* ]]; then
    cp -v tmp1/Firmware/$CALLAN tmp2/Firmware/$CALLAN
    cp -v tmp1/Firmware/WirelessPower/$WIRELESS tmp2/Firmware/WirelessPower/$WIRELESS
fi
if [[ ($IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$HAPTICASSET tmp2/Firmware/$HAPTICASSET
fi
cp -v tmp1/Firmware/all_flash/$DEVICETREE tmp2/Firmware/all_flash/$DEVICETREE
if [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$IOFW13 tmp2/Firmware/$IOFW
    cp -v tmp1/Firmware/ave/$AVE13 tmp2/Firmware/ave/$AVE
else
    cp -v tmp1/Firmware/$IOFW tmp2/Firmware/$IOFW
    cp -v tmp1/Firmware/ave/$AVE tmp2/Firmware/ave/$AVE
    cp -v tmp1/Firmware/$fs_dmg_name.root_hash tmp2/Firmware/$fs_dmg_18_name.root_hash 
    cp -v tmp1/Firmware/$fs_dmg_name.mtree tmp2/Firmware/$fs_dmg_18_name.mtree 
fi
if [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPhone12,8 ]]; then
    echo "Using latest MTFW"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    echo "Using latest MTFW"
else
    cp -v tmp1/Firmware/$MTFW tmp2/Firmware/$MTFW # copy MTFW for target iOS
fi
if [[ ($IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$LEAPHAPTIC tmp2/Firmware/$LEAPHAPTIC
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
if [[ $IDENTIFIER == iPhone12* ]]; then
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
cp -v $fs_dmg $fs_dmg_18 # replace rootfs in the IPSW
cp -v tmp1/Firmware/$fs_dmg_name.trustcache tmp2/Firmware/$fs_dmg_18_name.trustcache 
if [[ $VERSION == 16.4 ]]; then
    cp -v "$target_trustcache_path" "$base_trustcache_path"
else
    cp -v tmp1/Firmware/$ramdisk_dmg_name.trustcache tmp2/Firmware/$ramdisk_dmg_name_18.trustcache
fi
if [[ $VERSION == 16.4 ]]; then
    "$IOS164_IMG4" -i tmp1/$KERNEL -o work/kernel.raw
else
    ./bin/img4 -i tmp1/$KERNEL -o work/kernel.raw
fi
    if [[ $VERSION == 16.4 ]]; then
        # Use the verified 16.4 kernel patch set.
        "$LITER8_PYTHON" ./bin/patch_ios164_kernel.py \
            work/kernel.raw work/kernelboot.patch \
            --kernel64-patcher ./bin/Kernel64Patcher3
    elif [[ $VERSION == 14.* ]]; then
        ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -b # use kernel64patcher3, properly patch trust evaluation check on ios 14 arm64e
elif [[ $VERSION == 13.* ]]; then
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -b13 -n # make booting take less time (added -b13 to hopefully fix haptics issue)
else
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -e -o -r -b15
fi
./bin/kerneldiff work/kernel.raw work/kernelboot.patch work/kernelboot.diff
rm -rf tmp2/$KERNEL
if [[ $VERSION == 16.4 ]]; then
    "$IOS164_IMG4" -i tmp1/$KERNEL -o tmp2/$KERNEL2 -T krnl -J -P work/kernelboot.diff
else
    ./bin/img4 -i tmp1/$KERNEL -o tmp2/$KERNEL2 -T krnl -J -P work/kernelboot.diff || true
fi
if [[ $VERSION == 16.4 ]]; then
    # Reuse the verified kernel output.
    cp work/kernelboot.patch work/kernel.patch
else
    ./bin/KPlooshFinder work/kernel.raw work/kernel.patch
fi
./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
if [[ $VERSION == 16.4 ]]; then
    "$IOS164_IMG4" -i tmp1/$KERNEL -o tmp2/$KERNEL -T krnl -J -P work/kernel.diff
else
    ./bin/img4 -i tmp1/$KERNEL -o tmp2/$KERNEL -T krnl -J -P work/kernel.diff || true
fi
if [[ $VERSION == 16.4 ]]; then
    # Use the macOS path for the 16.4 APFS ramdisk and verify it.
    ./bin/patch_ios164_ramdisk.sh \
        "$restore_ramdisk_dmg" work/ramdisk.raw work \
        "$IOS164_IMG4" ./bin/asr64_patcher ./bin/libimg4_patcher ./bin/ldid
else
    ./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
    ./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
    ./bin/asr64_patcher work/asr work/asr_patched
    ./bin/ldid -e work/asr > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/asr_patched
    ./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
        if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
            ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
        ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
        ./bin/ldid -Swork/ents.plist work/libimg4.patch
        ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib
        ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
    fi
fi
    if [[ $VERSION == 15.* ]]; then
    if [[ $restored == "restored_update" ]]; then
        ramdisk_download_name="018-80166-001.dmg"
    else
        ramdisk_download_name="018-79907-001.dmg"
    fi
    ramdisk_url="https://updates.cdn-apple.com/2021FallFCS/fullrestores/002-02910/AF984499-D03A-43E7-9472-6D16BA756E5E/iPhone10,3,iPhone10,6_15.0_19A346_Restore.ipsw"
else
    if [[ $restored == "restored_update" ]]; then
        ramdisk_download_name="048-58813-634.dmg"
    else
        ramdisk_download_name="048-58904-639.dmg"
    fi
    ramdisk_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46617/B62CA88B-EB85-4A5A-9440-7E0B90B02006/iPhone10,3,iPhone10,6_14.0_18A373_Restore.ipsw"
fi
    if [[ $VERSION == 16.4 ]]; then
        # Keep the native 16.4 restore binary.
        echo "iOS 16.4: retaining native restored_external"
    elif [[ $IDENTIFIER == iPhone12,3 && $IPHONE12_3_BB_MODE == normal ]]; then
    # Keep the native d421 restore binary for this mode.
    ./bin/hfsplus work/ramdisk.raw extract usr/local/bin/$restored work/restored_external
    "${LITER8_PYTHON:-python3}" ./bin/d421_restored_patcher.py \
        work/restored_external work/restored_patch
    if cmp -s work/restored_external work/restored_patch; then
        echo "FATAL: native d421 restored patch produced no byte changes"
        exit 1
    fi
elif [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
    sudo ./bin/pzb -g $ramdisk_download_name $ramdisk_url
    ./bin/img4 -i $ramdisk_download_name -o work/ramdisk2.raw
    sudo rm -rf $ramdisk_download_name
    ./bin/hfsplus work/ramdisk2.raw extract usr/local/bin/$restored work/restored_external
    ./bin/ipx_restored_patcher work/restored_external work/restored_patch
    if [[ $IDENTIFIER == iPhone12,3 && $IPHONE12_3_BB_MODE == workaround ]]; then
        # Keep the upstream workaround for recovery testing.
        mv -v work/restored_patch work/restored_pat
        ./bin/restoredpatcher work/restored_pat work/restored_patch -b
    fi
fi
if [[ -f work/restored_patch ]]; then
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/$restored
    ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/$restored
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/$restored
fi
if [[ $VERSION == 15.* || $VERSION == 16.4 ]]; then
    if [[ $VERSION == 16.4 ]]; then
        trustcache_input="$target_trustcache_path"
        trustcache_output="$base_trustcache_path"
    else
        trustcache_input="tmp1/Firmware/$ramdisk_dmg_name.trustcache"
        trustcache_output="tmp2/Firmware/$ramdisk_dmg_name_18.trustcache"
    fi
    if [[ $VERSION == 16.4 ]]; then
        "$IOS164_IMG4" -i "$trustcache_input" -o work/trustcache.raw || exit 1
    else
        ./bin/img4 -i "$trustcache_input" -o work/trustcache.raw || exit 1
    fi
    if [[ $VERSION == 16.4 ]]; then
        [[ -s work/asr_patched && -s work/libimg4.patch ]] || {
            echo "FATAL: iOS 16.4 trust-cache inputs are missing"
            exit 1
        }
        cp work/trustcache.raw work/trustcache.stock.raw
    fi
    if [[ -f work/restored_patch ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
        ./bin/trustcache append work/trustcache.raw work/restored_patch || exit 1
    fi
    ./bin/trustcache append work/trustcache.raw work/asr_patched || exit 1
    ./bin/trustcache append work/trustcache.raw work/libimg4.patch || exit 1
    if [[ $VERSION == 16.4 ]]; then
        "$IOS164_IMG4" -i work/trustcache.raw -o "$trustcache_output" -A -T rtsc || exit 1
    else
        ./bin/img4 -i work/trustcache.raw -o "$trustcache_output" -A -T rtsc || exit 1
    fi
    if [[ $VERSION == 16.4 ]]; then
        # Add the patched files to the restore trust cache.
        [[ -s work/trustcache.raw && -s "$trustcache_output" ]] &&
        ! cmp -s work/trustcache.stock.raw work/trustcache.raw || {
            echo "FATAL: iOS 16.4 RestoreTrustCache injection failed"
            exit 1
        }
    fi
fi
# pack rdsk into im4p
if [[ $VERSION == 16.4 ]]; then
    "$IOS164_IMG4" -i work/ramdisk.raw -o $restore_ramdisk_dmg_18 -A -T rdsk
else
    ./bin/img4 -i work/ramdisk.raw -o $restore_ramdisk_dmg_18 -A -T rdsk
fi
cd tmp2
zip -0 -r ../custom.ipsw *
cd ..
if [[ $VERSION == 16.4 ]]; then
    validate_ios164_archive_boot_components custom.ipsw "$IPSW_PATH_LATEST" "$restoredir" || {
        rm -f custom.ipsw
        rm -rf tmp1 tmp2 work
        exit 1
    }
fi
rm -rf "tmp1"
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
rm -rf "work"

}

just_boot(){

if [[ ! -f boot/$ECID.txt ]]; then
    read -p "Input the version you'd like to boot: " VERSION
else
    VERSION=$(cat boot/$ECID.txt) 
fi
bootdir="boot/$IDENTIFIER/$VERSION"
if [[ ! -d $bootdir ]]; then
    echo "Please do a tethered restore to iOS $VERSION, then try tether boot again."
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* || $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device

sleep 5

echo "Sending iBSS"
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    ensure_liter8ctl || exit 1
    if [[ -z "${LITER8_PYTHON:-}" ]]; then
        LITER8_PYTHON="python3"
        [[ -x "$SCRIPT_DIR/.venv/bin/python" ]] && LITER8_PYTHON="$SCRIPT_DIR/.venv/bin/python"
    fi
    if ! "$LITER8_PYTHON" -c 'from usb.backend import libusb1; raise SystemExit(libusb1.get_backend() is None)' 2>/dev/null; then
        echo "FATAL: pyusb or its libusb backend is unavailable ($LITER8_PYTHON)."
        exit 1
    fi
    if [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
        "$LITER8_PYTHON" bin/liter8ctl boot $bootdir/iBSS.boot || true
        echo "If you see the error: No such device (it may have been disconnected)"
        echo "This error is normal on Linux as long as the Device actually starts booting after iBSS is sent."
    else
        "$LITER8_PYTHON" bin/liter8ctl boot $bootdir/iBSS.boot
    fi
    echo "Device should now boot"
    exit 0
fi
./bin/irecovery -f $bootdir/iBSS.img4
if [[ $IDENTIFIER == iPhone10* ]]; then
    echo "Device should now boot"
    exit 0
fi
sleep 5
echo "Sending iBEC"
./bin/irecovery -f $bootdir/iBEC.img4
sleep 5
echo "Sending DeviceTree"
./bin/irecovery -f $bootdir/DeviceTree.img4
./bin/irecovery -c devicetree
if [[ $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "Sending trustcache"
    ./bin/irecovery -f $bootdir/Trustcache.img4
    ./bin/irecovery -c firmware
fi
echo "Sending Kernelcache"
./bin/irecovery -f $bootdir/Kernelcache.img4
./bin/irecovery -c bootx
echo "Device should now boot"
exit 0

}

prepare_boot_files(){

rm -rf "work"
if [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87486/23310DA1-A434-4192-87BC-31429FD2D625/iPhone_4.7_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87451/EE6AEB4B-1BF7-4FBF-9D29-A8C7B970B495/iPhone_5.5_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87865/458334F5-D8E1-498A-A9FD-08BBD20FE007/iPhone10,3,iPhone10,6_14.3_18C66_Restore.ipsw"
fi
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
bootdir="boot/$IDENTIFIER/$VERSION"
if [[ $VERSION == 10.2* || $VERSION == 10.1* ]]; then
    krnl="$KERNEL10"
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS10" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC10" -d work
    unzip -j "$IPSW_PATH" "Firmware/all_flash/$ALLFLASH/$DEVICETREE" -d work
    ./bin/img4 -i work/$IBSS10 -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC10 -o work/iBEC.raw -k $IBEC_KEY
else
    krnl="$KERNEL"
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC" -d work
    unzip -j "$IPSW_PATH" "Firmware/all_flash/$DEVICETREE" -d work
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0 ]]; then # just for 14.0 beta 4 restore
        cd work
        sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
        sudo ../bin/pzb -g Firmware/dfu/$IBEC $ipsw_url
        cd ..
    fi
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
fi
if [[ $VERSION == 10.* || $VERSION == 11.* || $VERSION == 12.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="iBoot64Patcher"
fi
rm -rf "$bootdir"
mkdir -p boot
mkdir -p boot/$IDENTIFIER
mkdir -p boot/$IDENTIFIER/$VERSION
if [[ $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* ]]; then
    unzip -j "$IPSW_PATH" "Firmware/*.dmg.trustcache" -d work
    trustcache_use=$(ls -S work/*.trustcache 2>/dev/null | head -n 1)
    ./bin/img4 -i $trustcache_use -o $bootdir/Trustcache.img4
fi
unzip -j "$IPSW_PATH" "$krnl" -d work
./bin/$ibootpatcher work/iBSS.raw work/iBSS.patch
./bin/$ibootpatcher work/iBEC.raw work/iBEC.patch -b "-v" 
if [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patch -l -b "-v"
fi
./bin/img4 -i work/iBSS.patch -o $bootdir/iBSS.img4 -A -T ibss -M $im4m
./bin/img4 -i work/iBEC.patch -o $bootdir/iBEC.img4 -A -T ibec -M $im4m
./bin/img4 -i work/$DEVICETREE -o $bootdir/DeviceTree.img4 -T rdtr -M $im4m
./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m
if [[ $VERSION == 14.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -b
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
elif [[ $VERSION == 15.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -e -o -r -b15
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
elif [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -b13 -n
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi
if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 11.* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi
if [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi

}

do_tethered_restore(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "No IPSW selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW does not exist: $IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW is not selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW does not exist: $IPSW_PATH_LATEST"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.3* || $VERSION == 14.4* || $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* || $VERSION == 15.* ]]; then
    echo "SEP is partially incompatible, read the following:"
    echo "The device will be unable to activate after the restore."
    echo "You will need to tether restore to 14.0 beta 4 first, activate the device, then tether restore to the desired version."
    echo "Sideloading outside of TrollStore may or may not work, your mileage may vary."
    echo "And potentially other broken features"
    echo "You cannot set a Passcode or use Touch ID because of BPR being enforced"
    read -p "Press enter to continue"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "Your device may have deep sleep issues after this restore"
    read -p "Press enter to continue"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.* ]]; then
    echo "Your device may have deep sleep issues after this restore"
    echo "Touch ID will not work"
    read -p "Press enter to continue"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 12.* || $VERSION == 11.4* || $VERSION == 11.3* ]]; then
    echo "Touch ID will not work"
    if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 12.* ]]; then
        echo "USB accessories will not work"
        echo "Your device may have deep sleep issues after this restore"
    fi
    read -p "Press enter to continue"
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    echo "Touch ID will not work"
    read -p "Press enter to continue"
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0* || $VERSION == 14.1* || $VERSION == 14.2* ]] && [[ $BUILD != 18A5342e ]]; then
    echo "14.2 and lower downgrades are unsupported, except for 14.0 beta 4"
    if [[ $VERSION == 13.* || $VERSION == 12.* || $VERSION == 11.* ]]; then
        echo "Also, 14.3 iBoot workaround does not work on 13.x and lower. SEP is totally incompatible"
    fi
    exit 1
fi
if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4* ]] && [[ $VERSION == 10.3.3 ]] && [[ $BUILD == 14G60 ]]; then
    echo "10.3.3 tether downgrades are not supported on this device."
    if [[ $IDENTIFIER == iPad4,6 ]]; then
        echo "10.3.3 is also not OTA signed for this device, so you cannot restore to 10.3.3 without saved blobs"
    fi
    exit 1
fi
if [[ $IDENTIFIER == iPad4,6 || $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 || $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP is incompatible"
    exit 1
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPod7* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.0* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP is incompatible"
    exit 1
fi

if [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.1* || $VERSION == 13.2* || $VERSION == 13.3* ]]; then
    echo "13.x restores below 13.4 are not supported"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION != 16.6* ]] && [[ $BUILD == 20* ]]; then
    echo "iOS 16.0-16.5.1 restores are unsupported"
    echo "And iOS 16.7.x restores are unsupported"
    exit 1
elif [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.6* ]]; then
    echo "You will have some issues with the restore:"
    echo "iMessage/SMS may not work"
    echo "VPNs may not work, and potentially other issues."
    read -p "Press enter to continue"
fi

if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    echo "11.3-12.4.1 downgrades are supported but they have not been integrated yet into surrealra1n $CURRENT_VERSION"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device
det_rsep_flag
echo "Fetching shsh blobs for iOS $LATEST_VERSION"
rm -rf "shsh"
mkdir -p shsh
mkdir -p boot
ECID=$(./bin/irecovery -q | grep "^ECID:" | cut -d ':' -f2 | xargs)
echo "$VERSION" > boot/$ECID.txt
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh

# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "No SHSH file found in the shsh folder. Aborting"
    exit 1
fi

restoredir="restorefiles/$IDENTIFIER/$VERSION"

if [[ ! -f "$restoredir/custom.ipsw" ]] && [[ ! -f "$restoredir/ramdisk.im4p" ]] && [[ ! -f "$restoredir/kernel.im4p" ]]; then
    echo "Restore files does not exist, making new ones"
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.* ]]; then
        make_custom_ipsw_ios16
    else
        make_custom_ipsw
    fi
else
    echo "Restore files already exist"
    read -p "Would you like to make new ones? (y/n): " restorefiles_remake
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        rm -rf "$restoredir"
        if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.* ]]; then
            make_custom_ipsw_ios16
        else
            make_custom_ipsw
        fi
    fi
fi

if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]] && [[ $VERSION == 10.* ]]; then
    download_tvos_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad4* || $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.* ]]; then
    download_1033_ota_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    download_iphone6_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
else
    prepatch_ibssibec_fr
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.* || $VERSION == 15.* ]] && [[ $BUILD != 18A5342e ]]; then
        ramdisk_det="updateramdisk"
    else
        ramdisk_det="ramdisk"
    fi
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu --skip-blob --rdsk $restoredir/$ramdisk_det.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p --latest-sep \
            $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore segfaulted (exit 139), retrying..."
            sleep 2
        else
            break
        fi
    done
fi

if [[ ${EXIT_CODE:-1} -eq 0 ]]; then
    echo "Restore has completed! Read above if there are any errors"
    prepare_boot_files
    exit 0
fi
echo "futurerestore failed with exit code ${EXIT_CODE:-unknown}"
exit 1

}

do_tethered_restore_a12_a13(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "No IPSW selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW does not exist: $IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW is not selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW does not exist: $IPSW_PATH_LATEST"
    exit 1
fi

if [[ $IDENTIFIER == iPhone11,4 ]] && [[ $VERSION == 14.1* ]]; then
    echo "14.1 downgrades are not supported on this device"
    exit 1
fi

if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "SEP is partially incompatible, read the following:"
    echo "The device will be unable to activate after the restore."
    echo "Sideloading outside of TrollStore may or may not work, your mileage may vary."
    echo "And potentially other broken features"
    echo "You cannot set a Passcode or use Touch ID because of BPR being enforced"
    if [[ $IDENTIFIER == iPhone11* ]]; then
        echo "You will need to tether restore to 14.0 beta 4 first, activate the device, then tether restore to the desired version."
    elif [[ $IDENTIFIER == iPhone12,8 ]]; then
        echo "You will need to tether restore to iOS 13.4.1 - 13.7 first, activate the device (may have to activate via Finder/iTunes/Legacy iOS Kit), then tether restore to the desired version."
        echo "You may also stay on iOS 13 if desired more than iOS 15."
        echo "Haptic home button will not work."
    fi
    read -p "Press enter to continue"
    elif [[ $VERSION == 16.4 ]]; then
        echo "iOS 16.4 is an experimental tethered target."
        echo "The first pass uses --no-baseband; SEP/U1/activation are independent risks."
    elif [[ $VERSION == 16.* || $VERSION == 17.* || $VERSION == 18.* || $VERSION == 26.* ]]; then
        echo "Only iOS 16.4 is wired into this experimental A12/A13 path."
        exit 1
elif [[ $VERSION == 13.* || $VERSION == 12.* ]] && [[ $IDENTIFIER == iPhone11* ]]; then
    echo "SEP is incompatible"
    exit 1
elif [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    echo "SEP is partially incompatible"
    echo "You cannot set a Passcode or use Touch ID because of BPR being enforced"
    echo "Haptic home button will not work, and AssistiveTouch home button will also not appear"
    read -p "Press enter to continue"
fi

if [[ $IDENTIFIER == iPhone12* ]] && [[ $VERSION == 14.* ]]; then
    echo "iOS 14 downgrades on A13 are not supported at the moment"
    exit 1
fi

if [[ $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.0* || $VERSION == 15.1* || $VERSION == 15.2* || $VERSION == 15.3* ]] && [[ $IDENTIFIER == iPhone12* ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
    # U1 compatibility is still uncertain.
    echo
    echo "================================================================"
    echo " WARNING: Rose (U1) is very likely incompatible on this target"
    echo " Device: $IDENTIFIER   Target: iOS $VERSION"
    echo " Expect failed restore, hang, or broken UWB — not “supported”."
    echo " You need matching keys in keys/$IDENTIFIER.txt (e.g. ibss-$VERSION)."
    echo "================================================================"
    read -p "Force continue and try anyway? (y/N): " rose_force
    if [[ $rose_force != y && $rose_force != Y ]]; then
        echo "Aborted (Rose gate)."
        exit 1
    fi
    echo "Proceeding past Rose gate at your own risk..."
elif [[ $VERSION == 15.4* || $VERSION == 15.5* || $VERSION == 15.6* ]] && [[ $IDENTIFIER == iPhone12* ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
    echo "iOS $LATEST_VERSION Rose may or may not be compatible"
    echo "Proceed with very extreme caution."
    read -p "Press enter to continue"
fi

if [[ $VERSION == 16.4 ]]; then
    prepare_ios164_build_inputs "$IPSW_PATH" "$IPSW_PATH_LATEST"
    ensure_ios164_futurerestore || exit 1
fi

	dfu_helper_a11
	pwn_device
	det_rsep_flag

	# Start 16.4 experiments without updating modem firmware.
	if [[ $VERSION == 16.4 ]]; then
	    case "${SURREALRA1N_IOS164_BASEBAND:-none}" in
	        none) updatebb_flag="--no-baseband" ;;
	        latest) updatebb_flag="--latest-baseband" ;;
	        *) echo "Invalid SURREALRA1N_IOS164_BASEBAND (use none or latest)"; exit 1 ;;
	    esac
	    echo "iOS 16.4 baseband mode: ${SURREALRA1N_IOS164_BASEBAND:-none} ($updatebb_flag)"
	fi

restoredir="restorefiles/$IDENTIFIER/$VERSION"

# Normal mode keeps the native d421 updater.
IPHONE12_3_BB_MODE="${SURREALRA1N_11PRO_BB_MODE:-normal}"
IPHONE12_3_BB_ENGINE="native-d421-v1"
[[ $IPHONE12_3_BB_MODE == workaround ]] && IPHONE12_3_BB_ENGINE="upstream-workaround-v1"
if [[ $IDENTIFIER == iPhone12,3 && $VERSION != 16.4 ]]; then
    if [[ $IPHONE12_3_BB_MODE != workaround && $IPHONE12_3_BB_MODE != normal ]]; then
        echo "Invalid SURREALRA1N_11PRO_BB_MODE='$IPHONE12_3_BB_MODE' (use workaround or normal)."
        exit 1
    fi
    if [[ -z ${SURREALRA1N_11PRO_BB_MODE:-} ]]; then
        echo
        echo "iPhone 11 Pro baseband mode:"
        echo "  [Y] Native normal baseband (default): required for service; activation still depends on SEP"
        echo "  [n] Upstream workaround: known restore success, but no usable baseband / activation"
        read -p "Use native normal baseband? (Y/n): " iphone12_3_bb_choice
        if [[ $iphone12_3_bb_choice == N || $iphone12_3_bb_choice == n ]]; then
            IPHONE12_3_BB_MODE="workaround"
            IPHONE12_3_BB_ENGINE="upstream-workaround-v1"
        fi
    fi
    echo "iPhone 11 Pro baseband mode: $IPHONE12_3_BB_MODE"
fi

if [[ ! -f "$restoredir/custom.ipsw" ]]; then
    echo "Restore files does not exist, making new ones"
    make_custom_ipsw_a12_ios14
else
    echo "Restore files already exist"
    restorefiles_remake=""
    if [[ $VERSION == 16.4 ]] && ! validate_ios164_archive_boot_components "$restoredir/custom.ipsw" "$IPSW_PATH_LATEST"; then
        echo "The existing iOS 16.4 artifact is invalid (likely a hybrid 26.x archive) and will be rebuilt."
        restorefiles_remake="Y"
    fi
    if [[ $IDENTIFIER == iPhone12,3 && $VERSION != 16.4 ]]; then
        existing_bb_mode="$(cat "$restoredir/.iphone12_3_bb_mode" 2>/dev/null || true)"
        existing_bb_engine="$(cat "$restoredir/.iphone12_3_bb_engine" 2>/dev/null || true)"
        # Earlier IPSWs used the baseless workaround.
        [[ -z $existing_bb_mode ]] && existing_bb_mode="workaround"
        [[ -z $existing_bb_engine && $existing_bb_mode == workaround ]] && \
            existing_bb_engine="upstream-workaround-v1"
        if [[ $existing_bb_mode != $IPHONE12_3_BB_MODE || \
              $existing_bb_engine != $IPHONE12_3_BB_ENGINE ]]; then
            echo "The existing custom IPSW uses '$existing_bb_mode/$existing_bb_engine'."
            echo "Rebuilding it for '$IPHONE12_3_BB_MODE/$IPHONE12_3_BB_ENGINE'."
            restorefiles_remake="Y"
        fi
    fi
    if [[ -z $restorefiles_remake ]]; then
        read -p "Would you like to make new ones? (y/n): " restorefiles_remake
    fi
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        if [[ ($IDENTIFIER == iPhone12,3 || $VERSION == 16.4) && -d $restoredir ]]; then
            restorefiles_backup="${restoredir}.backup-$(date +%Y%m%d-%H%M%S)"
            echo "Preserving existing restore files at: $restorefiles_backup"
            mv "$restoredir" "$restorefiles_backup"
        else
            rm -rf "$restoredir"
        fi
        make_custom_ipsw_a12_ios14
    fi
fi
if [[ $IDENTIFIER == iPhone12,3 && $VERSION != 16.4 ]]; then
    # Save the baseband mode with the generated IPSW.
    printf '%s\n' "$IPHONE12_3_BB_MODE" > "$restoredir/.iphone12_3_bb_mode"
    printf '%s\n' "$IPHONE12_3_BB_ENGINE" > "$restoredir/.iphone12_3_bb_engine"
fi
local boot_ibss_path="boot/$IDENTIFIER/iBSS.patch"
if [[ $VERSION == 16.4 ]]; then
    boot_ibss_path="boot/$IDENTIFIER/$VERSION/iBSS.patch"
    [[ -s "$boot_ibss_path" ]] || {
        echo "FATAL: missing versioned iOS 16.4 restore iBSS: $boot_ibss_path"
        exit 1
    }
    [[ -s "$restoredir/ramdisk.im4p" && -s "$restoredir/kernel.im4p" ]] || {
        echo "FATAL: missing iOS 16.4 --rdsk/--rkrn artifacts in $restoredir"
        echo "Rebuild restore files (answer y when prompted)."
        exit 1
    }
fi
ensure_liter8ctl || exit 1
# pyusb is required before booting.
if [[ -z "${LITER8_PYTHON:-}" ]]; then
    LITER8_PYTHON="python3"
    [[ -x "$SCRIPT_DIR/.venv/bin/python" ]] && LITER8_PYTHON="$SCRIPT_DIR/.venv/bin/python"
fi
if ! "$LITER8_PYTHON" -c 'from usb.backend import libusb1; raise SystemExit(libusb1.get_backend() is None)' 2>/dev/null; then
    echo "FATAL: pyusb or its libusb backend is unavailable ($LITER8_PYTHON)."
    echo "Install pyusb in .venv and install libusb before retrying."
    exit 1
fi
# Keep the device in pwned DFU until the files are ready.
echo "Booting patched iBSS with liter8ctl ($LITER8_PYTHON)..."
if [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
    "$LITER8_PYTHON" bin/liter8ctl boot "$boot_ibss_path" || true
    echo "If you see the error: No such device (it may have been disconnected)"
    echo "This error is normal on Linux as long as the Device enters iBSS recovery mode (screen Should remain blank but be detected as Recovery mode device)."
elif [[ $dist == 3 ]] && [[ ${macos_ver:-} == 27.* || ${macos_ver:-} == 26.* ]]; then
    "$LITER8_PYTHON" bin/liter8ctl boot "$boot_ibss_path" || true
    echo "usbliter8ctl may error out after a successful handoff."
    echo "The error may be normal as long as the Device enters iBSS recovery mode (screen Should remain blank but be detected as Recovery mode device)."
else
    "$LITER8_PYTHON" bin/liter8ctl boot "$boot_ibss_path"
fi
sleep 6
echo "Checking if device is in Recovery mode"
MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs || true)
if [[ $MODE == Recovery ]]; then
    echo "Device has been detected in Recovery mode."
else
    echo "Device not detected in Recovery (mode='${MODE:-none}'). Staying in DFU usually means liter8ctl never loaded iBSS."
    echo "Checklist:"
    echo "  1) pyusb works:  $LITER8_PYTHON -c 'import usb'"
    echo "  2) phone still PWND DFU (re-pwn with Pico if needed)"
    echo "  3) boot file exists: $boot_ibss_path"
    echo "  4) re-run Start Restore; custom.ipsw is already built — answer n to remake"
    exit 1
fi
APNONCE=$(./bin/irecovery -q | grep "^NONC:" | cut -d ':' -f2 | xargs)
ECID=$(./bin/irecovery -q | grep "^ECID:" | cut -d ':' -f2 | xargs)
mkdir -p boot
echo "$VERSION" > boot/$ECID.txt
if [[ $IDENTIFIER == iPhone12,8 ]]; then
    sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -ey $restoredir/custom.ipsw
    echo "Restore has finished! Read above if there are any errors"
    exit 0
fi
echo "Fetching shsh blobs for iOS $LATEST_VERSION"
rm -rf "shsh"
mkdir -p shsh
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh --apnonce $APNONCE
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "No SHSH file found in the shsh folder. Aborting"
    exit 1
fi
mkdir -p logs
restore_log="logs/${IDENTIFIER//,/_}-${VERSION}-$(date +%Y%m%d-%H%M%S).log"
echo "Saving the complete futurerestore log to: $restore_log"
local restore_attempt=0
local max_restore_attempts=3
local attempt_log=""
local tee_exit_code=0
local -a pipe_status=()
local fr_bin="./futurerestore/futurerestore"
local -a fr_args=()
local fr_cache=""
if [[ $VERSION == 16.4 ]]; then
    ensure_ios164_futurerestore || exit 1
    fr_bin="./futurerestore/futurerestore-usbliter8"
    stage_ios164_futurerestore_iboot "$restoredir" "$SHSH_PATH" || exit 1
    fr_cache="${TMPDIR:-/tmp}/surrealra1n-fr-cache-${IOS164_BASE_BUILD}"
    mkdir -p "$fr_cache"
    # Prefer local base IPSW over CDN pzb for Cryptex1 (LFZP mid-download fails are common).
    seed_ios164_futurerestore_cache "$IPSW_PATH_LATEST" "$fr_cache" || true
    # Proven A13 tethered path: live liter8 Recovery + Odysseus flags + external rdsk/rkrn.
    # Do NOT pass plain stock FR against a hybrid 26.x archive — that is the
    # "Unable to place device into restore mode" failure mode from beta22 logs.
    fr_args=(
        -t "$SHSH_PATH"
        --latest-sep
        --use-pwndfu
        --no-ibss
        --skip-blob
        --rdsk "$restoredir/ramdisk.im4p"
        --rkrn "$restoredir/kernel.im4p"
        --custom-latest-buildid "$IOS164_BASE_BUILD"
    )
    # Expand baseband flag into the array (may be --no-baseband or --latest-baseband).
    # shellcheck disable=SC2206
    fr_args+=($updatebb_flag)
    [[ -n "${rsep_flag:-}" ]] && fr_args+=($rsep_flag)
    fr_args+=("$restoredir/custom.ipsw")
    echo "iOS 16.4 Odysseus futurerestore argv:"
    printf '  %q' "$fr_bin"
    printf ' %q' "${fr_args[@]}"
    printf '\n'
    echo "iOS 16.4 FR cache (TMPDIR): $fr_cache"
else
    fr_args=(-t "$SHSH_PATH" $rsep_flag --latest-sep $updatebb_flag "$restoredir/custom.ipsw")
fi
while true; do
    restore_attempt=$((restore_attempt + 1))
    attempt_log=$(mktemp "${TMPDIR:-/tmp}/surrealra1n-futurerestore.XXXXXX") || {
        echo "Could not create a futurerestore attempt log."
        exit 1
    }
    set +e
    if [[ $VERSION == 16.4 ]]; then
        # Re-seed before every attempt so a purged cryptex cache is refilled from IPSW.
        seed_ios164_futurerestore_cache "$IPSW_PATH_LATEST" "$fr_cache" || true
        sudo env \
            HOME="$HOME" \
            TMPDIR="$fr_cache" \
            FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            "$fr_bin" "${fr_args[@]}" 2>&1 | tee -a "$restore_log" "$attempt_log"
    else
        sudo "$fr_bin" "${fr_args[@]}" 2>&1 | tee -a "$restore_log" "$attempt_log"
    fi
    pipe_status=("${PIPESTATUS[@]}")
    EXIT_CODE=${pipe_status[0]}
    tee_exit_code=${pipe_status[1]}
    set -e
    if [[ $EXIT_CODE -eq 139 ]]; then
        rm -f "$attempt_log"
        if [[ $restore_attempt -ge $max_restore_attempts ]]; then
            echo "futurerestore kept crashing after $restore_attempt attempts."
            break
        fi
        echo "futurerestore segfaulted (exit 139), retrying..."
        sleep 2
        continue
    fi
    if [[ $VERSION == 16.4 ]] &&
       { grep -Fq 'Could not download Cryptex1' "$attempt_log" ||
         grep -Fq '[LFZP] failed to download file' "$attempt_log" ||
         grep -Fq 'failed to download file (487)' "$attempt_log"; }; then
        echo "Cryptex/CDN download failed (libfragmentzip). Purging partial cache and retrying from base IPSW seed..."
        purge_ios164_partial_cryptex_cache "$fr_cache"
        rm -f "$attempt_log"
        if [[ $restore_attempt -ge $max_restore_attempts ]]; then
            echo "Cryptex download kept failing after $restore_attempt attempts."
            EXIT_CODE=1
            break
        fi
        sleep 2
        continue
    fi
    if [[ $tee_exit_code -ne 0 ]]; then
        echo "Could not save the futurerestore log."
        EXIT_CODE=1
    elif grep -Fq 'Done: restoring failed!' "$attempt_log" ||
         grep -Fq '[exception]:' "$attempt_log"; then
        echo "futurerestore reported a restore failure despite exit code $EXIT_CODE."
        EXIT_CODE=1
    elif ! grep -Fq 'Done: restoring succeeded!' "$attempt_log"; then
        echo "futurerestore exited without a verified completion marker."
        EXIT_CODE=1
    fi
    rm -f "$attempt_log"
    break
done
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Restore has completed! Read above if there are any errors"
    exit 0
else
    echo "futurerestore failed with exit code $EXIT_CODE"
    if [[ $VERSION == 16.4 ]]; then
        echo "iOS 16.4 tip: stay in post-iBSS Recovery (do not reboot) between liter8 and FR."
        echo "If NONC changed, re-pwn DFU and re-run Start Restore so a fresh ticket is minted."
        echo "If you saw Cryptex/LFZP errors: wipe FR cache and re-seed from the base IPSW:"
        echo "  sudo rm -rf \"\${TMPDIR:-/tmp}/surrealra1n-fr-cache-${IOS164_BASE_BUILD}\""
        echo "  (or on Linux: sudo rm -rf /tmp/surrealra1n-fr-cache-23F84)"
        echo "Full log: $restore_log"
    fi
    exit 1
fi

}

prepare_seprmvr64_ipsw_legacy(){

if [[ $VERSION == 7.* ]]; then
    IBSS_2="$IBSS7"
    IBEC_2="$IBEC7"
else
    IBSS_2="$IBSS10"
    IBEC_2="$IBEC10"
fi
if [[ $VERSION == 9.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="ipatcher"
fi
if [[ $VERSION == 7.* ]]; then
    grow_to="2500000000"
elif [[ $VERSION == 8.* ]]; then
    grow_to="3200000000"
fi

mkdir -p noseprestore
mkdir -p noseprestore/$IDENTIFIER
mkdir -p noseprestore/$IDENTIFIER/$VERSION
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
DTRE_KEY=$(grep "dtre-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
RDSK_KEY=$(grep "rdsk-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
KRNL_KEY=$(grep "krnl-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
ROOT_KEY=$(grep "fstm-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
# ramdisk handling
smallestlatest_dmg=$(find_dmg tmp2 smallest)
rootfs_dmg=$(find_dmg tmp1 largest)
rootfslatest_dmg=$(find_dmg tmp2 largest)
if [[ $VERSION == 7.0* ]]; then
    smallest_dmg=$(find_dmg tmp1 largest 10370000)
else
    smallest_dmg=$(find_dmg tmp1 smallest)
fi
./bin/img4 -i tmp1/Firmware/dfu/$IBSS_2 -o tmp1/iBSS.raw -k $IBSS_KEY
./bin/img4 -i tmp1/Firmware/dfu/$IBEC_2 -o tmp1/iBEC.raw -k $IBEC_KEY
./bin/$ibootpatcher tmp1/iBSS.raw tmp1/iBSS.patch
./bin/$ibootpatcher tmp1/iBEC.raw tmp1/iBEC.patch -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1"
./bin/img4 -i tmp1/iBSS.patch -o tmp2/Firmware/dfu/$IBSS -A -T ibss
./bin/img4 -i tmp1/iBEC.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
./bin/img4 -i tmp1/Firmware/all_flash/$ALLFLASH/$DEVICETREE -o tmp1/DeviceTree.raw -k $DTRE_KEY
perl -pi -e 's/content-protect/content-protecV/g' tmp1/DeviceTree.raw
./bin/img4 -i tmp1/DeviceTree.raw -o tmp2/Firmware/all_flash/$DEVICETREE -A -T rdtr
./bin/img4 -i tmp1/$KERNEL10 -o tmp1/kernel.raw -k $KRNL_KEY
./bin/img4 -i tmp1/$KERNEL10 -o tmp1/kernel.im4p -k $KRNL_KEY -D
if [[ $VERSION == 7.* ]]; then
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 7 -m 7 -e 7 -f 7 -k
elif [[ $VERSION == 8.* ]]; then
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
else
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 9 -f 9 -k -v
fi
./bin/kerneldiff tmp1/kernel.raw tmp1/kernel.patch tmp1/kernel.diff
./bin/img4 -i tmp1/kernel.im4p -o tmp2/$KERNEL -T rkrn -P tmp1/kernel.diff -J || true
./bin/img4 -i $smallest_dmg -o tmp1/ramdisk.raw -k $RDSK_KEY
./bin/hfsplus tmp1/ramdisk.raw grow 40000000
./bin/hfsplus tmp1/ramdisk.raw extract usr/sbin/asr tmp1/asr
./bin/asr64_patcher tmp1/asr tmp1/asr_patched
if [[ $VERSION == 8.* || $VERSION == 9.* ]]; then
    ./bin/ldid -e tmp1/asr > tmp1/ents.plist
    ./bin/ldid -Stmp1/ents.plist tmp1/asr_patched
fi
./bin/hfsplus tmp1/ramdisk.raw rm usr/sbin/asr
./bin/hfsplus tmp1/ramdisk.raw add tmp1/asr_patched usr/sbin/asr
./bin/hfsplus tmp1/ramdisk.raw chmod 100755 usr/sbin/asr
./bin/img4 -i tmp1/ramdisk.raw -o $smallestlatest_dmg -A -T rdsk
rm -rf $rootfslatest_dmg
./bin/dmg extract $rootfs_dmg tmp1/rootfs.raw -k $ROOT_KEY
if [[ $VERSION == 7.* || $VERSION == 8.* ]]; then
    ./bin/hfsplus tmp1/rootfs.raw grow $grow_to
fi
if [[ $VERSION == 9.* ]]; then
    echo "Skipping removal of powerd"
else
    # Try and work around deep sleep issues without jailbreak
    echo "Removing powerd"
    ./bin/hfsplus tmp1/rootfs.raw rm System/Library/CoreServices/powerd.bundle/powerd
    ./bin/hfsplus tmp1/rootfs.raw rm System/Library/LaunchDaemons/com.apple.powerd.plist
fi
if [[ $JAILBREAK == 1 ]] && [[ $VERSION == 7.* ]]; then
    if [[ $VERSION == 7.1* ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/panguaxe.tar"
    elif [[ $VERSION == 7.0.* ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/evasi0n7-untether.tar"
    elif [[ $VERSION == 7.0 ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/evasi0n7-untether-70.tar"
    fi
    curl -L -o tmp1/freeze.tar.gz https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/freeze.tar.gz
    curl -L -o tmp1/untether.tar $untether
    gzip -d tmp1/freeze.tar.gz
    ./bin/hfsplus tmp1/rootfs.raw untar tmp1/freeze.tar
    ./bin/hfsplus tmp1/rootfs.raw untar tmp1/untether.tar
fi
./bin/dmg build tmp1/rootfs.raw $rootfslatest_dmg
cd tmp2
zip -0 -r ../$restoredir/$ipsw_custom *
cd ..
rm -rf "tmp1"
rm -rf "tmp2"

}

prepare_boot_files_seprmvr64(){

if [[ $VERSION == 7.* ]]; then
    IBSS_2="$IBSS7"
    IBEC_2="$IBEC7"
else
    IBSS_2="$IBSS10"
    IBEC_2="$IBEC10"
fi
if [[ $VERSION == 9.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="ipatcher"
fi
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
DTRE_KEY=$(grep "dtre-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
KRNL_KEY=$(grep "krnl-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
bootdir="boot/$IDENTIFIER/$VERSION"
mkdir -p boot
mkdir -p boot/$IDENTIFIER
mkdir -p boot/$IDENTIFIER/$VERSION
unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS_2" -d work
unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC_2" -d work
unzip -j "$IPSW_PATH" "Firmware/all_flash/$ALLFLASH/$DEVICETREE" -d work
unzip -j "$IPSW_PATH" "$KERNEL10" -d work
./bin/img4 -i work/$IBSS_2 -o work/iBSS.raw -k $IBSS_KEY
./bin/img4 -i work/$IBEC_2 -o work/iBEC.raw -k $IBEC_KEY
./bin/img4 -i work/$DEVICETREE -o work/DeviceTree.im4p -k $DTRE_KEY -D
./bin/img4 -i work/$KERNEL10 -o work/kernel.raw -k $KRNL_KEY
./bin/img4 -i work/$KERNEL10 -o work/kernel.im4p -k $KRNL_KEY -D
./bin/$ibootpatcher work/iBSS.raw work/iBSS.patch
./bin/$ibootpatcher work/iBEC.raw work/iBEC.patch -b "-v"
./bin/img4 -i work/iBSS.patch -o $bootdir/iBSS.img4 -A -T ibss -M $im4m
./bin/img4 -i work/iBEC.patch -o $bootdir/iBEC.img4 -A -T ibec -M $im4m
./bin/img4 -i work/DeviceTree.im4p -o $bootdir/DeviceTree.img4 -T rdtr -M $im4m
if [[ $VERSION == 7.* ]]; then
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 7 -m 7 -e 7 -f 7 -k
elif [[ $VERSION == 8.* ]]; then
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
else
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 9 -f 9 -k -v
fi
./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
./bin/img4 -i work/kernel.im4p -o $bootdir/Kernelcache.img4 -T rkrn -P work/kernel.diff -J -M $im4m || true
rm -rf "work"

}

do_tethered_seprmvr64_restore(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "No IPSW selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW does not exist: $IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW is not selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "Latest IPSW does not exist: $IPSW_PATH_LATEST"
    exit 1
fi

echo "Here is the following things that may happen on seprmvr64 restore:"
echo "1. Touch ID will not work"
echo "2. Passcode will not work"
echo "3. Password protected Wi-Fi networks will not work"
echo "4. Battery life may be affected on iOS 7/8, because we use a workaround there to make deep sleep panics not occur"
echo "5. Potentially other broken features"
read -p "Press enter to continue"
if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]]; then
    echo "A8 is currently unsupported as we are rewriting surrealra1n, but it should be back eventually."
    exit 1
fi

restoredir="noseprestore/$IDENTIFIER/$VERSION"
stitch_activation=0
if [[ $JAILBREAK == 1 ]] && [[ $stitch_activation != 1 ]]; then
    ipsw_custom="customJB.ipsw"
elif [[ $JAILBREAK == 1 ]] && [[ $stitch_activation == 1 ]]; then
    ipsw_custom="customJB_$ECID.ipsw"
elif [[ $JAILBREAK != 1 ]] && [[ $stitch_activation == 1 ]]; then
    ipsw_custom="custom_$ECID.ipsw"
else
    ipsw_custom="custom.ipsw"
fi

if [[ ! -f "$restoredir/$ipsw_custom" ]]; then
    echo "Restore files does not exist, making new ones"
    prepare_seprmvr64_ipsw_legacy
else
    echo "Restore files already exist"
    read -p "Would you like to make new ones? (y/n): " restorefiles_remake
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        rm -rf "$restoredir"
        prepare_seprmvr64_ipsw_legacy
    fi
fi

rm -rf "shsh"
mkdir -p shsh
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "No SHSH file found in the shsh folder. Aborting"
    exit 1
fi
./bin/img4tool -s "$SHSH_PATH" -e -m "$IDENTIFIER-im4m"
im4m="$IDENTIFIER-im4m"

dfu_helper
pwn_device
sleep 5
ECID=$(./bin/irecovery -q | grep "^ECID:" | cut -d ':' -f2 | xargs)
mkdir -p boot
echo "$VERSION" > boot/$ECID.txt
sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -ey $restoredir/$ipsw_custom
echo "Restore has finished! Read above if there's any errors"
prepare_boot_files_seprmvr64
exit 0

}

restore_tethered_opts(){

clear 
echo "$INFO_TEXT"
echo "seprmvr64 restores to iOS 7 and 9 are not removed."
echo "The separate seprmvr64 restore options was removed because the functionality was migrated to this menu"
echo ""
echo "Options:"
echo ""
echo "1. Select Target IPSW"
echo "2. Select Base IPSW"
echo "3. Start Restore"
echo "4. Back"
read -p "Please input an option (1-4): " tether_options
if [[ $tether_options == 1 ]]; then
    IPSW_PATH=$(pick_file "Select an IPSW file")
    if [[ -z "$IPSW_PATH" ]]; then
        echo "No IPSW selected. Aborting."
        exit 1
    fi
    rm -rf work/BuildManifest.plist
    unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
    BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    restore_tethered_opts
elif [[ $tether_options == 2 ]]; then
    IPSW_PATH_LATEST=$(pick_file "Select iOS $LATEST_VERSION IPSW file")
    if [[ -z "$IPSW_PATH_LATEST" ]]; then
        echo "No IPSW selected. Aborting."
        exit 1
    fi
    rm -rf work/BuildManifest.plist
    unzip -j "$IPSW_PATH_LATEST" "BuildManifest.plist" -d work
    VERSION_LATEST=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    if [[ $VERSION_LATEST != $LATEST_VERSION ]]; then
        echo "Invalid IPSW. You must select IPSW for iOS $LATEST_VERSION, not iOS $VERSION_LATEST"
        exit 1
    fi
    restore_tethered_opts
elif [[ $tether_options == 3 ]]; then
    if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
        do_tethered_restore_a12_a13
    elif [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* ]]; then
        if [[ $VERSION == 8.* ]]; then
            echo "seprmvr64 restores to 8.x are not supported in surrealra1n"
            exit 1
        elif [[ $VERSION == 7.* ]]; then
            read -p "Would you like to jailbreak as part of this restore? (Y/n): " jailbreak_choice
            if [[ $jailbreak_choice == Y || $jailbreak_choice == y ]]; then
                echo "Jailbreak option enabled"
                JAILBREAK=1
            else
                echo "Jailbreak option disabled"
            fi
        fi
        do_tethered_seprmvr64_restore
    else
        do_tethered_restore
    fi
elif [[ $tether_options == 4 ]]; then
    reset_restore_vars
    restore_utils
else
    echo "Invalid option. Exiting."
    exit 0
fi

}

restore_a7_to_1033(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "No IPSW selected. Aborting."
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW does not exist: $IPSW_PATH"
    exit 1
fi
dfu_helper
pwn_device
download_1033_ota_sep
rm -rf "shsh"
mkdir -p shsh
sudo ./bin/tsschecker -d $IDENTIFIER -i 10.3.3 -e $ECID -o -m tmp/BuildManifest-SEP.plist -s --save-path shsh
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "No SHSH file found in the shsh folder. Aborting"
    exit 1
fi
det_rsep_flag
prepatch_ibssibec_fr
while true; do
    set +e
    sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
        ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
        --sep $sep_path --sep-manifest $manifest_path \
        --custom-latest $LATEST_VERSION \
        $updatebb_flag $rsep_flag $IPSW_PATH
    EXIT_CODE=$?
    set -e
    if [[ $EXIT_CODE -eq 139 ]]; then
        echo "futurerestore segfaulted (exit 139), retrying..."
        sleep 2
    else
        break
    fi
done
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Restore has completed! Read above if there are any errors"
    exit 0
else
    echo "futurerestore failed with exit code $EXIT_CODE"
    exit 1
fi


}

restore_a7_options(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]]; then
    clear
else
    restore_utils
    return
fi
 
echo "$INFO_TEXT"
echo "This OTA restore will use $LATEST_VERSION baseband"
echo ""
echo "Options:"
echo ""
echo "1. Select 10.3.3 IPSW"
echo "2. Start Restore"
echo "3. Back"
read -p "Please input an option (1-3): " restore_a7_options_choice
if [[ $restore_a7_options_choice == 1 ]]; then
    IPSW_PATH=$(pick_file "Select an IPSW file")
    if [[ -z "$IPSW_PATH" ]]; then
        echo "No IPSW selected. Aborting."
        exit 1
    fi
    rm -rf work/BuildManifest.plist
    unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
    BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
    if [[ $VERSION == 10.3.3 ]] && [[ $BUILD == 14G60 ]]; then
        restore_a7_options
    else
        echo "IPSW is invalid"
        sleep 2
        reset_restore_vars
        restore_a7_options
    fi
elif [[ $restore_a7_options_choice == 2 ]]; then
    restore_a7_to_1033
elif [[ $restore_a7_options_choice == 3 ]]; then
    reset_restore_vars
    restore_utils
fi

}

restore_utils(){

if [[ $IDENTIFIER == NONE ]]; then
    main_menu
    return
fi

if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    echo "A12/A13 device support is entirely experimental."
    echo "Expect to have issues or bugs."
    read -p "Press enter to continue"
fi

clear 
echo "$INFO_TEXT"
echo ""
echo "Options:"
echo ""
echo "1. Restore (with SHSH blobs)"
echo "2. Restore (Tethered)"
echo "3. Restore to 10.3.3 untethered (some A7 devices only)"
echo "4. Just Boot"
echo "5. Back"
read -p "Please input an option (1-5): " restore_options
if [[ $restore_options == 1 ]]; then
    restore_untethered_opts
elif [[ $restore_options == 2 ]]; then
    restore_tethered_opts
elif [[ $restore_options == 3 ]]; then
    restore_a7_options
elif [[ $restore_options == 4 ]]; then
    just_boot
elif [[ $restore_options == 5 ]]; then
    main_menu
else
    echo "Invalid option. Exiting."
    exit 1
fi

}

fix_ios164_tool_permissions(){
    local tool
    for tool in "$@"; do
        [[ -e "$tool" ]] || {
            echo "Missing required iOS 16.4 tool: $tool"
            exit 2
        }
        if [[ ! -x "$tool" ]]; then
            chmod u+x "$tool" 2>/dev/null || {
                echo "Cannot make iOS 16.4 tool executable: $tool"
                exit 2
            }
        fi
        xattr -d com.apple.quarantine "$tool" 2>/dev/null || true
    done
}

verify_ios164_host_tools(){
    local tool tool_info

    [[ "$(uname -m)" == "x86_64" ]] || return 0
    command -v file >/dev/null 2>&1 || return 0
    for tool in "$@"; do
        # Skip missing optional tools (caller decides).
        [[ -e "$tool" ]] || continue
        tool_info=$(file -b "$tool" 2>/dev/null || true)
        # Linux `file` prints "x86-64"; macOS prints "x86_64".
        [[ "$tool_info" == *x86_64* || "$tool_info" == *x86-64* ]] || {
            echo "iOS 16.4 helper is not Intel-compatible: $tool"
            echo "  file: $tool_info"
            echo "Use a clean source checkout so the Intel bootstrap can rebuild its generated tools."
            return 1
        }
    done
}

# tools/img4-ios164 is a macOS Mach-O helper. On Linux use the ELF bin/img4 from Semaphorin.
select_ios164_img4(){
    if [[ "$(uname -s)" == "Darwin" ]]; then
        IOS164_IMG4="$SCRIPT_DIR/tools/img4-ios164"
        [[ -x "$IOS164_IMG4" ]] || {
            echo "FATAL: missing macOS iOS 16.4 img4 helper: $IOS164_IMG4"
            return 1
        }
    else
        IOS164_IMG4="$SCRIPT_DIR/bin/img4"
        [[ -x "$IOS164_IMG4" ]] || {
            echo "FATAL: missing Linux img4 helper: $IOS164_IMG4"
            echo "Run surrealra1n once so Linux binaries are downloaded into bin/."
            return 1
        }
        # Refuse to try the Mach-O bundle on Linux (fails with "cannot execute binary file").
        if file -b "$IOS164_IMG4" 2>/dev/null | grep -qi 'Mach-O'; then
            echo "FATAL: bin/img4 is a macOS binary on a Linux host."
            return 1
        fi
        echo "Linux: using $IOS164_IMG4 for iOS 16.4 img4 work (tools/img4-ios164 is macOS-only)."
    fi
    return 0
}

prepare_ios164_build_inputs(){
    local target_ipsw="$1"
    local base_ipsw="$2"
    local python_bin="${LITER8_PYTHON:-python3}"
    local target_values base_values
    local target_version target_build base_version base_build
    local img4_probe img4_output
    local -a ios164_tools=()

    if [[ "$(uname -s)" == "Darwin" ]]; then
        command -v hdiutil >/dev/null 2>&1 || {
            echo "iOS 16.4 beta builds require hdiutil on macOS."
            exit 2
        }
    else
        # Linux experimental: ramdisk patching uses linux-apfs-rw (see bin/patch_ios164_ramdisk.sh).
        echo "Linux: experimental iOS 16.4 path (APFS ramdisk via linux-apfs-rw)."
    fi
    [[ -f "$target_ipsw" ]] || { echo "Missing target IPSW: $target_ipsw"; exit 2; }
    [[ -f "$base_ipsw" ]] || { echo "Missing base IPSW: $base_ipsw"; exit 2; }
    case "$IDENTIFIER" in
        iPhone11,2|iPhone11,6|iPhone11,8|iPhone12,1|iPhone12,3|iPhone12,5|iPhone12,8) ;;
        *)
            echo "iOS 16.4 build supports A12/A13 iPhones only; detected: $IDENTIFIER"
            exit 2
            ;;
    esac

    select_ios164_img4 || exit 2

    ios164_tools=(
        "$IOS164_IMG4"
        "$SCRIPT_DIR/bin/iBootPatch"
        "$SCRIPT_DIR/bin/iBootpatch2"
        "$SCRIPT_DIR/bin/Kernel64Patcher3"
        "$SCRIPT_DIR/bin/asr64_patcher"
        "$SCRIPT_DIR/bin/libimg4_patcher"
        "$SCRIPT_DIR/bin/ldid"
        "$SCRIPT_DIR/bin/trustcache"
        "$SCRIPT_DIR/bin/kerneldiff"
        "$SCRIPT_DIR/bin/img4"
        "$SCRIPT_DIR/bin/patch_ios164_kernel.py"
        "$SCRIPT_DIR/bin/patch_ios164_ramdisk.sh"
        "$SCRIPT_DIR/bin/patch_ios164_restored_external.py"
    )
    # macOS also keeps the dedicated iOS 16 img4 bundle for Intel rebuild checks.
    if [[ "$(uname -s)" == "Darwin" ]]; then
        ios164_tools+=("$SCRIPT_DIR/tools/img4-ios164")
    fi

    fix_ios164_tool_permissions "${ios164_tools[@]}"
    verify_ios164_host_tools "${ios164_tools[@]}" || exit 2
    [[ -f "$SCRIPT_DIR/tools/kernel_patchfinder.py" ]] || {
        echo "Missing required iOS 16.4 patchfinder: $SCRIPT_DIR/tools/kernel_patchfinder.py"
        exit 2
    }
    [[ -f "$SCRIPT_DIR/bin/inspect_ios164_manifest.py" ]] || {
        echo "Missing iOS 16.4 manifest checker."
        exit 2
    }
    [[ -f "$SCRIPT_DIR/requirements-ios164.txt" ]] || {
        echo "Missing iOS 16.4 Python requirements."
        exit 2
    }

    target_values=$("$python_bin" "$SCRIPT_DIR/bin/inspect_ios164_manifest.py" \
        "$target_ipsw" "$IDENTIFIER" "$BOARDID")
    base_values=$("$python_bin" "$SCRIPT_DIR/bin/inspect_ios164_manifest.py" \
        "$base_ipsw" "$IDENTIFIER" "$BOARDID")
    IFS=$'\t' read -r target_version target_build IOS164_TARGET_IDENTITY \
        IOS164_TARGET_KERNEL IOS164_TARGET_OS IOS164_TARGET_RAMDISK \
        IOS164_TARGET_TRUSTCACHE IOS164_TARGET_IBSS IOS164_TARGET_IBEC <<<"$target_values"
    IFS=$'\t' read -r base_version base_build IOS164_BASE_IDENTITY \
        IOS164_BASE_KERNEL IOS164_BASE_OS IOS164_BASE_RAMDISK \
        IOS164_BASE_TRUSTCACHE IOS164_BASE_IBSS IOS164_BASE_IBEC <<<"$base_values"

    [[ "$target_version" == "16.4" && "$target_build" == "20E247" ]] || {
        echo "Target must be iOS 16.4 (20E247), got $target_version ($target_build)"
        exit 2
    }
    [[ "$base_version" == "$LATEST_VERSION" && "$base_build" == "$IOS164_BASE_BUILD" ]] || {
        echo "Base IPSW must be iOS $LATEST_VERSION ($IOS164_BASE_BUILD) for $IDENTIFIER, got $base_version ($base_build)"
        exit 2
    }
    [[ -n "$IOS164_TARGET_IDENTITY" && -n "$IOS164_BASE_IDENTITY" && \
       -n "$IOS164_TARGET_KERNEL" && -n "$IOS164_BASE_KERNEL" && \
       -n "$IOS164_TARGET_OS" && -n "$IOS164_BASE_OS" && \
       -n "$IOS164_TARGET_RAMDISK" && -n "$IOS164_BASE_RAMDISK" && \
       -n "$IOS164_TARGET_TRUSTCACHE" && -n "$IOS164_BASE_TRUSTCACHE" && \
       -n "$IOS164_TARGET_IBSS" && -n "$IOS164_BASE_IBSS" && \
       -n "$IOS164_TARGET_IBEC" && -n "$IOS164_BASE_IBEC" ]] || {
        echo "Could not resolve the selected iOS 16.4 manifest identity."
        exit 2
    }
    local ibss_key expected_ibss_path expected_ibec_path
    expected_ibss_path="Firmware/dfu/$IBSS"
    expected_ibec_path="Firmware/dfu/$IBEC"
    [[ "$IOS164_TARGET_IBSS" == "$expected_ibss_path" && "$IOS164_BASE_IBSS" == "$expected_ibss_path" && \
       "$IOS164_TARGET_IBEC" == "$expected_ibec_path" && "$IOS164_BASE_IBEC" == "$expected_ibec_path" ]] || {
        echo "The selected IPSW does not match the expected iBSS/iBEC path for $IDENTIFIER."
        exit 2
    }
    ibss_key=$(grep '^ibss-16.4:' "$KEY_FILE" | cut -d':' -f2 | xargs)
    [[ "$ibss_key" =~ ^[0-9A-Fa-f]{96}$ ]] || {
        echo "Missing iBSS 16.4 key in $KEY_FILE"
        exit 2
    }

    img4_probe=$(mktemp /tmp/surreal-ios164-kernel.XXXXXX)
    img4_output=$(mktemp /tmp/surreal-ios164-kernel-output.XXXXXX)
    unzip -p "$target_ipsw" "$IOS164_TARGET_KERNEL" >"$img4_probe" || {
        rm -f "$img4_probe" "$img4_output"
        echo "Could not extract $IOS164_TARGET_KERNEL from the target IPSW"
        exit 2
    }
    if ! "$IOS164_IMG4" -i "$img4_probe" -o "$img4_output" >/dev/null 2>&1 || [[ ! -s "$img4_output" ]]; then
        rm -f "$img4_probe" "$img4_output"
        echo "The iOS 16.4 img4 tool could not extract the target kernel."
        echo "  tool: $IOS164_IMG4"
        echo "  file: $(file -b "$IOS164_IMG4" 2>/dev/null || echo unknown)"
        if [[ "$(uname -s)" != "Darwin" ]]; then
            echo "  On Linux, bin/img4 must be the ELF helper (not tools/img4-ios164, which is macOS-only)."
        fi
        exit 2
    fi
    rm -f "$img4_probe" "$img4_output"

    if ! "$python_bin" -c 'import capstone' 2>/dev/null; then
        echo "Installing the iOS 16.4 patchfinder dependency (capstone)..."
        "$python_bin" -m pip install -q -r requirements-ios164.txt || {
            echo "Could not install capstone; run: $python_bin -m pip install -r requirements-ios164.txt"
            exit 2
        }
    fi

    [[ "$IOS164_TARGET_KERNEL" == "$KERNEL" ]] || {
        echo "Target kernel path for $IDENTIFIER changed: $IOS164_TARGET_KERNEL"
        exit 2
    }
    IOS164_TARGET_VERSION="$target_version"
    IOS164_TARGET_BUILD="$target_build"
    IOS164_BASE_VERSION="$base_version"
    echo "Validated $IDENTIFIER target identity $IOS164_TARGET_IDENTITY and base identity $IOS164_BASE_IDENTITY."
}

ios164_build(){

    # This command only builds local artifacts.
    local target_arg base_arg
    if [[ $# -eq 4 && "$2" == iPhone* ]]; then
        target_arg="$3"
        base_arg="$4"
    elif [[ $# -eq 3 ]]; then
        target_arg="$2"
        base_arg="$3"
    else
        echo "Usage: $0 ios164-build [iPhone12,3] <16.4-target.ipsw> <current-base.ipsw>"
        exit 2
    fi

    local target_ipsw base_ipsw
    resolve_ipsw() {
        local input="$1" output
        if [[ "$input" == http://* || "$input" == https://* ]]; then
            mkdir -p ipsw
            output="ipsw/${input##*/}"
            output="${output%%\?*}"
            if [[ ! -s "$output" ]]; then
                echo "Downloading IPSW to $output" >&2
                curl --fail --location --continue-at - --output "$output" "$input"
            fi
            printf '%s\n' "$output"
        else
            printf '%s\n' "$input"
        fi
    }
    target_ipsw=$(resolve_ipsw "$target_arg")
    base_ipsw=$(resolve_ipsw "$base_arg")
    [[ -f "$target_ipsw" ]] || { echo "Missing target IPSW: $target_ipsw"; exit 2; }
    [[ -f "$base_ipsw" ]] || { echo "Missing base IPSW: $base_ipsw"; exit 2; }

    case "$IDENTIFIER" in
        iPhone11,2|iPhone11,6|iPhone11,8|iPhone12,1|iPhone12,3|iPhone12,5|iPhone12,8) ;;
        *)
            echo "iOS 16.4 build supports A12/A13 iPhones only; detected: $IDENTIFIER"
            exit 2
            ;;
    esac

    prepare_ios164_build_inputs "$target_ipsw" "$base_ipsw"

    echo "Building experimental iOS 16.4 bundle for $IDENTIFIER ($BOARDID)"
    echo "Baseband mode: none (no modem update will be requested by the restore phase)"
    echo "iOS 16 img4: $IOS164_IMG4"
    local scratch
    for scratch in tmp1 tmp2 work; do
        if [[ -e "$scratch" ]]; then
            echo "Refusing to reuse existing build scratch directory: $scratch"
            echo "Move it aside, then rerun this build command."
            exit 2
        fi
    done
    IPSW_PATH="$target_ipsw"
    IPSW_PATH_LATEST="$base_ipsw"
    VERSION="16.4"
    BUILD="20E247"
    VERSION_LATEST="$IOS164_BASE_VERSION"
    updatebb_flag="--no-baseband"
    IPHONE12_3_BB_MODE="workaround"
    IPHONE12_3_BB_ENGINE="ios164-no-baseband"
    restoredir="restorefiles/$IDENTIFIER/$VERSION"

    if [[ -e "$restoredir" ]]; then
        local previous_restoredir="${restoredir}.pre-ios164-build-$(date +%Y%m%d-%H%M%S)"
        mv "$restoredir" "$previous_restoredir"
        echo "Preserved existing artifact directory as $previous_restoredir"
    fi
    make_custom_ipsw_a12_ios14

    [[ -s "boot/$IDENTIFIER/$VERSION/iBSS.patch" ]] || {
        echo "Build failed: missing versioned restore iBSS"
        exit 1
    }
    [[ -s "$restoredir/custom.ipsw" ]] || {
        echo "Build failed: missing custom IPSW"
        exit 1
    }
    for f in ramdisk.im4p kernel.im4p ibss.patched.bin ibec.patched.bin; do
        [[ -s "$restoredir/$f" ]] || {
            echo "Build failed: missing Odysseus artifact $restoredir/$f"
            exit 1
        }
    done
    echo "Build complete: boot/$IDENTIFIER/$VERSION/iBSS.patch"
    echo "Build complete: $restoredir/custom.ipsw"
    echo "Build complete: $restoredir/ramdisk.im4p + kernel.im4p + patched iBSS/iBEC"
    echo "No device state was changed. Use the normal restore flow only after reviewing the generated artifacts."
    echo "Note: existing hybrid 26.x custom.ipsw archives are invalid for this path and will be auto-rebuilt."
}

main_menu(){

clear
echo "$INFO_TEXT"
echo ""
echo "Options:"
echo ""
echo "1. Downgrade Options"
echo "2. Misc Utilities"
echo "3. Switch to main branch"
echo "4. Exit"
read -p "Please input an option (1-4): " option
if [[ $option == 1 ]]; then
    restore_utils
elif [[ $option == 2 ]]; then
    misc_utils
elif [[ $option == 3 ]]; then
    switch_to_main
elif [[ $option == 4 ]]; then
    echo "surrealra1n is exiting"
    exit 0
else
    echo "Invalid option. Exiting."
    exit 1
fi

}

if [[ "${1:-}" == "ios164-build" ]]; then
    ios164_build "$@"
    exit $?
fi

main_menu
