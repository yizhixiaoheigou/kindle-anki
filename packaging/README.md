<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Packaging

Local only. Do not upload Release zips without a separate approval.

## Host tests

```bash
python3 -m unittest discover -s tests -p 'test_kindle_*.py'
```

## Dev environment

The converter and server in `tools/` run on the Python standard library alone.
The venvs below exist only for PyInstaller builds.

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
```

The universal2 build additionally needs an x86_64 CPython venv (any x86_64
Python 3.12, e.g. under `arch -x86_64` or from uv):

```bash
python3 -m venv .venv-x86_64 && .venv-x86_64/bin/pip install -r requirements-dev.txt
```

## macOS .app (universal2)

Unsigned. Gatekeeper: right-click → Open. Apple Silicon and Intel.

```bash
.venv/bin/pyinstaller --noconfirm --clean --distpath dist/arm64 --workpath build/arm64 packaging/kindleanki.spec
arch -x86_64 .venv-x86_64/bin/pyinstaller --noconfirm --clean --distpath dist/x86_64 --workpath build/x86_64 packaging/kindleanki.spec
.venv/bin/python packaging/merge_universal_app.py \
  "dist/arm64/Kindle Anki Import.app" \
  "dist/x86_64/Kindle Anki Import.app" \
  "dist/Kindle Anki Import.app"
```

Output: `dist/Kindle Anki Import.app` (no Terminal window). Icons:
`python3 packaging/make_dock_icon.py` (needs Pillow) rewrites
`packaging/Kindle-Anki-Import.icns` and the Windows
`packaging/Kindle-Anki-Import.ico`.

## Windows onedir

On a Windows machine with Python 3 (Tcl/Tk) from python.org, copy this project
over and run:

```bat
packaging\build_windows.bat
```

The script creates `.venv-windows`, installs PyInstaller, and writes
`dist\Kindle-Anki-Import\Kindle-Anki-Import.exe` (windowed, no console).
Unsigned: SmartScreen may ask for "More info → Run anyway". Copy the
`Kindle-Anki-Import` folder back into `dist/` here so `make_release_zips.sh`
picks it up. `desktop/Kindle-Anki-Import.bat` also finds it there.

## Release zip layouts

```bash
./packaging/make_release_zips.sh 0.1.0
```

Writes into `dist/release/`. Zip A is the plugin. Zip B is the Python fallback
with launchers whose `here` is the zip root. Zip C is the macOS `.app` and
Zip D is the Windows onedir; each is added only if it exists.
