#!/bin/bash
# install.sh — Standable Full Body Estimation Linux port installer
# Repo: https://github.com/.../standable-linux-port
#
#   ./install.sh              install / repair (idempotent)
#   ./install.sh --check      doctor: verify a running setup
#   ./install.sh --uninstall  remove everything this script added
#
# Works with any host-launchable Proton build. Tested on Arch Linux.

set -u
APP_ID=2370570
GAME_SUBDIR="Standable Full Body Estimation"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ->\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
bak()  { # bak <file> — timestamped backup before overwrite
    [ -f "$1" ] && cp -n "$1" "$1.bak-$STAMP" 2>/dev/null
}

# ---------------------------------------------------------------- detection --
detect_steam_root() {
    for c in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steampipe"; do
        [ -d "$c/steamapps" ] && { STEAM_ROOT="$c"; return 0; }
    done
    return 1
}

detect_game_dir() {
    # default library, then every library in libraryfolders.vdf
    local libs=("$STEAM_ROOT")
    if [ -f "$STEAM_ROOT/steamapps/libraryfolders.vdf" ]; then
        while IFS= read -r p; do libs+=("$p"); done < <(
            grep -oE '"path"\s+"[^"]+"' "$STEAM_ROOT/steamapps/libraryfolders.vdf" \
                | sed 's/.*"\t*//; s/"$//' | sed 's/\\\\/\//g')
    fi
    for lib in "${libs[@]}"; do
        [ -d "$lib/steamapps/common/$GAME_SUBDIR" ] || continue
        GAME_DIR="$lib/steamapps/common/$GAME_SUBDIR"; return 0
    done
    return 1
}

