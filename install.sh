#!/bin/bash
# install.sh - Standable FBE Linux patch (RETIRED)
#
# Standable now ships official Linux support, so this repo no longer installs
# anything. The script is kept as the uninstaller for people who used an older
# version of the patch.
#
#   ./install.sh              explain the retirement (changes nothing)
#   ./install.sh --uninstall  remove everything the old patch added
#   ./install.sh --uninstall --dry-run
#                          print every command, change nothing
#   ./install.sh --uninstall --assume-yes
#                          do not refuse while SteamVR is running
#   --log FILE               write the transcript somewhere else
#
# Archived. Active work: https://github.com/meeyao/standable-wivrn-port

set -u
APP_ID=2370570
GAME_SUBDIR="Standable Full Body Estimation"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*";  _log ">>> $*"; }
warn() { printf '\033[1;33m ->\033[0m %s\n' "$*";  _log "WARN $*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; _log "ERROR $*"; exit 1; }
_log() { [ -n "${LOG_FILE:-}" ] && printf '%s\n' "$*" >> "$LOG_FILE"; }
# run - execute a mutating command, or print it verbatim under --dry-run.
run() {
    if [ -n "$DRY_RUN" ]; then
        printf '\033[1;36m # \033[0m%s\n' "$*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------- flags --
UNINSTALL=""
ASSUME_YES=""
LOG_FILE=""
DRY_RUN=""
for a in "$@"; do
    case "$a" in
        --uninstall|uninstall|remove) UNINSTALL=1 ;;
        --assume-yes|-y) ASSUME_YES=1 ;;
        --dry-run|-n) DRY_RUN=1 ;;
        --log) LOG_FILE="PENDING" ;;
        --verbose|-v) set -x ;;
        *) [ "$LOG_FILE" = "PENDING" ] && LOG_FILE="$a" ;;
    esac
done
[ "$LOG_FILE" = "PENDING" ] && die "--log requires a file path"
LOG_FILE="${LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/standable/uninstall.log}"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
_log "=== standable uninstall log - $(date -Iseconds) ==="
_log "argv: $0 $*"

# ---------------------------------------------------------------- detection --
detect_steam_root() {
    for c in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steampipe"; do
        [ -d "$c/steamapps" ] && { STEAM_ROOT="$c"; return 0; }
    done
    return 1
}

detect_game_dir() {
    # default library, then every library in libraryfolders.vdf. A library only
    # counts if Steam's appmanifest for Standable is present there - an orphaned
    # leftover dir (e.g. after a move/update) with no manifest is NOT Standable.
    local libs=("$STEAM_ROOT")
    if [ -f "$STEAM_ROOT/steamapps/libraryfolders.vdf" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] && libs+=("$p")
        done < <(awk -F'"' '/"path"/{print $4}' "$STEAM_ROOT/steamapps/libraryfolders.vdf")
    fi
    for lib in "${libs[@]}"; do
        [ -f "$lib/steamapps/appmanifest_$APP_ID.acf" ] || continue
        [ -d "$lib/steamapps/common/$GAME_SUBDIR" ] || continue
        GAME_DIR="$lib/steamapps/common/$GAME_SUBDIR"; GAME_LIB="$lib"; return 0
    done
    return 1
}

pick_prefix() {
    # the Proton prefix lives next to Standable in its own Steam library
    local GIRO="${GAME_LIB:-$STEAM_ROOT}"
    COMPAT="$GIRO/steamapps/compatdata/$APP_ID"
    PFX="$COMPAT/pfx"
}

STEAM_ROOT=""
GAME_DIR=""
GAME_LIB=""
COMPAT=""
PFX=""
WIN64=""

if [ "$UNINSTALL" != "1" ]; then
    cat <<'EOF'
Standable now supports Linux officially, so this patch is retired.

Nothing needs to be installed. Install Standable from Steam and launch it
normally. The official build has a native SteamVR driver and runs the
Standable GUI through Proton.

To move to the official build, remove the old patch with:

  ./install.sh --uninstall

then run "Verify integrity of game files" for Standable in Steam
(Properties -> Installed Files).

I'm still working on the WiVRn port:
  https://github.com/meeyao/standable-wivrn-port
EOF
    exit 0
fi

