#!/bin/bash
# install.sh — Standable Full Body Estimation Linux port installer
# Repo: https://github.com/meeyao/standable-linux-port
#
#   ./install.sh              install / repair (idempotent)
#   ./install.sh --check      doctor: verify a running setup
#   ./install.sh --uninstall  remove everything this script added
#   ./install.sh --build-from-source  cross-compile Ignition shim from source
#                          (needs clang/lld/cmake/ninja + Windows SDK via xwin;
#                          falls back to prebuilt vendor/ copies without it)
#   Every run is logged to ~/.local/state/standable/install.log
#   (--log FILE writes there instead). --diagnose appends a full system
#   dump to the log for sharing when filing issues.
#
# Works with any host-launchable Proton build. Tested on Arch Linux.

set -u
APP_ID=2370570
GAME_SUBDIR="Standable Full Body Estimation"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*";  _log ">>> $*"; }
warn() { printf '\033[1;33m ->\033[0m %s\n' "$*";  _log "WARN $*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; _log "ERROR $*"; exit 1; }
_log() { [ -n "${LOG_FILE:-}" ] && printf '%s\n' "$*" >> "$LOG_FILE"; }
bak()  { # bak <file> — timestamped backup before overwrite
    [ -f "$1" ] && cp -n "$1" "$1.bak-$STAMP" 2>/dev/null
}

IGNITION_URL="${IGNITION_URL:-https://github.com/BnuuySolutions/Ignition.git}"
IGNITION_SRC="${IGNITION_SRC:-$HOME/.cache/standable-ignition}"
XWIN_VERSION="${XWIN_VERSION:-0.10.0}"
XWIN_URL="${XWIN_URL:-https://github.com/Jake-Shadle/xwin/releases/download/$XWIN_VERSION/xwin-$XWIN_VERSION-x86_64-unknown-linux-musl.tar.gz}"

# Ensure xwin is available (PATH = ~/.local/bin if a rootless copy exists). 
ensure_xwin() {
    export PATH="$HOME/.local/bin:$PATH"
    if command -v xwin >/dev/null 2>&1; then return 0; fi
    if [ ! -f "$HOME/.local/bin/xwin" ]; then
        say "Fetching prebuilt xwin v$XWIN_VERSION …"
        mkdir -p "$HOME/.local/bin"
        tmp=$(mktemp)
        if ! curl -fsSL "$XWIN_URL" -o "$tmp"; then
            rm -f "$tmp"; return 1
        fi
        tar -xzf "$tmp" -C "$HOME/.local/bin" --strip-components=1 || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
        chmod +x "$HOME/.local/bin/xwin"
    fi
    command -v xwin >/dev/null 2>&1
}

# Ensure the Windows SDK is splatted to ~/.xwin-cache/splat via xwin (one-time,
# ~1-2 GB download).
ensure_xwin_sdk() {
    [ -d "$HOME/.xwin-cache/splat" ] && return 0
    ensure_xwin || return 1
    say "Downloading Windows SDK via xwin (~1-2 GB, one-time)…"
    mkdir -p "$HOME/.xwin-cache"
    XWIN_ACCEPT_LICENSE=1 xwin splat --output "$HOME/.xwin-cache/splat" >>"${LOG_FILE:-/dev/null}" 2>&1
}

# ensure_build_toolchain — make sure every tool needed by `--build-from-source`
# exists. Installs missing system packages via the distro package manager (with
# user confirmation + sudo), fetches prebuilt xwin, and splats the SDK.
ensure_build_toolchain() {
    local missing_all=""
    for t in cmake ninja clang clang++ lld-link llvm-rc llvm-ml; do
        command -v "$t" >/dev/null 2>&1 || missing_all="$missing_all $t"
    done
    command -v strace >/dev/null 2>&1 || missing_all="$missing_all strace"
    command -v git >/dev/null 2>&1    || missing_all="$missing_all git"

    if [ -n "$missing_all" ]; then
        local id id_like; . /etc/os-release 2>/dev/null
        local pm=""; local pkgs=""
        case "$ID $ID_LIKE" in
            *arch*|*cachyos*|*manjaro*) pm="pacman -S --needed"; pkgs="clang lld llvm cmake ninja strace git" ;;
            *fedora*|*centos*|*rhel*|*rocky*) pm="dnf install -y";            pkgs="clang lld llvm cmake ninja-build strace git" ;;
            *debian*|*ubuntu*|*mint*) pm="apt-get install -y";                pkgs="clang lld llvm cmake ninja-build strace git" ;;
            *) pm="";;
        esac
        if [ -z "$pm" ]; then
            die "--build-from-source: missing:$missing_all. Install them manually (clang, lld, cmake, ninja, strace, git)."
        fi
        local doit=""
        [ -n "${ASSUME_YES:-}" ] || { read -r -p "Missing build tools (${missing_all# }). Install via '$pm $pkgs' (needs sudo)? [y/N] " doit; }
        case "$doit" in y|Y|yes) ;; *) die "--build-from-source: aborting, no toolchain installed.";; esac
        say "Installing build toolchain (may prompt for sudo)…"
        sudo -v 2>/dev/null || true
        sudo $pm $pkgs >>"$LOG_FILE" 2>&1 || die "--build-from-source: package install failed (see $LOG_FILE)"
    fi

    ensure_xwin_sdk || die "--build-from-source: could not set up xwin/Windows SDK (download the Linux xwin release from github.com/Jake-Shadle/xwin)."
}


