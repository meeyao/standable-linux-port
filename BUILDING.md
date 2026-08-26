# Verifying or rebuilding the shipped binaries

`vendor/` contains two prebuilt files from the
[Ignition](https://github.com/BnuuySolutions/Ignition) project (MIT):

| File | What it is |
|---|---|
| `libdriver_ignition.so` | Linux shim SteamVR loads as a native driver |
| `ignition_server.exe`   | Windows helper run under Proton by the shim |

Don't trust them? You have three options, in increasing order of effort.

## 1. Check the hashes

```sh
cd vendor && sha256sum -c SHA256SUMS
```

## 2. Use the official upstream release instead

Download the official `Ignition-Linux-Windows.zip` from the
[Ignition v1.0.0 release](https://github.com/BnuuySolutions/Ignition/releases/tag/v1.0.0)
and replace both files in `vendor/`. Their hashes:

```
26d2c1bc3eb59309f398335a22a5096543b6b7cee508767665ccde70faa33cf7  libdriver_ignition.so
6f96485e12811a57a3d9fce004954202018cf789064fd0c37c5a823323330db8  ignition_server.exe
```

(The shipped files were built from upstream commit `bbb7a70b`, one commit
after v1.0.0, so they differ only by that rebuild.)

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