# =============================================================== UNINSTALL ==
command -v python3 >/dev/null 2>&1 || \
    warn "python3 not found - the OpenVR path and registry cleanup will be skipped"
detect_steam_root || warn "Steam not found - cleaning user files only"
detect_game_dir || warn "Standable not found - cleaning user files only"
[ -n "$STEAM_ROOT" ] && pick_prefix
[ -n "$PFX" ] && WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"
# The beta ships driver.vrdrivermanifest at Standable's root. From that point the
# official build owns the driver, its OpenVR registration, the Proton vrclient
# copies and the Steam registry values, so leave those shared paths alone.
OFFICIAL=""
[ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/driver.vrdrivermanifest" ] && OFFICIAL=1

# Never pull a loaded driver out from under a running vrserver: deleting
# driver_standable.so mid-session crashes it. Refuse while it runs.
if pgrep -x vrserver >/dev/null 2>&1; then
    if [ -n "$DRY_RUN" ]; then
        warn "SteamVR is running - a real run would refuse until it quits"
    elif [ -z "$ASSUME_YES" ]; then
        die "SteamVR is running - quit it first so the loaded driver can unload, then re-run"
    else
        warn "SteamVR is running - removing its loaded driver will crash it"
    fi
fi

say "Removing patch artifacts…"
run rm -fv "$HOME/bin/standable-gui" "$HOME/bin/standable_launch_hook.sh" "$HOME/.local/bin/standable_launch_hook.sh" "$HOME/Desktop/standable-gui.desktop" "$HOME/Desktop/Standable GUI.desktop"
run rm -f "$HOME/.local/bin"/standable_launch_hook.sh.bak-* "$HOME/bin"/standable_launch_hook.sh.bak-*
run rm -fv "$HOME/.local/share/icons/standable.png"
run rm -rf "$HOME/.cache/standable-ignition"

# The dashboard-overlay helper from the internal build (if it ever landed in
# the Standable directory) - the standalone copy in ~/.local is left alone.
if [ -n "$GAME_DIR" ]; then
    run rm -fv "$GAME_DIR/bin/linux64/standable_overlay"
    run rm -f "$GAME_DIR/bin/linux64"/standable_overlay.bak-* \
        "$GAME_DIR/bin/linux64"/libopenvr_api.so.bak-*
fi

if [ -n "$PFX" ]; then
    run rm -fv "$PFX/drive_c/vr_bootstrap.exe" "$PFX/drive_c/regq.txt" "$PFX/drive_c/typetest.txt"
    # s: and the prefix vrclient copies are shared with Steam/Proton once the
    # official build is installed; only pre-beta installs needed them from us.
    [ -z "$OFFICIAL" ] && run rm -fv "$PFX/dosdevices/s:"
    run rm -fv "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"   # VRChat log link (auto-calibration)
    # Prefix shims: restore a pre-existing file from our .bak. Without a
    # backup, only delete the exact patch stub - never an unknown/newer file
    # that Steam may have installed there since.
    _shim_sha=7e4ecf516b21d5e933b98cb1a7dea2b15d310c0a049acf434e77af8b61cd8a65
    for _shim in vrpathreg.exe vrmonitor.exe; do
        _f="$WIN64/$_shim"
        _bak=$(ls -1t "$_f".bak-* 2>/dev/null | head -1)
        if [ -n "$_bak" ]; then
            run mv -f "$_bak" "$_f"
            [ -n "$DRY_RUN" ] || say "restored $_f from backup"
        elif [ -f "$_f" ]; then
            _have=$(sha256sum "$_f" 2>/dev/null | cut -d' ' -f1)
            if [ "$_have" = "$_shim_sha" ]; then
                run rm -fv "$_f"
            else
                warn "left $_f (not the patch's shim)"
            fi
        fi
    done
    unset _shim _shim_sha _f _bak _have
    # Pre-beta installs needed our vrclient copies; the official build now
    # deploys its own into this Proton-managed directory, so leave it.
    [ -z "$OFFICIAL" ] && run rm -fv "$PFX/drive_c/vrclient/bin"/vrclient*.dll*
fi

if [ -n "$GAME_DIR" ]; then
    # driver_standable.so: restore Standable's own file when we backed one up.
    # With no backup, keep it when it matches the official build manifest and
    # delete it only when it is something the patch installed.
    _lin="$GAME_DIR/bin/linux64"
    _drv="$_lin/driver_standable.so"
    _want=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next((f["sha256"] for f in d.get("files",[]) if f["file"]=="driver_standable.so"),""))' "$_lin/linux-build.json" 2>/dev/null)
    _have=$(sha256sum "$_drv" 2>/dev/null | cut -d' ' -f1)
    _drv_bak=$(ls -1t "$_drv".bak-* 2>/dev/null | head -1)
    # The beta's driver matches the manifest: keep it even when an old .bak
    # exists, or we would downgrade the official driver to the pre-beta one.
    if [ -n "$_want" ] && [ "$_want" = "$_have" ]; then
        [ -n "$DRY_RUN" ] || say "kept Standable's official driver_standable.so"
    elif [ -n "$_drv_bak" ]; then
        run mv -f "$_drv_bak" "$_drv"
        [ -n "$DRY_RUN" ] || say "restored Standable's original driver_standable.so"
    elif [ -f "$_drv" ]; then
        if [ -z "$_want" ]; then
            # No manifest hash to compare against (missing file or no
            # python3): never guess in the destructive direction.
            warn "could not verify driver_standable.so - leaving it in place; use Steam's Verify integrity to restore the official file"
        else
            run rm -fv "$_drv"
        fi
    fi
    # bin/win64/steam_api64.dll: official builds ship a stub; only restore a
    # file we replaced, never delete one that might belong to Standable.
    _sa="$GAME_DIR/bin/win64/steam_api64.dll"
    _sa_bak=$(ls -1t "$_sa".bak-* 2>/dev/null | head -1)
    [ -n "$_sa_bak" ] && run mv -f "$_sa_bak" "$_sa"

    # Everything else under bin/linux64 is ours (Standable's own files are
    # Standable.exe, openvr_api.dll, vrclient_x64.dll, libsteam_api.so,
    # libopenvr_api.so, linux-build.json and bin/win64/driver_standable.dll).
    run rm -fv "$_lin/ignition_server.exe" \
        "$_lin/ignition_bridge.dll" \
        "$_lin/launch_serverhelper.sh" \
        "$_lin/ignition.json" \
        "$_lin/wine_psvr2_hidraw.reg" \
        "$_lin/steam_api64.dll" \
        "$_lin/python3" \
        "$_lin/proton_resolve.sh" \
        "$_lin/sweep.sh" \
        "$_lin/win_vrpath.sh"
    run rm -f "$_lin"/driver_standable.so.bak-* \
        "$_lin"/ignition_server.exe.bak-* \
        "$_lin"/ignition_bridge.dll.bak-* \
        "$_lin"/launch_serverhelper.sh.bak-* \
        "$_lin"/ignition.json.bak-* \
        "$_lin"/wine_psvr2_hidraw.reg.bak-* \
        "$_lin"/steam_api64.dll.bak-* \
        "$GAME_DIR/bin/win64"/steam_api64.dll.bak-* \
        "$_lin"/python3.bak-* \
        "$_lin"/proton_resolve.sh.bak-* \
        "$_lin"/sweep.sh.bak-* \
        "$_lin"/win_vrpath.sh.bak-*