# build_ignition — clone + cross-compile Ignition (Linux .so + Windows .exe/.dll)
# from source. Needs clang/lld/llvm (MSVC target), cmake, ninja, and the Windows
# SDK via xwin (~/.xwin-cache). Only used with --build-from-source; otherwise the
# prebuilt vendor/ copies are used. Outputs:
#   $IGNITION_SRC/build/Ignition-Linux-Windows/{libdriver_ignition.so,ignition_server.exe,ignition_bridge.dll}
# Skips work (and the slow build) when the cached source is already up to date
# with upstream and the artifacts exist.
build_ignition() {
    local out="$IGNITION_SRC/build/Ignition-Linux-Windows"
    local have=0
    [ -f "$out/libdriver_ignition.so" ] && [ -f "$out/ignition_server.exe" ] && [ -f "$out/ignition_bridge.dll" ] && have=1

    if [ ! -d "$IGNITION_SRC/.git" ]; then
        say "Cloning Ignition source…"
        git clone --depth 1 "$IGNITION_URL" "$IGNITION_SRC"
    fi

    # Decide whether we need (re)building: skip only if artifacts exist AND the
    # cached source is current with upstream. Fetching is cheap; the build isn't.
    local dirty=0
    ( cd "$IGNITION_SRC" && git fetch origin >/dev/null 2>&1 ) || dirty=1
    local local_head remote_head
    local_head=$(git -C "$IGNITION_SRC" rev-parse HEAD 2>/dev/null)
    remote_head=$(git -C "$IGNITION_SRC" rev-parse origin/HEAD 2>/dev/null || \
                  git -C "$IGNITION_SRC" rev-parse origin/master 2>/dev/null || \
                  git -C "$IGNITION_SRC" rev-parse origin/main 2>/dev/null)
    if [ -z "$local_head" ] || [ -z "$remote_head" ] || [ "$local_head" != "$remote_head" ]; then
        dirty=1
    fi
    if [ "$have" = 1 ] && [ "$dirty" = 0 ]; then
        return 0    # already built at current upstream commit
    fi

    # We're actually going to build — make sure the toolchain + SDK are present.
    ensure_build_toolchain

    if [ "$dirty" = 1 ] && [ "$have" = 1 ]; then
        say "Ignition source changed upstream — rebuilding…"
    fi

    say "Building Ignition from source (this can take several minutes)…"
    ( cd "$IGNITION_SRC" \
        && git fetch origin --depth 1 \
        && ( git checkout -f origin/HEAD 2>/dev/null \
             || git checkout -f origin/main 2>/dev/null \
             || git reset --hard origin/master ) \
        && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release \
        && cmake --build build ) >>"$LOG_FILE" 2>&1 \
        || die "--build-from-source: Ignition build failed (full output in $LOG_FILE)"

    [ -f "$out/libdriver_ignition.so" ] && [ -f "$out/ignition_server.exe" ] && [ -f "$out/ignition_bridge.dll" ] \
        || die "--build-from-source: built artifacts missing at $out"
}

# build_shims — cross-compile vr_bootstrap.exe and vrpathreg2.exe from the C
# sources in build/ using xwin. Outputs are cached in
# ~/.cache/standable-ignition/shims/ and only rebuilt when the source is newer.
# Sets SHIM_DIR to the directory containing the usable .exe files.
SHIM_CACHE="$HOME/.cache/standable-ignition/shims"
SHIM_DIR=""
build_shims() {
    mkdir -p "$SHIM_CACHE"
    local src_bc="$REPO/build/vr_bootstrap.c"
    local src_rc="$REPO/build/vrpathreg2.c"
    local out_bc="$SHIM_CACHE/vr_bootstrap.exe"
    local out_rc="$SHIM_CACHE/vrpathreg2.exe"
    local need=0
    [ ! -f "$out_bc" ] || [ "$src_bc" -nt "$out_bc" ] && need=1
    [ ! -f "$out_rc" ] || [ "$src_rc" -nt "$out_rc" ] && need=1
    if [ "$need" = 1 ]; then
        say "Building VR shims from source (vr_bootstrap + vrpathreg2)…"
        local xwin="$HOME/.xwin-cache/splat"
        local inc_flags="-I$xwin/crt/include -I$xwin/sdk/include/ucrt -I$xwin/sdk/include/um -I$xwin/sdk/include/shared"
        local lib_flags="-Wl,/LIBPATH:$xwin/crt/lib/x86_64 -Wl,/LIBPATH:$xwin/sdk/lib/um/x86_64 -Wl,/LIBPATH:$xwin/sdk/lib/ucrt/x86_64 -lkernel32 -luser32 -ladvapi32 -lshell32 -llibcmt -llibucrt -loldnames"
        clang --target=x86_64-pc-windows-msvc -fuse-ld=lld-link -DWIN32_LEAN_AND_MEAN \
            $inc_flags "$src_bc" -o "$out_bc" $lib_flags >>"$LOG_FILE" 2>&1 \
            || die "build_shims: vr_bootstrap.exe failed (see $LOG_FILE)"
        clang --target=x86_64-pc-windows-msvc -fuse-ld=lld-link -DWIN32_LEAN_AND_MEAN \
            $inc_flags "$src_rc" -o "$out_rc" $lib_flags >>"$LOG_FILE" 2>&1 \
            || die "build_shims: vrpathreg2.exe failed (see $LOG_FILE)"
    fi
    SHIM_DIR="$SHIM_CACHE"
}

