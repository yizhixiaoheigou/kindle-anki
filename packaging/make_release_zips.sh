#!/bin/bash
# Assemble the plugin zip and the offline converter page. Does not upload anything.
set -euo pipefail
root="$(cd -- "$(dirname "$0")/.." && pwd)"
version="${1:-$(sed -n 's/.*"CFBundleShortVersionString": *"\([^"]*\)".*/\1/p' "$root/packaging/kindleanki.spec" | head -n 1)}"
version="${version:-0.1.0}"
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
cp "$root/plugin/kindleanki.koplugin/LICENSE" "$plugin_stage/kindleanki.koplugin/"
# The browser import page (:8767) is served from the plugin's own web/.
cp -R "$root/plugin/kindleanki.koplugin/web" "$plugin_stage/kindleanki.koplugin/"
plugin_zip="$out/kindleanki.koplugin-v${version}.zip"
rm -f "$plugin_zip"
( cd "$plugin_stage" && zip -r "$plugin_zip" kindleanki.koplugin )
fail_if_forbidden "$plugin_zip"
if ! unzip -Z -1 "$plugin_zip" | grep -qx 'kindleanki.koplugin/web/index.html'; then
  echo "web/ missing from $plugin_zip" >&2
  exit 1
fi

# The computer converter is the same browser page as one offline HTML file;
# the Tk app and its macOS/Windows builds are no longer released.
html="$out/Kindle-Anki-converter-v${version}.html"
python3 "$root/packaging/build_standalone_html.py" "$html" >/dev/null
if grep -qE '<script[^>]*[[:space:]]src=' "$html"; then
  echo "external script in $html" >&2
  exit 1
fi
rm -f "$out/Kindle-Anki-converter-v${version}.zip" \
  "$out/Kindle-Anki-Import-macOS-v${version}.zip" \
  "$out/Kindle-Anki-Import-windows-v${version}.zip"

echo "Wrote:"
ls -1 "$out"
