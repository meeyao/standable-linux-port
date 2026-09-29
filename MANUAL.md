# Standable FBE Linux Patch - Manual Install

This is the manual version of the installer.

You're copying the files into your Steam installation and Standable's Proton prefix yourself. No installer script is used.

> **Use the `testing/rc` branch.** `main` is stale.

## Before You Start

You need:

* Native Linux Steam
* SteamVR
* Standable Full Body Estimation (AppID `2370570`)
* A Proton build
* This repository

Get the repository:

```sh
git clone -b testing/rc https://github.com/meeyao/standable-linux-port.git
cd standable-linux-port
```

If you just want to install Standable, use the normal `README.md` instructions instead. This guide is mainly for people who want to know exactly what is being copied and changed.

---

# 1. Set Your Paths

These are the paths used by the rest of this guide.

Change `PROTON` if you're using a different Proton build.

```sh
STEAM_ROOT="$HOME/.local/share/Steam"
GAME="$STEAM_ROOT/steamapps/common/Standable Full Body Estimation"
COMPAT="$STEAM_ROOT/steamapps/compatdata/2370570"
PFX="$COMPAT/pfx"
PROTON="/usr/share/steam/compatibilitytools.d/proton-cachyos-slr/proton"
```

`PROTON` must point to the **same Proton build selected for Standable in Steam**.

You can check it in:

**Standable → Properties → Compatibility**

If the game and driver use different Proton builds, they cannot talk to each other.

---

# 2. Create the Proton Prefix

Steam normally creates this automatically.

If it doesn't exist yet:

```sh
mkdir -p "$PFX"

STEAM_COMPAT_DATA_PATH="$COMPAT" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
"$PROTON" run cmd /c exit
```

If that fails, launch Standable once from Steam and try again.

---

# 3. Copy the SteamVR Files

The driver needs a few SteamVR Windows files inside the Proton prefix.

```sh
WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"

mkdir -p "$PFX/drive_c/vrclient/bin" "$WIN64"

cp build/vr_bootstrap.exe "$PFX/drive_c/"

cp build/vrpathreg2.exe "$WIN64/vrpathreg.exe"
cp build/vrpathreg2.exe "$WIN64/vrmonitor.exe"

PC="$(dirname "$PROTON")/files/lib/wine/x86_64-windows"

cp "$PC"/vrclient*.dll "$PFX/drive_c/vrclient/bin/"
```

These files do different jobs:

| File               | Purpose                                        |
| ------------------ | ---------------------------------------------- |
| `vr_bootstrap.exe` | Patches the driver's Windows-side registration |
| `vrpathreg.exe`    | Shim used by Standable's existence checks      |
| `vrmonitor.exe`    | Shim used by Standable's existence checks      |
| `vrclient*.dll`    | SteamVR client DLLs from your Proton build     |

---

# 4. Copy the Standable Driver

Create the Linux driver directory:

```sh
mkdir -p "$GAME/bin/linux64"
```

Copy the driver files:

```sh
cp vendor/libdriver_ignition.so \
   "$GAME/bin/linux64/driver_standable.so"

cp vendor/ignition_server.exe \
   "$GAME/bin/linux64/"

cp vendor/ignition_bridge.dll \
   "$GAME/bin/linux64/"

cp config/wine_psvr2_hidraw.reg \
   "$GAME/bin/linux64/"
```

The important part is:

```text
bin/linux64/
├── driver_standable.so
├── ignition_server.exe
├── ignition_bridge.dll
└── wine_psvr2_hidraw.reg
```

`driver_standable.so` is the Linux driver SteamVR loads.

The other files are used by the Windows side of the driver.

`wine_psvr2_hidraw.reg` is imported at every driver boot for PSVR2 Sense controller support, so it must sit beside the launch scripts.

---

# 5. Copy `steam_api64.dll`

The Windows driver needs Steamworks' `steam_api64.dll`.

First check whether Standable already has one:

```sh
SRC="$GAME/bin/win64/steam_api64.dll"

[ -f "$SRC" ] || SRC="vendor/steam_api64.dll"
```

