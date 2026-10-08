#!/usr/bin/env bash
# Push the plugin onto a Kindle over Wi-Fi through KOReader's own SSH server,
# so testing a change needs no USB cable.
#
#   scripts/kindle-deploy.sh <kindle-ip>             install plugin/kindleanki.koplugin
#   scripts/kindle-deploy.sh <kindle-ip> --crash-log print the end of KOReader's crash.log
#   scripts/kindle-deploy.sh <kindle-ip> --rollback  put the previously installed copy back
#
# The IP may also come from KINDLE_HOST. One-time setup on the Kindle:
# put your public key in koreader/settings/SSH/authorized_keys, then in
# KOReader turn on Tools → More tools → SSH server → "Start SSH server with
# KOReader" and "Login with key only", and start the server.
# KOReader loads plugins at start-up, so restart it after installing
# (Exit → Restart KOReader).
set -euo pipefail

HOST="${1:-${KINDLE_HOST:-}}"
ACTION="${2:-install}"
PORT="${KINDLE_SSH_PORT:-2222}"
if [ -z "$HOST" ] || [ "${HOST#-}" != "$HOST" ]; then
    echo "usage: $0 <kindle-ip> [--crash-log|--rollback]   (or set KINDLE_HOST)" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/plugin/kindleanki.koplugin"
PLUGINS="${KINDLE_PLUGINS_DIR:-/mnt/us/koreader/plugins}"  # override only for tests
TARGET="$PLUGINS/kindleanki.koplugin"
# Kept beside the live copy for --rollback. KOReader only loads folders
# whose name ends in ".koplugin", so this one is ignored.
PREVIOUS="$PLUGINS/.kindleanki.koplugin.previous"

kindle() {
    ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=8 \
        -o StrictHostKeyChecking=accept-new "root@$HOST" "$@"
}

if ! kindle true 2>/dev/null; then
    echo "Cannot reach KOReader's SSH server at $HOST:$PORT." >&2
    echo "Check that KOReader is open, Wi-Fi is on, and Tools → More tools → SSH server is running." >&2
    exit 1
fi

case "$ACTION" in
    --crash-log)
        kindle "tail -n 60 /mnt/us/koreader/crash.log"
        exit 0
        ;;
    --rollback)
        kindle "set -e; [ -d '$PREVIOUS' ] || { echo 'no previous copy on the Kindle' >&2; exit 1; }
            rm -rf '$TARGET.rollback'; mv '$TARGET' '$TARGET.rollback'
            mv '$PREVIOUS' '$TARGET'; rm -rf '$TARGET.rollback'"
        echo "Rolled back. Restart KOReader (Exit → Restart KOReader)."
        exit 0
        ;;
    install) ;;
    *)
        echo "unknown action: $ACTION" >&2
        exit 2
        ;;
esac

# Unpack beside the live copy, then swap, so a dropped connection never
# leaves a half-written plugin behind.
COPYFILE_DISABLE=1 tar -C "$SOURCE" --exclude '._*' --exclude '.DS_Store' -cf - . |
    kindle "set -e; rm -rf '$TARGET.incoming'; mkdir -p '$TARGET.incoming'
        tar -xf - -C '$TARGET.incoming'
        rm -rf '$PREVIOUS'
        if [ -d '$TARGET' ]; then mv '$TARGET' '$PREVIOUS'; fi
        mv '$TARGET.incoming' '$TARGET'; sync"

# Same "hash  ./path" lines as the Kindle's busybox md5sum; macOS has md5.
file_md5() {
    if command -v md5sum >/dev/null; then md5sum "$1"; else printf '%s  %s\n' "$(md5 -q "$1")" "$1"; fi
}
local_sums="$(cd "$SOURCE" && find . -type f ! -name '._*' ! -name '.DS_Store' | LC_ALL=C sort |
    while IFS= read -r file; do file_md5 "$file"; done)"
remote_sums="$(kindle "cd '$TARGET' && find . -type f | LC_ALL=C sort | while IFS= read -r file; do md5sum \"\$file\"; done")"
if [ "$local_sums" != "$remote_sums" ]; then
    echo "Installed files differ from $SOURCE:" >&2
    diff <(echo "$local_sums") <(echo "$remote_sums") >&2 || true
    exit 1
fi
count="$(echo "$local_sums" | wc -l | tr -d ' ')"
echo "Installed $count files to $HOST:$TARGET and verified them."
echo "Restart KOReader to load it (Exit → Restart KOReader)."
