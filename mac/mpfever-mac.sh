#!/bin/bash
# MPFever on macOS (Apple Silicon and Intel), through Wine.
#
# MPFever patches the Windows build of Transport Fever 3 (TransportFever3.exe), so on a Mac it runs the Windows game and
# the Windows MPFever.exe together, in one Wine "bottle" (CrossOver, Whisky, or a plain Wine prefix). The Mac's own build of
# the game is a different program that MPFever cannot patch, and its numbers may differ from the Windows ones: players of the
# Windows build and of the Mac build could not stay in the same world. Running the Windows build keeps a Mac player in step
# with everybody else.
#
#   mpfever-mac.sh install   find the game's bottle, copy MPFever into the game's folder, remember the choice
#   mpfever-mac.sh play      start MPFever (it starts Transport Fever 3 itself); runs install first when needed
#   mpfever-mac.sh doctor    say what was found and what is missing, change nothing
#   mpfever-mac.sh app [dir] make MPFever.app (a double-clickable start) in dir (default: ~/Applications)
#
# Settings (environment variables, all optional):
#   MPF_PREFIX    the bottle / Wine prefix to use (the folder with drive_c in it)
#   MPF_WINE      the wine program to use (wine64 / wine of CrossOver, Whisky...)
#   MPF_GAMEDIR   the game's folder (the one with TransportFever3.exe), as a Mac path
#   MPF_SRC       the MPFever folder to install (default: the folder of this script's folder)
#   MPF_AVX=0     do not tell Rosetta 2 to offer AVX to the game (on by default; needs macOS 15 or later)
#   MPF_DRY_RUN=1 print what would run, run nothing
#
# Written for the bash 3.2 that macOS has: only what that old bash can do.

set -u

SELF="$0"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"

CONF_DIR="${HOME}/Library/Application Support/MPFever"
CONF="${CONF_DIR}/mac.conf"
LOG="${HOME}/Library/Logs/MPFever-mac.log"
DRY="${MPF_DRY_RUN:-0}"