fi

# vrpath: on a pre-beta install, strip the patch's seed entries. After the
# official update Standable ships driver.vrdrivermanifest at its root and owns
# that same entry, so keep it (and the S:\ form the Proton GUI checks) and only
# drop a stale old bin/linux64 shim entry. If Standable isn't installed, leave
# the file alone entirely.
if [ -z "$GAME_DIR" ]; then
    warn "Standable not found - leaving the OpenVR driver paths alone"
elif [ -n "$DRY_RUN" ]; then
    printf '\033[1;36m # \033[0mpython3 removes only stale Standable shim entries from ~/.config/openvr/openvrpaths.vrpath (keeps the official driver registration)\n'
else
    python3 - "$GAME_DIR" <<'PYEOF' 2>/dev/null
import json, os, sys
p = os.path.expanduser('~/.config/openvr/openvrpaths.vrpath')
try:
    data = json.load(open(p))
except Exception:
    raise SystemExit(0)
ed = data.get('external_drivers') or []
game_dir = sys.argv[1] if len(sys.argv) > 1 else ''
official = bool(game_dir) and os.path.isfile(os.path.join(game_dir, 'driver.vrdrivermanifest'))

def old_shim(e):
    return 'Standable' in e and e.replace('\\', '/').rstrip('/').endswith('/bin/linux64')