find_proton_builds() {
    # prints "label|path" candidates; host-launchable proton scripts only
    local d p
    for d in "$HOME/.local/share/Steam/compatibilitytools.d"/* \
             /usr/share/steam/compatibilitytools.d/* \
             "$STEAM_ROOT/steamapps/common/Proton -"*; do
        p="$d/proton"
        [ -x "$p" ] && [ -d "$d/files/lib/wine" ] && printf '%s|%s\n' "$(basename "$d")" "$p"
    done
}

pick_proton() {
    if [ -n "$PROTON_OVERRIDE" ] && [ "$PROTON_OVERRIDE" != "PENDING" ]; then
        [ -x "$PROTON_OVERRIDE" ] || die "--proton: not executable: $PROTON_OVERRIDE"
        PROTON="$PROTON_OVERRIDE"; return 0
    fi
    # Preserve the existing proton choice if the scripts already work.
    # Silently switching builds breaks gamedrive conventions and s: links.
    local existing=""
    for f in "$HOME/bin/standable-gui" "$GAME_DIR/bin/linux64/launch_serverhelper.sh"; do
        [ -f "$f" ] || continue
        existing=$(grep '^PROTON=' "$f" 2>/dev/null | head -1 | sed 's/^PROTON="//;s/"$//;s/^PROTON=//')
        [ -n "$existing" ] && [ -x "$existing" ] && { PROTON="$existing"; return 0; }
    done
    mapfile -t CANDS < <(find_proton_builds)
    [ ${#CANDS[@]} -gt 0 ] || die "no Proton builds found. Install one (Steam built-in Proton, Proton-GE, ...), or pass --proton /path/to/proton."
    # prefer Steam's own bundled Proton, else interactive pick, else first
    local c
    for c in "${CANDS[@]}"; do
        case "$c" in *"steamapps/common/Proton"*) PROTON="${c#*|}"; return 0;; esac
    done
    if [ -t 0 ] && [ ${#CANDS[@]} -gt 1 ]; then
        echo "Multiple Proton builds found:"
        select c in "${CANDS[@]}"; do [ -n "$c" ] && break; done
        PROTON="${c#*|}"; return 0
    fi
    PROTON="${CANDS[0]#*|}"
}

pick_prefix() {
    COMPAT="$STEAM_ROOT/steamapps/compatdata/$APP_ID"
    PFX="$COMPAT/pfx"
}

# ------------------------------------------------------------------- checks --
require() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

# ---------------------------------------------------------- --proton flag --
PROTON_OVERRIDE=""
ARGS=()
for a in "$@"; do
    if [ "$a" = "--proton" ]; then PROTON_OVERRIDE="PENDING"
    elif [ "$PROTON_OVERRIDE" = "PENDING" ]; then PROTON_OVERRIDE="$a"
    else ARGS+=("$a"); fi
done
set -- ${ARGS[@]+"${ARGS[@]}"}

# ================================================================== DOCTOR ==
if [ "${1:-}" = "--check" ]; then
    detect_steam_root || die "Steam root not found"
    pick_prefix
    fail=0
    ok(){ say "OK  $1"; }
    bad(){ warn "FAIL $1"; fail=1; }
    [ -f "$PFX/drive_c/vr_bootstrap.exe" ] && ok "vr_bootstrap.exe deployed" || bad "vr_bootstrap.exe missing"
    [ -f "$PFX/drive_c/vrclient/bin/vrclient_x64.dll" ] && ok "vrclient copy present" || bad "vrclient copy missing"
    VRPATH="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrpathreg.exe"
    [ -f "$VRPATH" ] && ok "vrpathreg stub present" || bad "vrpathreg stub missing"
    grep -aq '"SteamPath"' "$PFX/user.reg" 2>/dev/null && ok "SteamPath registry set" || bad "SteamPath registry missing"
    [ -L "$PFX/dosdevices/s:" ] && ok "s: dosdevice link alive" || bad "s: link missing (recreated on next launch)"
    grep -aq "Standable" "$HOME/.config/openvr/openvrpaths.vrpath" 2>/dev/null \
        && ok "seed entry in ~/.config/openvr/openvrpaths.vrpath" || bad "seed entry missing"
    [ -x "$HOME/bin/standable-gui" ] && ok "~/bin/standable-gui installed" || bad "GUI launcher missing"
    N=$(pgrep -xc wineserver | tail -1); N=${N:-0}
    if [ "$N" = 0 ]; then ok "no wineservers (nothing running)"
    elif [ "$N" = 1 ]; then ok "single wineserver (GUI+driver shared)"
    else bad "$N wineservers running, IPC will be split!"; fi
    LOG="$STEAM_ROOT/logs/vrserver.txt"
    if [ -f "$LOG" ]; then
        F=$(tail -n 300 "$LOG" | grep -ac "Failed to Load from\|Failed to send message" 2>/dev/null)
        L=$(stat -c %Y "$LOG"); NOW=$(date +%s)
        if [ $((NOW-L)) -lt 3600 ] && [ "${F:-0}" != 0 ]; then
            warn "recent driver failures in vrserver.txt ($F), check TROUBLESHOOTING.md"
        else
            ok "vrserver.txt clean of known failure patterns"
        fi
    fi
    exit $fail
fi

# =============================================================== UNINSTALL ==
if [ "${1:-}" = "--uninstall" ]; then
    detect_steam_root || die "Steam root not found"
    detect_game_dir || die "game not found"
    pick_prefix
    say "Removing port artifacts…"
    rm -fv "$HOME/bin/standable-gui" "$HOME/Desktop/standable-gui.desktop" "$HOME/Desktop/Standable GUI.desktop"
    rm -fv "$PFX/drive_c/vr_bootstrap.exe" "$PFX/drive_c/regq.txt" "$PFX/drive_c/typetest.txt"
    rm -fv "$PFX/dosdevices/s:"
    say "Restored files are next to the modified ones (*.bak-*). vrpath seeds and"
    say "the SteamPath registry key were left alone , see RESTORE.md to strip them."
    exit 0
fi

# ================================================================= INSTALL ==
for r in bash python3 tar; do require "$r"; done

say "Detecting environment…"
detect_steam_root || {
    [ -d "$HOME/.var/app/com.valvesoftware.Steam" ] \
        && die "Flatpak Steam detected but not supported, install Steam natively."
    die "Steam not found (~/.local/share/Steam)"
}
detect_game_dir   || die "game '$GAME_SUBDIR' not found in any Steam library"
pick_proton
pick_prefix
STEAMVR="$STEAM_ROOT/steamapps/common/SteamVR"
WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"

say "Steam root : $STEAM_ROOT"
say "Game       : $GAME_DIR"
say "Prefix     : $COMPAT (pfx: $PFX)"
say "Proton     : $PROTON"

[ -d "$STEAMVR" ] || die "SteamVR not installed at $STEAMVR, install it in Steam first."
[ -f "$GAME_DIR/bin/win64/driver_standable.dll" ] || die "unexpected game layout (driver dll missing)"
[ -f "$GAME_DIR/driver.vrdrivermanifest" ] || die "driver.vrdrivermanifest missing, game layout changed or incomplete install"
for v in libdriver_ignition.so ignition_server.exe ignition_bridge.dll; do
    [ -f "$REPO/vendor/$v" ] || die "vendor/$v missing, incomplete checkout?"
done

# -- prefix bootstrap --------------------------------------------------------
if [ ! -d "$PFX/drive_c/windows" ]; then
    say "Prefix missing, creating via Proton (one-time, ~30 s)…"
    mkdir -p "$PFX"
    STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
        timeout 300 "$PROTON" run cmd /c exit >/dev/null 2>&1 \
        || die "prefix creation failed, launch the game once in Steam, then re-run"
fi

# -- prefix binaries ---------------------------------------------------------
# PSVR2 Sense controller registry (Ignition) — imported by the shim each run
bak "$GAME_DIR/bin/linux64/wine_psvr2_hidraw.reg"
cp "$REPO/config/wine_psvr2_hidraw.reg" "$GAME_DIR/bin/linux64/"

say "Deploying prefix binaries…"
mkdir -p "$PFX/drive_c/vrclient/bin" "$WIN64"
bak "$PFX/drive_c/vr_bootstrap.exe";  cp "$REPO/build/vr_bootstrap.exe" "$PFX/drive_c/"
bak "$WIN64/vrpathreg.exe";           cp "$REPO/build/vrpathreg2.exe"   "$WIN64/vrpathreg.exe"
cp "$REPO/build/vrpathreg2.exe"       "$WIN64/vrmonitor.exe"           # existence-check only
PC="$PROTON"; PC="${PC%/proton}/files/lib/wine/x86_64-windows"
ls "$PC"/vrclient*.dll >/dev/null 2>&1 || die "vrclient dlls not found at $PC"
bak "$PFX/drive_c/vrclient/bin/vrclient_x64.dll"
cp "$PC"/vrclient*.dll "$PFX/drive_c/vrclient/bin/"

# -- registry ----------------------------------------------------------------
say "Setting SteamPath registry (HKCU\\Software\\Valve\\Steam)…"
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    timeout 120 "$PROTON" run reg add 'HKCU\Software\Valve\Steam' /v SteamPath \
    /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f >/dev/null 2>&1 \
    || warn "reg add failed (will retry on next shim run)"

# -- s: link -----------------------------------------------------------------
# Valve Proton maps s: to the Steam parent (S:\steamapps\common\...) via
# get_validated_steamapps_parent(). Other builds map s: to steamapps directly
# (S:\common\...). Detect which by checking for the parent wrapper.
PROTON_DIR_S="$(dirname "$PROTON")"
if grep -q 'get_validated_steamapps_parent' "$PROTON_DIR_S/proton" 2>/dev/null; then
    S_TARGET="$STEAM_ROOT"
else
    S_TARGET="$STEAM_ROOT/steamapps"
fi
ln -sfn "$S_TARGET" "$PFX/dosdevices/s:" && say "Created s: dosdevice link."

# -- seed merge --------------------------------------------------------------
say "Merging external_drivers into ~/.config/openvr/openvrpaths.vrpath…"
python3 - "$HOME" <<'PYEOF'
import json, os, sys
home = sys.argv[1]
zpath = os.path.join(home, '.local/share/Steam/steamapps/common',
                     'Standable Full Body Estimation')
upath = zpath
seed_path = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')
os.makedirs(os.path.dirname(seed_path), exist_ok=True)
try:
    data = json.load(open(seed_path))
except Exception:
    data = {"runtime": [], "version": 1}
ed = [e for e in data.get('external_drivers', [])
      if not ('Standable' in e and ('\\' in e or upath == e))]
if upath not in ed: ed.insert(0, upath)
data['external_drivers'] = ed
json.dump(data, open(seed_path, 'w'), indent=2)
print("  entries:", ", ".join(e[:40] for e in ed))
PYEOF

# -- scripts -----------------------------------------------------------------
say "Deploying Linux driver shim (Ignition)…"
bak "$GAME_DIR/bin/linux64/driver_standable.so"
rm -f "$GAME_DIR/bin/linux64/driver_standable.so"
cp "$REPO/vendor/libdriver_ignition.so" "$GAME_DIR/bin/linux64/driver_standable.so"
bak "$GAME_DIR/bin/linux64/ignition_server.exe"
cp "$REPO/vendor/ignition_server.exe" "$GAME_DIR/bin/linux64/"
bak "$GAME_DIR/bin/linux64/ignition_bridge.dll"
cp "$REPO/vendor/ignition_bridge.dll" "$GAME_DIR/bin/linux64/"

# glibc compat check: warn early if the .so won't load on this system
if command -v ldd >/dev/null 2>&1; then
    _bad=$(ldd "$GAME_DIR/bin/linux64/driver_standable.so" 2>&1 | grep "not found" || true)
    if [ -n "$_bad" ]; then
        warn "driver_standable.so may fail to load on this system:"
        echo "$_bad"
        say "Rebuild from source or swap in upstream release binaries (see BUILDING.md)"
    fi
fi

say "Installing launchers…"
gen() { # gen <template> <dest>
    sed -e "s|@GAME_DIR@|$GAME_DIR|g" -e "s|@COMPAT@|$COMPAT|g" -e "s|@PFX@|$PFX|g" \
        -e "s|@PROTON@|$PROTON|g"       -e "s|@STEAMVR@|$STEAMVR|g" \
        -e "s|@STEAM_ROOT@|$STEAM_ROOT|g" -e "s|@HOME@|$HOME|g" \
        "$REPO/templates/$1" > "$2"
}
mkdir -p "$HOME/bin"
bak "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
gen launch_serverhelper.sh.in "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
chmod +x "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
bak "$HOME/bin/standable-gui"
gen standable-gui.in "$HOME/bin/standable-gui"; chmod +x "$HOME/bin/standable-gui"
gen ignition.json.in "$GAME_DIR/bin/linux64/ignition.json"
gen standable-gui.desktop.in "$HOME/Desktop/Standable GUI.desktop"
chmod +x "$HOME/Desktop/Standable GUI.desktop" 2>/dev/null

say "Done."
cat <<EOF

  Next steps
    1. In Steam: ensure the game uses '$(basename "$PROTON" | sed 's/^proton-//')'
       as its compatibility tool (Settings → Compatibility), or just never
       launch it from Steam. (Proton in use: $(basename "$(dirname "$PROTON")"))
    2. Start SteamVR.
    3. Run ./standable gui (or use the "Standable GUI" desktop entry).

  Verify anytime with:  $REPO/install.sh --check
  Problems?             See TROUBLESHOOTING.md in the repo.
EOF
