# Standable FBE Linux patch - manual install

Everything the installer does, done by hand. You're copying files into your
Steam install and a Wine prefix. No script involved.

You need: a Linux Steam install with the game (AppId 2370570) and SteamVR, a
Proton build, and this repo checked out for the binaries and templates.

```sh
git clone -b testing/rc https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
```

## What you're copying where

| File | Goes to | What it is |
|---|---|---|
| `vendor/libdriver_ignition.so` | `$GAME/bin/linux64/driver_standable.so` | Linux driver SteamVR loads |
| `vendor/ignition_server.exe` | `$GAME/bin/linux64/` | Windows half of the driver |
| `vendor/ignition_bridge.dll` | `$GAME/bin/linux64/` | IPC bridge |
| `vendor/steam_api64.dll` | `$GAME/bin/linux64/` and `$GAME/bin/win64/` | Steamworks runtime the driver DLL imports |
| `build/vr_bootstrap.exe` | `$PFX/drive_c/` | Driver registration patch |
| `build/vrpathreg2.exe` | prefix `SteamVR/bin/win64/vrpathreg.exe` and `vrmonitor.exe` | Existence-check shims |
| vrclient DLLs | `$PFX/drive_c/vrclient/bin/` | From the Proton's wine tree |

`vendor/` contents are Ignition (MIT) built from upstream commit `6bb3c8a`
with the local patch in `build/patches/ignition-rpc-timeout.patch`. The
`steam_api64.dll` is Valve's Steamworks SDK 1.60 redistributable. Verify
everything with the hashes in [`vendor/SHA256SUMS`](vendor/SHA256SUMS):

```sh
cd vendor && sha256sum -c SHA256SUMS
```

