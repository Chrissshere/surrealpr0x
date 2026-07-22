# surrealra1n 

A tethered downgrade tool for some A7/A8(X) devices, all A11 devices and A12/A13 iPhones.

## Experimental iOS 16.4 beta builder

The build-only iOS 16.4 path covers iPhone XS/XS Max/XR and iPhone 11, 11 Pro,
11 Pro Max, and SE (2nd generation). It creates the local-boot iBSS payload and
a custom restore IPSW without communicating with a connected phone.

The iOS 16.4 builder currently requires macOS. It validates that both IPSWs
contain the selected device and resolves the matching erase BuildIdentity from
each manifest before building. It also fixes executable bits for its local tools
without requiring sudo. The normal first-run setup can still request sudo for
its existing system dependency setup.

```bash
./surrealra1n.sh ios164-build \
  iPhone12,3 \
  'https://updates.cdn-apple.com/2023SpringFCS/fullrestores/032-68595/CAB5C1E0-E5A2-49A9-AB9F-936B976FF218/iPhone12,3,iPhone12,5_16.4_20E247_Restore.ipsw' \
  '/absolute/path/to/iPhone12,3,iPhone12,5_26.5.2_23F84_Restore.ipsw'
```

Use the exact IPSW for the selected product type. iPhone 11, 11 Pro, and 11 Pro
Max keep the futurerestore test route. iPhone SE (2nd generation) keeps its
existing idevicerestore test route. All device paths remain experimental and
require separate package and hardware validation.

The bundled kernel patchfinder is from usbliter8ra1n and is available under its
MIT license in [tools/LICENSE.usbliter8ra1n](tools/LICENSE.usbliter8ra1n).

For surrealra1n support, join the [surrealra1n](https://discord.gg/kDXVHhTQs2) Discord Server

# Compatible devices and versions:

View the [Supported Devices](https://github.com/pwnerblu/surrealra1n/wiki/Supported-Devices) section in the wiki for more information

# Usage:

Download surrealra1n [here](https://github.com/pwnerblu/surrealra1n/releases/latest) or clone it using git:
```
git clone -b development https://github.com/pwnerblu/surrealra1n
```
Extract the zip file and open a terminal window to the folder that contains surrealra1n, then launch it using the command: ```./surrealra1n.sh```.



# Thanks to:

libimobiledevice team, tihmstar, LukeeGD/LukeZGD, xerub, plooshi, etc! (for the tools it has to download)

Mineek - iPhone X restored patcher, used for ipx restores 14.3-15.6.1 (my fork of the patcher is used for seprmvr64 restores on A8+), openra1n, and seprmvr64

Nathan (verygenericname) - SSHRD_Script