# resolve_shims — pick vendored or freshly-built shim binaries (.exe).
# Sets SHIM_DIR to the directory containing vr_bootstrap.exe + vrpathreg2.exe.
resolve_shims() {
    if [ -n "$BUILD_FROM_SOURCE" ]; then
        build_shims
    else
        SHIM_DIR="$REPO/build"
    fi
    [ -f "$SHIM_DIR/vr_bootstrap.exe" ] && [ -f "$SHIM_DIR/vrpathreg2.exe" ] \
        || die "vr_bootstrap.exe / vrpathreg2.exe missing from $SHIM_DIR"
}

# resolve_ignition — pick source that actually produces the 3 shim binaries.
# Prefers a local source build (only when --build-from-source), else vendor/.
resolve_ignition() {
    if [ -n "$BUILD_FROM_SOURCE" ]; then
        build_ignition
        local out="$IGNITION_SRC/build/Ignition-Linux-Windows"
        IGN_LINUX64="$out"
    else
        IGN_LINUX64="$REPO/vendor"
    fi
    for v in libdriver_ignition.so ignition_server.exe ignition_bridge.dll; do
        [ -f "$IGN_LINUX64/$v" ] || die "$v missing ($IGN_LINUX64)"
    done
    resolve_shims
}

# resolve_reg — PSVR2 hidraw registry file is vendored in config/, but when
# building Ignition from source we use the fresh copy from its support/ so it
# stays in lockstep with upstream. Sets IGN_PSVR2_REG.
resolve_reg() {
    if [ -n "$BUILD_FROM_SOURCE" ] && [ -f "$IGN_LINUX64/wine_psvr2_hidraw.reg" ]; then
        IGN_PSVR2_REG="$IGN_LINUX64/wine_psvr2_hidraw.reg"
    else
        IGN_PSVR2_REG="$REPO/config/wine_psvr2_hidraw.reg"
    fi
    [ -f "$IGN_PSVR2_REG" ] || die "wine_psvr2_hidraw.reg missing ($IGN_PSVR2_REG)"
}

# Steamworks SDK mirror URLs for steam_api64.dll. Valve's official
# ValveSoftware/steamworks_sdk repo is gone; the SDK is otherwise only
# downloadable from the Steamworks partner portal (login required). These are
# faithful public mirrors of the SDK's redistributable_bin/win64/steam_api64.dll.
STEAM_API64_MIRRORS="
https://raw.githubusercontent.com/rlabrecque/SteamworksSDK/master/redistributable_bin/win64/steam_api64.dll
https://raw.githubusercontent.com/ceifa/steamworks.js/main/sdk/redistributable_bin/win64/steam_api64.dll
"
# Exports the Windows driver imports (steam_api64.dll must provide these).
STEAM_API64_NEEDED="SteamInternal_SteamAPI_Init SteamInternal_FindOrCreateUserInterface SteamInternal_ContextInit SteamAPI_GetHSteamUser"

# fetch_steam_api64 — download the Steamworks redistributable from a public
# mirror into ~/.cache/standable-ignition/ and verify it's a PE exporting the
# four entry points the driver needs. Prints the cached path on success,
# empty string on any failure (caller falls back to vendored).
fetch_steam_api64() {
    local cache="$HOME/.cache/standable-ignition/steam_api64.dll"
    if [ -s "$cache" ] && verify_steam_api64 "$cache"; then
        echo "$cache"; return 0
    fi
    local url need_ok=0
    for url in $STEAM_API64_MIRRORS; do
        _log "Fetching steam_api64.dll from Steamworks SDK mirror: $url"
        curl -fsSL --max-time 90 "$url" -o "$cache" 2>/dev/null || continue
        if verify_steam_api64 "$cache"; then need_ok=1; break; fi
        rm -f "$cache"
    done
    if [ "$need_ok" = 1 ]; then echo "$cache"; else echo ""; fi
}

# verify_steam_api64 — cheap sanity check: MZ header + the four exported names
# present as ASCII strings in the DLL (export names are stored verbatim).
verify_steam_api64() {
    [ -f "$1" ] || return 1
    [ "$(head -c 2 "$1")" = "MZ" ] || return 1
    local name
    for name in $STEAM_API64_NEEDED; do
        grep -aq "$name" "$1" || return 1
    done
    return 0
}

# resolve_steam_api64 — pick the source for steam_api64.dll (the driver's
# Steamworks runtime). Order: game's own build (if a game update ships one),
# freshly fetched SDK mirror build, vendored copy as last resort.
SA64_SRC=""
resolve_steam_api64() {
    if [ -f "$GAME_DIR/bin/win64/steam_api64.dll" ]; then
        SA64_SRC="$GAME_DIR/bin/win64/steam_api64.dll"
        say "using game's own steam_api64.dll"
    else
        SA64_SRC="$(fetch_steam_api64)"
        if [ -n "$SA64_SRC" ]; then
            say "using Steamworks SDK steam_api64.dll"
        else
            say "offline/fetch failed — using vendored steam_api64.dll"
            SA64_SRC="$REPO/vendor/steam_api64.dll"
        fi
    fi
    [ -f "$SA64_SRC" ] || die "steam_api64.dll source missing ($SA64_SRC)"
}

# ---------------------------------------------------------------- detection --
detect_steam_root() {
    for c in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steampipe"; do
        [ -d "$c/steamapps" ] && { STEAM_ROOT="$c"; return 0; }
    done
    return 1
}