if official:
    new_ed = [e for e in ed if not old_shim(e)]
    removed = [e for e in ed if old_shim(e)]
    if removed:
        print("  removed %d stale Standable shim entr%s" % (len(removed), 'y' if len(removed) == 1 else 'ies'))
    else:
        print("  kept the official Standable driver registration")
else:
    new_ed = [e for e in ed if 'Standable' not in e]
    if len(new_ed) != len(ed):
        print("  removed %d Standable seed entr%s" % (len(ed) - len(new_ed), 'y' if len(ed) - len(new_ed) == 1 else 'ies'))
if new_ed != ed:
    data['external_drivers'] = new_ed
    json.dump(data, open(p, 'w'), indent=2)
PYEOF
fi

# SteamPath registry value: only pre-beta installs needed it from us. Steam
# owns that value now; on an official install, leave it alone.
if [ -n "$PFX" ] && [ -z "$OFFICIAL" ]; then
    if [ -n "$DRY_RUN" ]; then
        printf '\033[1;36m # \033[0mpython3 removes the SteamPath value from the prefix user.reg\n'
    else
        python3 - "$PFX" <<'PYEOF' 2>/dev/null
import re, sys
p = sys.argv[1] + '/user.reg'
try:
    raw = open(p, 'rb').read()
except Exception:
    raise SystemExit(0)
lines = raw.split(b'\n')
out, insec, dropped = [], False, False
for ln in lines:
    if ln.startswith(b'['):
        insec = bool(re.match(br'\[Software\\\\Valve\\\\Steam\](\s+\d+)?$', ln.strip()))
        out.append(ln)
        continue
    if insec and re.match(br'"SteamPath"="C:\\\\Program Files \(x86\)\\\\Steam"$', ln.strip()):
        dropped = True
        continue
    out.append(ln)
if dropped:
    open(p, 'wb').write(b'\n'.join(out))
    print("  removed SteamPath from user.reg")
PYEOF
    fi
fi

# Restore the user's original SteamVR settings (backed up before our first
# boot-time modification), and drop the crash-timestamp trigger. Never restore
# that pre-beta backup once the official build is installed - it would undo
# SteamVR settings made since.
if [ -n "$STEAM_ROOT" ]; then
    if [ -z "$GAME_DIR" ]; then
        [ -n "$DRY_RUN" ] || say "Standable not found - left SteamVR settings alone"
    elif [ -z "$OFFICIAL" ] && [ -f "$STEAM_ROOT/config/steamvr.vrsettings.standable.bak" ]; then
        run mv -f "$STEAM_ROOT/config/steamvr.vrsettings.standable.bak" "$STEAM_ROOT/config/steamvr.vrsettings"
        [ -n "$DRY_RUN" ] || say "Restored your original steamvr.vrsettings"
    elif [ -n "$OFFICIAL" ]; then
        [ -n "$DRY_RUN" ] || say "Kept your current steamvr.vrsettings (official build)"
    else
        [ -n "$DRY_RUN" ] || say "No steamvr.vrsettings backup found - left your settings as-is"
    fi
    run rm -f "$STEAM_ROOT/config/vrserver_crash_timestamp.txt"
fi

if [ -n "$DRY_RUN" ]; then
    echo
    say "Dry run - nothing was changed."
    exit 0
fi

if [ -z "$GAME_DIR" ]; then
    say "Uninstall complete - user files removed. Standable wasn't found, so its files and OpenVR paths were left alone."
    echo
    say "When you install Standable from Steam, it will set up its own driver."
    exit 0
fi

say "Uninstall complete - patch artifacts removed; official driver and registration kept."
echo
say "Final step in Steam: Standable -> Properties -> Installed Files ->"
say "  \"Verify integrity of game files\""
say "That restores any official Linux file the patch replaced."
say "If anything still looks wrong, uninstall/reinstall Standable (~50 MB)."
exit 0
