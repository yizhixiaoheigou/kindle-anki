#!/bin/bash
# Double-click on macOS to open the Kindle Anki converter.
set -euo pipefail
here="$(cd -- "$(dirname "$0")" && pwd)"
root="$(cd -- "$here/.." && pwd)"
cd "$root"
if [[ -d "$root/dist/Kindle Anki Import.app" ]]; then
  exec open "$root/dist/Kindle Anki Import.app"
fi
if ! command -v python3 >/dev/null 2>&1; then
  osascript -e 'display alert "Need python3" message "Install Python 3, then double-click this file again."'
  exit 1
fi
exec python3 "$root/tools/kindle_import_app.py"