detect_game_dir() {
    # default library, then every library in libraryfolders.vdf. A library only
    # counts if Steam's appmanifest for this game is present there — an orphaned
    # leftover dir (e.g. after a move/update) with no manifest is NOT the game.
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
        # accept directory (append /proton) or path to proton binary
        [ -d "$PROTON_OVERRIDE" ] && [ -x "$PROTON_OVERRIDE/proton" ] && PROTON_OVERRIDE="$PROTON_OVERRIDE/proton"
        [ -x "$PROTON_OVERRIDE" ] || die "--proton: not executable: $PROTON_OVERRIDE"
        PROTON="$PROTON_OVERRIDE"; return 0
    fi
    # Preserve the existing proton choice if the scripts already work.
    # Silently switching builds breaks gamedrive conventions and s: links.
    local existing=""
    for f in "$GAME_DIR/bin/linux64/launch_serverhelper.sh"; do
        [ -f "$f" ] || continue
        existing=$(grep '^PROTON=' "$f" 2>/dev/null | head -1 | sed 's/^PROTON="//;s/"$//;s/^PROTON=//')
        # must be a regular file (not a directory) and executable
        [ -n "$existing" ] && [ -f "$existing" ] && [ -x "$existing" ] && { PROTON="$existing"; return 0; }
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
    # sanity: if PROTON is a directory, append /proton
    [ -d "$PROTON" ] && [ -x "$PROTON/proton" ] && PROTON="$PROTON/proton"
}

pick_prefix() {
    # the Proton prefix lives next to the game in its own Steam library
    # (steamapps/compatdata/<APP_ID>), which for a secondary drive is NOT the
    # default Steam root. Fall back to the default root if the game library
    # hasn't been located yet (e.g. in --check before detect_game_dir runs).
    local GIRO="${GAME_LIB:-$STEAM_ROOT}"
    COMPAT="$GIRO/steamapps/compatdata/$APP_ID"
    PFX="$COMPAT/pfx"
}

# ------------------------------------------------------------- VRChat link ---
# Standable's auto-calibration ("VRChat" / "OSC" feature) works by having
# driver_standable.dll read VRChat's IK-debug log from
#   %UserProfile%\AppData\LocalLow\VRChat\VRChat\output_log_*.txt
# (it regex-parses "Changed player height ... tracking scale ..." and
# "eyeToNeck:(...) scaled:(...)" lines; confirmed against the driver's
# WS2_32/ExpandEnvironmentStringsW/FindFirstFileW imports and the UTF-16 path
# string near the AutoCalibration region). VRChat runs in its OWN Proton prefix
# (AppID 438100), so inside the Standable prefix that path is empty. We symlink
# VRChat's LocalLow data into the Standable prefix so the driver can see
# VRChat's live IK log.
VRC_APP_ID=438100
detect_vrchat_prefix() {
    # locate VRChat's Proton prefix across all Steam libraries (any drive).
    local libs=("$STEAM_ROOT")
    [ -f "$STEAM_ROOT/steamapps/libraryfolders.vdf" ] && {
        while IFS= read -r p; do
            [ -n "$p" ] && libs+=("$p")
        done < <(awk -F'"' '/"path"/{print $4}' "$STEAM_ROOT/steamapps/libraryfolders.vdf")
    }
    VRC_COMPAT=""
    local lib
    for lib in "${libs[@]}"; do
        if [ -d "$lib/steamapps/compatdata/$VRC_APP_ID" ]; then
            VRC_COMPAT="$lib/steamapps/compatdata/$VRC_APP_ID"; return 0
        fi
    done
    return 1
}

# host path of VRChat's LocalLow data (empty if not installed / prefix not made)
vrchat_low() {
    [ -n "${VRC_COMPAT:-}" ] || return 0
    printf '%s/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat' "$VRC_COMPAT"
}

setup_vrchat_link() {
    local src; src="$(vrchat_low)"
    local dst="$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
    if [ -z "$src" ] || [ ! -d "$src" ]; then
        return 0    # nothing to link yet
    fi
    # Don't clobber a real directory someone created deliberately.
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        warn "Leaving $dst alone (real dir/link); remove it to let the port manage it"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
    say "Linked VRChat LocalLow into Standable prefix for auto-calibration."
}

# ------------------------------------------------------------------- checks --
require() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

# ---------------------------------------------------- flags (--proton etc.) --
ORIG_ARGS=("$@")
BUILD_FROM_SOURCE=""
PROTON_OVERRIDE=""
ASSUME_YES=""
LOG_FILE=""
DIAGNOSE=""
ARGS=()
for a in "$@"; do
    case "$a" in
        --build-from-source) BUILD_FROM_SOURCE=1 ;;
        --proton) PROTON_OVERRIDE="PENDING" ;;
        --assume-yes|-y) ASSUME_YES=1 ;;
        --log) LOG_FILE="PENDING" ;;
        --diagnose) DIAGNOSE=1 ;;
        --install) : ;;                 # explicit default (also run when omitted)
        --verbose|-v) set -x ;;
        *)
            if [ "$PROTON_OVERRIDE" = "PENDING" ]; then PROTON_OVERRIDE="$a"
            elif [ "$LOG_FILE" = "PENDING" ]; then LOG_FILE="$a"
            else ARGS+=("$a"); fi
            ;;
    esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
