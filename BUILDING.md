# Verifying or rebuilding the shipped binaries

`vendor/` contains prebuilt files:

| File | What it is | Origin |
|---|---|---|
| `libdriver_ignition.so` | Linux shim SteamVR loads as a native driver | Ignition (MIT) |
| `ignition_server.exe`   | Windows helper run under Proton by the shim | Ignition (MIT) |
| `ignition_bridge.dll`   | Wine IPC bridge between server and shim | Ignition (MIT) |
| `steam_api64.dll`       | Steamworks runtime the Windows driver loads | Valve Steamworks SDK redistributable |

## Check the hashes

```sh
cd vendor && sha256sum -c SHA256SUMS
```

## Use the official upstream release instead

Download `Ignition-Linux-Windows.zip` from the
[Ignition v1.0.0 release](https://github.com/BnuuySolutions/Ignition/releases/tag/v1.0.0)
and replace each file in `vendor/` with its counterpart. Official release
hashes:

```
26d2c1bc3eb59309f398335a22a5096543b6b7cee508767665ccde70faa33cf7  libdriver_ignition.so
6f96485e12811a57a3d9fce004954202018cf789064fd0c37c5a823323330db8  ignition_server.exe
```

The shipped files are a build of upstream `main` with a local patch applied
(`build/patches/ignition-rpc-timeout.patch`), so they differ from the release
zip. Run `./install.sh` after swapping.

## Build from source

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git apply /path/to/standable-linux-port/build/patches/ignition-rpc-timeout.patch
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

You need `cmake`, a C++ toolchain, `clang` with the Windows target for the PE
binaries, and `winebuild` (wine development tools). Copy
`build/Linux/lib/libdriver_ignition.so` and
`build/Windows/bin/ignition_server.exe` into `vendor/`, then run
`./install.sh`.

Or use the installer's own path: `./install.sh --build` clones, patches, and
cross-compiles Ignition, then deploys the result.

## About `vendor/steam_api64.dll`

Standable's Windows driver links against the Steamworks runtime and will not
load without `steam_api64.dll` on the DLL search path. Missing it made
`ignition_server.exe` fail to load the driver, the handshake never completed,
and SteamVR aborted with a ~21 s watchdog timeout.

It is Valve's `steam_api64.dll` from the **Steamworks SDK 1.60**
(`redistributable_bin/win64`), verified byte-for-byte:

```
1add7f151fa644870a735ae86e68d1f019f296130d8e7c0a7ed3ecc7482dccbc  steam_api64.dll
```

The copy in `vendor/` was taken from the Steam game TaskbarHero, which ships
it as part of its Steamworks integration. The same file appears, byte-identical,
in every Steamworks game and in the SDK's `redistributable_bin/win64`.

The game's own `bin/win64/steam_api64.dll`, when present, is the Steamworks
SDK 1.61 build — newer but ABI-compatible. Either works; the vendored 1.60
copy is the default for reproducibility.

To replace it, download the official Steamworks SDK from the
[Steamworks partner site](https://partner.steamgames.com/doc/sdk), take
`redistributable_bin/win64/steam_api64.dll`, and update `vendor/SHA256SUMS`.