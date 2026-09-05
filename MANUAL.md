# Manual install (no installer)

This is the same thing `./install.sh` does, by hand. Run
`./install.sh --dry-run` first — it prints every command with your real
paths, so copy-paste from that rather than trusting this doc's placeholders.

Why bother doing it manually? The installer is just shell. If you want to
know what it's doing, or want to place the files yourself, everything below
is the actual sequence. **Why** each step exists is noted inline.

## The shipped binaries

`vendor/` contains prebuilt files:

| File | What it is | Origin |
|---|---|---|
| `libdriver_ignition.so` | Linux shim SteamVR loads as a native driver | Ignition (MIT) |
| `ignition_server.exe`   | Windows helper run under Proton by the shim | Ignition (MIT) |
| `ignition_bridge.dll`   | Wine IPC bridge between server and shim | Ignition (MIT) |
| `steam_api64.dll`       | Steamworks runtime the Windows driver loads | Valve Steamworks SDK redistributable |

They're built from upstream Ignition at commit `6bb3c8a` (Implement
SetCameraFrameBuffering) with the local patch
(`build/patches/ignition-rpc-timeout.patch`) applied, so they differ from the
official [v1.0.0 release](https://github.com/BnuuySolutions/Ignition/releases/tag/v1.0.0).

### Check the hashes

```sh
cd vendor && sha256sum -c SHA256SUMS
```

### Use the official upstream release instead

Download `Ignition-Linux-Windows.zip` from the v1.0.0 release and replace each
file in `vendor/`. Official release hashes:

```
26d2c1bc3eb59309f398335a22a5096543b6b7cee508767665ccde70faa33cf7  libdriver_ignition.so
6f96485e12811a57a3d9fce004954202018cf789064fd0c37c5a823323330db8  ignition_server.exe
```

Run the install steps below after swapping.

### Build from source

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git apply /path/to/standable-linux-port/build/patches/ignition-rpc-timeout.patch
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

You need `cmake`, a C++ toolchain, `clang` with the Windows target for the PE
binaries, and `winebuild` (wine development tools). Copy
`build/Ignition-Linux-Windows/libdriver_ignition.so`,
`build/Ignition-Linux-Windows/ignition_server.exe`, and
`build/Ignition-Linux-Windows/ignition_bridge.dll` into `vendor/`.

Or let the installer do it: `./install.sh --build` clones, applies the patch,
cross-compiles, and deploys.

### About `vendor/steam_api64.dll`

`driver_standable.dll` links against the Steamworks runtime and won't load
without `steam_api64.dll` on the DLL search path. Missing it made
`ignition_server.exe` fail to load the driver and SteamVR abort after a ~21 s
watchdog timeout. It's Valve's `steam_api64.dll` from the **Steamworks SDK
1.60** (`redistributable_bin/win64`), verified byte-for-byte:

```
1add7f151fa644870a735ae86e68d1f019f296130d8e7c0a7ed3ecc7482dccbc  steam_api64.dll
```

The copy in `vendor/` was taken from the Steam game TaskbarHero, which ships
it as part of its Steamworks integration. The same file appears byte-identical
in every Steamworks game and in the SDK's `redistributable_bin/win64`. The
game's own `bin/win64/steam_api64.dll`, when present, is the Steamworks SDK
1.61 build — newer but ABI-compatible; either works.

## 0. Figure out your paths

```sh
STEAM_ROOT="$HOME/.local/share/Steam"               # your Steam install
GAME="$STEAM_ROOT/steamapps/common/Standable Full Body Estimation"
COMPAT="$STEAM_ROOT/steamapps/compatdata/2370570"   # game's Proton prefix
PFX="$COMPAT/pfx"
PROTON=/usr/share/steam/compatibilitytools.d/proton-cachyos-slr/proton
```

`PROTON` is whichever build you want the driver to run under. It must match
what Steam uses for the game. Check what Steam forces:

```sh
# in Steam: right-click Standable → Properties → Compatibility
# the driver and game MUST run under the same Proton or their IPC breaks.
```

The `s:` drive convention differs per Proton build. Newer Valve builds map
`s:` to the Steam root, older forks to `steamapps`:

```sh
if grep -q get_validated_steamapps_parent "$(dirname "$PROTON")/proton"; then
    S_TARGET="$STEAM_ROOT"
else
    S_TARGET="$STEAM_ROOT/steamapps"
fi
```

## 1. Create the prefix (first time only)

Proton manages a Windows prefix per game. The driver and game share it.

```sh
mkdir -p "$PFX"
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    "$PROTON" run cmd /c exit
```

## 2. Copy prefix binaries

SteamVR's Windows-side bits the game/driver need inside Wine.

```sh
WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"
mkdir -p "$PFX/drive_c/vrclient/bin" "$WIN64"
cp build/vr_bootstrap.exe "$PFX/drive_c/"
cp build/vrpathreg2.exe "$WIN64/vrpathreg.exe"
cp build/vrpathreg2.exe "$WIN64/vrmonitor.exe"      # existence-check only
cp "$(dirname "$PROTON")/files/lib/wine/x86_64-windows"/vrclient*.dll \
   "$PFX/drive_c/vrclient/bin/"
```

Why `vr_bootstrap.exe`? It's an Ignition helper that patches the driver's
Windows-side registration at runtime. `vrpathreg`/`vrmonitor` are shims the
game's existence checks look for.

## 3. Deploy the driver shim into the game

SteamVR loads `driver_standable.so` as a native Linux driver. It's Ignition's
`libdriver_ignition.so` renamed. `ignition_server.exe` + `ignition_bridge.dll`
are its Windows half.

```sh
mkdir -p "$GAME/bin/linux64"
cp vendor/libdriver_ignition.so "$GAME/bin/linux64/driver_standable.so"
cp vendor/ignition_server.exe "$GAME/bin/linux64/"
cp vendor/ignition_bridge.dll "$GAME/bin/linux64/"
```

## 4. steam_api64.dll (Steamworks runtime)

`driver_standable.dll` (Windows side) imports `steam_api64.dll`. Without it
beside the DLL, the driver fails to load, the handshake never completes, and
SteamVR aborts after ~20 s into Safe Mode.

```sh
# use the game's own copy if it ships one, else the vendored one
SRC="$GAME/bin/win64/steam_api64.dll"
[ -f "$SRC" ] || SRC=vendor/steam_api64.dll
cp "$SRC" "$GAME/bin/linux64/"
cp "$SRC" "$GAME/bin/win64/"        # Wine resolves it from the DLL's own dir
```

## 5. SteamPath registry

The game/driver under Wine need Steam's path registered so they find the
runtime.

```sh
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    "$PROTON" run reg add 'HKCU\Software\Valve\Steam' /v SteamPath \
    /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f
```

## 6. s: drive link

SteamVR driver path conventions use `s:`. The link must match the Proton's
convention (see step 0). Broken here = "steamVR driver path not found" dialog.

```sh
ln -sfn "$S_TARGET" "$PFX/dosdevices/s:"
```

## 7. Register the driver with SteamVR

SteamVR reads `~/.config/openvr/openvrpaths.vrpath`. Add the game dir to
`external_drivers` (keep existing entries):

```sh
python3 - "$HOME" "$GAME" <<'PY'
import json, os, sys
home, game = sys.argv[1], sys.argv[2]
p = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except Exception:
    d = {"runtime": [], "version": 1}
ed = [e for e in (d.get('external_drivers') or [])
      if not ('Standable' in e and ('\\' in e or game == e))]
if game not in ed: ed.insert(0, game)
d['external_drivers'] = ed
json.dump(d, open(p, 'w'), indent=2)
PY
```

## 8. Seed the game's Windows-side openvrpaths

The game runs under Wine and reads a **separate** `openvrpaths.vrpath` inside
the prefix. Seed its runtime path:

```sh
python3 - "$PFX" <<'PY'
import json, os, sys
pfx = sys.argv[1]
p = os.path.join(pfx, 'drive_c/users/steamuser/AppData/Local/openvr/openvrpaths.vrpath')
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except Exception:
    d = {}
runtime = [r for r in d.get('runtime', []) if 'vrclient' not in r.lower()]
steamvr = r'C:\Program Files (x86)\Steam\steamapps\common\SteamVR'
if steamvr not in runtime: runtime.insert(0, steamvr)
d['runtime'] = runtime
d['version'] = 1
json.dump(d, open(p, 'w'), indent=3)
PY
```

## 9. Launch scripts

Two scripts run at boot to keep the install healthy:

- `launch_serverhelper.sh` — the driver calls it to start `ignition_server.exe`
  under Proton. Repairs the `s:` link, VRChat link, and SteamVR safe-mode flags
  each boot, and sweeps stale foreign-Proton wineservers (the #1 cause of the
  20 s Safe-Mode crash after a Proton switch).
- `standable_launch_hook.sh` — set as Steam Launch Options. Runs the game in
  host context so the desktop settings window renders while SteamVR runs.

Both are templates with `@PLACEHOLDERS@` substituted. Generating them by hand
is tedious and error-prone; this is the one step where the installer earns its
keep. If you insist:

```sh
# templates/launch_serverhelper.sh.in and templates/standable_launch_hook.sh.in
# substitute @GAME_DIR@ @COMPAT@ @PFX@ @PROTON@ @STEAM_ROOT@ @S_ROOT@ @S_TARGET@
# @APP_ID@ @HOME@ @VRCHAT_VRC_DIR@ with your paths, then chmod +x.
# Copy launch_serverhelper.sh + proton_resolve.sh + python3 shim into
# $GAME/bin/linux64/ and the hook into ~/bin/.
```

## 10. VRChat auto-calibration (optional)

Standable's auto-calibration reads VRChat's IK log. Link it into this prefix:

```sh
mkdir -p "$PFX/drive_c/users/steamuser/AppData/LocalLow"
ln -sfn "$STEAM_ROOT/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat" \
       "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
```

## Verify

```sh
./standable check
```

This runs the installer's doctor. It's the same checks the installer uses, so
if it's green, the manual install matches what the script would have done.