if [ -n "$LOG_FILE" ] && [ "$LOG_FILE" = "PENDING" ]; then
    die "--log requires a file path (e.g. --log standable-install.log)"
fi
# Logging is always on: every run writes a full transcript (say/warn/die plus
# toolchain & build command output). --log overrides the location.
LOG_FILE="${LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/standable/install.log}"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"   # fresh transcript per run
_log "=== standable install log — $(date -Iseconds) ==="
_log "argv: $0 ${ORIG_ARGS[*]}"
_log "pwd: $PWD  user: $(id -un)  kernel: $(uname -r)"

# ================================================================== DOCTOR ==
if [ "${1:-}" = "--check" ] || [ -n "$DIAGNOSE" ]; then
    detect_steam_root || die "Steam root not found"
    if detect_game_dir; then
        GAME_FOUND=1
        S_ROOT="${GAME_LIB:-$STEAM_ROOT}"
    else
        GAME_FOUND=0
        S_ROOT="$STEAM_ROOT"
    fi
    pick_prefix
    detect_vrchat_prefix || true
    PROTON=""
    for f in "$GAME_DIR/bin/linux64/launch_serverhelper.sh"; do
        [ -f "$f" ] || continue
        PROTON=$(grep '^PROTON=' "$f" 2>/dev/null | head -1 | sed 's/^PROTON="//;s/"$//;s/^PROTON=//')
        [ -n "$PROTON" ] && [ -f "$PROTON" ] && break
    done
    fail=0
    ok(){ say "OK  $1"; }
    bad(){ warn "FAIL $1"; fail=1; }
    [ -f "$PFX/drive_c/vr_bootstrap.exe" ] && ok "vr_bootstrap.exe deployed" || bad "vr_bootstrap.exe missing"
    [ -f "$PFX/drive_c/vrclient/bin/vrclient_x64.dll" ] && ok "vrclient copy present" || bad "vrclient copy missing"
    VRPATH="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64/vrpathreg.exe"
    [ -f "$VRPATH" ] && ok "vrpathreg stub present" || bad "vrpathreg stub missing"
    grep -aq '"SteamPath"' "$PFX/user.reg" 2>/dev/null && ok "SteamPath registry set" || bad "SteamPath registry missing"
    [ -L "$PFX/dosdevices/s:" ] && ok "s: dosdevice link alive" || bad "s: link missing (recreated on next launch)"
    # s: must point at the LIBRARY that holds the game (secondary libraries need
    # S_ROOT, not the default Steam root); a wrong target breaks the driver's
    # CWD->s: mapping and makes the handshake fail -> SteamVR disables the driver.
    if [ -L "$PFX/dosdevices/s:" ]; then
        STGT="$S_ROOT"
        if [ -n "$PROTON" ] && [ -f "$PROTON" ] \
           && ! grep -q 'get_validated_steamapps_parent' "$(dirname "$PROTON")/proton" 2>/dev/null; then
            STGT="$S_ROOT/steamapps"
        fi
        SLINK_TGT="$(readlink "$PFX/dosdevices/s:")"
        if [ "$SLINK_TGT" = "$STGT" ]; then
            ok "s: maps to game library ($STGT)"
        else
            warn "s: maps to '$SLINK_TGT' but game library is '$STGT' (fix with install.sh)"
            fail=1
        fi
    fi
    # SteamVR persistently disables drivers that fail/abort at load ("Not loading
    # driver X because it is disabled in settings"). Look for that flag so users
    # aren't stuck in a re-enable/disable loop.
    CFG="$STEAM_ROOT/config/steamvr.vrsettings"
    if grep -q '"driver_standable"' "$CFG" 2>/dev/null; then
        if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("bad" if d.get("driver_standable",{}).get("enable",True) is False else "ok")' "$CFG" 2>/dev/null | grep -q bad; then
            bad "SteamVR has disabled the standable driver (re-enable via install.sh or Settings/Developer)"
        else
            ok "standable driver not disabled in SteamVR settings"
        fi
    else
        ok "standable driver not disabled in SteamVR settings"
    fi
    # SteamVR safe mode loads only the whitelist (safe_mode_driver_whitelist.json);
    # standable is NOT on it, so a safe-mode session will silently skip the driver.
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("bad" if d.get("steamvr",{}).get("enableSafeMode",False) else "ok")' "$CFG" 2>/dev/null | grep -q bad; then
        warn "SteamVR SAFE MODE is on — standable is not whitelisted and won't load (clear safe mode in SteamVR Settings)"
        fail=1
    else
        ok "SteamVR safe mode off"
    fi
    # Linux SteamVR 307: "A key component of SteamVR isn't working" often
    # relates to enableLinuxVulkanAsync on Wayland compositors.
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("bad" if d.get("steamvr",{}).get("enableLinuxVulkanAsync",False) else "ok")' "$CFG" 2>/dev/null | grep -q bad; then
        warn "enableLinuxVulkanAsync is on in steamvr.vrsettings — known cause of SteamVR 307 on Wayland (set false or use X11 session)"
    else
        ok "enableLinuxVulkanAsync off"
    fi
    if [ -n "${VRC_COMPAT:-}" ]; then
        VRCLOW="$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
        SRCLOW="$(vrchat_low)"
        if [ -L "$VRCLOW" ] && [ -d "$SRCLOW" ]; then
            ok "VRChat LocalLow linked into Standable prefix (auto-calibration log)"
        else
            bad "VRChat log link missing — run install to enable auto-calibration"
        fi
    else
        warn "VRChat not found — auto-calibration requires it to be installed"
    fi
    grep -aq "Standable" "$HOME/.config/openvr/openvrpaths.vrpath" 2>/dev/null \
        && ok "seed entry in ~/.config/openvr/openvrpaths.vrpath" || bad "seed entry missing"
    [ -x "$HOME/bin/standable_launch_hook.sh" ] && ok "~/bin/standable_launch_hook.sh installed" || bad "Steam launch hook missing"
    if [ "$GAME_FOUND" = 1 ]; then
        [ -f "$GAME_DIR/bin/linux64/steam_api64.dll" ] \
            && ok "steam_api64.dll deployed (driver's Steamworks dep)" \
            || bad "steam_api64.dll missing — re-run install, SteamVR crashes on driver load"
    else
        bad "game '$GAME_SUBDIR' not found in any Steam library"
    fi
    N=$(pgrep -xc wineserver | tail -1); N=${N:-0}
    if [ "$N" = 0 ]; then ok "no wineservers (nothing running)"
    elif [ "$N" = 1 ]; then ok "single wineserver (GUI+driver shared)"
    else bad "$N wineservers running, IPC will be split!"; fi
    LOG="$STEAM_ROOT/logs/vrserver.txt"
    if [ -f "$LOG" ]; then
        F=$(tail -n 300 "$LOG" | grep -v "Failed to send message: SteamUser" | grep -ac "Failed to Load from\|Failed to send message" 2>/dev/null)
        L=$(stat -c %Y "$LOG"); NOW=$(date +%s)
        if [ $((NOW-L)) -lt 3600 ] && [ "${F:-0}" != 0 ]; then
            warn "recent driver failures in vrserver.txt ($F), check TROUBLESHOOTING.md"
        else
            ok "vrserver.txt clean of known failure patterns"
        fi
        # SteamVR error 307: "A key component of SteamVR isn't working" —
        # a vrcompositor/vulkan startup failure. Pull the smoking-gun lines.
        # NB: avoid matching "307" inside microsecond timestamps.
        if tail -n 400 "$LOG" | grep -aqE "Error.*\b307\b|vrcompositor.*(crash|segfault)|Failed to (connect|load|init).*compositor|enableLinuxVulkanAsync|Vulkan.*(failed|error)"; then
            G=$(tail -n 400 "$LOG" | grep -aiE "\b307\b|vrcompositor|enableLinuxVulkanAsync|Vulkan" | tail -5)
            warn "possible SteamVR 307 (compositor) failure in vrserver.txt:"
            echo "$G" | sed 's/^/        /'
        else
            ok "no SteamVR 307 / compositor failure signature in vrserver.txt"
        fi
    fi
    # --diagnose: dump system info + check output to a file for sharing.
    if [ -n "$DIAGNOSE" ]; then
        {
            echo ""
            echo "--- system ---"
            uname -a
            [ -f /etc/os-release ] && { echo ""; cat /etc/os-release; }
            echo ""
            echo "--- cpu ---"
            grep -m1 "model name" /proc/cpuinfo 2>/dev/null || true
            echo ""
            echo "--- memory ---"
            free -h 2>/dev/null || true
            echo ""
            echo "--- gpu ---"
            if command -v vulkaninfo >/dev/null 2>&1; then
                vulkaninfo 2>/dev/null | grep -E "deviceName|driverInfo|apiVersion" | head -6
            elif [ -d /sys/class/drm ]; then
                for c in /sys/class/drm/card*/device/vendor; do
                    [ -f "$c" ] && echo "$(dirname "$c"): $(cat "$c" 2>/dev/null)"
                done
            fi
            echo ""
            echo "--- display server ---"
            echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
            echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
            echo "DISPLAY=${DISPLAY:-unset}"
            echo ""
            echo "--- steam ---"
            echo "STEAM_ROOT=$STEAM_ROOT"
            if [ -f "$STEAM_ROOT/package.txt" ]; then
                echo "steam package: $(cat "$STEAM_ROOT/package.txt" 2>/dev/null)"
            fi
            if [ -d "$STEAM_ROOT/steamapps/common/SteamVR" ]; then
                cat "$STEAM_ROOT/steamapps/common/SteamVR/bin/linux64/runtime_resource.vrmanifest" 2>/dev/null \
                    | grep -E '"version_string"|"api_version"' || true
            fi
            echo ""
            echo "--- proton ---"
            echo "detected: $PROTON"
            if [ -n "$PROTON" ] && [ -f "$PROTON" ]; then
                head -3 "$PROTON" 2>/dev/null | grep -oE "Proton [0-9a-zA-Z.-]+" || true
            fi
            echo ""
            echo "--- game ---"
            echo "GAME_DIR=$GAME_DIR"
            echo "GAME_FOUND=$GAME_FOUND"
            if [ -n "$GAME_DIR" ] && [ -f "$GAME_DIR/bin/linux64/launch_serverhelper.sh" ]; then
                grep -E "^(PROTON|STEAM_ROOT|S_TARGET|S_ROOT)=" "$GAME_DIR/bin/linux64/launch_serverhelper.sh" 2>/dev/null
            fi
            echo ""
            echo "--- prefix ---"
            echo "PFX=$PFX"
            [ -f "$PFX/user.reg" ] && grep -E "SteamPath|S:" "$PFX/user.reg" 2>/dev/null | head -5
            echo ""
            echo "--- openvr ---"
            cat "$HOME/.config/openvr/openvrpaths.vrpath" 2>/dev/null || echo "(not found)"
            echo ""
            echo "--- steamvr settings ---"
            CFG="$STEAM_ROOT/config/steamvr.vrsettings"
            if [ -f "$CFG" ]; then
                python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sv = d.get('steamvr', {})
dr = d.get('driver_standable', {})
for k in ('enableSafeMode','enableLinuxVulkanAsync'):
    print(f'steamvr.{k} = {sv.get(k, \"(unset)\")}')
print(f'driver_standable.enable = {dr.get(\"enable\", \"(unset)\")}')
" "$CFG" 2>/dev/null || echo "(json parse failed)"
            else
                echo "(steamvr.vrsettings not found)"
            fi
            echo ""
            echo "--- wineserver ---"
            pgrep -a wineserver 2>/dev/null || echo "(none)"
            echo ""
            echo "--- vrserver.txt (last 20 lines) ---"
            tail -20 "$STEAM_ROOT/logs/vrserver.txt" 2>/dev/null || echo "(not found)"
            echo ""
            echo "--- /check output above ---"
        } >> "$LOG_FILE" 2>&1
        say "Diagnostics appended to $LOG_FILE — share this file when filing issues"
    fi
    exit $fail
