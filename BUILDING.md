# Verifying or rebuilding the shipped binaries

`vendor/` contains prebuilt files:

| File | What it is | Origin |
|---|---|---|
| `libdriver_ignition.so` | Linux shim SteamVR loads as a native driver | Ignition (MIT) |
| `ignition_server.exe`   | Windows helper run under Proton by the shim | Ignition (MIT) |
| `ignition_bridge.dll`   | Wine IPC bridge between server and shim | Ignition (MIT) |
| `steam_api64.dll`       | Steamworks runtime the Windows driver loads (`SteamAPI_*`) | Valve Steamworks SDK redistributable |

Don't trust them? You have three options, in increasing order of effort.

## 1. Check the hashes

```sh
cd vendor && sha256sum -c SHA256SUMS
```

## 2. Use the official upstream release instead

Download the official `Ignition-Linux-Windows.zip` from the
[Ignition v1.0.0 release](https://github.com/BnuuySolutions/Ignition/releases/tag/v1.0.0)
and, for each file below, replace its counterpart in `vendor/`. The shim
(`libdriver_ignition.so`), server (`ignition_server.exe`) and IPC bridge
(`ignition_bridge.dll`) all come from that zip. Official release hashes:

```
26d2c1bc3eb59309f398335a22a5096543b6b7cee508767665ccde70faa33cf7  libdriver_ignition.so
6f96485e12811a57a3d9fce004954202018cf789064fd0c37c5a823323330db8  ignition_server.exe
```

(The shipped files were built from upstream commit `bbb7a70b`, one commit
after v1.0.0, so they differ only by that rebuild. The `ignition_bridge.dll`
shipped here matches the same build; swap in the release copy and re-run
`./install.sh` either way.)

## 3. Build from source

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

You'll need `cmake`, a C++ toolchain, `clang` with the Windows target for
the PE binaries, and `winebuild` (wine development tools). Copy
`build/Linux/lib/libdriver_ignition.so` and
`build/Windows/bin/ignition_server.exe` into `vendor/`.

After swapping either 2 or 3 in, re-run `./install.sh`.

## About `vendor/steam_api64.dll`

Standable's Windows driver (`driver_standable.dll`) links against the
Steamworks runtime and will **not load without `steam_api64.dll` on the DLL
search path**. Older releases of this installer shipped without it; missing it
made `ignition_server.exe` fail to load the driver, the IPC handshake never
completed, and SteamVR aborted with a ~21 s watchdog timeout (safe-mode crash
loop). This file fixes that.

It is Valve's official `steam_api64.dll` from the **Steamworks SDK 1.60**
(`redistributable_bin/win64`), verified byte-for-byte by SHA-256 against the
SDK 1.60 release:

```
1add7f151fa644870a735ae86e68d1f019f296130d8e7c0a7ed3ecc7482dccbc  steam_api64.dll   # = Steamworks SDK 1.60
```

Origin: the copy in `vendor/` was taken from the Steam game **TaskbarHero**
(`steamapps/common/TaskbarHero/TaskBarHero_Data/Plugins/x86_64/steam_api64.dll`),
which ships it as part of its Steamworks integration — a genuine Valve build
delivered via Valve's CDN. The same file is present, byte-identical, in every
Steamworks game and in the Steamworks SDK's `redistributable_bin/win64`.

The game's own `bin/win64/steam_api64.dll`, when present, is the **Steamworks
SDK 1.61** build — a newer but ABI-compatible release. Either works; the
vendored 1.60 copy is the default so installs are reproducible.

To verify or replace it, download the official Steamworks SDK from the
[Steamworks partner site](https://partner.steamgames.com/doc/sdk) and take
`redistributable_bin/win64/steam_api64.dll`; update `vendor/SHA256SUMS` after
swapping. Any SDK 1.60+ release exports the same functions the driver imports
(`SteamInternal_SteamAPI_Init`, `SteamInternal_ContextInit`,
`SteamInternal_FindOrCreateUserInterface`, `SteamAPI_GetHSteamUser`).
