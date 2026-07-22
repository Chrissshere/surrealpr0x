# surrealra1n 

A tethered downgrade tool for some A7/A8(X) devices, all A11 devices and A12/A13 iPhones.

## Experimental iOS 16.4 beta builder

Build a local iOS 16.4 bundle with:

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
- `<base.ipsw>` must be the iOS 26.5.2 (23F84) IPSW for that same identifier.
- The builder requires macOS.

The builder validates both IPSWs and resolves their matching erase identities
before building. It creates the local-boot iBSS payload and custom restore IPSW
without communicating with a connected phone. iPhone 11, 11 Pro, and 11 Pro Max
keep the futurerestore test route; iPhone SE (2nd generation) keeps its existing
idevicerestore test route. All device paths remain experimental and require
separate package and hardware validation.

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








