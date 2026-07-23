# surrealra1n 

A tethered downgrade tool for some A7/A8(X) devices, all A11 devices and A12/A13 iPhones.

## Experimental iOS 16.4 beta builder

Build a local iOS 16.4 Odysseus bundle with:

```bash
./surrealra1n.sh ios164-build <target-identifier> <target.ipsw> <base.ipsw>
```

Requirements:

- `<target-identifier>` must be one of:
  - `iPhone11,2` — iPhone XS
  - `iPhone11,6` — iPhone XS Max
  - `iPhone11,8` — iPhone XR
  - `iPhone12,1` — iPhone 11
  - `iPhone12,3` — iPhone 11 Pro
  - `iPhone12,5` — iPhone 11 Pro Max
  - `iPhone12,8` — iPhone SE (2nd generation)
- `<target.ipsw>` must be the iOS 16.4 (20E247) IPSW for that identifier.
- `<base.ipsw>` must be the iOS 26.5.2 (23F84) IPSW for that same identifier (carrier/SEP ticket source).
- **macOS:** Apple Silicon for the 16.4 restore handoff (usbliter8 futurerestore patches are arm64-only).
- **Linux:** experimental; uses stock futurerestore Build 329 and `linux-apfs-rw` for APFS ramdisk work. Load `linux-apfs-rw/apfs.ko` if needed.
- Cryptex1/SEP for the restore phase are seeded from the local base IPSW when possible (avoids flaky multi‑GB CDN downloads).
- If an archive includes helpers built on another Mac CPU, the builder rebuilds its iOS 16.4 helpers for the current host.

The builder validates both IPSWs and resolves their matching erase identities
before building. It produces a **target-based** custom IPSW (ProductVersion 16.4)
plus Odysseus sidecars (`ramdisk.im4p`, `kernel.im4p`, patched iBSS/iBEC). At
restore time, surrealra1n boots patched iBSS with liter8, then runs futurerestore
with `--use-pwndfu --no-ibss --skip-blob --rdsk --rkrn --custom-latest-buildid 23F84`.
Hybrid base (26.x) custom.ipsw archives from older betas are rejected and rebuilt
automatically.

Release zips: `surrealpr0x-*-macos.zip` and `surrealpr0x-*-linux.zip` on the
[releases](https://github.com/Chrissshere/surrealpr0x/releases) page.

The bundled kernel patchfinder is from usbliter8ra1n and is available under its
MIT license in [tools/LICENSE.usbliter8ra1n](tools/LICENSE.usbliter8ra1n).

For surrealra1n support, join the [surrealra1n](https://discord.gg/kDXVHhTQs2) Discord Server

# Compatible devices and versions:

View the [Supported Devices](https://github.com/pwnerblu/surrealra1n/wiki/Supported-Devices) section in the wiki for more information

# Usage:

Download the [latest beta release](https://github.com/Chrissshere/surrealpr0x/releases/latest) or clone it using git:
```
git clone -b ios164-beta https://github.com/Chrissshere/surrealpr0x
```
Extract the zip file and open a terminal window to the folder that contains surrealra1n, then launch it using the command: ```./surrealra1n.sh```.



# Thanks to:

libimobiledevice team, tihmstar, LukeeGD/LukeZGD, xerub, plooshi, etc! (for the tools it has to download)

Mineek - iPhone X restored patcher, used for ipx restores 14.3-15.6.1 (my fork of the patcher is used for seprmvr64 restores on A8+), openra1n, and seprmvr64

Nathan (verygenericname) - SSHRD_Script




