# Verification log — Resurgence v1

Recorded as each task lands. **An unrun step is recorded as "not run", never as a pass.**
Evidence is `logs/games_mp.log` unless stated otherwise. Test rig: iw6-mod dedicated,
`mp_prisonbreak`, `g_gametype dm`, `+set sv_maxclients 4 +set sv_botsAutoJoin 1`,
`scr_resurgence_debug 1`, ring disabled.

## Task 1 — deploy and run

| Step | Result | Evidence |
| --- | --- | --- |
| `deploy.sh` copies sources | **PASS** | `deployed N file(s)` with each path listed |
| Bad `GHOSTS_DIR` refuses | **PASS** | `no data/ directory under /tmp/nope`, `exit=1` |
| Server launches | **PASS** | two `iw6x.exe` processes; `status` returns `map: mp_prisonbreak` |
| `server.cfg` applies | **PASS** after two fixes | `sv_hostname` = `Resurgence Test`, `g_gametype` = `dm` |
| Bots join | **PASS** | `bot1`–`bot4` in `status` |

Two fixes were needed before the config applied at all: it must live in `main/` (the
install root is not on the `exec` path), and every line needs `set` (a bare `name value`
line fails silently for a dvar that is not yet registered).

## Task 2 — replacefunc spike

See `docs/SPIKE-replacefunc.md`. Same-file **and** cross-script `replacefunc` both work;
`logprint` is the only working log channel.

## Task 3 — entry point and callback installation

| Step | Result | Evidence |
| --- | --- | --- |
| Inert with mod off | **PASS** | zero `RSG:` lines, no script error, server healthy |
| Dvars registered, `level.rsg` built | **PASS** | `RSG: init: enabled, squadsize 2, redeploy 15s` |
| Callbacks installed after the gametype | **PASS** | passes 1 and 2 at `0:00`, pass 3 at `0:20` |
| `_gamelogic.gsc` re-assert hook | **ABANDONED** | CBServers restored the file within ~3s; replaced by a thread (ADR-5/ADR-6) |

## Task 4 — squads

| Step | Result | Evidence |
| --- | --- | --- |
| Bots fire `connected` and get assigned | **PASS** | `RSG: squad: StarBerry -> squad 0` |
| Duo packing, `squadsize 2` | **PASS** | `squad 0 [2/2]`, `squad 1 [2/2]` |
| `squadsize` is read, not hardcoded | **PASS** | `squadsize 4` → `squad 0 [4/4]`, one squad |
| Capacity respected on same-frame connects | **PASS after fix** | see below |
| Disconnect frees a seat | **NOT RUN** | `clientkick` / `kick` do nothing over rcon; no second human client available |

**Bug found and fixed here.** The first implementation counted squad members by scanning
`level.players`, but a player is **not yet in `level.players`** when its `connected` notify
fires. Three bots connecting in the same frame therefore all read the same stale count and
piled into one squad — observed as **five players in a squad of four**. In duos that
silently breaks the mode's core rule. Replaced with an authoritative roster
(`level.rsg.roster`) written at assign time and pruned by `isdefined` / `isplayer` on read,
so same-frame connects count each other and a freed entity leaves the count on its own.

**On the unrun step.** `squad_members` prunes entries whose entity is gone, so a
disconnect frees its seat by construction, and `init()` rebuilds the roster per map. But
that is an argument, not evidence. Related observation: bots were replaced across
`map_restart` and **no `left squad` line ever appeared**, so the `disconnect` notify does
not reach our per-player thread for bots. Harmless given the pruning, but it means the
disconnect path is entirely untested. It needs a second human client, or `clientkick`
typed in the server's own console window.

## Rig limitations found

Commands that work over rcon: dvar get/set, `status`, `exec`, `map_restart`, `map_rotate`.

Commands that do **nothing** over rcon, and appear to be console-only:
`addbot`, `bot_team`, `addtestclient`, `spawntestclient`, `clientkick`, `kick`.
Bots can therefore only be produced with `+set sv_botsAutoJoin 1` at launch, and their
count controlled with `+set sv_maxclients N`.

## Task 5 — redeploy

| Step | Result | Evidence |
| --- | --- | --- |
| Our `level.onrespawndelay` is the one invoked | **PASS** | `RSG: respawndelay: Dsso squad 1 -> 10s`, with the value tracking the dvar (20 → 10) |
| ADR-5 works on a real gametype callback | **PASS** | as above — the thread re-assert survives the gametype, no file edit |
| `may_redeploy` true with a living squadmate | **PASS** | `squadmate alive: 1` while the probe showed the squadmate `isalive=1 playing` |
| `eliminate()` makes a player a permanent spectator | **PASS** | `RSG: eliminate: My Flaws (squad 0)`, still `sessionstate=spectator` 19s later |
| The `mayspawn` gate denies an eliminated player | **PASS** | forced a spawn attempt: `RSG: mayspawn: clang eliminated, denied`, stayed spectator while others played |
| Debug backdoor removed | **PASS** | setting `scr_resurgence_debug_eliminate 1` after removal produces zero eliminations |
| Countdown visibly clears mid-wait | **NOT RUN** | needs a human client to see the on-screen timer; the underlying `notify( "end_respawn" )` is exercised by the elimination path |

**The significant bug found here: the stock liveness predicate is wrong for bots.**
`maps\mp\_utility::isreallyalive()` returned false for every bot while the state probe
showed `isalive=1 sessionstate=playing isplayer=1` and the kill log showed them fighting.
Every squad containing a bot would have read as permanently wiped. Replaced throughout by
`_squads::rsg_is_alive` (ADR-7). Before the fix: `squadmate alive: 0` for a bot whose
partner was plainly alive. After: `1`.

**A self-inflicted bug worth recording**, because it shows what the cycle catches: when
removing the temporary debug watcher I sliced out `rsg_mayspawn` along with it. The
`replacefunc` then referenced a missing function, `init()` died, and the entire mod went
silent — no error, just an empty log. Caught immediately because the verification step
expects specific lines and got none.
