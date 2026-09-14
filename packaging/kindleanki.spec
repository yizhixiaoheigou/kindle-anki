# -*- mode: python ; coding: utf-8 -*-
"""Windowed converter. macOS: build once per arch, then merge with merge_universal_app.py.
Windows: produces the dist/Kindle-Anki-Import onedir."""

import sys
from pathlib import Path

root = Path(SPECPATH).resolve().parent

exe_kwargs = {}
if sys.platform == "win32":
    exe_kwargs["icon"] = str(root / "packaging" / "Kindle-Anki-Import.ico")

a = Analysis(
    [str(root / "tools" / "kindle_import_app.py")],
    pathex=[str(root / "tools")],
    binaries=[],
    datas=[
        (str(root / "docs" / "USER_GUIDE.md"), "docs"),
        (str(root / "docs" / "USER_GUIDE.zh_CN.md"), "docs"),
    ],
    hiddenimports=[
        "kindle_anki_importer",
        "kindle_apkg",
        "kindle_bundle",
        "kindle_cards",
        "kindle_pack_server",
        "kindle_import_ui",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["anki_importer", "folo_cards", "folo_package"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Kindle-Anki-Import",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    **exe_kwargs,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name="Kindle-Anki-Import",
)

if sys.platform == "darwin":
    app = BUNDLE(
        coll,
        name="Kindle Anki Import.app",
        icon=str(root / "packaging" / "Kindle-Anki-Import.icns"),
        bundle_identifier="dev.kindleanki.import",
        info_plist={
            "CFBundleName": "Kindle Anki Import",
            "CFBundleDisplayName": "Kindle Anki Import",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "0.1.0",
            "LSMinimumSystemVersion": "11.0",
            "NSHighResolutionCapable": True,
            "NSAppleEventsUsageDescription": "Open the user guide in a browser.",
        },
    )