Hashes reference the shipped files only. The upstream release is
[Ignition v1.0.0](https://github.com/BnuuySolutions/Ignition/releases/tag/v1.0.0)
- its binaries won't match `vendor/SHA256SUMS` because the shipped ones carry
an extra patch.

### The patch

`build/patches/ignition-rpc-timeout.patch` adds timeouts to Ignition's RPC
calls. Without it, a call that never gets an answer (e.g. the game isn't
running) blocks forever, and SteamVR's watchdog aborts the driver into Safe
Mode after ~20 s. The patch touches 3 files:

- `rpc_core.cpp` / `rpc_core.h` - adds a timeout to the internal RPC call,
  default 60 s
- `rpc_server_tracked_device_provider.cpp` - uses short timeouts for the
  driver's `Cleanup`/`RunFrame` so a stalled game DLL can't wedge SteamVR's
  shutdown watchdog

To reproduce it:

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git checkout 6bb3c8a   # the commit the shipped binaries are built from
# apply the edits by hand (see build/patches/ignition-rpc-timeout.patch),
# then regenerate:
git diff > /path/to/standable-linux-port/build/patches/ignition-rpc-timeout.patch
```

### Build from source

If you don't trust the vendored binaries, rebuild the three Ignition files.
You need `cmake`, a C++ toolchain, `clang` with the Windows target for the
PE binaries, and `winebuild` (wine dev tools).

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git apply /path/to/standable-linux-port/build/patches/ignition-rpc-timeout.patch
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Copy the outputs into `vendor/` and use them in place of the shipped files:

```sh
cp build/Ignition-Linux-Windows/libdriver_ignition.so \
   build/Ignition-Linux-Windows/ignition_server.exe \
   build/Ignition-Linux-Windows/ignition_bridge.dll \
   /path/to/standable-linux-port/vendor/
```

`steam_api64.dll` is Valve's Steamworks SDK 1.60 redistributable - download it
from the [Steamworks SDK](https://partner.steamgames.com/doc/sdk) (or copy
from any Steamworks game) if you want your own copy.

## 0. Set your paths

```sh
STEAM_ROOT="$HOME/.local/share/Steam"
GAME="$STEAM_ROOT/steamapps/common/Standable Full Body Estimation"
COMPAT="$STEAM_ROOT/steamapps/compatdata/2370570"
PFX="$COMPAT/pfx"
PROTON="/usr/share/steam/compatibilitytools.d/proton-cachyos-slr/proton"
```

`PROTON` must be the same build Steam uses for the game (right-click the game
→ Properties → Compatibility). If they differ, the game and driver can't
talk.

## 1. Create the prefix (first time only)

Proton keeps a per-game Windows environment in `$COMPAT`. Make it:

```sh
mkdir -p "$PFX"
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    "$PROTON" run cmd /c exit
```

If this errors, launch the game once in Steam first so Steam creates the
prefix, then re-run.

## 2. Copy prefix binaries

SteamVR's Windows pieces the game and driver look for inside Wine:

```sh
WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"
mkdir -p "$PFX/drive_c/vrclient/bin" "$WIN64"
cp build/vr_bootstrap.exe "$PFX/drive_c/"
cp build/vrpathreg2.exe "$WIN64/vrpathreg.exe"
cp build/vrpathreg2.exe "$WIN64/vrmonitor.exe"
PC="$(dirname "$PROTON")/files/lib/wine/x86_64-windows"
cp "$PC"/vrclient*.dll "$PFX/drive_c/vrclient/bin/"
```

`vr_bootstrap.exe` patches the driver's Windows-side registration at boot.
`vrpathreg.exe` and `vrmonitor.exe` are shims the game's existence checks
expect.

## 3. Deploy the driver into the game folder

SteamVR loads `driver_standable.so` as a native Linux driver - it's Ignition's
shim renamed. Its Windows server and bridge sit beside it:

```sh
mkdir -p "$GAME/bin/linux64"
cp vendor/libdriver_ignition.so "$GAME/bin/linux64/driver_standable.so"
cp vendor/ignition_server.exe "$GAME/bin/linux64/"
cp vendor/ignition_bridge.dll "$GAME/bin/linux64/"
```

## 4. steam_api64.dll (Steamworks runtime)

The Windows driver (`driver_standable.dll`) imports `steam_api64.dll`. Wine
resolves the import from the DLL's own directory, so it must sit in
`bin/win64/`. Without it the driver fails to load and SteamVR aborts into
Safe Mode after ~20 s.

```sh
SRC="$GAME/bin/win64/steam_api64.dll"
[ -f "$SRC" ] || SRC=vendor/steam_api64.dll
cp "$SRC" "$GAME/bin/linux64/"
cp "$SRC" "$GAME/bin/win64/"
```

## 5. SteamPath registry key

The game/driver under Wine need Steam's path registered:

```sh
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    "$PROTON" run reg add 'HKCU\Software\Valve\Steam' /v SteamPath \
    /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f
```

## 6. `s:` drive link

The driver resolves game paths through the `s:` drive. Its target depends on
the Proton build - newer Valve builds point it at the Steam root, older forks
at `steamapps`:

```sh
if grep -q get_validated_steamapps_parent "$(dirname "$PROTON")/proton"; then
    S_TARGET="$STEAM_ROOT"
else
    S_TARGET="$STEAM_ROOT/steamapps"
fi
ln -sfn "$S_TARGET" "$PFX/dosdevices/s:"
```

Get this wrong and you get the "steamVR driver path not found" dialog on every
boot.

## 7. Register the driver with SteamVR

SteamVR reads `~/.config/openvr/openvrpaths.vrpath`. Add the game folder to
`external_drivers`, keeping anything already there:

```sh
python3 - "$GAME" <<'PY'
import json, os, sys
game = sys.argv[1]
p = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except Exception:
    d = {"runtime": [], "version": 1}
ed = [e for e in (d.get('external_drivers') or [])
      if not ('Standable' in e and ('\\' in e or game == e))]
if game not in ed:
    ed.insert(0, game)
d['external_drivers'] = ed
json.dump(d, open(p, 'w'), indent=2)
PY
```

## 8. Seed the game's Windows-side openvrpaths

The game runs under Wine and reads a different `openvrpaths.vrpath` inside the
prefix. Point its runtime at SteamVR:

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
if steamvr not in runtime:
    runtime.insert(0, steamvr)
d['runtime'] = runtime
d['version'] = 1
json.dump(d, open(p, 'w'), indent=3)
PY
```

## 9. Launch scripts

Two scripts keep the setup healthy at boot. Both are templates with
`@PLACEHOLDERS@`; substitute your paths, then install them.

`launch_serverhelper.sh` - the driver calls this to start `ignition_server.exe`
under Proton. It repairs the `s:` link, the VRChat link, SteamVR's safe-mode
flags, and kills stale foreign-Proton wineservers each boot. Goes in
`$GAME/bin/linux64/`.

`standable_launch_hook.sh` - set as the game's Steam Launch Options. Runs the
game in host context so the desktop settings window shows while SteamVR runs.
Goes in `~/.local/bin/` (older installs used `~/bin/`, still supported).

Generate each with sed (this is the substitution the installer does):

```sh
vars=(-e "s|@GAME_DIR@|$GAME|g"
      -e "s|@COMPAT@|$COMPAT|g" -e "s|@PFX@|$PFX|g"
      -e "s|@PROTON@|$PROTON|g" -e "s|@STEAMVR@|$STEAM_ROOT/steamapps/common/SteamVR|g"
      -e "s|@STEAM_ROOT@|$STEAM_ROOT|g" -e "s|@S_ROOT@|$STEAM_ROOT|g"
      -e "s|@S_TARGET@|$S_TARGET|g" -e "s|@APP_ID@|2370570|g"
      -e "s|@HOME@|$HOME|g"
      -e "s|@VRCHAT_VRC_DIR@|$STEAM_ROOT/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat|g")

sed "${vars[@]}" templates/launch_serverhelper.sh.in > "$GAME/bin/linux64/launch_serverhelper.sh"
sed "${vars[@]}" templates/proton_resolve.sh.in > "$GAME/bin/linux64/proton_resolve.sh"
sed "${vars[@]}" templates/win_vrpath.sh.in > "$GAME/bin/linux64/win_vrpath.sh"
sed "${vars[@]}" templates/proton_python.sh.in > "$GAME/bin/linux64/python3"
sed "${vars[@]}" templates/ignition.json.in > "$GAME/bin/linux64/ignition.json"
sed "${vars[@]}" templates/standable_launch_hook.sh.in > "$HOME/.local/bin/standable_launch_hook.sh"

chmod +x "$GAME/bin/linux64/launch_serverhelper.sh" \
        "$GAME/bin/linux64/win_vrpath.sh" \
        "$GAME/bin/linux64/python3" \
        "$HOME/.local/bin/standable_launch_hook.sh"
```

Then set the hook in Steam: right-click the game → Properties → Launch
Options → `bash ~/.local/bin/standable_launch_hook.sh %command%`.

## 10. VRChat auto-calibration (optional)

The driver reads VRChat's IK-debug log for auto-calibration. VRChat runs in
its own prefix, so link its log folder into this one:

```sh
mkdir -p "$PFX/drive_c/users/steamuser/AppData/LocalLow"
ln -sfn "$STEAM_ROOT/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat" \
       "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
```

Skip this if you don't use auto-calibration.

## Launch

1. Start SteamVR.
2. Launch the game from Steam.
3. Desktop settings window appears while SteamVR runs (via the hook).

## Uninstall (manual)

Delete what you added, in reverse:

```sh
rm -f "$GAME/bin/linux64/driver_standable.so" \
      "$GAME/bin/linux64/ignition_server.exe" \
      "$GAME/bin/linux64/ignition_bridge.dll" \
      "$GAME/bin/linux64/steam_api64.dll" \
      "$GAME/bin/win64/steam_api64.dll" \
      "$GAME/bin/linux64/python3" \
      "$GAME/bin/linux64/proton_resolve.sh" \
      "$GAME/bin/linux64/win_vrpath.sh" \
      "$HOME/.local/bin/standable_launch_hook.sh" \
      "$PFX/drive_c/vr_bootstrap.exe" \
      "$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrpathreg.exe" \
      "$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrmonitor.exe"
rm -f "$PFX/dosdevices/s:"
rm -f "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
```

Remove the game entry from `external_drivers` in
`~/.config/openvr/openvrpaths.vrpath` and delete the `SteamPath` value from
`HKCU\Software\Valve\Steam` if you added it (step 5). Your original
`steamvr.vrsettings` is kept at `steamvr.vrsettings.standable.bak` if the
scripts modified it - restore it with `mv` to undo.

## Why these files exist

- `driver_standable.so` is a native Linux driver so SteamVR loads Standable's
  Windows driver through the [Ignition](https://github.com/BnuuySolutions/Ignition)
  bridge - Windows-only SteamVR drivers can't run directly on Linux.
- `ignition_server.exe` runs under Proton and loads the game's real
  `driver_standable.dll`, talking to the Linux shim over shared memory. That
  link is what makes settings updates realtime.
- The launch hook keeps the game and driver on the same Proton and same
  prefix - a mismatch breaks their IPC, which is why switching Protons without
  redoing this causes crashes.