#!/bin/bash
# Assemble plugin and converter zip layouts. Does not upload anything.
set -euo pipefail
root="$(cd -- "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
out="$root/dist/release"
stage="$(mktemp -d "${TMPDIR:-/tmp}/kindle-anki-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

fail_if_forbidden() {
  local zip_path="$1"
  local names
  names="$(unzip -Z -1 "$zip_path")"
  if printf '%s\n' "$names" | grep -E '(^|/)foloanki|(^|/)anki_importer\.py$|\.apkg$'; then
    echo "forbidden path inside $zip_path" >&2
    exit 1
  fi
  while IFS= read -r name; do
    case "$name" in
      *.json)
        if unzip -p "$zip_path" "$name" | grep -q '"api_key"'; then
          echo "api_key in $name inside $zip_path" >&2
          exit 1
        fi
        ;;
    esac
  done <<< "$names"
}

mkdir -p "$out"

plugin_stage="$stage/plugin"
mkdir -p "$plugin_stage/kindleanki.koplugin"
cp "$root/plugin/kindleanki.koplugin/"*.lua "$plugin_stage/kindleanki.koplugin/"
plugin_zip="$out/kindleanki.koplugin-v${version}.zip"
( cd "$plugin_stage" && zip -r "$plugin_zip" kindleanki.koplugin )
fail_if_forbidden "$plugin_zip"

conv_stage="$stage/converter"
mkdir -p "$conv_stage/tools" "$conv_stage/docs"
cp "$root/tools/"kindle_*.py "$conv_stage/tools/"
cp "$root/docs/USER_GUIDE.md" "$root/docs/USER_GUIDE.zh_CN.md" "$conv_stage/docs/"
cat > "$conv_stage/Kindle-Anki-Import.command" << 'EOF'
#!/bin/bash
set -euo pipefail
here="$(cd -- "$(dirname "$0")" && pwd)"
cd "$here"
exec python3 "$here/tools/kindle_import_app.py"
EOF
chmod +x "$conv_stage/Kindle-Anki-Import.command"
cat > "$conv_stage/Kindle-Anki-Import.bat" << 'EOF'
@echo off
cd /d "%~dp0"
where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 tools\kindle_import_app.py
  goto :eof
)
where python >nul 2>&1
if %ERRORLEVEL%==0 (
  python tools\kindle_import_app.py
  goto :eof
)
echo Need Python 3. Install it from https://www.python.org/downloads/ then double-click this file again.
pause
EOF
conv_zip="$out/Kindle-Anki-converter-v${version}.zip"
( cd "$conv_stage" && zip -r "$conv_zip" . )
fail_if_forbidden "$conv_zip"

if [[ -d "$root/dist/Kindle Anki Import.app" ]]; then
  mac_zip="$out/Kindle-Anki-Import-macOS-v${version}.zip"
  ( cd "$root/dist" && zip -r "$mac_zip" "Kindle Anki Import.app" )
  fail_if_forbidden "$mac_zip"
fi

if [[ -d "$root/dist/Kindle-Anki-Import" ]]; then
  win_zip="$out/Kindle-Anki-Import-windows-v${version}.zip"
  ( cd "$root/dist" && zip -r "$win_zip" "Kindle-Anki-Import" )
  fail_if_forbidden "$win_zip"
fi

echo "Wrote:"
ls -1 "$out"