The fallback is the copy bundled with this repository (Valve's Steamworks SDK 1.60 redistributable).

Then copy it to both driver locations:

```sh
cp "$SRC" "$GAME/bin/linux64/"
cp "$SRC" "$GAME/bin/win64/"
```

You should now have:

```text
bin/linux64/steam_api64.dll
bin/win64/steam_api64.dll
```

Wine resolves the import from the DLL's own directory, so the `bin/win64/` copy is the one the Windows driver actually loads. Without it, the driver cannot load correctly.

---

# 6. Add the SteamPath Registry Entry

The Windows side of the driver needs Steam's path registered inside the Proton prefix.

Run:

```sh
STEAM_COMPAT_DATA_PATH="$COMPAT" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
"$PROTON" run reg add 'HKCU\Software\Valve\Steam' \
    /v SteamPath \
    /t REG_SZ \
    /d 'C:\Program Files (x86)\Steam' \
    /f
```

---

# 7. Create the `s:` Drive Link

The driver uses the `s:` drive to resolve Steam paths.

Different Proton builds use slightly different targets, so detect it from Proton:

```sh
if grep -q get_validated_steamapps_parent "$(dirname "$PROTON")/proton"; then
    S_TARGET="$STEAM_ROOT"
else
    S_TARGET="$STEAM_ROOT/steamapps"
fi

ln -sfn "$S_TARGET" "$PFX/dosdevices/s:"
```

You can check the result with:

```sh
ls -l "$PFX/dosdevices/s:"
```

If this points to the wrong place, Standable can show:

> SteamVR driver path not found

---

# 8. Register Standable with SteamVR

SteamVR gets its list of external drivers from:

```text
~/.config/openvr/openvrpaths.vrpath
```

The following adds both the normal Linux path and the Windows-style `S:\` path.

It keeps existing drivers.

```sh
python3 - "$GAME" "$S_TARGET" <<'PY'
import json
import os
import sys

game, s_target = sys.argv[1], sys.argv[2]

try:
    rel = os.path.relpath(game, s_target)
except Exception:
    rel = None

expected = None
if rel and not rel.startswith('..'):
    expected = 'S:\\' + rel.replace('/', '\\')

p = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')
os.makedirs(os.path.dirname(p), exist_ok=True)

try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    d = {"runtime": [], "version": 1}

external = d.get('external_drivers') or []

# Remove old Standable entries.
external = [
    e for e in external
    if not ('Standable' in e and (e == game or ('\\' in e and e != expected)))
]

if game not in external:
    external.insert(0, game)

if expected and expected not in external:
    external.insert(1 if game in external else 0, expected)

d['external_drivers'] = external

with open(p, 'w') as f:
    json.dump(d, f, indent=2)
PY
```

The Linux path is used by SteamVR itself.

The `S:\` entry is needed because Standable also checks the path from inside Wine.

---

# 9. Seed the Windows `openvrpaths.vrpath`

The game has its own Windows-side copy inside the Proton prefix.

Create it with SteamVR as the runtime:

```sh
python3 - "$PFX" <<'PY'
import json
import os
import sys

pfx = sys.argv[1]

p = os.path.join(
    pfx,
    'drive_c/users/steamuser/AppData/Local/openvr/openvrpaths.vrpath'
)

os.makedirs(os.path.dirname(p), exist_ok=True)

try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    d = {}

runtime = [
    r for r in d.get('runtime', [])
    if 'vrclient' not in r.lower()
]

steamvr = r'C:\Program Files (x86)\Steam\steamapps\common\SteamVR'

if steamvr not in runtime:
    runtime.insert(0, steamvr)

d['runtime'] = runtime
d['version'] = 1

with open(p, 'w') as f:
    json.dump(d, f, indent=3)
PY
```

This is separate from the Linux `openvrpaths.vrpath`.

---

# 10. Install the Launch Scripts

There are two main scripts involved:

### `launch_serverhelper.sh`

This is started by the Linux SteamVR driver.

It:

* Starts `ignition_server.exe` through Proton
* Keeps the server in the correct working directory
* Repairs the `s:` link
* Handles SteamVR Safe Mode flags
* Cleans up stale Proton/Wine processes
* Restarts the server if it dies

It also sources three shared helper files placed beside it: `proton_resolve.sh` (runtime Proton switching), `sweep.sh` (the stale wineserver sweep) and `win_vrpath.sh` (Windows-side driver path repair).

### `standable_launch_hook.sh`

This is the Steam launch option.

It starts Standable in host context so the normal desktop settings window can appear while SteamVR is running.

The scripts are templates, so their paths need to be filled in first.

Create the destination:

```sh
mkdir -p "$HOME/.local/bin"
```

Then substitute your paths:

```sh
vars=(
  -e "s|@GAME_DIR@|$GAME|g"
  -e "s|@COMPAT@|$COMPAT|g"
  -e "s|@PFX@|$PFX|g"
  -e "s|@PROTON@|$PROTON|g"
  -e "s|@STEAMVR@|$STEAM_ROOT/steamapps/common/SteamVR|g"
  -e "s|@STEAM_ROOT@|$STEAM_ROOT|g"
  -e "s|@S_ROOT@|$STEAM_ROOT|g"
  -e "s|@S_TARGET@|$S_TARGET|g"
  -e "s|@APP_ID@|2370570|g"
  -e "s|@HOME@|$HOME|g"
  -e "s|@VRCHAT_VRC_DIR@|$STEAM_ROOT/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat|g"
)
```

Generate the scripts:

```sh
sed "${vars[@]}" templates/launch_serverhelper.sh.in \
    > "$GAME/bin/linux64/launch_serverhelper.sh"

sed "${vars[@]}" templates/proton_resolve.sh.in \
    > "$GAME/bin/linux64/proton_resolve.sh"

sed "${vars[@]}" templates/sweep.sh.in \
    > "$GAME/bin/linux64/sweep.sh"

sed "${vars[@]}" templates/win_vrpath.sh.in \
    > "$GAME/bin/linux64/win_vrpath.sh"

sed "${vars[@]}" templates/proton_python.sh.in \
    > "$GAME/bin/linux64/python3"

sed "${vars[@]}" templates/ignition.json.in \
    > "$GAME/bin/linux64/ignition.json"

sed "${vars[@]}" templates/standable_launch_hook.sh.in \
    > "$HOME/.local/bin/standable_launch_hook.sh"
```

Make the required scripts executable:

```sh
chmod +x \
    "$GAME/bin/linux64/launch_serverhelper.sh" \
    "$GAME/bin/linux64/win_vrpath.sh" \
    "$GAME/bin/linux64/python3" \
    "$HOME/.local/bin/standable_launch_hook.sh"
```

The `python3` file is a shim: modern Proton launchers need Python 3.11 or newer, but SteamVR's runtime only ships 3.9, so the shim finds a working interpreter.

---

# 11. Add the Steam Launch Option

In Steam:

**Standable → Properties → General → Launch Options**

Add:

```text
bash ~/.local/bin/standable_launch_hook.sh %command%
```

That's what makes the desktop settings window work normally.

---

# 12. Optional: VRChat Auto-Calibration

Standable can read VRChat's IK debug log for auto-calibration.

VRChat has its own Proton prefix, so link its log directory into Standable's prefix:

```sh
mkdir -p "$PFX/drive_c/users/steamuser/AppData/LocalLow"

ln -sfn \
    "$STEAM_ROOT/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat" \
    "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
```

Skip this if you don't use VRChat auto-calibration.

---

# 13. Start It

That's the manual installation done.

1. Start SteamVR.
2. Check that the Standable skeleton appears.
3. Launch Standable from Steam.
4. The desktop settings window should appear.

If the driver doesn't appear in SteamVR, check the files first:

```sh
ls "$GAME/bin/linux64/"
```

Then check the SteamVR logs and the relevant files under:

```text
~/.local/state/standable/
```

---

# Uninstall

**Quit SteamVR before doing this.**

Deleting the driver out from under a running SteamVR crashes it.

Remove the files added by this guide:

```sh
rm -f \
  "$GAME/bin/linux64/driver_standable.so" \
  "$GAME/bin/linux64/ignition_server.exe" \
  "$GAME/bin/linux64/ignition_bridge.dll" \
  "$GAME/bin/linux64/launch_serverhelper.sh" \
  "$GAME/bin/linux64/ignition.json" \
  "$GAME/bin/linux64/wine_psvr2_hidraw.reg" \
  "$GAME/bin/linux64/steam_api64.dll" \
  "$GAME/bin/linux64/python3" \
  "$GAME/bin/linux64/proton_resolve.sh" \
  "$GAME/bin/linux64/sweep.sh" \
  "$GAME/bin/linux64/win_vrpath.sh" \
  "$GAME/bin/win64/steam_api64.dll" \
  "$HOME/.local/bin/standable_launch_hook.sh" \
  "$PFX/drive_c/vr_bootstrap.exe" \
  "$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrpathreg.exe" \
  "$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrmonitor.exe" \
  "$PFX/drive_c/vrclient/bin/vrclient.dll" \
  "$PFX/drive_c/vrclient/bin/vrclient_x64.dll"
```

Remove the `s:` link:

```sh
rm -f "$PFX/dosdevices/s:"
```

Remove the optional VRChat link if you created it:

```sh
rm -f "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
```

### Remove the Standable SteamVR entries

Open:

```text
~/.config/openvr/openvrpaths.vrpath
```

and remove the Standable entries from `external_drivers`.

You can also do it with:

```sh
python3 - <<'PY'
import json
import os

p = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')

with open(p) as f:
    d = json.load(f)

d['external_drivers'] = [
    e for e in d.get('external_drivers') or []
    if 'Standable' not in e
]

with open(p, 'w') as f:
    json.dump(d, f, indent=2)
PY
```

### Remove the SteamPath registry entry

Only do this if you added it specifically for this patch:

```sh
STEAM_COMPAT_DATA_PATH="$COMPAT" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
"$PROTON" run reg delete 'HKCU\Software\Valve\Steam' \
    /v SteamPath \
    /f
```

If the launch scripts created a backup of your SteamVR settings:

```text
steamvr.vrsettings.standable.bak
```

restore it if needed.

---

# What's Actually Being Installed?

For reference, these are all the files involved:

| Source                         | Destination                               | Purpose                          |
| ------------------------------ | ----------------------------------------- | -------------------------------- |
| `vendor/libdriver_ignition.so` | `$GAME/bin/linux64/driver_standable.so`   | Linux SteamVR driver             |
| `vendor/ignition_server.exe`   | `$GAME/bin/linux64/`                      | Windows driver server            |
| `vendor/ignition_bridge.dll`   | `$GAME/bin/linux64/`                      | Linux/Windows IPC bridge         |
| `vendor/steam_api64.dll`       | `$GAME/bin/linux64/` and `bin/win64/`     | Steamworks runtime               |
| `build/vr_bootstrap.exe`       | `$PFX/drive_c/`                           | Driver registration              |
| `build/vrpathreg2.exe`         | SteamVR `vrpathreg.exe` / `vrmonitor.exe` | Standable existence checks       |
| Proton `vrclient*.dll`         | `$PFX/drive_c/vrclient/bin/`              | SteamVR client DLLs              |
| `wine_psvr2_hidraw.reg`        | `$GAME/bin/linux64/`                      | PSVR2 Sense controller support   |
| launch scripts                 | `$GAME/bin/linux64/`                      | Driver startup and maintenance   |
| launch hook                    | `~/.local/bin/`                           | Starts Standable in host context |

The game's original files are not replaced.

---

# Building Ignition Yourself

The repository includes prebuilt Ignition binaries.

If you would rather build them yourself, use the exact upstream commit and patches included here.

You need:

* `cmake`
* A C++ toolchain
* `clang` with the Windows target
* `winebuild` / Wine development tools

Clone Ignition:

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git checkout 6bb3c8a
```

Apply the patches:

```sh
git apply /path/to/standable-linux-port/build/patches/ignition-rpc-timeout.patch
git apply /path/to/standable-linux-port/build/patches/ignition-server-registration-order.patch
```

Build:

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Copy the resulting files:

```sh
cp \
  build/Ignition-Linux-Windows/libdriver_ignition.so \
  build/Ignition-Linux-Windows/ignition_server.exe \
  build/Ignition-Linux-Windows/ignition_bridge.dll \
  /path/to/standable-linux-port/vendor/
```

Your locally built files should match the shipped code, but **their SHA256 hashes will not necessarily match** the files in `vendor/`.

The Windows executables contain a linker timestamp, so the builds are not byte-for-byte reproducible.

`steam_api64.dll` is not built here; it is Valve's Steamworks SDK redistributable, copied from the game if present or from `vendor/`.

---

# Checking the Shipped Binaries

The repository contains hashes for the exact binaries shipped in `vendor/`.

Run:

```sh
cd vendor
sha256sum -c SHA256SUMS
```

This verifies that the files match the copies shipped with this repository.

It does **not** prove that the binaries are safe or that they came from a particular person or build system.

If you want maximum trust, read the patches and build the binaries yourself.

The shipped Ignition binaries are based on upstream commit `6bb3c8a` plus the two patches below. Upstream's own release binaries will not match `SHA256SUMS`; these carry the patches.

---

# The Ignition Patches

### `ignition-server-registration-order.patch`

Fixes intermittent:

```text
VRInitError_Init_InterfaceNotFound
```

The server previously started listening for RPC requests before registering the server's tracked-device-provider function.

The driver can ask for that function immediately after starting the server. If the request arrives before registration, it gets a null response and the driver fails.

The patch registers the function first.

Affected file:

```text
projects/ignition_server/main.cpp
```

### `ignition-rpc-timeout.patch`

Adds timeouts to Ignition RPC calls.

Without these timeouts, an RPC call can wait up to the default 60 seconds. SteamVR's watchdog is much shorter, so a dead server can make SteamVR abort and enter Safe Mode.

The patch adds:

* `CallMethodTimeout` in `rpc_core.cpp` / `rpc_core.h`
* A timeout on the driver's initial handshake
* A timeout on `Cleanup`
* A timeout on `RunFrame`

The driver handshake is limited to 15 seconds.

`Cleanup` is limited to 4 seconds.

`RunFrame` is limited to 3 seconds.

Upstream later added similar timeout functionality for time-sync, but the additional driver and shutdown call sites above are still needed for the failure modes this patch handles.

---

# Regenerating a Patch

Start from the exact upstream commit:

```sh
git clone https://github.com/BnuuySolutions/Ignition.git
cd Ignition
git checkout 6bb3c8a
```

Make your changes, then:

```sh
git diff > /path/to/standable-linux-port/build/patches/my-change.patch
```

---

# Credits

* [Ignition](https://github.com/BnuuySolutions/Ignition) by Bnuuy Solutions, MIT
* Standable Full Body Estimation by the Standable developers

This project is unofficial and is not affiliated with or endorsed by Standable.