say()  { printf '%s\n' "$*"; }
warn() { printf 'MPFever: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

# ------------------------------------------------------------------ what is where

# The MPFever folder to install: the Windows archive's MPFever folder, in which this script is (MPFever/mac/) or beside which it is.
find_src() {
    if [ -n "${MPF_SRC:-}" ]; then echo "$MPF_SRC"; return; fi
    local up
    up="$(cd "$SELF_DIR/.." && pwd)"
    if [ -f "$up/MPFever.exe" ]; then echo "$up"; return; fi
    if [ -f "$SELF_DIR/MPFever.exe" ]; then echo "$SELF_DIR"; return; fi
    # the app copy of this script (MPFever.app/Contents/Resources): the folder remembered at install
    if [ -f "$CONF" ]; then
        local s
        s="$(conf_get SRC)"
        if [ -n "$s" ] && [ -f "$s/MPFever.exe" ]; then echo "$s"; return; fi
    fi
}

conf_get() { [ -f "$CONF" ] && sed -n "s/^$1=//p" "$CONF" | tail -n 1; }

conf_set() {
    mkdir -p "$CONF_DIR" || return 1
    local tmp="$CONF.tmp.$$"
    { [ -f "$CONF" ] && grep -v "^$1=" "$CONF"; printf '%s=%s\n' "$1" "$2"; } > "$tmp" 2>/dev/null
    mv "$tmp" "$CONF"
}

is_prefix() { [ -d "$1/drive_c" ] && { [ -f "$1/system.reg" ] || [ -d "$1/drive_c/windows" ]; }; }

# every Wine prefix this script knows how to look in, one per line, with the kind that picks the wine program:
#   whisky|crossover|wine  <TAB>  folder
list_prefixes() {
    local d
    if [ -n "${MPF_PREFIX:-}" ]; then
        local kind=wine
        case "$MPF_PREFIX" in */CrossOver/Bottles/*) kind=crossover ;; */com.isaacmarovitz.Whisky/*) kind=whisky ;; esac
        printf '%s\t%s\n' "$kind" "$MPF_PREFIX"
        return
    fi
    for d in "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"/*; do
        is_prefix "$d" && printf 'whisky\t%s\n' "$d"
    done
    for d in "$HOME/Library/Application Support/CrossOver/Bottles"/*; do
        is_prefix "$d" && printf 'crossover\t%s\n' "$d"
    done
    for d in "$HOME/.wine" "$HOME/.local/share/wineprefixes"/* "$HOME/Games/Heroic/Prefixes"/*/* "$HOME/Games/Heroic/Prefixes"/*; do
        is_prefix "$d" && printf 'wine\t%s\n' "$d"
    done
}

# the game's folder inside a prefix (Mac path), or nothing
game_in_prefix() {
    local p="$1" c
    for c in "$p/drive_c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3" \
             "$p/drive_c/Program Files/Steam/steamapps/common/Transport Fever 3" \
             "$p/drive_c/Steam/steamapps/common/Transport Fever 3" \
             "$p/drive_c/SteamLibrary/steamapps/common/Transport Fever 3" \
             "$p/drive_c/Games/Transport Fever 3"; do
        if [ -f "$c/TransportFever3.exe" ]; then echo "$c"; return; fi
    done
    # another Steam library inside the bottle: look for the exe a few levels down
    local f
    f="$(find "$p/drive_c" -maxdepth 7 -name TransportFever3.exe -not -path '*/windows/*' 2>/dev/null | head -n 1)"
    [ -n "$f" ] && dirname "$f"
}

# the wine program for a kind of prefix; MPF_WINE wins
find_wine() {
    local kind="$1" c
    if [ -n "${MPF_WINE:-}" ]; then echo "$MPF_WINE"; return; fi
    case "$kind" in
        whisky)
            for c in "$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"; do
                [ -x "$c" ] && { echo "$c"; return; }
            done ;;
        crossover)
            for c in "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
                     "$HOME/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"; do
                [ -x "$c" ] && { echo "$c"; return; }
            done ;;
    esac
    for c in "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64" \
             "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine64" \
             "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64" \
             "/opt/homebrew/bin/wine64" "/usr/local/bin/wine64" "/opt/homebrew/bin/wine" "/usr/local/bin/wine"; do
        [ -x "$c" ] && { echo "$c"; return; }
    done
    command -v wine64 2>/dev/null || command -v wine 2>/dev/null
}

# ------------------------------------------------------------------ choose the bottle

# sets KIND PREFIX GAMEDIR WINE; returns 1 with a message when something is missing
resolve() {
    KIND=""; PREFIX=""; GAMEDIR=""; WINE=""
    local line k p g first=""
    # the choice of the last install, unless the settings above say otherwise
    if [ -z "${MPF_PREFIX:-}" ] && [ -f "$CONF" ]; then
        k="$(conf_get KIND)"; p="$(conf_get PREFIX)"; g="$(conf_get GAMEDIR)"
        if [ -n "$p" ] && is_prefix "$p" && [ -f "$g/TransportFever3.exe" ]; then
            KIND="$k"; PREFIX="$p"; GAMEDIR="${MPF_GAMEDIR:-$g}"
        fi
    fi
    if [ -z "$PREFIX" ]; then
        local IFS_SAVE="$IFS" tab=$'\t'
        IFS=$'\n'
        for line in $(list_prefixes); do
            k="${line%%"$tab"*}"; p="${line#*"$tab"}"
            [ -z "$first" ] && first="$line"
            g="${MPF_GAMEDIR:-}"
            if [ -z "$g" ] || [ ! -f "$g/TransportFever3.exe" ]; then g="$(game_in_prefix "$p")"; fi
            if [ -n "$g" ] && [ -f "$g/TransportFever3.exe" ]; then KIND="$k"; PREFIX="$p"; GAMEDIR="$g"; break; fi
        done
        IFS="$IFS_SAVE"
    fi
    if [ -z "$PREFIX" ]; then
        if [ -z "$first" ]; then
            warn "no Wine bottle found (looked for Whisky, CrossOver and Wine prefixes)."
            warn "Install CrossOver (https://www.codeweavers.com/crossover) or Whisky, make a bottle, install Steam in it"
            warn "(the Windows Steam) and Transport Fever 3 through that Steam, then run this again."
        else
            warn "a Wine bottle was found, but Transport Fever 3 (TransportFever3.exe) is not installed in it."
            warn "Start the Windows Steam in the bottle, install Transport Fever 3 there, then run this again."
            warn "(The Mac version of the game is not the one MPFever works with: see docs/INSTALL-MAC.txt.)"
            warn "If the game is somewhere else, give its folder: MPF_GAMEDIR=\"/path/to/Transport Fever 3\" MPF_PREFIX=\"/path/to/bottle\""
        fi
        return 1
    fi
    WINE="$(find_wine "$KIND")"
    if [ -z "$WINE" ]; then
        warn "no wine program found for the bottle $PREFIX. Install CrossOver, or Whisky, or give MPF_WINE=/path/to/wine64."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------ install

do_install() {
    resolve || return 1
    local src dst
    src="$(find_src)"
    [ -n "$src" ] && [ -f "$src/MPFever.exe" ] || die "MPFever.exe not found: run this from the MPFever folder of the archive (MPFever-x.y.z.zip), or give MPF_SRC."
    [ -f "$src/winhttp.dll" ] || die "winhttp.dll is missing next to MPFever.exe in $src: extract the whole archive again."
    dst="$GAMEDIR/MPFever"
    say "Bottle:    $PREFIX ($KIND)"
    say "Game:      $GAMEDIR"
    say "Wine:      $WINE"
    say "Installing MPFever into: $dst"
    if [ "$DRY" = 1 ]; then
        say "(dry run) cp -R \"$src/.\" \"$dst/\" (without mac/)"
    else
        mkdir -p "$dst" || die "cannot write into $dst"
        # everything but this folder; what is already there stays (its logs and settings), the files of the archive replace the old ones
        local f base
        for f in "$src"/* "$src"/.[!.]*; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            [ "$base" = mac ] && continue
            cp -R "$f" "$dst/" || die "copy of $base failed"
        done
    fi
    conf_set SRC "$src" && conf_set KIND "$KIND" && conf_set PREFIX "$PREFIX" && conf_set GAMEDIR "$GAMEDIR" && conf_set WINE "$WINE" \
        || warn "could not save the choice in $CONF (it is found again next time)."
    say "MPFever installed. Start it with:  bash \"$SELF\" play"
}

# ------------------------------------------------------------------ play

# runs the wine program in the bottle, with what Transport Fever 3 needs on a Mac
wine_run() {
    if [ "$DRY" = 1 ]; then
        say "(dry run) WINEPREFIX=$PREFIX WINEDLLOVERRIDES=\"$WINEDLLOVERRIDES\" ROSETTA_ADVERTISE_AVX=${ROSETTA_ADVERTISE_AVX:-} $WINE $*"
        return 0
    fi
    if [ "$KIND" = crossover ]; then
        "$WINE" --bottle "$(basename "$PREFIX")" "$@"
    else
        WINEPREFIX="$PREFIX" "$WINE" "$@"
    fi
}

steam_running() { pgrep -f -i 'steam\.exe' >/dev/null 2>&1; }

do_play() {
    resolve || return 1
    local mpf="$GAMEDIR/MPFever"
    if [ ! -f "$mpf/MPFever.exe" ] || [ ! -f "$mpf/winhttp.dll" ]; then
        say "MPFever is not installed in the game's folder yet: installing."
        do_install || return 1
    else
        # a newer archive next to this script replaces the installed files (MPFever updates itself too, in place)
        local src
        src="$(find_src)"
        if [ -n "$src" ] && [ -f "$src/MPFever.exe" ] && [ "$src/MPFever.exe" -nt "$mpf/MPFever.exe" ] && ! cmp -s "$src/MPFever.exe" "$mpf/MPFever.exe"; then
            say "A newer MPFever is next to this script: updating."
            do_install || return 1
        fi
    fi
    # What the game and MPFever need under Wine:
    #  - the native module is the game folder's winhttp.dll: Wine must prefer it over its own (native first);
    #  - Rosetta 2 (macOS 15 and later) offers AVX to the game only when asked.
    export WINEDLLOVERRIDES="winhttp=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
    [ "${MPF_AVX:-1}" != 0 ] && export ROSETTA_ADVERTISE_AVX=1
    [ "$KIND" = whisky ] && export WINEMSYNC=1
    export WINEDEBUG="${WINEDEBUG:--all}"
    mkdir -p "$(dirname "$LOG")" 2>/dev/null
    say "Log: $LOG"
    # the game needs Steam running in the same bottle
    if [ "$DRY" != 1 ] && ! steam_running; then
        local steam="$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
        if [ -f "$steam" ]; then
            say "Starting Steam in the bottle (the game needs it)..."
            ( wine_run "C:\\Program Files (x86)\\Steam\\steam.exe" -silent >>"$LOG" 2>&1 & )
            local i=0
            while [ $i -lt 40 ] && ! steam_running; do sleep 1; i=$((i + 1)); done
            sleep 8   # (its sign-in)
        else
            warn "Steam does not seem to be running, and its steam.exe was not found in the bottle: start Steam first."
        fi
    fi
    say "Starting MPFever (it starts Transport Fever 3 itself)..."
    if [ "$DRY" = 1 ]; then
        ( cd "$mpf" 2>/dev/null; wine_run MPFever.exe )
        return 0
    fi
    cd "$mpf" || die "cannot enter $mpf"
    wine_run MPFever.exe >>"$LOG" 2>&1
}

# ------------------------------------------------------------------ doctor

do_doctor() {
    local ok=1 arch os
    arch="$(uname -m)"; os="$(sw_vers -productVersion 2>/dev/null || uname -sr)"
    say "System:    macOS $os, $arch"
    if [ "$arch" = arm64 ]; then
        if /usr/bin/pgrep oahd >/dev/null 2>&1 || [ -f /Library/Apple/usr/share/rosetta/rosetta ]; then say "Rosetta 2: installed"
        else say "Rosetta 2: NOT found (softwareupdate --install-rosetta --agree-to-license)"; ok=0; fi
    fi
    local src; src="$(find_src)"
    if [ -n "$src" ] && [ -f "$src/MPFever.exe" ] && [ -f "$src/winhttp.dll" ]; then say "MPFever:   $src"
    else say "MPFever:   archive not found next to this script (extract the whole MPFever-x.y.z.zip)"; ok=0; fi
    if resolve; then
        say "Bottle:    $PREFIX ($KIND)"
        say "Game:      $GAMEDIR"
        say "Wine:      $WINE"
        if [ -f "$GAMEDIR/MPFever/MPFever.exe" ]; then say "Installed: yes ($GAMEDIR/MPFever)"; else say "Installed: not yet (run: install)"; fi
    else ok=0; fi
    [ "$ok" = 1 ] && say "All set." || say "Something is missing: see above."
    [ "$ok" = 1 ]
}

# ------------------------------------------------------------------ MPFever.app

do_app() {
    local dir="${1:-$HOME/Applications}" app res
    app="$dir/MPFever.app"; res="$app/Contents/Resources"
    mkdir -p "$app/Contents/MacOS" "$res" || die "cannot write into $dir"
    cp "$SELF" "$res/mpfever-mac.sh" || die "cannot copy the script"
    chmod +x "$res/mpfever-mac.sh"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MPFever</string>
    <key>CFBundleDisplayName</key><string>MPFever</string>
    <key>CFBundleIdentifier</key><string>io.github.dkdknight.mpfever.mac</string>
    <key>CFBundleExecutable</key><string>MPFever</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
    cat > "$app/Contents/MacOS/MPFever" <<'LAUNCH'
#!/bin/bash
# starts MPFever through Wine (see Resources/mpfever-mac.sh); the log is ~/Library/Logs/MPFever-mac.log
here="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec /bin/bash "$here/mpfever-mac.sh" play
LAUNCH
    chmod +x "$app/Contents/MacOS/MPFever"
    say "Made $app"
    say "(The folder of the extracted archive is remembered at install: run 'install' once before using the app.)"
}

# ------------------------------------------------------------------ main

cmd="${1:-play}"
case "$cmd" in
    install) do_install ;;
    play)    do_play ;;
    doctor)  do_doctor ;;
    app)     shift; do_app "${1:-}" ;;
    -h|--help|help) sed -n '2,29p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command '$cmd' (install, play, doctor, app)" ;;
esac
