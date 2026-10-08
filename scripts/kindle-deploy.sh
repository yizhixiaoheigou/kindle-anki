#!/usr/bin/env bash
# Push the plugin onto a Kindle over Wi-Fi through KOReader's own SSH server,
# so testing a change needs no USB cable.
#
#   scripts/kindle-deploy.sh <kindle-ip>             install plugin/kindleanki.koplugin
#   scripts/kindle-deploy.sh <kindle-ip> --crash-log print the end of KOReader's crash.log
#   scripts/kindle-deploy.sh <kindle-ip> --rollback  put the previously installed copy back
#   scripts/kindle-deploy.sh <kindle-ip> --restart   restart KOReader (needs --enable-restart once)
#   scripts/kindle-deploy.sh <kindle-ip> --enable-restart
#                       let this Kindle be restarted remotely; afterwards
#                       every install restarts KOReader by itself
#
# The IP may also come from KINDLE_HOST. One-time setup on the Kindle:
# put your public key in koreader/settings/SSH/authorized_keys, then in
# KOReader turn on Tools → More tools → SSH server → "Start SSH server with
# KOReader" and "Login with key only", and start the server.
# KOReader loads plugins at start-up, so it must restart after an install:
# by itself once --enable-restart has been run, or by hand (Exit → Restart
# KOReader).
set -euo pipefail

HOST="${1:-${KINDLE_HOST:-}}"
ACTION="${2:-install}"
PORT="${KINDLE_SSH_PORT:-2222}"
if [ -z "$HOST" ] || [ "${HOST#-}" != "$HOST" ]; then
    echo "usage: $0 <kindle-ip> [--crash-log|--rollback|--restart|--enable-restart]   (or set KINDLE_HOST)" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/plugin/kindleanki.koplugin"
PLUGINS="${KINDLE_PLUGINS_DIR:-/mnt/us/koreader/plugins}"  # override only for tests
TARGET="$PLUGINS/kindleanki.koplugin"
# Kept beside the live copy for --rollback. KOReader only loads folders
# whose name ends in ".koplugin", so this one is ignored.
PREVIOUS="$PLUGINS/.kindleanki.koplugin.previous"
# The plugin restarts KOReader when REQUEST appears, but only on a Kindle
# that has MARKER (see watch_dev_restart in main.lua).
MARKER="${KINDLE_RESTART_MARKER:-/mnt/us/kindle-anki/dev-remote-restart}"
REQUEST="${KINDLE_RESTART_REQUEST:-/tmp/kindle-anki-restart}"

kindle() {
    ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=8 \
        -o StrictHostKeyChecking=accept-new "root@$HOST" "$@"
}

if ! kindle true 2>/dev/null; then
    echo "Cannot reach KOReader's SSH server at $HOST:$PORT." >&2
    echo "Check that KOReader is open, Wi-Fi is on, and Tools → More tools → SSH server is running." >&2
    exit 1
fi

koreader_pid() {
    kindle "ps -o pid,args 2>/dev/null | awk '/[.]\/luajit [.]\/reader[.]lua/ {print \$1; exit}'" 2>/dev/null || true
}

# Ask the plugin to restart KOReader and wait until a new KOReader runs.
restart_koreader() {
    if ! kindle "[ -f '$MARKER' ]"; then
        echo "Remote restart is off on this Kindle. Run: $0 $HOST --enable-restart," >&2
        echo "then restart KOReader by hand once (Exit → Restart KOReader)." >&2
        return 1
    fi
    local before after
    before="$(koreader_pid)"
    kindle "touch '$REQUEST'"
    for _ in $(seq 1 45); do
        sleep 2
        after="$(koreader_pid)"
        if [ -n "$after" ] && [ "$after" != "$before" ]; then
            echo "KOReader restarted."
            return 0
        fi
    done
    if kindle "[ -e '$REQUEST' ]"; then
        kindle "rm -f '$REQUEST'"
        echo "KOReader did not pick up the restart request. Is the running plugin older than" >&2
        echo "remote restart, or is KOReader asleep? Restart it by hand (Exit → Restart KOReader)." >&2
    else
        echo "KOReader took the request but has not come back within 90 s; check the Kindle." >&2
    fi
    return 1
}

case "$ACTION" in
    --restart)
        restart_koreader
        exit $?
        ;;
    --enable-restart)
        kindle "mkdir -p '$(dirname "$MARKER")' && touch '$MARKER'"
        echo "Remote restart enabled. Restart KOReader by hand once so the plugin starts watching."
        exit 0
        ;;
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
if kindle "[ -f '$MARKER' ]"; then
    restart_koreader
else
    echo "Restart KOReader to load it (Exit → Restart KOReader)."
fi
