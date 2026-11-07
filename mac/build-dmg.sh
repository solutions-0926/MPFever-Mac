#!/bin/bash
# Builds MPFever-<version>-mac.dmg: MPFever.app with its own Wine inside, the Windows MPFever, and the start script.
# Run it on a Mac (or the macOS runner of GitHub, see .github/workflows/mac-dmg.yml). It needs network access to download Wine.
#
#   bash mac/build-dmg.sh <MPFever-x.y.z.zip | extracted MPFever folder> [output folder]
#
# Settings (all optional):
#   MPF_WINE_TARBALL   a Wine for macOS to use instead of downloading one (a .tar.xz / .tar.gz of a Wine*.app, as the builds
#                      of https://github.com/Gcenx/macOS_Wine_builds are)
#   MPF_WINE_REPO      the GitHub repository whose latest release holds that Wine (default: Gcenx/macOS_Wine_builds)
#   MPF_WINE_PATTERN   the name of its asset, as an extended regular expression (default: wine-staging-.*-osx64\.tar\.xz)
#   MPF_SKIP_DMG=1     stop after the folder that goes into the .dmg (no hdiutil: for tests on another system)
#
# The Wine inside is LGPL software (https://www.winehq.org); its license text stays in the app (Resources/wine/LICENSE*).

set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-}"
OUT="${2:-$PWD/release}"
[ -n "$SRC" ] || { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
# absolute paths: the script changes folder while it works
case "$SRC" in /*) ;; *) SRC="$PWD/$SRC" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mpfever-dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- the Windows MPFever
if [ -f "$SRC" ]; then
    mkdir -p "$WORK/zip" && (cd "$WORK/zip" && unzip -q "$SRC") || { echo "cannot unzip $SRC" >&2; exit 1; }
    MPF="$WORK/zip/MPFever"
else
    MPF="$SRC"
fi
[ -f "$MPF/MPFever.exe" ] && [ -f "$MPF/winhttp.dll" ] || { echo "$MPF has no MPFever.exe / winhttp.dll: give the archive or its MPFever folder" >&2; exit 1; }
# the version: from the archive's name (MPFever-0.7.5.zip), else dev
VERSION=dev
[ -f "$SRC" ] && VERSION="$(basename "$SRC" .zip | sed 's/^MPFever-//')"

# --- Wine
TAR="${MPF_WINE_TARBALL:-}"
if [ -z "$TAR" ]; then
    REPO="${MPF_WINE_REPO:-Gcenx/macOS_Wine_builds}"
    PAT="${MPF_WINE_PATTERN:-wine-staging-.*-osx64\.tar\.xz}"
    echo "Looking for the latest Wine in $REPO ..."
    URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*"\(https[^"]*\)"/\1/' | grep -E "/$PAT\$" | head -n 1)"
    [ -n "$URL" ] || { echo "no asset matching $PAT in the latest release of $REPO" >&2; exit 1; }
    echo "Downloading $URL"
    TAR="$WORK/$(basename "$URL")"
    curl -fL --retry 3 -o "$TAR" "$URL"
fi
mkdir -p "$WORK/wine-src"
tar -xf "$TAR" -C "$WORK/wine-src"
# the Wine of such a build: <something>.app/Contents/Resources/wine (bin, lib, share). Recent Wine has one `wine` for 32 and 64
# bit, older has `wine64`: the app's start script wants wine64, so a link is made when it is missing.
WINEDIR="$(find "$WORK/wine-src" -type d -path '*/Contents/Resources/wine' | head -n 1)"
if [ -z "$WINEDIR" ] || { [ ! -x "$WINEDIR/bin/wine64" ] && [ ! -x "$WINEDIR/bin/wine" ]; }; then
    echo "no Contents/Resources/wine/bin/wine64 (or wine) in $TAR; what it holds:" >&2
    (cd "$WORK/wine-src" && find . -maxdepth 5 | head -n 40) >&2
    exit 1
fi

# --- the app
STAGE="$WORK/stage"
APP="$STAGE/MPFever.app"
RES="$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$RES"
cp -R "$WINEDIR" "$RES/wine"
[ -e "$RES/wine/bin/wine64" ] || ln -s wine "$RES/wine/bin/wine64"
cp -R "$MPF" "$RES/MPFever"
rm -rf "$RES/MPFever/mac"
cp "$HERE/mpfever-mac.sh" "$RES/mpfever-mac.sh"
chmod +x "$RES/mpfever-mac.sh"
cp "$HERE/../LICENSE" "$RES/LICENSE-MPFever.txt"
cp "$HERE/../docs/INSTALL-MAC.txt" "$STAGE/Read me first.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MPFever</string>
    <key>CFBundleDisplayName</key><string>MPFever</string>
    <key>CFBundleIdentifier</key><string>io.github.dkdknight.mpfever.mac</string>
    <key>CFBundleExecutable</key><string>MPFever</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
cat > "$APP/Contents/MacOS/MPFever" <<'LAUNCH'
#!/bin/bash
# starts MPFever with the Wine inside this app; the first start makes the bottle and installs Steam in it.
here="$(cd "$(dirname "$0")/../Resources" && pwd)"
# the Windows MPFever of this app is what gets installed into the game's folder
export MPF_SRC="$here/MPFever"
exec /bin/bash "$here/mpfever-mac.sh" play
LAUNCH
chmod +x "$APP/Contents/MacOS/MPFever"
ln -s /Applications "$STAGE/Applications"

if [ "${MPF_SKIP_DMG:-0}" = 1 ]; then
    mkdir -p "$OUT"; rm -rf "$OUT/dmg-contents"; cp -R "$STAGE" "$OUT/dmg-contents"
    echo "Folder for the .dmg: $OUT/dmg-contents"
    exit 0
fi

# --- sign (ad hoc: Apple Silicon refuses unsigned code), then the .dmg
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" || echo "codesign failed: the app may need  xattr -dr com.apple.quarantine /Applications/MPFever.app" >&2
fi
mkdir -p "$OUT"
DMG="$OUT/MPFever-$VERSION-mac.dmg"
rm -f "$DMG"
hdiutil create -volname "MPFever $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Built $DMG"
