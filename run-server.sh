#!/usr/bin/env bash
# Start a Resurgence session.
#
#   ./run-server.sh              9 bots, 3 human slots
#   BOTS=5 HUMANS=1 ./run-server.sh
#   SQUADSIZE=2 ./run-server.sh  duos instead of solos
#
# Bots can only be created by sv_botsAutoJoin at launch, and it fills every
# slot, so we start with sv_maxclients = BOTS, let them fill it, then raise
# the cap over rcon to open slots for people. Bots do not backfill the new
# slots because autojoin only runs at map load.
set -euo pipefail

GHOSTS_DIR="${GHOSTS_DIR:-/mnt/d/games/cod_cbservers/ghosts_game_files}"
BOTS="${BOTS:-9}"
HUMANS="${HUMANS:-3}"
PORT="${PORT:-28960}"
SQUADSIZE="${SQUADSIZE:-1}"
RCON_PASSWORD="${RCON_PASSWORD:-rsgdev-local}"
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/deploy.sh" >/dev/null
echo "deployed"

taskkill.exe /IM iw6x.exe /F >/dev/null 2>&1 || true
sleep 2
rm -f "$GHOSTS_DIR/logs/games_mp.log"

cd "$GHOSTS_DIR"
nohup ./iw6x.exe -dedicated \
    +set net_port "$PORT" \
    +set rcon_password "$RCON_PASSWORD" \
    +exec server.cfg \
    +set sv_maxclients "$BOTS" \
    +set sv_botsAutoJoin 1 \
    +set scr_resurgence_squadsize "$SQUADSIZE" \
    +map_rotate >/dev/null 2>&1 &

printf "waiting for %d bots" "$BOTS"
for _ in $(seq 1 14); do printf "."; sleep 5; done
echo

RCON_PASSWORD="$RCON_PASSWORD" "$HERE/tools/rcon.py" "set sv_maxclients $((BOTS + HUMANS))" >/dev/null 2>&1 || true

echo
echo "ready — connect to 127.0.0.1:$PORT"
echo "  squads of $SQUADSIZE, $BOTS bots, $HUMANS human slot(s)"
echo
grep -E "RSG: init:|zone: center" "$GHOSTS_DIR/logs/games_mp.log" 2>/dev/null | sed 's/^ *//' || true
