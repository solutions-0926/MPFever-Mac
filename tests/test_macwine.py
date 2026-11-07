"""The macOS start (mac/mpfever-mac.sh): finds a Wine bottle (Whisky, CrossOver or a plain prefix) with Transport Fever 3 in it,
copies MPFever into the game's folder, and starts MPFever.exe through Wine with the settings the native module needs. Run on
any system with bash: the script runs against a made-up HOME and a wine program that only records how it was called.

    python tests/test_macwine.py
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "mac" / "mpfever-mac.sh"
failed = False


def check(cond, what):
    global failed
    print(("  ok    " if cond else "  FAIL  ") + what)
    failed = failed or not cond


def touch(p, text="x"):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def make_src(base):
    """A made-up MPFever folder of the archive (with the mac folder in it, as in the zip)."""
    src = base / "MPFever"
    touch(src / "MPFever.exe", "exe1")
    touch(src / "winhttp.dll")
    touch(src / "mod" / "mpfever_1" / "mod.json", "{}")
    (src / "mac").mkdir(parents=True, exist_ok=True)
    shutil.copy(SCRIPT, src / "mac" / "mpfever-mac.sh")
    return src


def make_bottle(root, with_game=True, game_rel="drive_c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3"):
    touch(root / "system.reg")
    (root / "drive_c" / "windows").mkdir(parents=True, exist_ok=True)
    if with_game:
        touch(root / game_rel / "TransportFever3.exe")
    return root


def make_wine(path):
    """A wine that writes how it was called (arguments, prefix, overrides, folder) into <path>.calls."""
    touch(path, '#!/bin/bash\n{ echo "args: $*"; echo "prefix: $WINEPREFIX"; echo "overrides: $WINEDLLOVERRIDES"; '
                'echo "avx: $ROSETTA_ADVERTISE_AVX"; echo "msync: $WINEMSYNC"; echo "cwd: $PWD"; } >> "' + str(path) + '.calls"\n')
    path.chmod(0o755)
    return path


def run(home, args, **env):
    pathlib.Path(home).mkdir(parents=True, exist_ok=True)
    e = {"PATH": os.environ["PATH"], "HOME": str(home), "LANG": "C"}
    e.update({k: str(v) for k, v in env.items()})
    p = subprocess.run(["bash", str(SCRIPT)] + args, env=e, capture_output=True, timeout=60, cwd=str(home))
    return p.returncode, (p.stdout + p.stderr).decode("utf-8", "replace")


def make_wine_tarball(base):
    """A made-up Wine build of macOS (Wine Staging.app/Contents/Resources/wine/bin/wine64): a wine that records its calls and makes a bottle."""
    root = base / "tarsrc" / "Wine Staging.app" / "Contents" / "Resources" / "wine"
    w = root / "bin" / "wine64"
    touch(w, '#!/bin/bash\n{ echo "args: $*"; echo "prefix: $WINEPREFIX"; echo "overrides: $WINEDLLOVERRIDES"; } >> "$MPF_TEST_CALLS"\n'
             'if [ "$1" = wineboot ]; then mkdir -p "$WINEPREFIX/drive_c/windows"; echo x > "$WINEPREFIX/system.reg"; fi\n'
             'if [ "${1##*.}" = exe ] && [ "$(basename "$1")" = SteamSetup.exe ]; then mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam"; echo x > "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe"; fi\n')
    w.chmod(0o755)
    touch(root / "lib" / "libwine.dylib")
    tar = base / "wine.tar.gz"
    subprocess.run(["tar", "-czf", str(tar), "-C", str(base / "tarsrc"), "Wine Staging.app"], check=True)
    return tar


def test_dmg(t):
    """build-dmg.sh assembles MPFever.app with its own Wine; the app makes its bottle at the first start, then finds the game."""
    src = make_src(t / "arch-dmg")
    tar = make_wine_tarball(t / "dmgwork")
    out = t / "dmgout"
    p = subprocess.run(["bash", str(ROOT / "mac" / "build-dmg.sh"), str(src), str(out)], capture_output=True, timeout=120,
                       env={"PATH": os.environ["PATH"], "HOME": str(t / "hb"), "MPF_WINE_TARBALL": str(tar), "MPF_SKIP_DMG": "1"})
    check(p.returncode == 0, "build-dmg.sh assembles the app: " + (p.stdout + p.stderr).decode()[-200:].replace("\n", " | "))
    app = out / "dmg-contents" / "MPFever.app" / "Contents"
    check((app / "Resources" / "wine" / "bin" / "wine64").is_file(), "Wine is inside the app")
    check((app / "Resources" / "MPFever" / "MPFever.exe").is_file() and not (app / "Resources" / "MPFever" / "mac").exists(), "the Windows MPFever is inside the app")
    check(os.access(app / "MacOS" / "MPFever", os.X_OK) and (out / "dmg-contents" / "Applications").is_symlink(), "the app starts, Applications link for the drag to install")
    check("CFBundleShortVersionString" in (app / "Info.plist").read_text(), "Info.plist written")

    # first start: no bottle -> setup makes it, a curl that fetches Steam's installer, wine runs it
    home = t / "hb"
    home.mkdir(parents=True, exist_ok=True)
    fakebin = t / "fakebin"
    touch(fakebin / "curl", '#!/bin/bash\nout=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done; echo exe > "$out"\n')
    (fakebin / "curl").chmod(0o755)
    calls = t / "dmg.calls"
    env = {"PATH": str(fakebin) + os.pathsep + os.environ["PATH"], "HOME": str(home), "MPF_TEST_CALLS": str(calls), "WINEDEBUG": "-all"}
    p = subprocess.run([str(app / "MacOS" / "MPFever")], env=env, capture_output=True, timeout=60)
    txt = calls.read_text() if calls.exists() else ""
    prefix = home / "Library/Application Support/MPFever/Prefix"
    check("args: wineboot -u" in txt and "prefix: " + str(prefix) in txt, "first start: wineboot makes the app's own bottle")
    check("SteamSetup.exe" in txt, "first start: the Steam installer is run in it")
    check(p.returncode != 0 and b"not installed in MPFever's bottle" in (p.stdout + p.stderr), "without the game it says to install it in Steam")
    # the player installed the game: next start runs MPFever.exe from the game's folder with winhttp native first
    game = prefix / "drive_c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3"
    touch(game / "TransportFever3.exe")
    calls.unlink()
    p = subprocess.run([str(app / "MacOS" / "MPFever")], env=env, capture_output=True, timeout=60)
    txt = calls.read_text() if calls.exists() else ""
    check(p.returncode == 0 and "args: MPFever.exe" in txt and "overrides: winhttp=n,b" in txt, "with the game: MPFever.exe starts through the app's Wine")
    check((game / "MPFever" / "MPFever.exe").is_file() and (game / "MPFever" / "winhttp.dll").is_file(), "the app's MPFever is installed into the game's folder")
    # other bottles are ignored by the app (it has its own Wine and bottle)
    make_bottle(home / "Library/Containers/com.isaacmarovitz.Whisky/Bottles/X")
    p = subprocess.run(["bash", str(app / "Resources" / "mpfever-mac.sh"), "doctor"], env=env, capture_output=True, timeout=60)
    check(("Bottle:    " + str(prefix)).encode() in p.stdout, "the app keeps to its own bottle, not CrossOver's or Whisky's")


def main():
    if os.name == "nt":
        # (the Windows build runs this too: its "bash" is the WSL launcher, and the scripts are for a Mac. They are tested by the
        # Linux and macOS jobs of the CI)
        print("macOS scripts: not run on Windows (the CI's Linux and macOS jobs run them)")
        return 0
    if shutil.which("bash") is None:
        print("test skipped: no bash")
        return 0
    with tempfile.TemporaryDirectory() as t2:
        test_dmg(pathlib.Path(t2))
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)

        # --- Whisky bottle with the game, MPFever archive next to the script
        home = t / "h1"
        src = make_src(t / "arch1")
        whisky = home / "Library/Containers/com.isaacmarovitz.Whisky/Bottles/AAAA"
        make_bottle(whisky)
        game = whisky / "drive_c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3"
        wine = make_wine(t / "wine1")
        code, out = run(home, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check(code == 0, "install in a Whisky bottle succeeds: " + out.strip().replace("\n", " | ")[:200])
        check((game / "MPFever" / "MPFever.exe").is_file() and (game / "MPFever" / "winhttp.dll").is_file(), "MPFever.exe and winhttp.dll copied into the game's folder")
        check((game / "MPFever" / "mod" / "mpfever_1" / "mod.json").is_file(), "the mod's folder copied")
        check(not (game / "MPFever" / "mac").exists(), "the mac folder itself is not copied")
        conf = (home / "Library/Application Support/MPFever/mac.conf").read_text()
        check("PREFIX=" + str(whisky) in conf and "KIND=whisky" in conf, "the choice is remembered")

        # a log or setting the player has stays when the archive is installed again
        touch(game / "MPFever" / "settings.json", "mine")
        run(home, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check((game / "MPFever" / "settings.json").read_text() == "mine", "installing again keeps the files MPFever made")

        # --- play: through wine, in the game's MPFever folder, native winhttp first
        code, out = run(home, ["play"], MPF_SRC=src, MPF_WINE=wine)
        calls = pathlib.Path(str(wine) + ".calls")
        txt = calls.read_text() if calls.exists() else ""
        check(code == 0, "play exits 0")
        check("args: MPFever.exe" in txt, "wine starts MPFever.exe")
        check("prefix: " + str(whisky) in txt, "WINEPREFIX is the bottle")
        check("overrides: winhttp=n,b" in txt, "winhttp is native first")
        check("avx: 1" in txt and "msync: 1" in txt, "Rosetta AVX and msync for Whisky")
        check(txt.split("cwd: ")[-1].strip().replace("/private", "").endswith("Transport Fever 3/MPFever"), "started from MPFever's own folder")
        calls.unlink()
        run(home, ["play"], MPF_SRC=src, MPF_WINE=wine, MPF_AVX=0)
        check("avx: 1" not in calls.read_text(), "MPF_AVX=0 turns the AVX setting off")

        # --- dry run runs nothing
        calls.unlink()
        code, out = run(home, ["play"], MPF_SRC=src, MPF_WINE=wine, MPF_DRY_RUN=1)
        check(code == 0 and "(dry run)" in out and not calls.exists(), "a dry run prints the command and runs nothing")

        # --- CrossOver bottle: wine is told the bottle by name
        home2 = t / "h2"
        cx = home2 / "Library/Application Support/CrossOver/Bottles/Steam"
        make_bottle(cx)
        wine2 = make_wine(t / "wine2")
        code, out = run(home2, ["play"], MPF_SRC=src, MPF_WINE=wine2)
        txt = pathlib.Path(str(wine2) + ".calls").read_text()
        check(code == 0 and "args: --bottle Steam MPFever.exe" in txt, "CrossOver: wine --bottle <name> MPFever.exe")
        check("msync: 1" not in txt, "no msync outside Whisky")

        # --- a plain prefix, the game in another Steam library inside it
        home3 = t / "h3"
        make_bottle(home3 / ".wine", game_rel="drive_c/Games/SteamLib/steamapps/common/Transport Fever 3")
        code, out = run(home3, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check(code == 0 and (home3 / ".wine/drive_c/Games/SteamLib/steamapps/common/Transport Fever 3/MPFever/MPFever.exe").is_file(), "a plain ~/.wine prefix, game in another library, is found")

        # --- the first bottle without the game is skipped
        home4 = t / "h4"
        make_bottle(home4 / "Library/Containers/com.isaacmarovitz.Whisky/Bottles/EMPTY", with_game=False)
        make_bottle(home4 / "Library/Containers/com.isaacmarovitz.Whisky/Bottles/ZZZ")
        code, out = run(home4, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check(code == 0 and "ZZZ" in out, "a bottle without the game is skipped for one that has it")

        # --- explicit settings win
        home5 = t / "h5"
        mine = make_bottle(t / "mybottle")
        code, out = run(home5, ["install"], MPF_SRC=src, MPF_WINE=wine, MPF_PREFIX=mine)
        check(code == 0 and (mine / "drive_c/Program Files (x86)/Steam/steamapps/common/Transport Fever 3/MPFever/MPFever.exe").is_file(), "MPF_PREFIX picks the bottle")

        # --- the messages when something is missing
        home6 = t / "h6"
        home6.mkdir()
        code, out = run(home6, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check(code != 0 and "no Wine bottle found" in out, "no bottle: says what to install")
        make_bottle(home6 / "Library/Containers/com.isaacmarovitz.Whisky/Bottles/NOGAME", with_game=False)
        code, out = run(home6, ["install"], MPF_SRC=src, MPF_WINE=wine)
        check(code != 0 and "not installed in it" in out, "a bottle without the game: says to install it there")
        code, out = run(home, ["install"], MPF_SRC=t / "nowhere", MPF_WINE=wine)
        check(code != 0 and "MPFever.exe not found" in out, "no MPFever archive: says so")
        nodll = make_src(t / "arch2")
        (nodll / "winhttp.dll").unlink()
        code, out = run(home, ["install"], MPF_SRC=nodll, MPF_WINE=wine)
        check(code != 0 and "winhttp.dll is missing" in out, "an archive without winhttp.dll is refused")
        code, out = run(home, ["nonsense"])
        check(code != 0 and "unknown command" in out, "unknown command refused")

        # --- the .app
        code, out = run(home, ["app", str(t / "apps")], MPF_SRC=src)
        app = t / "apps" / "MPFever.app" / "Contents"
        check(code == 0 and (app / "MacOS" / "MPFever").is_file() and os.access(app / "MacOS" / "MPFever", os.X_OK), "MPFever.app made with an executable")
        check((app / "Info.plist").is_file() and "CFBundleExecutable" in (app / "Info.plist").read_text(), "Info.plist written")
        calls = pathlib.Path(str(wine) + ".calls")
        calls.unlink(missing_ok=True)
        e = {"PATH": os.environ["PATH"], "HOME": str(home), "MPF_WINE": str(wine)}
        p = subprocess.run([str(app / "MacOS" / "MPFever")], env=e, capture_output=True, timeout=60)
        check(p.returncode == 0 and "args: MPFever.exe" in (calls.read_text() if calls.exists() else ""), "the app starts MPFever through the remembered bottle")

        # --- syntax for the bash 3.2 of macOS: nothing of bash 4
        text = SCRIPT.read_text()
        check("declare -A" not in text and "mapfile" not in text and "readarray" not in text, "no bash 4 features (macOS has bash 3.2)")
        check("readlink -f" not in text and "-printf" not in text and "sed -r" not in text, "no GNU-only options (macOS has the BSD tools)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