fi

# =============================================================== UNINSTALL ==
if [ "${1:-}" = "--uninstall" ]; then
    detect_steam_root || die "Steam root not found"
    detect_game_dir || die "game not found"
    pick_prefix
    say "Removing port artifacts…"
    rm -fv "$HOME/bin/standable-gui" "$HOME/bin/standable_launch_hook.sh" "$HOME/Desktop/standable-gui.desktop" "$HOME/Desktop/Standable GUI.desktop"
    rm -fv "$HOME/.local/share/icons/standable.png"
    rm -fv "$PFX/drive_c/vr_bootstrap.exe" "$PFX/drive_c/regq.txt" "$PFX/drive_c/typetest.txt"
    rm -fv "$PFX/dosdevices/s:"
    rm -fv "$PFX/drive_c/users/steamuser/AppData/LocalLow/VRChat"   # VRChat log link (auto-calibration)
    rm -fv "$GAME_DIR/bin/linux64/steam_api64.dll"
    say "Restored files are next to the modified ones (*.bak-*). vrpath seeds and"
    say "the SteamPath registry key were left alone , see RESTORE.md to strip them."
    exit 0
fi

# ================================================================= INSTALL ==
for r in bash python3 tar curl; do require "$r"; done

say "Detecting environment…"
detect_steam_root || {
    [ -d "$HOME/.var/app/com.valvesoftware.Steam" ] \
        && die "Flatpak Steam detected but not supported, install Steam natively."
    die "Steam not found (~/.local/share/Steam)"
}
detect_game_dir   || die "game '$GAME_SUBDIR' not found in any Steam library"
pick_proton
pick_prefix
detect_vrchat_prefix || warn "VRChat not found in any Steam library — auto-calibration link will be skipped"
STEAMVR="$STEAM_ROOT/steamapps/common/SteamVR"
WIN64="$PFX/drive_c/Program Files (x86)/Steam/steamapps/common/SteamVR/bin/win64"

