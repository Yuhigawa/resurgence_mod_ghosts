#!/usr/bin/env bash
# Copy mod sources into the Ghosts install. Copies, never deletes:
# the game is a Windows process reading NTFS, and WSL symlinks are not
# followed by Windows applications.
set -euo pipefail

GHOSTS_DIR="${GHOSTS_DIR:-/mnt/d/games/cod_cbservers/ghosts_game_files}"
SRC="$(cd "$(dirname "$0")" && pwd)/src/data"

if [ ! -d "$GHOSTS_DIR/data" ]; then
    echo "error: no data/ directory under $GHOSTS_DIR" >&2
    echo "       set GHOSTS_DIR to the install root" >&2
    exit 1
fi

if [ ! -d "$SRC" ]; then
    echo "error: no sources at $SRC" >&2
    exit 1
fi

echo "deploying $SRC -> $GHOSTS_DIR/data"
count=0
while IFS= read -r -d '' file; do
    rel="${file#"$SRC"/}"
    dest="$GHOSTS_DIR/data/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    echo "  $rel"
    count=$((count + 1))
done < <(find "$SRC" -type f ! -name '.gitkeep' -print0)

echo "deployed $count file(s)"

# server.cfg goes in main/, NOT the install root: `exec` only searches the
# fs path, and a copy at the root is silently ignored -- verified by exec'ing
# both and watching sv_hostname. Nothing auto-execs it either way, so it is
# still named on the command line (+exec server.cfg).
if [ -f "$(dirname "$0")/config/server.cfg" ]; then
    mkdir -p "$GHOSTS_DIR/main"
    cp "$(dirname "$0")/config/server.cfg" "$GHOSTS_DIR/main/server.cfg"
    echo "  server.cfg -> $GHOSTS_DIR/main/server.cfg"
fi
