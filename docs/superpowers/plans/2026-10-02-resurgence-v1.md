# Resurgence v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a playable Warzone-style Resurgence mode on a Call of Duty: Ghosts (IW6) dedicated server — virtual squads in free-for-all, redeploy while a squadmate lives, permanent elimination on squad wipe, spawn near squad, a shrinking lethal ring, killstreak-free loadouts, and last-squad-standing victory.

**Architecture:** Server-side GSC only. `g_gametype dm` runs and Resurgence layers on top via an auto-loaded entry script plus six single-purpose modules, all inert unless `scr_resurgence_enabled 1`. Hooks are installed twice (in `init()` and again after `[[ level.onstartgametype ]]()`) so gametype load order cannot silently win. Sources live in this repo and are copied into the game install by `deploy.sh`.

**Tech Stack:** IW6 GSC (plain-text, loaded from the game's `data/` — no compile step), `replacefunc` from the server's script extensions, bash for deployment. Design doc: `docs/superpowers/specs/2026-10-02-resurgence-design.md`.

## Global Constraints

- **Game install (deploy target):** `/mnt/d/games/cod_cbservers/ghosts_game_files` — overridable via `GHOSTS_DIR`.
- **Repo sources:** everything under `src/data/`, mirroring the install's `data/` layout exactly.
- **Namespace rule:** `data/` is the script root, so `src/data/scripts/mp/resurgence/_squads.gsc` is addressed in GSC as `scripts\mp\resurgence\_squads`.
- **Master switch:** `scr_resurgence_enabled` defaults to `0`. Every module returns immediately when it is 0. A broken build is disabled by dvar, never by deleting files.
- **Required server config:** `g_gametype dm`, `scr_friendlyfire 0`, `scr_dm_numlives 0`. ADR-2 depends on `numlives` staying 0 and `level.disablespawning` never being set.
- **Never modify a file CBServers ships.** The platform restores them within ~3s of launch, silently and before scripts load (ADR-6, found in Task 3). `src/data/` holds only new files; every hook goes through `replacefunc` or a `level.*` pointer, both verified working.
- **`rsg_log` uses `logprint( "...\n" )`.** `logstring` and `println` write nothing to the log on this build. Output appears in `logs/games_mp.log`, readable from WSL.
- **Define `init()` only, never `main()`.** The loader enters both on the same file, so defining both wires everything twice.
- **`init()` must not read gametype `level` state** (`level.teambased`, `level.gametype`) — it runs before the gametype and that is a script error, not a value.
- **`#include common_scripts\utility;`** is required for `max()` and friends; without it a script dies silently mid-function.
- Config lines need **`set`**: a bare `name value` line only works for an already-registered dvar and fails silently for ours.
- **No death hook.** `level.onplayerkilled` is deliberately never assigned (spec: "No death hook anywhere").
- **Player field prefix:** `rsg_`. Level state lives on `level.rsg` (a `spawnstruct()`), except the two zone values `level.rsg_center` / `level.rsg_radius` named in the spec.
- **Logging:** all debug output goes through `scripts\mp\_resurgence::rsg_log()`, gated on `scr_resurgence_debug`.

## Testing Reality — read before Task 1

**There is no GSC test harness and none can be built here.** GSC runs only inside the game server; there is no interpreter, no assertion library, no way to call a function from outside a match. So the TDD cycle in this plan is adapted, not skipped:

- **"Write the failing test"** means: add a `rsg_log()` line (or a temporary debug thread) that will print a specific, checkable string, and know what output proves the behaviour.
- **"Run it to verify it fails"** means: deploy, start the server, join, perform the in-game action, and confirm the expected line is **absent** or shows the wrong value.
- **"Run it to verify it passes"** means: the same loop, confirming the exact expected line.

This makes each task's verification slower than a unit test but no less binding: **no step may be checked off on the basis of reading the code.** Every `- [ ]` that says "observe" requires the actual console line or in-game observation. If a step cannot be verified, say so and stop rather than marking it done.

Multiple players come from bots: `spawn_bot` (see Task 1 Step 6). Bots are real entities in
`level.players`, so they are squad-assigned, killable, and count for wipe detection — but
they will not walk out of the ring on command, so Task 9's out-of-ring damage must be
verified with a real client.

`rsg_log()` writes via `logstring()`, which is attested in the local overlay (`_gamelogic.gsc:97`). Console visibility of `logstring` on this server build is itself unproven — **Task 2 Step 2 establishes it**, and if `logstring` is not visible, every later task substitutes `iprintln()` (in-game text, attested at `_gamelogic.gsc:96`) as the debug channel. Do not proceed past Task 2 without a working debug channel; everything downstream depends on being able to see output.

## File Structure

| Path | Responsibility |
| --- | --- |
| `deploy.sh` | Copy `src/data/` into `$GHOSTS_DIR/data/`. Never deletes. Prints what it wrote. |
| `config/server.cfg` | Server config: gametype, the Resurgence dvars, bot auto-join, map rotation. Deployed to the install root. |
| `docs/RUNNING.md` | How to start the server and where its console output goes. Written in Task 1. |
| `src/data/scripts/mp/_resurgence.gsc` | Entry point: dvar registration, `level.rsg` state, `rsg_log()`, module wiring, `install_callbacks()`. No gameplay logic. |
| `src/data/scripts/mp/resurgence/_squads.gsc` | Sole owner of squad membership and the queries over it. |
| `src/data/scripts/mp/resurgence/_redeploy.gsc` | `mayspawn` replacement, redeploy delay, elimination of a player. |
| `src/data/scripts/mp/resurgence/_spawning.gsc` | `level.getspawnpoint` — in-ring spawn nearest a living squadmate. |
| `src/data/scripts/mp/resurgence/_friendlyfire.gsc` | `attackerishittingteam` replacement — squadmates cannot damage each other. |
| `src/data/scripts/mp/resurgence/_loadout.gsc` | `level.custom_giveloadout` — clear slate, killstreaks off. |
| `src/data/scripts/mp/resurgence/_zone.gsc` | Ring state, phase schedule, out-of-ring damage. |
| `src/data/scripts/mp/resurgence/_win.gsc` | Wipe detection, elimination, last-squad-standing end. |
| `src/data/maps/mp/gametypes/_gamelogic.gsc` | Copy of the install's file + the ADR-5 re-assert hook (Task 3). |
| `src/data/maps/mp/gametypes/_menus.gsc` | Copy of the install's file + two `custom_giveloadout` guards (Task 7). |

Dependency order: `_squads` is the root — `_redeploy`, `_spawning`, `_friendlyfire` and `_win` all query it. `_zone` is queried by `_spawning`. `_loadout` depends on nothing.

---

### Task 1: Deployment and the ability to run the server

**Files:**
- Create: `deploy.sh`
- Create: `config/server.cfg`
- Create: `docs/RUNNING.md`
- Create: `src/data/scripts/mp/resurgence/.gitkeep`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `./deploy.sh` copies `src/data/**` to `$GHOSTS_DIR/data/**`, defaulting `GHOSTS_DIR=/mnt/d/games/cod_cbservers/ghosts_game_files`. Every later task's verification begins by running it.

- [ ] **Step 1: Write `deploy.sh`**

```bash
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

# server.cfg lives beside the binary, not under data/. Nothing in the
# binary auto-execs it; it is named on the command line (+exec server.cfg).
if [ -f "$(dirname "$0")/config/server.cfg" ]; then
    cp "$(dirname "$0")/config/server.cfg" "$GHOSTS_DIR/server.cfg"
    echo "  server.cfg -> $GHOSTS_DIR/server.cfg"
fi
```

- [ ] **Step 2: Make it executable and run it against an empty source tree**

```bash
cd ~/ws/personal/resurgence_mod_ghost
mkdir -p src/data/scripts/mp/resurgence && touch src/data/scripts/mp/resurgence/.gitkeep
chmod +x deploy.sh && ./deploy.sh
```

Expected: `deploying ... -> /mnt/d/games/cod_cbservers/ghosts_game_files/data` then `deployed 0 file(s)`. This proves the path resolution and the install check before any GSC exists. If it reports the `no data/ directory` error, `GHOSTS_DIR` is wrong — fix it before continuing.

- [ ] **Step 3: Verify the guard rails**

```bash
cd ~/ws/personal/resurgence_mod_ghost && GHOSTS_DIR=/tmp/nope ./deploy.sh; echo "exit=$?"
```

Expected: the `no data/ directory under /tmp/nope` error and `exit=1`. A deploy script that silently writes to the wrong place is worse than none.

- [ ] **Step 4: Write `config/server.cfg`**

`iw6x.exe` is CBServers' iw6-mod and ships a dedicated-server component — confirmed by
the RTTI symbols `component@dedicated` / `component@dedicated_info`, `isdedicatedserver`,
the banner strings `iw6-mod Dedicated Server` and `Server started!`, and the dvars
`sv_hostname`, `sv_maxclients`, `sv_mapRotation`, `net_port`, `sv_lanOnly`, `map_rotate`.
The dedicated path sets `onlinegame 1`, `xblive_privatematch 0`, calls
`xstartprivatematch` itself and preloads the `*_mp` fastfiles, so it brings up MP with no
lobby. There is **no** `server.cfg` string literal in the binary — nothing auto-execs it,
so it must be named on the command line.

Create `config/server.cfg`:

```
sv_hostname "Resurgence Test"
sv_maxclients 18
g_gametype dm
scr_friendlyfire 0
scr_dm_numlives 0
scr_dm_playerrespawndelay 0
scr_dm_scorelimit 0
scr_dm_timelimit 0

scr_resurgence_enabled 1
scr_resurgence_debug 1
scr_resurgence_squadsize 2
scr_resurgence_zone_enabled 0

sv_botsAutoJoin 1

sv_mapRotation "gametype dm map mp_prisonbreak"
```

Both limits are `0` and the ring starts **off** on purpose: the first several verification
cycles should not be fighting a shrinking zone or a match that ends on the clock. Task 9
turns the zone on.

- [ ] **Step 5: Start the server**

From the install directory:

```bash
cd /mnt/d/games/cod_cbservers/ghosts_game_files && ./iw6x.exe -dedicated +set net_port 28960 +exec server.cfg +map_rotate
```

If `-dedicated` is not picked up, try `+set dedicated 2` (`2` = internet, `1` = LAN) — the
dvar exists in the binary, but the arg parser's accepted spelling is not visible because
the dash is stripped before the string lands. `-headless` additionally suppresses the
window.

Expected: the `iw6-mod Dedicated Server` banner and `Server started!`. A useful
independent confirmation: `verifydedicatedconfiguration` (`_gamelogic.gsc:1664-1665`) runs
only when `getdvar( "dedicated" )` is `dedicated LAN server` or
`dedicated internet server`, so if that dvar holds either string, the server itself agrees
it is dedicated.

- [ ] **Step 6: Get a second and third client in — verify bots work**

Several later tasks need 2-4 players, and the two most valuable (redeploy in Task 5,
win conditions in Task 10) are unreachable with one client. iw6-mod has bot support. `component@bots` is real and registers console
commands via its `post_unpack( params@command& )`: `spawn_bot`, `bot_team`,
`bot_team_join` and `addbot`, alongside `addtestclient` / `spawntestclient` /
`canspawntestclient` and the `sv_botsAutoJoin` dvar set in Step 4.

On the running server console, run `spawn_bot 3`. If that spelling is rejected, try
`addbot`, then `spawntestclient`. Use `bot_team` if bots need placing explicitly.

Expected: three bots join and appear on the scoreboard. Confirm they are real player
entities rather than UI placeholders — the local GSC is full of `isai( self )` branches
and `level.bot_funcs` (`_playerlogic.gsc:687-688`, `_damage.gsc:854-855`), which only run
for entities in `level.players`. One of the bots component's `post_unpack` lambdas takes `netadr_s&` — a network
address — which suggests bots connect through a synthesized address on the real
client-connect path rather than being conjured as entities. That makes it likely they
fire `connected`, but it is inference from a symbol signature, not proof.

**This matters for Task 4**: `_squads` assigns on
`level waittill( "connected", player )`, so if bots do not fire `connected` they will
never be squad-assigned, and that changes how every later task is verified. Note in
`docs/RUNNING.md` which command worked and whether bots get squad-assigned once Task 4
lands.

If no bot command works, stop and decide the multi-client route with the user before
writing nine verification cycles that assume more than one player — a second machine on
the LAN with `sv_lanOnly 1` is the fallback.

- [ ] **Step 7: Write `docs/RUNNING.md`**

Record concretely: the launch command that actually worked (including which `dedicated`
spelling), where console output appears (window, log file, or stdout), the bot command
that worked, how to join as a client, and that `config/server.cfg` is deployed to the
install root by `deploy.sh`. Write what you observed, not what this plan predicted.

- [ ] **Step 8: Point README at reality**

In `README.md`, replace the line

```
- Deploy: `./deploy.sh` — **not written yet**; overrides the install path with `GHOSTS_DIR=...`
```

with

```
- Deploy: `./deploy.sh` (override the install path with `GHOSTS_DIR=...`)
- Running the server: [docs/RUNNING.md](docs/RUNNING.md)
```

and delete the line `Nothing is implemented yet — the repo currently holds the design only.`

- [ ] **Step 9: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add deploy.sh config/server.cfg docs/RUNNING.md README.md src/data/scripts/mp/resurgence/.gitkeep
git commit -m "Add deploy.sh, server.cfg, and how to run the server

iw6x.exe is iw6-mod and ships a dedicated component; nothing auto-execs
server.cfg, so it is passed with +exec. Bots come from spawn_bot, which
makes the multi-client verification steps reachable."
```

---

### Task 2: Spike — does `replacefunc` patch same-file calls?

This is the highest-leverage five minutes in the plan. `_redeploy` is built entirely on `replacefunc( ..._playerlogic::mayspawn, ... )`, and `mayspawn` is called from `spawnclient()` at `_playerlogic.gsc:122` — **inside the same script file**. If this loader only patches cross-script resolution, `_redeploy` as designed cannot work and must instead edit `mayspawn` in the local overlay. Finding that out now costs one throwaway file; finding it out in Task 5 costs the module.

**Files:**
- Create (throwaway, deleted in Step 6): `src/data/scripts/mp/_rsg_spike.gsc`
- Create: `docs/SPIKE-replacefunc.md`

**Interfaces:**
- Consumes: `./deploy.sh` and `docs/RUNNING.md` from Task 1.
- Produces: a recorded answer to two questions — (a) does same-file `replacefunc` work, (b) is `logstring` visible on the console — that Tasks 3-9 depend on. Also produces the chosen debug channel (`logstring` or `iprintln`).

- [ ] **Step 1: Write the spike script**

```gsc
// THROWAWAY. Deleted at the end of Task 2. Answers two questions:
//   1. does replacefunc patch a same-file call (_playerlogic.gsc:122 -> mayspawn)?
//   2. is logstring visible on this server's console?

main()
{
    logstring( "RSG_SPIKE main() reached" );
    iprintln( "RSG_SPIKE main() reached" );

    replacefunc( maps\mp\gametypes\_playerlogic::mayspawn, ::spike_mayspawn );
    replacefunc( maps\mp\_utility::attackerishittingteam, ::spike_hittingteam );
}

spike_mayspawn()
{
    logstring( "RSG_SPIKE mayspawn stub reached" );
    iprintln( "RSG_SPIKE mayspawn stub reached" );
    return 1;
}

spike_hittingteam( var_0, var_1 )
{
    logstring( "RSG_SPIKE attackerIsHittingTeam stub reached" );
    return 0;
}
```

Note `main()` rather than `init()`: `_patches.gsc` uses `main()` and is the file that proves `replacefunc` works here, so the spike copies its shape exactly to avoid testing two unknowns at once.

- [ ] **Step 2: Deploy, start the server, and look for `main()`**

```bash
cd ~/ws/personal/resurgence_mod_ghost && ./deploy.sh
```

Then start the server per `docs/RUNNING.md`, join, and look for `RSG_SPIKE main() reached`.

Expected, in order of what it tells you:
- Line appears **via `logstring`** → debug channel is `logstring`. Record it.
- Line appears **only in-game** (the `iprintln`) → debug channel is `iprintln`. Record it; every later task's `rsg_log()` uses `iprintln`.
- **Neither appears** → scripts under `data/scripts/mp/` are not auto-loaded the way `_patches.gsc` suggests, or the deploy did not land. Stop. Confirm `ls /mnt/d/games/cod_cbservers/ghosts_game_files/data/scripts/mp/` shows `_rsg_spike.gsc`, then re-read `docs/RUNNING.md`. Do not continue to Task 3 with no debug channel.

- [ ] **Step 3: Verify the same-file patch — the actual question**

Die in-game (or rejoin) so `spawnclient()` runs, and watch for `RSG_SPIKE mayspawn stub reached`.

Expected: PASS = the line appears → same-file `replacefunc` works → `_redeploy` proceeds as specified in Task 5.
FAIL = no line, despite `main()` having been reached → same-file calls are not patched → **Task 5 switches to the fallback**: a marked edit to `mayspawn` in `src/data/maps/mp/gametypes/_playerlogic.gsc` (a fifth overlay edit, and a whole-file copy of `_playerlogic.gsc` into `src/data/`).

- [ ] **Step 4: Verify the cross-script patch**

Shoot another player. Expected: `RSG_SPIKE attackerIsHittingTeam stub reached`. This is cross-script and expected to work; it confirms the friendly-fire hook Task 5 does not install but the design depends on. If this fails too, `replacefunc` is not usable at all on this build and the whole hooking strategy needs rework — stop and report.

- [ ] **Step 5: Record the answers**

Write `docs/SPIKE-replacefunc.md` with four lines, each stating the observed result and the console output that proved it: `main()` reached (yes/no), debug channel (`logstring`/`iprintln`), same-file `replacefunc` (works/does not), cross-script `replacefunc` (works/does not). Do not write what you expect — write what you saw.

- [ ] **Step 6: Remove the spike from both trees**

```bash
cd ~/ws/personal/resurgence_mod_ghost
rm src/data/scripts/mp/_rsg_spike.gsc
rm /mnt/d/games/cod_cbservers/ghosts_game_files/data/scripts/mp/_rsg_spike.gsc
ls /mnt/d/games/cod_cbservers/ghosts_game_files/data/scripts/mp/
```

Expected: only `_patches.gsc` and `_team_balance.gsc`. `deploy.sh` never deletes, so the install copy must go by hand — leaving a stray `replacefunc` of `mayspawn` in the install would silently break every later task.

- [ ] **Step 7: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add docs/SPIKE-replacefunc.md
git commit -m "Record replacefunc spike results

Answers whether this loader patches same-file calls, which decides how
_redeploy hooks mayspawn, and establishes the debug channel."
```

---

### Task 3: Entry point, dvars, and the ADR-5 re-assert hook

**Files:**
- Create: `src/data/scripts/mp/_resurgence.gsc`
- Create: `src/data/maps/mp/gametypes/_gamelogic.gsc` (whole-file copy of the install's, plus the marked hook)

**Interfaces:**
- Consumes: the debug channel from Task 2.
- Produces:
  - `scripts\mp\_resurgence::rsg_log( msg )` — no-op unless `scr_resurgence_debug`.
  - `scripts\mp\_resurgence::rsg_on()` → returns 1 when the mod is active this match.
  - `level.rsg` — a `spawnstruct()` holding `squadsize`, `redeploydelay`, `debug`, `primary`, `secondary`, and the zone fields read in Task 9.
  - `level.rsg_install_callbacks` — pointer the `_gamelogic.gsc` hook calls.
  - Later tasks add their own `install_callbacks()` and register them here.

- [ ] **Step 1: Write the entry point**

```gsc
init()
{
    setdvarifuninitialized( "scr_resurgence_enabled", 0 );
    setdvarifuninitialized( "scr_resurgence_squadsize", 2 );
    setdvarifuninitialized( "scr_resurgence_redeploydelay", 15 );
    setdvarifuninitialized( "scr_resurgence_primary", "" );
    setdvarifuninitialized( "scr_resurgence_secondary", "" );
    setdvarifuninitialized( "scr_resurgence_zone_enabled", 1 );
    setdvarifuninitialized( "scr_resurgence_zone_phases", 5 );
    setdvarifuninitialized( "scr_resurgence_zone_radius_start", 4000 );
    setdvarifuninitialized( "scr_resurgence_zone_radius_end", 400 );
    setdvarifuninitialized( "scr_resurgence_zone_hold", 45 );
    setdvarifuninitialized( "scr_resurgence_zone_shrink", 30 );
    setdvarifuninitialized( "scr_resurgence_zone_damage", 5 );
    setdvarifuninitialized( "scr_resurgence_debug", 0 );

    if ( !getdvarint( "scr_resurgence_enabled" ) )
        return;

    level.rsg = spawnstruct();
    level.rsg.debug = getdvarint( "scr_resurgence_debug" );
    level.rsg.squadsize = max( 1, getdvarint( "scr_resurgence_squadsize" ) );
    level.rsg.redeploydelay = getdvarint( "scr_resurgence_redeploydelay" );
    level.rsg.primary = getdvar( "scr_resurgence_primary" );
    level.rsg.secondary = getdvar( "scr_resurgence_secondary" );

    rsg_log( "init: enabled, squadsize " + level.rsg.squadsize + ", redeploy " + level.rsg.redeploydelay + "s" );

    level.rsg_install_callbacks = ::install_callbacks;
    install_callbacks();
}

// Called once from init() and again from the marked hook in
// _gamelogic.gsc::callback_startgametype, immediately after
// [[ level.onstartgametype ]](). Whichever runs later wins, so the
// gametype cannot silently overwrite our callbacks (ADR-5).
install_callbacks()
{
    if ( !rsg_on() )
        return;

    rsg_log( "install_callbacks" );
}

rsg_on()
{
    return isdefined( level.rsg );
}

rsg_log( msg )
{
    if ( !isdefined( level.rsg ) || !level.rsg.debug )
        return;

    logstring( "RSG: " + msg );
}
```

If Task 2 recorded `iprintln` as the debug channel, `rsg_log`'s body is `iprintln( "RSG: " + msg );` instead. Use what the spike proved, not what is written here.

- [ ] **Step 2: Deploy and confirm the entry point is reached with the mod off**

```bash
cd ~/ws/personal/resurgence_mod_ghost && ./deploy.sh
```

Start the server **without** `scr_resurgence_enabled`. Expected: server starts, no script error, and **no** `RSG:` output — `init()` returned at the enabled check. This is the "fails" half of the cycle: the switch works.

- [ ] **Step 3: Turn it on and confirm the log line**

Set `scr_resurgence_enabled 1` and `scr_resurgence_debug 1` per `docs/RUNNING.md`, restart.

Expected: `RSG: init: enabled, squadsize 2, redeploy 15s` followed by `RSG: install_callbacks`. If `install_callbacks` appears once, only `init()` has run so far — Step 5 adds the second call site.

- [ ] **Step 4: Add the re-assert thread (replaces the planned `_gamelogic.gsc` edit)**

The original plan patched `callback_startgametype`. **That does not work**: CBServers
restores any file it ships within ~3s of launch, deleting the addition before scripts
load, with no error. Use a thread instead — see `reassert_callbacks()` in the committed
`_resurgence.gsc`: install in `init()`, again after `wait 0.05` (the next frame, after the
whole synchronous body of `callback_startgametype`, which is the pass that sticks), and
once more on `level waittill( "prematch_over" )`.

- [ ] **Step 5: Verify the passes**

Deploy and restart with the mod on. Expected in `logs/games_mp.log`:

```
0:00 RSG: init: enabled, squadsize 2, redeploy 15s
0:00 RSG: install_callbacks (pass 1)
0:00 RSG: install_callbacks (pass 2)
0:20 RSG: install_callbacks (pass 3)
```

Pass 2 is the important one — one frame later than pass 1, therefore after the gametype.
Only pass 1 means the thread died; no passes means `init()` died before it (check the
`#include` and that config lines use `set`).

- [ ] **Step 6: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/_resurgence.gsc src/data/maps/mp/gametypes/_gamelogic.gsc
git commit -m "Add Resurgence entry point and the ADR-5 re-assert hook

_resurgence.gsc registers all 13 dvars, builds level.rsg, and exposes
rsg_log/rsg_on. The marked hook in _gamelogic.gsc calls
level.rsg_install_callbacks right after [[ level.onstartgametype ]](),
so gametype load order cannot leave our callbacks overwritten."
```

---

### Task 4: `_squads.gsc` — membership and queries

**Files:**
- Create: `src/data/scripts/mp/resurgence/_squads.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `rsg_log()`, `rsg_on()`, `level.rsg.squadsize` from Task 3.
- Produces, all in `scripts\mp\resurgence\_squads`:
  - `init()` — starts the connect watcher.
  - `squad_of( player )` → int, or `undefined`.
  - `same_squad( a, b )` → 1 / 0. Zero when either is undefined or `a == b`.
  - `squad_members( id )` → array of connected players.
  - `squad_living_members( id )` → members passing `isreallyalive`.
  - `squad_is_wiped( id )` → 1 when the squad has members but none alive.
  - `living_squad_ids()` → array of ids with at least one living member.
  - `dump_squads()` → logs the whole table; used by every later task's verification.

- [ ] **Step 1: Write the module**

```gsc
init()
{
    level thread watch_connects();
}

watch_connects()
{
    for (;;)
    {
        level waittill( "connected", var_0 );
        var_0 thread on_connect();
    }
}

on_connect()
{
    self endon( "disconnect" );

    assign( self );
    scripts\mp\_resurgence::rsg_log( "squad: " + self.name + " -> squad " + self.rsg_squad );
    dump_squads();

    self waittill( "disconnect" );
}

// Fills the lowest-numbered squad with a free slot. Terminates because an
// id beyond every assigned squad always has zero members.
assign( player )
{
    for ( var_0 = 0; ; var_0++ )
    {
        if ( squad_members( var_0 ).size < level.rsg.squadsize )
        {
            player.rsg_squad = var_0;
            player.rsg_eliminated = 0;
            return var_0;
        }
    }
}

squad_of( player )
{
    if ( !isdefined( player ) )
        return undefined;

    return player.rsg_squad;
}

same_squad( a, b )
{
    if ( !isdefined( a ) || !isdefined( b ) )
        return 0;

    if ( a == b )
        return 0;

    if ( !isdefined( a.rsg_squad ) || !isdefined( b.rsg_squad ) )
        return 0;

    return a.rsg_squad == b.rsg_squad;
}

squad_members( squadid )
{
    var_0 = [];

    foreach ( var_1 in level.players )
    {
        if ( !isdefined( var_1 ) || !isdefined( var_1.rsg_squad ) )
            continue;

        if ( var_1.rsg_squad == squadid )
            var_0[var_0.size] = var_1;
    }

    return var_0;
}

squad_living_members( squadid )
{
    var_0 = [];

    foreach ( var_1 in squad_members( squadid ) )
    {
        if ( var_1 maps\mp\_utility::isreallyalive() )
            var_0[var_0.size] = var_1;
    }

    return var_0;
}

squad_is_wiped( squadid )
{
    if ( squad_members( squadid ).size == 0 )
        return 0;

    return squad_living_members( squadid ).size == 0;
}

living_squad_ids()
{
    var_0 = [];

    foreach ( var_1 in level.players )
    {
        if ( !isdefined( var_1 ) || !isdefined( var_1.rsg_squad ) )
            continue;

        if ( !var_1 maps\mp\_utility::isreallyalive() )
            continue;

        if ( !common_scripts\utility::array_contains( var_0, var_1.rsg_squad ) )
            var_0[var_0.size] = var_1.rsg_squad;
    }

    return var_0;
}

dump_squads()
{
    if ( !isdefined( level.rsg ) || !level.rsg.debug )
        return;

    foreach ( var_0 in level.players )
    {
        if ( !isdefined( var_0 ) )
            continue;

        if ( !isdefined( var_0.rsg_squad ) )
        {
            scripts\mp\_resurgence::rsg_log( "  " + var_0.name + ": UNASSIGNED" );
            continue;
        }

        scripts\mp\_resurgence::rsg_log( "  " + var_0.name + ": squad " + var_0.rsg_squad + ", alive " + var_0 maps\mp\_utility::isreallyalive() + ", eliminated " + var_0.rsg_eliminated );
    }
}
```

`isreallyalive` is called as a method on the player (`var_1 maps\mp\_utility::isreallyalive()`) — that is how `_damage.gsc` calls it. `array_contains` comes from `common_scripts\utility`, which `_patches.gsc` includes, confirming the path.

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

Add to `init()`, immediately after the `rsg_log( "init: ..." )` line and **before** `level.rsg_install_callbacks` is set:

```gsc
    scripts\mp\resurgence\_squads::init();
```

- [ ] **Step 3: Deploy and verify assignment is wrong before it is right**

```bash
cd ~/ws/personal/resurgence_mod_ghost && ./deploy.sh
```

Restart with the mod on and `scr_resurgence_debug 1`, then join with **one** client. Expected: `RSG: squad: <name> -> squad 0` and a `RSG:   <name>: squad 0, alive ...` dump line. If the dump shows `UNASSIGNED`, the connect watcher is not firing — check the `waittill( "connected", var_0 )` spelling against `_menus.gsc:93`.

- [ ] **Step 4: Verify duo packing with four clients**

Join with one real client, then run `spawn_bot 3` on the console (or whichever command Task 1 Step 6 recorded). Expected, with `squadsize 2`: the four land in squads `0, 0, 1, 1` in join order, and `dump_squads` shows exactly that.

If the bots appear on the scoreboard but `dump_squads` reports them `UNASSIGNED`, bots do not fire `level waittill( "connected" )` on this build. Fix it here, not later: also assign in `_squads` from a sweep over `level.players` inside `dump_squads`'s caller, or hook `level.bot_funcs["player_spawned"]`. Every later task's multi-player verification depends on bots being squad members.

Then set `scr_resurgence_squadsize 4`, restart, rejoin all four. Expected: all four in squad `0`. This proves the dvar is read rather than the `2` being hardcoded.

- [ ] **Step 5: Verify disconnect frees the slot**

With `squadsize 2` and two clients in squad 0, disconnect the first, then join a third client. Expected: the newcomer is assigned **squad 0** — the freed slot — not squad 1. This is the behaviour `squad_members` scanning `level.players` gives for free; the test confirms `level.players` really drops disconnected players.

- [ ] **Step 6: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_squads.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _squads: virtual squad membership and queries

Assigns on connect into the lowest-numbered squad with a free slot,
capacity scr_resurgence_squadsize. Exposes squad_of, same_squad,
squad_members, squad_living_members, squad_is_wiped, living_squad_ids
and dump_squads, which later tasks verify against."
```

---

### Task 5: `_redeploy.gsc` — may I respawn, and after how long

**Files:**
- Create: `src/data/scripts/mp/resurgence/_redeploy.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `_squads::squad_of`, `_squads::squad_living_members`, `rsg_log`, `rsg_on`, `level.rsg.redeploydelay`.
- Produces, in `scripts\mp\resurgence\_redeploy`:
  - `init()` — installs the `mayspawn` replacement.
  - `install_callbacks()` — assigns `level.onrespawndelay`.
  - `eliminate( player )` — flags a player out, cancels any pending redeploy, drops them to spectator. **Called by `_win` in Task 10.**
  - `may_redeploy( player )` → 1 when the player has a living squadmate.

**Branch on the Task 2 spike:** if Step 3 of Task 2 recorded same-file `replacefunc` as *not working*, do not write `init()` as below. Instead copy `_playerlogic.gsc` into `src/data/maps/mp/gametypes/` and wrap its `mayspawn()` body (`:81-106`) with a marked early return calling `rsg_mayspawn`, leave `init()` empty, and note the deviation in the commit message. Everything else in this task is unchanged.

- [ ] **Step 1: Write the module**

```gsc
init()
{
    replacefunc( maps\mp\gametypes\_playerlogic::mayspawn, ::rsg_mayspawn );
}

install_callbacks()
{
    level.onrespawndelay = ::rsg_respawndelay;
}

rsg_respawndelay()
{
    return level.rsg.redeploydelay;
}

// Replaces _playerlogic::mayspawn. Returning 0 routes the player to
// spectator via spawnclient() (_playerlogic.gsc:122-155).
rsg_mayspawn()
{
    if ( isdefined( self.rsg_eliminated ) && self.rsg_eliminated )
    {
        scripts\mp\_resurgence::rsg_log( "mayspawn: " + self.name + " eliminated, denied" );
        return 0;
    }

    // Vanilla's checks. Dead code while scr_dm_numlives is 0 and
    // level.disablespawning is never set (ADR-2), kept so this behaves
    // correctly if numlives is ever enabled.
    if ( maps\mp\_utility::getgametypenumlives() || isdefined( level.disablespawning ) )
    {
        if ( isdefined( level.disablespawning ) && level.disablespawning )
            return 0;

        if ( isdefined( self.pers["teamKillPunish"] ) && self.pers["teamKillPunish"] )
            return 0;

        if ( self.pers["lives"] <= 0 && maps\mp\_utility::gamehasstarted() )
            return 0;
        else if ( maps\mp\_utility::gamehasstarted() )
        {
            if ( !level.ingraceperiod && !self.hasspawned && ( isdefined( level.allowlatecomers ) && !level.allowlatecomers ) )
            {
                if ( isdefined( self.siegelatecomer ) && !self.siegelatecomer )
                    return 1;

                return 0;
            }
        }
    }

    return 1;
}

may_redeploy( player )
{
    if ( !isdefined( player ) || !isdefined( player.rsg_squad ) )
        return 0;

    return scripts\mp\resurgence\_squads::squad_living_members( player.rsg_squad ).size > 0;
}

// Permanent elimination. Cancels a redeploy already being waited out:
// waitandspawnclient() endons "end_respawn" (_playerlogic.gsc:169).
eliminate( player )
{
    if ( !isdefined( player ) || ( isdefined( player.rsg_eliminated ) && player.rsg_eliminated ) )
        return;

    player.rsg_eliminated = 1;
    player notify( "end_respawn" );
    player maps\mp\_utility::clearlowermessage( "spawn_info" );
    scripts\mp\_resurgence::rsg_log( "eliminate: " + player.name + " (squad " + player.rsg_squad + ")" );

    if ( player.sessionstate == "playing" )
        player thread maps\mp\gametypes\_playerlogic::spawnspectator( player.origin + ( 0, 0, 60 ), player.angles );
}
```

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

Add after the `_squads::init()` line:

```gsc
    scripts\mp\resurgence\_redeploy::init();
```

and inside `install_callbacks()`, after its `rsg_log` line:

```gsc
    scripts\mp\resurgence\_redeploy::install_callbacks();
```

- [ ] **Step 3: Verify the redeploy delay is ours**

Deploy, restart with the mod on, `scr_resurgence_redeploydelay 20`, and `scr_dm_playerrespawndelay 0`. Die.

Expected: the on-screen spawn countdown reads **20 seconds**, not 0. That difference proves `level.onrespawndelay` is installed and that the gametype did not overwrite it — i.e. it is the first live confirmation of ADR-5. Set the dvar to `5`, restart, die again: the countdown must follow.

- [ ] **Step 4: Verify the eliminated gate denies spawning**

With two clients in one squad and `scr_resurgence_debug 1`, temporarily force the path by having one client die, then immediately kill the other. With `_win` not yet written nothing calls `eliminate()`, so **both must still respawn** — this is the failing half of the cycle, and it confirms `rsg_mayspawn` is not denying spawns on its own.

- [ ] **Step 5: Verify `eliminate()` actually eliminates**

Append a temporary debug thread to `_redeploy.gsc`:

```gsc
// TEMPORARY, removed in Step 7.
debug_eliminate_watcher()
{
    level endon( "game_ended" );

    for (;;)
    {
        wait 1;

        if ( !getdvarint( "scr_resurgence_debug_eliminate", 0 ) )
            continue;

        setdvar( "scr_resurgence_debug_eliminate", 0 );

        foreach ( var_0 in level.players )
        {
            if ( isdefined( var_0 ) && !var_0 maps\mp\_utility::isreallyalive() )
                eliminate( var_0 );
        }
    }
}
```

Start it from `init()` with `level thread debug_eliminate_watcher();`, deploy, restart. Die, and while dead set `scr_resurgence_debug_eliminate 1` on the server console.

Expected: `RSG: eliminate: <name> (squad N)`, the spawn countdown clears, the player stays a spectator and **never** respawns, and on the next death-and-rejoin cycle `RSG: mayspawn: <name> eliminated, denied` appears. This is the real test of both `eliminate()` and the `rsg_eliminated` gate, run before `_win` exists to drive them.

- [ ] **Step 6: Verify a pending redeploy gets cancelled**

With `scr_resurgence_redeploydelay 20`, die and set `scr_resurgence_debug_eliminate 1` **while the countdown is still running**. Expected: the countdown disappears immediately rather than finishing and spawning — the `notify( "end_respawn" )` path working, which is what the spec's grace-period and mid-wait wipe rules both rely on.

- [ ] **Step 7: Remove the temporary watcher and commit**

Delete `debug_eliminate_watcher()` and its `level thread` line.

```bash
cd ~/ws/personal/resurgence_mod_ghost && ./deploy.sh
git add src/data/scripts/mp/resurgence/_redeploy.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _redeploy: redeploy gating, delay, and elimination

rsg_mayspawn replaces _playerlogic::mayspawn and denies spawning to
eliminated players, keeping vanilla's numlives checks for the case where
numlives is ever enabled. level.onrespawndelay supplies the redeploy
delay. eliminate() flags a player out, breaks a pending redeploy via
notify end_respawn, and drops them to spectator."
```

Re-deploy after deleting the watcher, and confirm on the next server start that setting `scr_resurgence_debug_eliminate 1` does nothing. A debug backdoor left in the install would eliminate players during real matches.

---

### Task 6: `_spawning.gsc` — spawn near a living squadmate

**Files:**
- Create: `src/data/scripts/mp/resurgence/_spawning.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `_squads::squad_living_members`, `rsg_log`. Optionally reads `level.rsg_center` / `level.rsg_radius` if Task 9 has already set them; must work when they are undefined.
- Produces, in `scripts\mp\resurgence\_spawning`:
  - `install_callbacks()` — assigns `level.getspawnpoint`.
  - `rsg_getspawnpoint()` → a spawn **struct** (not an origin): `spawnplayer` passes the return value to `_spawnlogic::finalizespawnpointchoice` (`_playerlogic.gsc:659`) and `getspawnorigin` (`:660`), so a synthesised object will not do.

- [ ] **Step 1: Write the module**

```gsc
install_callbacks()
{
    level.getspawnpoint = ::rsg_getspawnpoint;
}

// Must return one of the map's own spawn structs: spawnplayer feeds the
// result to _spawnlogic::finalizespawnpointchoice (_playerlogic.gsc:659)
// and getspawnorigin (:660).
rsg_getspawnpoint()
{
    var_0 = spawn_candidates();

    if ( var_0.size == 0 )
    {
        scripts\mp\_resurgence::rsg_log( "getspawnpoint: NO CANDIDATES, falling back to dm random" );
        return maps\mp\gametypes\_spawnlogic::getspawnpoint_random( maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_dm_spawn" ) );
    }

    var_1 = in_zone( var_0 );

    if ( var_1.size == 0 )
    {
        scripts\mp\_resurgence::rsg_log( "getspawnpoint: no in-ring candidates, using all " + var_0.size );
        var_1 = var_0;
    }

    var_2 = nearest_living_squadmate();

    if ( !isdefined( var_2 ) )
    {
        scripts\mp\_resurgence::rsg_log( "getspawnpoint: " + self.name + " has no living squadmate, random of " + var_1.size );
        return maps\mp\gametypes\_spawnlogic::getspawnpoint_random( var_1 );
    }

    var_3 = closest_to( var_1, var_2.origin );
    scripts\mp\_resurgence::rsg_log( "getspawnpoint: " + self.name + " near " + var_2.name + " at " + distance( var_3.origin, var_2.origin ) + " units" );
    return var_3;
}

// FFA spawns are mp_dm_spawn. The classname is not verifiable from data/,
// so log the count and fall back to the tdm array, which aliens.gsc:787
// attests, rather than returning an empty set.
spawn_candidates()
{
    var_0 = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_dm_spawn" );

    if ( isdefined( var_0 ) && var_0.size > 0 )
        return var_0;

    scripts\mp\_resurgence::rsg_log( "getspawnpoint: mp_dm_spawn EMPTY, trying mp_tdm_spawn_axis_start" );
    var_1 = maps\mp\gametypes\_spawnlogic::getspawnpointarray( "mp_tdm_spawn_axis_start" );

    if ( isdefined( var_1 ) )
        return var_1;

    return [];
}

in_zone( points )
{
    if ( !isdefined( level.rsg_center ) || !isdefined( level.rsg_radius ) )
        return points;

    var_0 = [];

    foreach ( var_1 in points )
    {
        if ( distance2d( var_1.origin, level.rsg_center ) <= level.rsg_radius )
            var_0[var_0.size] = var_1;
    }

    return var_0;
}

nearest_living_squadmate()
{
    if ( !isdefined( self.rsg_squad ) )
        return undefined;

    var_0 = undefined;
    var_1 = 0;

    foreach ( var_2 in scripts\mp\resurgence\_squads::squad_living_members( self.rsg_squad ) )
    {
        if ( var_2 == self )
            continue;

        var_3 = distancesquared( var_2.origin, self.origin );

        if ( !isdefined( var_0 ) || var_3 < var_1 )
        {
            var_0 = var_2;
            var_1 = var_3;
        }
    }

    return var_0;
}

closest_to( points, origin )
{
    var_0 = points[0];
    var_1 = distancesquared( points[0].origin, origin );

    foreach ( var_2 in points )
    {
        var_3 = distancesquared( var_2.origin, origin );

        if ( var_3 < var_1 )
        {
            var_0 = var_2;
            var_1 = var_3;
        }
    }

    return var_0;
}
```

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

`_spawning` has no `init()` — it only installs a callback, so it is wired in
`install_callbacks()` **only**, never in `init()`. Add after the `_redeploy` line inside
`install_callbacks()`:

```gsc
    scripts\mp\resurgence\_spawning::install_callbacks();
```

- [ ] **Step 3: Verify the spawn array classname before trusting anything else**

Deploy, restart with debug on, join one client and spawn.

Expected: a `getspawnpoint:` line appears. If it says `mp_dm_spawn EMPTY, trying mp_tdm_spawn_axis_start`, the FFA classname is different on this build — record the working one in `docs/RUNNING.md` and make it the first choice in `spawn_candidates()`. If it says `NO CANDIDATES`, both arrays are empty and the map has no spawn points of either class: stop, and report which map was tested.

- [ ] **Step 4: Verify the solo path**

With one client only, die and respawn several times. Expected: `has no living squadmate, random of N` each time, with `N` constant and greater than 1, and the player spawns at varying locations. No script error.

- [ ] **Step 5: Verify the squadmate path**

Two clients, same squad (`squadsize 2`, both joined). Keep client A alive in a distinctive corner of the map; kill client B and let it redeploy.

Expected: `getspawnpoint: <B> near <A> at <d> units`, and B visibly spawns near A. Then move A to the opposite side of the map, kill B again: the reported distance must be measured to A's **new** position, and B must spawn there instead. Same number both times means the squadmate lookup is not re-running.

- [ ] **Step 6: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_spawning.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _spawning: in-ring spawn nearest a living squadmate

level.getspawnpoint returns one of the map's own spawn structs, because
spawnplayer passes the result to finalizespawnpointchoice. Candidates are
filtered to the ring when _zone has set one, then scored by distance to
the nearest living squadmate, with a random in-ring pick when the player
has none. Logs the spawn array size so a wrong classname is caught on the
first spawn."
```

---

### Task 7: `_friendlyfire.gsc` — squadmates cannot damage each other

Without this, duos are unplayable: in FFA every player is a valid target, so your partner
is too. The spec gives this its own section rather than a module; it gets its own file.

**Files:**
- Create: `src/data/scripts/mp/resurgence/_friendlyfire.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `_squads::same_squad`, and the Task 2 Step 4 finding that cross-script
  `replacefunc` works.
- Produces: `init()` — installs the `attackerishittingteam` replacement. Nothing else
  consumes this module; it works purely by making a stock predicate answer differently.

- [ ] **Step 1: Write the module**

```gsc
init()
{
    replacefunc( maps\mp\_utility::attackerishittingteam, ::rsg_attackerishittingteam );
}

// Replaces _utility::attackerishittingteam, consumed as var_13 at
// _damage.gsc:1602, which feeds every level.friendlyfire == 0 branch in
// the damage pipeline. Returning 1 for a squadmate pair blocks the damage
// everywhere at once, including paths in stock files we cannot read.
//
// Argument order follows the call site: attackerishittingteam( victim, attacker ).
//
// The stock body is unreadable, so the non-squadmate path reproduces the
// shape of the one visible analogue, _damage.gsc::isfriendlyfire (:20-37).
// That is safe here because we only ever run under dm, where
// level.teambased is 0 and the stock function therefore returns 0 for
// every pair anyway: the only behaviour this must preserve is "0 unless
// squadmates". It is also why init() is called only when the mod is
// enabled -- on a teamed gametype this replacement would be wrong.
rsg_attackerishittingteam( victim, attacker )
{
    if ( scripts\mp\resurgence\_squads::same_squad( attacker, victim ) )
        return 1;

    if ( !level.teambased )
        return 0;

    if ( !isdefined( attacker ) || !isdefined( victim ) )
        return 0;

    if ( !isplayer( attacker ) && !isdefined( attacker.team ) )
        return 0;

    if ( victim == attacker )
        return 0;

    return victim.team == attacker.team;
}
```

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

In `init()`, after `_redeploy::init()`:

```gsc
    scripts\mp\resurgence\_friendlyfire::init();
```

It is a `replacefunc`, so it is immune to load order and does **not** belong in
`install_callbacks()`.

- [ ] **Step 3: Confirm friendly fire is live before the fix**

Deploy with the module **not yet wired** (or with `scr_resurgence_enabled 0`), restart,
and have two clients in the same squad shoot each other.

Expected: damage registers, hitmarkers appear, squadmates can kill each other. This is
the failing half of the cycle — confirm it, because if FFA damage were already blocked by
something else, the rest of this task would prove nothing.

- [ ] **Step 4: Verify squadmate damage is blocked**

Wire the module, ensure `scr_friendlyfire 0`, deploy, restart. Two clients in squad 0.

Expected: shooting a squadmate does **no** damage and produces no hitmarker; health does
not drop. Then have one of them shoot a member of squad 1: damage registers normally. Both
halves matter — a hook that blocks all damage is as broken as one that blocks none.

- [ ] **Step 5: Verify explosives and the kill-yourself case**

Throw a grenade at a squadmate's feet: no damage to them. Throw one at your own feet: you
still take damage and can kill yourself. The `victim == attacker` check is what keeps
self-damage working, and `same_squad` returns 0 for `a == b` by contract.

- [ ] **Step 6: Verify stock behaviour returns when the mod is off**

Set `scr_resurgence_enabled 0`, restart, and have the same two clients shoot each other.

Expected: damage registers again. `init()` is never reached when the mod is off, so the
stock function is untouched — this confirms the master switch covers the damage path too.

- [ ] **Step 7: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_friendlyfire.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _friendlyfire: block damage between squadmates

Replaces _utility::attackerishittingteam, which _damage.gsc:1602 funnels
every friendly-fire decision through as var_13, so one cross-script hook
covers all damage paths including those in stock files we cannot read.
Non-squadmate pairs return 0, matching stock behaviour under dm where
level.teambased is 0; the module is only installed when the mod is
enabled, since the replacement would be wrong on a teamed gametype."
```

---

### Task 8: `_loadout.gsc` — clear slate, killstreaks off

**Files:**
- Create: `src/data/scripts/mp/resurgence/_loadout.gsc`
- Create: `src/data/maps/mp/gametypes/_menus.gsc` (whole-file copy + two marked guards)
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `level.rsg.primary`, `level.rsg.secondary`, `rsg_log`.
- Produces, in `scripts\mp\resurgence\_loadout`:
  - `install_callbacks()` — assigns `level.custom_giveloadout`.
  - `rsg_giveloadout( fauxspawn )` — takes vanilla's faux-spawn flag as its one argument, matching the call at `_playerlogic.gsc:697`.

- [ ] **Step 1: Write the module**

```gsc
install_callbacks()
{
    level.custom_giveloadout = ::rsg_giveloadout;
}

// Replaces _class::giveloadout at _playerlogic.gsc:696-699. Runs AFTER
// _class::setclass( self.class ) at :694, so this must be a clear slate,
// not a top-up, and killstreaks must be cleared here rather than assumed
// absent. Shape follows aliens.gsc:1107-1211.
rsg_giveloadout( fauxspawn )
{
    self takeallweapons();
    self.changingweapon = undefined;
    self.loadoutprimaryattachments = [];
    self.loadoutsecondaryattachments = [];
    maps\mp\_utility::_setactionslot( 1, "" );
    maps\mp\_utility::_setactionslot( 2, "" );
    maps\mp\_utility::_setactionslot( 3, "" );
    maps\mp\_utility::_setactionslot( 4, "" );
    maps\mp\_utility::_clearperks();
    self.killstreaktype = "none";
    self notify( "changed_kit" );
    self notify( "giveLoadout" );

    if ( isdefined( fauxspawn ) && fauxspawn )
        return;

    // No plain MP weapon name is verifiable from data/, so an unset dvar
    // means: keep the player's chosen class, minus killstreaks.
    if ( level.rsg.primary == "" && level.rsg.secondary == "" )
    {
        scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " class passthrough, killstreaks stripped" );
        maps\mp\gametypes\_class::giveloadout( self.team, self.class );
        self.killstreaktype = "none";
        return;
    }

    if ( level.rsg.primary != "" )
    {
        self giveweapon( level.rsg.primary );
        self setspawnweapon( level.rsg.primary );
    }

    if ( level.rsg.secondary != "" )
        self giveweapon( level.rsg.secondary );

    scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " fixed kit " + level.rsg.primary + " / " + level.rsg.secondary );
}
```

Note the second `self.killstreaktype = "none"` after the passthrough: `_class::giveloadout` is what grants killstreaks, so stripping them before calling it would accomplish nothing.

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

In `install_callbacks()`, after the `_spawning` line:

```gsc
    scripts\mp\resurgence\_loadout::install_callbacks();
```

- [ ] **Step 3: Deploy and verify the passthrough strips killstreaks**

Leave `scr_resurgence_primary` and `scr_resurgence_secondary` unset. Deploy, restart, spawn.

Expected: `RSG: loadout: <name> class passthrough, killstreaks stripped`, the player holds their normal class weapons, and **no killstreak is available** (check the killstreak HUD and that earning one grants nothing). If weapons are missing entirely, `_class::giveloadout`'s signature differs from `( team, class )` as used at `_playerlogic.gsc:699` — re-check that line and match it exactly.

- [ ] **Step 4: Find real weapon names and verify the fixed kit**

On the running server, find valid MP weapon names — try the console's `give` command, or inspect `mp/weaponsTable.csv` if a dump of it is reachable. Set `scr_resurgence_primary` to one confirmed name, restart, spawn.

Expected: `RSG: loadout: <name> fixed kit <weapon> / `, and the player spawns holding that weapon with no killstreak. If the server throws a script error on `giveweapon`, the name is invalid — clear the dvar to return to the passthrough, and record in `docs/RUNNING.md` that names remain unconfirmed. **A passthrough that works beats a fixed kit that crashes the server**; do not leave an unverified name in a committed default.

- [ ] **Step 5: Reproduce the class-change bypass before fixing it**

With the mod on, spawn, then **during the grace period** change class from the menu.

Expected: the loadout reverts to a vanilla kit **with killstreaks**, and **no** `RSG: loadout:` line appears for the change. That is `_menus.gsc:182` calling `_class::giveloadout` directly, bypassing `level.custom_giveloadout`. Confirm it before fixing it — this is the failing test.

- [ ] **Step 6: Hook `_class::giveloadout` (replaces the planned `_menus.gsc` edits)**

The two guards in `_menus.gsc:182` / `:598` **cannot be added** — CBServers restores that
file (ADR-6). Instead:

```gsc
replacefunc( maps\mp\gametypes\_class::giveloadout, ::rsg_class_giveloadout );
```

One cross-script hook covers all three call sites — both `_menus.gsc` grace-period paths
and the `else` branch at `_playerlogic.gsc:699` — so `level.custom_giveloadout` is not
needed at all. Cross-script `replacefunc` is verified working (Task 2).

- [ ] **Step 6b (superseded, do not do): add the two guards**

```bash
cd ~/ws/personal/resurgence_mod_ghost
cp /mnt/d/games/cod_cbservers/ghosts_game_files/data/maps/mp/gametypes/_menus.gsc src/data/maps/mp/gametypes/
grep -n "_class::giveloadout" src/data/maps/mp/gametypes/_menus.gsc
```

Expected: lines `182` and `598`. At **both**, replace

```gsc
                    maps\mp\gametypes\_class::giveloadout( self.pers["team"], self.pers["class"] );
```

with (preserving each site's original indentation)

```gsc
// RESURGENCE BEGIN
                    if ( isdefined( level.custom_giveloadout ) )
                        self [[ level.custom_giveloadout ]]( 0 );
                    else
                        maps\mp\gametypes\_class::giveloadout( self.pers["team"], self.pers["class"] );
// RESURGENCE END
```

This mirrors the guard at `_playerlogic.gsc:696-699`. The `0` is the faux-spawn flag: a class change is a real loadout grant, not a faux spawn.

- [ ] **Step 7: Verify the guard closes it**

Deploy, restart, and repeat Step 5 exactly.

Expected: `RSG: loadout: <name> class passthrough, killstreaks stripped` now **does** appear on the class change, and no killstreak is available afterwards. Then set `scr_resurgence_enabled 0`, restart, and change class during the grace period: the vanilla kit must come back, proving the `isdefined` guard leaves stock behaviour intact when the mod is off.

- [ ] **Step 8: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_loadout.gsc src/data/maps/mp/gametypes/_menus.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _loadout and close the two class-change bypass sites

rsg_giveloadout is a clear slate because it runs after _class::setclass:
weapons taken, action slots and perks cleared, killstreaktype none. With
no weapon dvars set it calls through to _class::giveloadout and strips
killstreaks after, since no plain MP weapon name is verifiable from data/.

_menus.gsc:182 and :598 called _class::giveloadout directly during the
grace period, bypassing level.custom_giveloadout and handing a class
switcher a vanilla kit with killstreaks for the rest of the match. Both
now use the same isdefined guard as _playerlogic.gsc:696-699."
```

---

### Task 9: `_zone.gsc` — the shrinking ring

**Files:**
- Create: `src/data/scripts/mp/resurgence/_zone.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `rsg_log`, the six `scr_resurgence_zone_*` dvars, and `_spawning::spawn_candidates` for the map centroid.
- Produces: `level.rsg_center` (vector) and `level.rsg_radius` (float), read by `_spawning::in_zone`. Both stay undefined when `scr_resurgence_zone_enabled 0`, which `in_zone` already handles.

- [ ] **Step 1: Write the module**

```gsc
init()
{
    if ( !getdvarint( "scr_resurgence_zone_enabled" ) )
    {
        scripts\mp\_resurgence::rsg_log( "zone: disabled" );
        return;
    }

    level thread run();
}

run()
{
    level endon( "game_ended" );

    level waittill( "prematch_over" );

    level.rsg_center = map_centroid();
    level.rsg_radius = getdvarfloat( "scr_resurgence_zone_radius_start" );

    var_0 = max( 1, getdvarint( "scr_resurgence_zone_phases" ) );
    var_1 = getdvarfloat( "scr_resurgence_zone_radius_start" );
    var_2 = getdvarfloat( "scr_resurgence_zone_radius_end" );
    var_3 = getdvarint( "scr_resurgence_zone_hold" );
    var_4 = getdvarint( "scr_resurgence_zone_shrink" );

    scripts\mp\_resurgence::rsg_log( "zone: center " + level.rsg_center + ", radius " + level.rsg_radius + ", " + var_0 + " phases" );
    level thread damage_loop();

    for ( var_5 = 1; var_5 <= var_0; var_5++ )
    {
        wait(var_3);

        var_6 = var_1 - ( var_1 - var_2 ) * var_5 / var_0;
        iprintln( "RESURGENCE: the ring is closing" );
        scripts\mp\_resurgence::rsg_log( "zone: phase " + var_5 + "/" + var_0 + " shrinking " + level.rsg_radius + " -> " + var_6 );
        shrink_to( var_6, var_4 );
    }

    scripts\mp\_resurgence::rsg_log( "zone: final radius " + level.rsg_radius );
}

shrink_to( target, seconds )
{
    var_0 = int( seconds * 10 );

    if ( var_0 < 1 )
        var_0 = 1;

    var_1 = level.rsg_radius;

    for ( var_2 = 1; var_2 <= var_0; var_2++ )
    {
        level.rsg_radius = var_1 + ( target - var_1 ) * var_2 / var_0;
        wait 0.1;
    }

    level.rsg_radius = target;
}

damage_loop()
{
    level endon( "game_ended" );

    var_0 = getdvarint( "scr_resurgence_zone_damage" );

    for (;;)
    {
        wait 1;

        if ( !isdefined( level.rsg_radius ) )
            continue;

        foreach ( var_1 in level.players )
        {
            if ( !isdefined( var_1 ) || !var_1 maps\mp\_utility::isreallyalive() )
                continue;

            if ( distance2d( var_1.origin, level.rsg_center ) <= level.rsg_radius )
            {
                if ( isdefined( var_1.rsg_outside ) && var_1.rsg_outside )
                {
                    var_1.rsg_outside = 0;
                    var_1 maps\mp\_utility::clearlowermessage( "rsg_zone" );
                }

                continue;
            }

            if ( !isdefined( var_1.rsg_outside ) || !var_1.rsg_outside )
            {
                var_1.rsg_outside = 1;
                var_1 maps\mp\_utility::setlowermessage( "rsg_zone", &"MP_WAITING_TO_SPAWN" );
                scripts\mp\_resurgence::rsg_log( "zone: " + var_1.name + " outside at " + distance2d( var_1.origin, level.rsg_center ) + " / " + level.rsg_radius );
            }

            var_1 dodamage( var_0, level.rsg_center );
        }
    }
}

map_centroid()
{
    var_0 = scripts\mp\resurgence\_spawning::spawn_candidates();

    if ( var_0.size == 0 )
        return ( 0, 0, 0 );

    var_1 = ( 0, 0, 0 );

    foreach ( var_2 in var_0 )
        var_1 = var_1 + var_2.origin;

    return var_1 / var_0.size;
}
```

The lower-message uses the attested localized string `&"MP_WAITING_TO_SPAWN"` (`_gamelogic.gsc` populates it as `game["strings"]["waiting_to_spawn"]`) purely as a placeholder that is known to exist — a custom string needs a localization entry, which v1 does not ship. The text will read wrong; Step 4 decides whether to keep it or drop the message.

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

In `init()`, after `_redeploy::init()`:

```gsc
    scripts\mp\resurgence\_zone::init();
```

`_zone` starts a thread rather than assigning a callback, so it does **not** go in `install_callbacks()` — calling it twice would start two rings.

- [ ] **Step 3: Verify it stays off when disabled**

Deploy, restart with `scr_resurgence_zone_enabled 0`.

Expected: `RSG: zone: disabled`, no phase lines, no damage anywhere on the map, and `_spawning` keeps reporting the full candidate count (its `in_zone` returns everything when `level.rsg_radius` is undefined).

- [ ] **Step 4: Verify phases with a compressed schedule**

Restart with `scr_resurgence_zone_enabled 1`, `scr_resurgence_zone_phases 3`, `scr_resurgence_zone_hold 10`, `scr_resurgence_zone_shrink 5`, `scr_resurgence_zone_radius_start 4000`, `scr_resurgence_zone_radius_end 400`.

Expected: `RSG: zone: center (x y z), radius 4000, 3 phases`, then three `zone: phase N/3 shrinking A -> B` lines roughly 15s apart, with the final radius at 400. Confirm the centroid is a plausible point **inside** the map and not `(0 0 0)` — `(0 0 0)` means `spawn_candidates()` came back empty and the ring is centred outside the world.

Judge the lower-message here: if the placeholder string reads as nonsense in-game, delete the `setlowermessage`/`clearlowermessage` calls and the `rsg_outside` tracking, keeping the `rsg_log` line. A wrong warning is worse than none.

- [ ] **Step 5: Verify out-of-ring damage**

With a small radius (`scr_resurgence_zone_radius_end 400`), walk outside the ring.

Expected: `RSG: zone: <name> outside at <d> / <r>` once on crossing out, health dropping about `scr_resurgence_zone_damage` per second, and death if you stay. Walk back in: damage stops and no further `outside` line appears until you cross out again. If `dodamage` throws a script error, its argument list differs on this build — reduce to `var_1 dodamage( var_0, var_1.origin )` and re-verify.

- [ ] **Step 6: Verify spawns respect the ring**

With the ring small, die and redeploy repeatedly. Expected: every spawn lands inside the ring, and `_spawning` logs either a squadmate line or `random of N` with `N` **smaller** than the full candidate count from Task 6 Step 4. If `N` is unchanged, `in_zone` is not filtering — check that `level.rsg_center` and `level.rsg_radius` are both set.

- [ ] **Step 7: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_zone.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _zone: shrinking ring with out-of-ring damage

Centres on the centroid of the map's spawn points, holds and shrinks on a
dvar-driven phase schedule, and damages anyone outside once per second.
Publishes level.rsg_center and level.rsg_radius for _spawning to filter
candidates against; both stay undefined when the ring is disabled."
```

---

### Task 10: `_win.gsc` — wipes and last squad standing

**Files:**
- Create: `src/data/scripts/mp/resurgence/_win.gsc`
- Modify: `src/data/scripts/mp/_resurgence.gsc`

**Interfaces:**
- Consumes: `_squads::squad_is_wiped`, `_squads::squad_members`, `_squads::living_squad_ids`, `_squads::dump_squads`, `_redeploy::eliminate`, `rsg_log`.
- Produces: nothing other tasks consume. This is the last task; it closes the loop by ending matches.

- [ ] **Step 1: Write the module**

```gsc
init()
{
    level thread watch();
}

// Polls rather than hooking a death callback: level.onplayerkilled is
// assigned by dm.gsc for scoring, and hooking it would add a fourth
// callback to ADR-5's overwrite exposure for no gain.
watch()
{
    level endon( "game_ended" );

    level waittill( "prematch_over" );

    for (;;)
    {
        wait 0.5;

        if ( game["state"] != "playing" )
            continue;

        // Grace-period deaths do not count. Also neutralises setteam()
        // at _menus.gsc:362, which suicides the player after clearing
        // self.hasspawned.
        if ( level.ingraceperiod )
            continue;

        check_wipes();
        check_last_squad();
    }
}

check_wipes()
{
    foreach ( var_0 in squad_ids() )
    {
        if ( !scripts\mp\resurgence\_squads::squad_is_wiped( var_0 ) )
            continue;

        var_1 = scripts\mp\resurgence\_squads::squad_members( var_0 );

        if ( all_eliminated( var_1 ) )
            continue;

        iprintln( "RESURGENCE: squad " + var_0 + " wiped" );
        scripts\mp\_resurgence::rsg_log( "win: squad " + var_0 + " wiped, eliminating " + var_1.size + " member(s)" );

        foreach ( var_2 in var_1 )
            scripts\mp\resurgence\_redeploy::eliminate( var_2 );
    }
}

check_last_squad()
{
    var_0 = scripts\mp\resurgence\_squads::living_squad_ids();

    if ( var_0.size != 1 )
        return;

    if ( squad_ids().size < 2 )
        return;

    var_1 = scripts\mp\resurgence\_squads::squad_living_members( var_0[0] );

    if ( var_1.size == 0 )
        return;

    iprintlnbold( "RESURGENCE: squad " + var_0[0] + " wins" );
    scripts\mp\_resurgence::rsg_log( "win: squad " + var_0[0] + " is last standing, ending match" );
    scripts\mp\resurgence\_squads::dump_squads();

    var_2 = game["end_reason"]["enemies_eliminated"];

    if ( !isdefined( var_2 ) )
        var_2 = game["end_reason"]["ended_game"];

    level thread maps\mp\gametypes\_gamelogic::endgame( var_1[0], var_2 );
}

squad_ids()
{
    var_0 = [];

    foreach ( var_1 in level.players )
    {
        if ( !isdefined( var_1 ) || !isdefined( var_1.rsg_squad ) )
            continue;

        if ( !common_scripts\utility::array_contains( var_0, var_1.rsg_squad ) )
            var_0[var_0.size] = var_1.rsg_squad;
    }

    return var_0;
}

all_eliminated( members )
{
    foreach ( var_0 in members )
    {
        if ( !isdefined( var_0.rsg_eliminated ) || !var_0.rsg_eliminated )
            return 0;
    }

    return 1;
}
```

`endgame`'s first argument is a **player entity** in non-teambased modes (`_gamelogic.gsc:134` passes one), which is why `var_1[0]` is passed rather than a squad id. The `squad_ids().size < 2` check stops a solo tester's single squad from instantly ending the match.

- [ ] **Step 2: Wire it in `_resurgence.gsc`**

In `init()`, after `_zone::init()`:

```gsc
    scripts\mp\resurgence\_win::init();
```

- [ ] **Step 3: Verify no wipe is reported during the grace period**

Deploy, restart with two clients in one squad, `squadsize 2`, debug on. **During the grace period**, have both clients die (or have one switch team via the menu, exercising `setteam` at `_menus.gsc:362`).

Expected: **no** `win: squad N wiped` line, no `RESURGENCE: squad N wiped` message, both players still respawn. This is spec verification step 3a, and it is the one that stops a menu team-switch from wiping a squad before the match starts.

- [ ] **Step 4: Verify a wipe after the grace period**

Four clients, `squadsize 2`, so squads 0 and 1. After the grace period, kill both members of squad 1 within the redeploy window.

Expected: `RSG: win: squad 1 wiped, eliminating 2 member(s)`, two `RSG: eliminate:` lines, the in-game `RESURGENCE: squad 1 wiped`, and **neither** member respawns. Kill only one member of squad 0: no wipe line, and that member redeploys normally.

- [ ] **Step 5: Verify the mid-wait cancellation**

With `scr_resurgence_redeploydelay 20`, kill one member of squad 1, then kill the second **while the first is still counting down**.

Expected: the wipe fires, the first player's countdown clears instead of completing, and neither spawns. This is the `squad_is_wiped` definition from the spec working end to end — a player in the redeploy delay does not count as alive.

- [ ] **Step 6: Verify the match ends**

Continue from Step 4 with squads 0 and 1: with squad 1 wiped, squad 0 is the only living squad.

Expected: `RSG: win: squad 0 is last standing, ending match`, the in-game `RESURGENCE: squad 0 wins`, a squad dump, and the match actually ending on the end-of-game screen. If the server throws on `endgame`, re-check the argument against `_gamelogic.gsc:2204` — it takes three parameters and defaults the third, so a two-argument call is correct.

- [ ] **Step 7: Verify a solo tester does not end the match instantly**

Restart with **one** client. Expected: no win line and no match end, despite exactly one living squad — the `squad_ids().size < 2` guard. Without this, every solo test would end the moment the grace period expired.

- [ ] **Step 8: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add src/data/scripts/mp/resurgence/_win.gsc src/data/scripts/mp/_resurgence.gsc
git commit -m "Add _win: squad wipes and last-squad-standing victory

A 0.5s watcher detects wipes and ends the match, rather than hooking
level.onplayerkilled, which dm.gsc assigns for scoring. Skips entirely
while level.ingraceperiod, so a grace-period death or a setteam suicide
cannot wipe a squad before the match starts. Ends via endgame() with a
living member of the winning squad, since FFA's winner is a player
entity, and announces the squad by text alongside it."
```

---

### Task 11: Full-match verification and documentation

**Files:**
- Create: `docs/VERIFICATION-v1.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: a recorded pass/fail for each of the spec's verification steps, and a usable README.

- [ ] **Step 1: Run the spec's verification list end to end**

Work through the spec's Verification section — steps 0 through 7 — in one sitting with four clients, the ring enabled on a compressed schedule, and debug on. Record for each: pass/fail, and the console line or in-game observation that proves it.

- [ ] **Step 2: Write `docs/VERIFICATION-v1.md`**

One row per spec verification step: step name, pass/fail, the evidence, the map tested on, and the dvar values used. Write what was observed. **An unrun step is recorded as "not run", never as a pass** — a verification doc that overstates what was tested is worse than no doc, because the next person trusts it.

- [ ] **Step 3: Record the tuning the spec could not**

The spec's zone defaults (4000→400 units over 5 phases, 45s hold, 30s shrink) were picked without a map. Add a short section to `docs/VERIFICATION-v1.md` giving the values that actually played well on the map tested, the map's approximate extent from the logged centroid and spawn spread, and whether `scr_resurgence_squadsize 2` produced sensible match length. If the defaults in `_resurgence.gsc` should change, change them and say why.

- [ ] **Step 4: Finish the README**

Add a "Status" section listing what works, what is unverified (weapon names if still unset; anything recorded "not run"), and the deferred items from the spec — squadmate blips, squad-aware scoreboard, a registered gametype ref. Point at `docs/VERIFICATION-v1.md` and `docs/RUNNING.md`.

- [ ] **Step 5: Commit**

```bash
cd ~/ws/personal/resurgence_mod_ghost
git add docs/VERIFICATION-v1.md README.md src/data/scripts/mp/_resurgence.gsc
git commit -m "Record v1 verification results and tuned zone defaults"
```

---

## Deviations to expect — status after Tasks 1-3

| Item | Status |
| --- | --- |
| Same-file `replacefunc` | **Resolved: works.** Task 5 proceeds as written; no `_playerlogic.gsc` fallback. |
| The FFA spawn classname | **Still open.** `mp_dm_spawn` inferred; Task 6 logs the count and falls back to the tdm array. |
| MP weapon names | **Resolved.** 11 real names harvested from kill lines (`docs/RUNNING.md`). |
| Bot command spelling | **Resolved differently.** `spawn_bot` / `bot_team_join` are not commands at all; `addbot` and friends do nothing over rcon. Controlled counts come from `+set sv_maxclients 4 +set sv_botsAutoJoin 1` at launch. |
| Editing files CBServers ships | **Resolved: impossible.** Restored within ~3s, silently. All four planned edits dropped; everything goes through `replacefunc` (ADR-6). |

Anything else that contradicts the spec's "verified hook points" table should be recorded
in the task's commit message and reported, not worked around silently.
