# Running the server

Everything here was verified against the install on 2026-10-02, not inferred.

## Launch

From the install directory, in WSL (Windows interop runs the exe directly):

```bash
cd /mnt/d/games/cod_cbservers/ghosts_game_files && ./iw6x.exe -dedicated +set net_port 28960 +set rcon_password <your-password> +exec server.cfg +map_rotate
```

- `-dedicated` **works** as written; the `+set dedicated 2` fallback was not needed.
- `+exec server.cfg` is required. Nothing auto-execs it.
- Two `iw6x.exe` processes appear (~1.1 GB and ~1.9 GB resident). That is normal.
- Stop it with `taskkill.exe /IM iw6x.exe /F`.

Confirm it came up:

```bash
RCON_PASSWORD=<your-password> tools/rcon.py "status"
```

## server.cfg must live in `main/`

`exec` searches the filesystem path, and **`main/` is on it while the install root is
not**. A `server.cfg` at the install root is silently ignored — no error, no warning,
every dvar simply stays at its default. This was verified by exec'ing both locations and
watching `sv_hostname`: at the root it stayed `CoD4Host`, from `main/` it became
`Resurgence Test`.

`deploy.sh` copies `config/server.cfg` to `$GHOSTS_DIR/main/server.cfg` for this reason.

## Console output goes to a log file, not to WSL

Launching from WSL yields **no stdout** — the server writes to its own console window.
But `logstring()` output lands in a file that is readable from WSL:

```
/mnt/d/games/cod_cbservers/ghosts_game_files/logs/games_mp.log
```

That is the verification channel for every task. Follow it with:

```bash
tail -f /mnt/d/games/cod_cbservers/ghosts_game_files/logs/games_mp.log
```

Do **not** pass `+set g_log 1`. `g_log` is a *filename* dvar whose default is already
`logs/games_mp.log`; setting it to `1` creates a file literally named `1`.

The log records kills in the form
`k;<victim>;<id>;<team>;<name>;<attacker>;<id>;<team>;<name>;<weapon>;<damage>;<MOD>;<hitloc>`,
which is useful well beyond our own `RSG:` lines.

## rcon

`component@rcon` is present in the binary, so the standard Quake3 out-of-band packet
works and `tools/rcon.py` wraps it:

```bash
export RCON_PASSWORD=<your-password>
tools/rcon.py "status"
tools/rcon.py "spawn_bot 3"
tools/rcon.py "scr_resurgence_squadsize 3"
tools/rcon.py "map_restart"
```

The password is **never committed** — this repo is public. Pass it at launch with
`+set rcon_password` and export the same value as `RCON_PASSWORD`.

**Replies drop under load.** With 18 bots fighting, a 1.5 s read window times out and the
tool reports the server as down while it is perfectly healthy. The default is now 5 s with
4 retries; raise `--timeout` further if a command looks unanswered. Confirm liveness with
`tasklist.exe | grep -i iw6x` and by watching the log grow before concluding anything
crashed.

## Bots

`sv_botsAutoJoin 1` fills **every one of the 18 slots** within seconds — far too many to
observe duo behaviour in. `config/server.cfg` therefore sets it to `0`, and bots are added
deliberately:

```bash
tools/rcon.py "spawn_bot 3"
```

Bots are real players: they appear in `status`, they are logged by name, and they fight
with real loadouts. They are the reason tasks 5 and 10 are verifiable at all.

Also attested: `bot_team`, `bot_team_join`, `addbot`, `addtestclient`,
`spawntestclient`.

## Two things the first run established for later tasks

**Real MP weapon names exist and are now known.** Harvested from kill lines, which
resolves the open question in Task 8 — these no longer need guessing:

```
iw6_p226_mp      iw6_m9a1_mp     iw6_microtar_mp  iw6_kriss_mp
iw6_imbel_mp     iw6_fads_mp     iw6_m27_mp       iw6_bren_mp
iw6_vepr_mp      iw6_l115a3_mp   iw6_fp6_mp
```

Attachments append to the base name (`iw6_microtar_mp_acogsmg_flashsuppress_scope1`), so
the base name alone is a valid weapon.

**`dm` is genuinely not team-based.** Bots are assigned nominal `axis` / `allies` values
and the log shows `bot4;axis` damaging `bot10;axis` freely, so the `.team` field is
cosmetic under `dm` and `level.teambased` is 0. That is what `_friendlyfire` assumes, and
Task 3's debug output should log `level.teambased` once to confirm it directly rather than
by inference from damage behaviour.

## Joining as a client

The server binds `net_port 28960` on the same machine. Launch the game normally and
connect to `127.0.0.1:28960` from the server browser or console. A human client is
required for the steps bots cannot do — walking out of the ring in Task 9, and changing
class mid-grace-period in Task 8.