say "Steam root : $STEAM_ROOT"
say "Game       : $GAME_DIR"
say "Prefix     : $COMPAT (pfx: $PFX)"
say "Proton     : $PROTON"
if [ -n "${VRC_COMPAT:-}" ]; then say "VRChat pfx : $VRC_COMPAT"; fi

[ -d "$STEAMVR" ] || die "SteamVR not installed at $STEAMVR, install it in Steam first."
[ -f "$GAME_DIR/bin/win64/driver_standable.dll" ] || die "unexpected game layout (driver dll missing)"
[ -f "$GAME_DIR/driver.vrdrivermanifest" ] || die "driver.vrdrivermanifest missing, game layout changed or incomplete install"
resolve_ignition
resolve_reg

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
mkdir -p "$GAME_DIR/bin/linux64"
bak "$GAME_DIR/bin/linux64/wine_psvr2_hidraw.reg"
cp "$IGN_PSVR2_REG" "$GAME_DIR/bin/linux64/"

say "Deploying prefix binaries…"
mkdir -p "$PFX/drive_c/vrclient/bin" "$WIN64"
bak "$PFX/drive_c/vr_bootstrap.exe";  cp "$SHIM_DIR/vr_bootstrap.exe" "$PFX/drive_c/"
bak "$WIN64/vrpathreg.exe";           cp "$SHIM_DIR/vrpathreg2.exe"   "$WIN64/vrpathreg.exe"
cp "$SHIM_DIR/vrpathreg2.exe"       "$WIN64/vrmonitor.exe"           # existence-check only
PC="$PROTON"; PC="${PC%/proton}/files/lib/wine/x86_64-windows"
ls "$PC"/vrclient*.dll >/dev/null 2>&1 || die "vrclient dlls not found at $PC"
bak "$PFX/drive_c/vrclient/bin/vrclient_x64.dll"
cp "$PC"/vrclient*.dll "$PFX/drive_c/vrclient/bin/"

# -- VRChat LocalLow link (auto-calibration) ---------------------------------
# The driver reads VRChat's IK-debug log from %UserProfile%\AppData\LocalLow\VRChat\VRChat\
# inside ITS OWN prefix; VRChat runs in a separate prefix (438100), so we link
# VRChat's data in. Also cached for the per-launch repair loops (@VRCHAT_VRC_DIR@).
setup_vrchat_link

