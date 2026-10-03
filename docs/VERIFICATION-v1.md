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
| Disconnect frees a seat | **PASS** | real disconnect: `13:53 Q;bot1;0;StarBerry` left squad 0 (`[2/2] StarBerry Dsso`), and the next joiner took the freed seat (`[2/2] Dsso josep`). The roster pruning works on a genuine disconnect, not just by construction. |

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

## Task 6 — spawning

| Step | Result | Evidence |
| --- | --- | --- |
| FFA spawn classname | **PASS — `mp_dm_spawn` confirmed, 15 points** | probed six candidates: `mp_dm_spawn` 15, `mp_tdm_spawn` 14, `mp_tdm_spawn_axis_start` 9, `mp_tdm_spawn_allies_start` 9, `mp_dm_spawn_start` 0, `mp_global_intermission` 0 |
| Solo path (no living squadmate) | **PASS** | `getspawnpoint: Dsso no living squadmate, random of 15` |
| Squadmate path | **PASS** | `getspawnpoint: Dsso near My Flaws, 193 units, from 15 candidates` |
| Re-evaluated per spawn, not cached | **PASS** | same pair reported 506 and 1053 units on different deaths |
| Squadmates do not spawn stacked | **PASS after fix** | see below |

**Bug found and fixed.** The closest spawn struct to a living squadmate is usually the one
he is standing on, so the first implementation produced spawns **0 units apart** — partners
stacked on a single point, both killed by one grenade and at risk of spawn collision. Added
`scr_resurgence_spawn_min_dist` (default 200) and `closest_to_but_not_on()`: take the
closest candidate at least that far away, falling back to the absolute closest only if
nothing qualifies. After the fix, observed distances were 506, 1053 and 1454 units.

**Known limitation, not a bug.** With only 15 spawn points on this map, "near your
squadmate" is coarse — the nearest qualifying point was sometimes 1454 units away. The rule
picks the closest legal point; it cannot invent one.

**Known regression, flagged for a decision.** Overriding `level.getspawnpoint` discards
whatever enemy-proximity scoring stock `dm` applied, so a redeploy can place you next to an
enemy. The spec only specifies squadmate proximity, so v1 matches the spec, but this is a
real loss of vanilla behaviour and should be an explicit choice rather than an oversight.

## Task 7 — friendly fire

| Step | Result | Evidence |
| --- | --- | --- |
| Squadmate damage blocked | **PASS** | 202 `friendlyfire: blocked` lines, every pair a correct squad member |
| Non-squadmate damage still lands | **PASS** | bracketing run, see below |
| Stock behaviour returns with the mod off | **NOT RUN** | `init()` is unreachable when disabled, so the stock function is untouched by construction; not separately measured |
| **Verified on a human client** | **PASS** | player `josep` in squad 0 with bot `Dsso`: 25 `friendlyfire: blocked josep -> Dsso` lines and **zero** damage events landing on Dsso, while the same player killed `My Flaws` (squad 1) twice with 4 damage events. Both halves, one session, one player — stronger than the bot bracketing below. |

**How non-squadmate damage was verified without a human client.** Bots lock into a futile
duel with their own partner — they spawn together (Task 6) and have no squad awareness, so
every shot they fire is blocked and the log showed 202 blocks with zero damage events. That
looks identical to "the hook blocks everything", so the two cases were bracketed by
squad size instead:

| Config | FF blocks | Damage events | Kills |
| --- | --- | --- | --- |
| `squadsize 1` — no pair is ever a squadmate | 0 | 8 | 3 |
| `squadsize 4` — every pair is a squadmate | 123 | 0 | 0 |

Damage lands when it should and is blocked when it should. Both halves proven.

**Consequence for later tasks: bots are poor opponents in this mode.** Because they shoot
their own squadmate and get blocked, squads do not reliably eliminate each other, so Task 10
(wipes and last-squad-standing) cannot be driven by bot combat alone. It will need either
`squadsize 1` to force hostility, or a human client.

## Task 8 (partial) — the class-selection blocker

Found by putting a human on the server, and it is a **mode-breaking bug that no amount of
bot testing could have surfaced**.

A human client never spawns. `waitforclassselect()` (`_menus.gsc:426`) parks on
`self waittill( "luinotifyserver", var_0, var_1 )` until the client's LUA sends
`class_select`; that notify never arrived, the player sat in spectator, and vanilla's
`kickifdontspawn` (`_playerlogic.gsc:1506`) dropped them after `scr_kick_time` (90s
default) with `EXE_PLAYERKICKED_INACTIVE`. Observed exactly that: joined, never spawned,
kicked for inactivity.

**Bots are immune**, which is why seven tasks' worth of bot verification never saw it:
`_menus.gsc:450` routes them through the `isBot` branch, and `:434`'s condition excludes
them via `!isai( self )`.

Fix, which is what the mode wanted anyway: Resurgence issues one fixed kit, so the class
step should not exist. `_menus.gsc:434` takes the `bypassclasschoice()` branch when
`allowclasschoice()` is false, and `:518` then calls `level.bypassclasschoicefunc`
(`aliens.gsc:50` is the precedent). Both predicates in that condition must be false —
precedence is `a || (b && c)` — so `_loadout::init()` replaces **both**
`_utility::allowclasschoice` and `_utility::showfakeloadout` with `return 0`, and
`install_callbacks()` sets `level.bypassclasschoicefunc` to return `class0`.

| Step | Result | Evidence |
| --- | --- | --- |
| Human spawns with no class menu | **PASS** | `RSG: getspawnpoint: josep no living squadmate, random of 15` immediately after `J;...;josep`, no menu interaction |
| Squadmate redeploys to a living human | **PASS** | `RSG: getspawnpoint: Dsso near josep, 708 units, from 15 candidates` |
| Fixed weapon kit + killstreaks off | **NOT BUILT** | remainder of Task 8 |

**A process note worth keeping.** Before the bypass, the player reached the menu manually
(Esc → Choose Class), selected a class, spawned — and then the game died. That was not a
mod fault: the server was restarted underneath them to deploy this very fix. No crash dumps
were written. Do not restart the server while someone is connected.