# -- registry ----------------------------------------------------------------
say "Setting SteamPath registry (HKCU\\Software\\Valve\\Steam)…"
STEAM_COMPAT_DATA_PATH="$COMPAT" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
    timeout 120 "$PROTON" run reg add 'HKCU\Software\Valve\Steam' /v SteamPath \
    /t REG_SZ /d 'C:\Program Files (x86)\Steam' /f >/dev/null 2>&1 \
    || warn "reg add failed (will retry on next shim run)"

# -- s: link -----------------------------------------------------------------
# Valve Proton maps s: to the Steam parent (S:\steamapps\common\...) via
# get_validated_steamapps_parent(). Other builds map s: to steamapps directly
# (S:\common\...). Detect which by checking for the parent wrapper. When the
# game lives on a secondary library, s: is that library's root, not the
# default Steam root.
S_ROOT="${GAME_LIB:-$STEAM_ROOT}"
PROTON_DIR_S="$(dirname "$PROTON")"
if grep -q 'get_validated_steamapps_parent' "$PROTON_DIR_S/proton" 2>/dev/null; then
    S_TARGET="$S_ROOT"
else
    S_TARGET="$S_ROOT/steamapps"
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
mkdir -p "$GAME_DIR/bin/linux64"
bak "$GAME_DIR/bin/linux64/driver_standable.so"
rm -f "$GAME_DIR/bin/linux64/driver_standable.so"
cp "$IGN_LINUX64/libdriver_ignition.so" "$GAME_DIR/bin/linux64/driver_standable.so"
bak "$GAME_DIR/bin/linux64/ignition_server.exe"
cp "$IGN_LINUX64/ignition_server.exe" "$GAME_DIR/bin/linux64/"
bak "$GAME_DIR/bin/linux64/ignition_bridge.dll"
cp "$IGN_LINUX64/ignition_bridge.dll" "$GAME_DIR/bin/linux64/"

# Steamworks runtime requirement of the Windows driver. driver_standable.dll
# imports steam_api64.dll (SteamAPI_* init); without it ignition_server.exe
# fails to load the driver, the handshake never completes and SteamVR aborts
# with a ~21s watchdog timeout (safe-mode crash loop). bin/linux64 is the
# Ignition server's working dir and is on Wine's DLL search path.
# The game does NOT ship steam_api64.dll (fresh installs only have
# driver_standable.dll in bin/win64), so source it from the user's own Steam
# library: another game that ships it (VRChat is the most likely; it's already
# required for auto-calibration). Vendored copy is the last resort.
bak "$GAME_DIR/bin/linux64/steam_api64.dll"
resolve_steam_api64
cp "$SA64_SRC" "$GAME_DIR/bin/linux64/"
say "copied steam_api64.dll from $(basename "$(dirname "$SA64_SRC")")"

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
# Desktop icon: copy the game's wave icon to the standard icons dir so the
# desktop entry resolves regardless of game updates/moves.
ICON_SRC="$GAME_DIR/resources/icons/stndbl_wave@2x.png"
ICON_DST="$HOME/.local/share/icons/standable.png"
if [ -f "$ICON_SRC" ]; then
    mkdir -p "$(dirname "$ICON_DST")"
    bak "$ICON_DST"
    cp "$ICON_SRC" "$ICON_DST"
else
    warn "icon not found: $ICON_SRC (desktop entry will fall back to generic)"
fi
gen() { # gen <template> <dest>
    S_TARGET="${S_TARGET:-$S_ROOT}"
    sed -e "s|@GAME_DIR@|$GAME_DIR|g" -e "s|@COMPAT@|$COMPAT|g" -e "s|@PFX@|$PFX|g" \
        -e "s|@PROTON@|$PROTON|g"       -e "s|@STEAMVR@|$STEAMVR|g" \
        -e "s|@STEAM_ROOT@|$STEAM_ROOT|g" -e "s|@S_ROOT@|$S_ROOT|g" -e "s|@S_TARGET@|$S_TARGET|g" \
        -e "s|@HOME@|$HOME|g" \
        -e "s|@VRCHAT_VRC_DIR@|$(vrchat_low)|g" \
        "$REPO/templates/$1" > "$2"
}
mkdir -p "$HOME/bin"
bak "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
gen launch_serverhelper.sh.in "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
chmod +x "$GAME_DIR/bin/linux64/launch_serverhelper.sh"
gen ignition.json.in "$GAME_DIR/bin/linux64/ignition.json"
# retire legacy GUI launcher from older installs
rm -fv "$HOME/bin/standable-gui" "$HOME/Desktop/Standable GUI.desktop" "$HOME/Desktop/standable-gui.desktop"
bak "$HOME/bin/standable_launch_hook.sh"
gen standable_launch_hook.sh.in "$HOME/bin/standable_launch_hook.sh"
chmod +x "$HOME/bin/standable_launch_hook.sh"

say "Done."
cat <<EOF

  Next steps:
    Right-click Standable in Steam → Properties → Launch Options, set:
      bash $HOME/bin/standable_launch_hook.sh %command%
    Then click Play.

  Start SteamVR first.
  Verify anytime with:  $REPO/install.sh --check
  Log for this run:     $LOG_FILE
  Build from source:    $REPO/install.sh --build-from-source
  Problems?             See TROUBLESHOOTING.md in the repo.
EOF
