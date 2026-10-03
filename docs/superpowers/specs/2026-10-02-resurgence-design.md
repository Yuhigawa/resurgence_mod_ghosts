# Resurgence for Call of Duty: Ghosts (IW6) — Design

**Date:** 2026-10-02
**Repo:** `~/ws/personal/resurgence_mod_ghost` (WSL)
**Deploy target:** `D:\games\cod_cbservers\ghosts_game_files` (WSL: `/mnt/d/games/cod_cbservers/ghosts_game_files`)
**Status:** Approved, ready for implementation planning

## Problem

Warzone-style **Resurgence** does not exist in Ghosts. We want its core loop on an
IW6 server: squads fight on one map, a dead player redeploys as long as a squadmate
lives, a wiped squad is out for good, a shrinking ring forces contact, and the last
squad standing wins.

## Scope

**v1 delivers:** virtual squads in FFA, redeploy-if-squadmate-alive, permanent
elimination on squad wipe, spawn near a living squadmate, a shrinking zone with
out-of-ring damage, fixed loadouts, and last-squad-standing victory.

**v1 excludes** (deliberate, see Deferred): squadmate compass blips / blue names,
a squad-aware scoreboard, buy stations, loot, contracts, gulag, a registered
`resurgence` gametype entry, and any client-side LUA work.

## Environment (verified on disk)

- Full IW6 install. Stock scripts are compiled inside `zone/*.ff`; **no stock GSC
  source is available locally**, and `git.alterware.dev` (the usual dump mirror) was
  returning 404/502 at design time. The design therefore depends only on local files
  plus `replacefunc`.
- This build loads **plain-text GSC from `data/`**. No `.gscbin` compile step.
- `data/` already contains full-file overrides of the three files that matter:
  `maps/mp/gametypes/_damage.gsc` (3302 lines), `_gamelogic.gsc` (2770),
  `_playerlogic.gsc` (1883), plus `_menus.gsc`, `aliens.gsc`, two map/alien scripts.
- `data/scripts/mp/_patches.gsc` proves `replacefunc` works here and that scripts
  under `data/scripts/mp/` are auto-loaded (`main()` in `_patches.gsc`, `init()` in
  `_team_balance.gsc` — both are entered by the loader).
- 13 CB-Servers LUA UI mods in `data/ui_scripts/`. Gametype identity comes from
  `mp/gameTypesTable.csv` inside a fastfile, which is why v1 does not register a new
  gametype ref.

### Verified hook points

| Hook | Location | Used for |
| --- | --- | --- |
| `mayspawn()` | `_playerlogic.gsc:81` | gate redeploy; returning 0 sends the player to spectator via `spawnclient()` |
| `level.onrespawndelay` | called at `_playerlogic.gsc:50` | per-player redeploy delay, overriding `scr_<gametype>_playerrespawndelay` |
| `level.getspawnpoint` | called at `_playerlogic.gsc:548`, `:578`, `:372` | spawn selection |
| `level.onspawnplayer` | called at `_playerlogic.gsc:678` | per-spawn setup |
| `maps\mp\_utility::attackerishittingteam` | consumed at `_damage.gsc:1602` as `var_13` | single gate feeding every `level.friendlyfire == 0` branch |
| `endgame( winner, reason )` | `_gamelogic.gsc:2204` | in non-teambased modes the winner is a **player entity**, not a team string |
| `level.ondeadevent` / `level.ononeleftevent` | `_gamelogic.gsc:90`, `:120` | vanilla elimination events (not used — see ADR-2) |
| `givelastonteamwarning()` | `_gamelogic.gsc:2481` | reference for callout style |

## Architecture

`g_gametype dm` (free-for-all) runs, and Resurgence layers on top. Every file is
auto-loaded by the server from the game's `data/scripts/mp/`, and does nothing unless
`scr_resurgence_enabled` is `1`.

Sources live in the repo under `src/data/`, mirroring the game's layout exactly, and
are copied into the install by `deploy.sh` (see Repository):

```
src/data/scripts/mp/_resurgence.gsc          entry point: dvars, wiring, nothing else
src/data/scripts/mp/resurgence/_squads.gsc   membership and queries
src/data/scripts/mp/resurgence/_redeploy.gsc may I respawn, and after how long
src/data/scripts/mp/resurgence/_spawning.gsc where I respawn
src/data/scripts/mp/resurgence/_zone.gsc     shrinking ring and gas damage
src/data/scripts/mp/resurgence/_friendlyfire.gsc squadmates cannot damage each other
src/data/scripts/mp/resurgence/_loadout.gsc  fixed kit, killstreaks off
src/data/scripts/mp/resurgence/_win.gsc      squad-wipe and last-squad-standing
```

Paths named elsewhere in this document (`_damage.gsc:1602` and similar) refer to the
installed game tree under `/mnt/d/games/cod_cbservers/ghosts_game_files/data/`.

### Module contracts

**`_resurgence.gsc`** — registers every dvar, then wires modules in dependency order
(`_squads` → `_redeploy` → `_spawning` → `_loadout` → `_zone` → `_win`). Each wiring
step is individually guarded: if a module cannot install its hook, it logs and leaves
vanilla behaviour intact rather than half-applying. Contains no gameplay logic.

**`_squads.gsc`** — the only owner of squad state. Exposes:

- `squad_of( player )` → int squad id, or `undefined` before assignment
- `same_squad( a, b )` → bool, false when either is undefined or `a == b`
- `squad_members( id )` → array of connected players in that squad
- `squad_living_members( id )` → members passing `maps\mp\_utility::isreallyalive`
- `squad_is_wiped( id )` → no member passes `isreallyalive`. A player sitting in the
  redeploy delay does **not** count as alive, so if the last living member dies while a
  squadmate is waiting to redeploy, the squad is wiped and that pending redeploy is
  cancelled — matching Resurgence.
- `living_squad_ids()` → array of squad ids not yet eliminated

Player fields: `player.rsg_squad` (int), `player.rsg_eliminated` (bool).
Assignment on connect fills the **lowest-numbered squad with a free slot**, capacity
`scr_resurgence_squadsize`. Membership survives death and is released on disconnect.

**`_redeploy.gsc`** — `replacefunc( maps\mp\gametypes\_playerlogic::mayspawn, ::rsg_mayspawn )`.
Returns 0 when `self.rsg_eliminated`, otherwise delegates to a copy of vanilla's
checks. Sets `level.onrespawndelay = ::rsg_respawndelay`, returning
`scr_resurgence_redeploydelay` (default 15). On death, if
`squad_living_members( squad_of( self ) )` is empty, the whole squad is flagged
eliminated; otherwise the player redeploys normally.

**Deaths during the grace period do not count.** `_redeploy` ignores any death while
`level.ingraceperiod` is set: no life is spent, no squad is flagged wiped. This is
correct on its own terms — no squad should be eliminated before the match has started —
and it also neutralises `setteam()` at `_menus.gsc:362`, a third
`ingraceperiod && !self.hasdonecombat` branch which sets `self.hasspawned = 0` (`:370`),
calls `self suicide()` (`:382`), and then re-enters `spawnclient()` (`:397`). FFA still
exposes team selection on some menu paths, so without this rule a grace-period team
switch would cost the squad a life, and would wipe the squad outright if the switcher was
its last living member. That site needs no guard of its own — it calls no loadout
function — only this rule.

A related latent coupling, documented so it is not rediscovered: `setteam()` falsifies
`self.hasspawned`, which is what vanilla's latecomer check at `_playerlogic.gsc:95` keys
on, and `rsg_mayspawn` copies that check. It cannot bite us **in this configuration**,
because the whole block holding both the lives and latecomer checks is gated at
`_playerlogic.gsc:82` on `getgametypenumlives() || isdefined( level.disablespawning )` —
and with `numlives` at 0 per ADR-2 and `disablespawning` never set, vanilla `mayspawn`
returns 1 unconditionally. The copied checks are therefore dead code under our config.
They are kept for fidelity: they are exactly what would start mattering if anyone ever
enables `numlives`, and `rsg_mayspawn` should behave correctly if they do.

Because a squad can be wiped *while* a member waits out the redeploy delay, this module
also listens for its own squad's wipe and cancels a pending redeploy: it sets
`rsg_eliminated`, notifies `end_respawn` to break the waiting thread
(`_playerlogic.gsc:169` endons it), clears the spawn lower-message, and leaves the
player as a spectator.

**`_spawning.gsc`** — `level.getspawnpoint = ::rsg_getspawnpoint`. Takes the map's
existing `mp_dm_spawn` structs via `maps\mp\gametypes\_spawnlogic::getspawnpointarray`,
discards any outside the current ring, scores the remainder by distance to the nearest
living squadmate, and returns the best. Falls back to
`_spawnlogic::getspawnpoint_random` over the in-ring set when the player has no living
squadmate (first spawn, or match start). Reuses real spawn structs rather than
synthesising origins, so players never spawn inside geometry.

**`_zone.gsc`** — owns `level.rsg_center` (vector), `level.rsg_radius` (float) and a
phase table built from dvars. The centre starts at the centroid of the map's dm spawn
points with a bounded random offset, and is pulled toward that centroid each phase. A
1-second loop damages every living player whose `distance2d( origin, center )` exceeds
the radius, and shows a lower-message warning while they are outside. Phase changes
announce via `iprintln`.

**`_loadout.gsc`** — one preset weapon/perk kit applied on spawn, killstreaks
disabled. Uses `level.custom_giveloadout = ::rsg_giveloadout`, which `spawnplayer`
consumes **unconditionally** at `_playerlogic.gsc:696-697`, replacing the default
`_class::giveloadout` call on the `else` branch. That path is gametype-agnostic and so
runs under `dm`; `aliens.gsc:58` is precedent for the same hook, not a dependency on it.

Note what *not* to use here: `level.custom_onspawnplayer_func` is read only inside
`aliens.gsc`'s own `onspawnplayer` (`aliens.gsc:648`) and is never consulted under
`dm`. Non-loadout per-spawn setup goes through `level.onspawnplayer`
(`_playerlogic.gsc:678`) instead. The callback receives vanilla's faux-spawn flag as
its one argument; pass it through.

**The hook runs after `setclass`.** `_class::setclass( self.class )` is called at
`_playerlogic.gsc:694`, two lines before our hook, so whatever the player's chosen class
grants is applied first and we overwrite on top. `rsg_giveloadout` must therefore be a
*clear slate*, not a top-up, and in particular **killstreaks must be disabled inside the
hook body** — never assumed absent because `setclass` ran. `aliens.gsc:1107-1211` is the
working precedent for exactly this shape: `takeallweapons()` (`:1109`), action slots
cleared (`:1113-1123`), `_clearperks()` (`:1125`), then `self.killstreaktype = "none"`
(`:1137`) before anything is granted. Follow that order.

**Weapon names are dvar-driven, with a call-through default.** No plain MP weapon name
is verifiable from `data/` — every attested `iw6_*_mp` string there is an alien or
special variant — and a bad name passed to `giveweapon` risks a script error. So
`scr_resurgence_primary` and `scr_resurgence_secondary` default to **empty**, and when
both are empty `rsg_giveloadout` strips killstreaks and perks and then calls through to
`_class::giveloadout`, leaving the player their chosen class. That makes "no killstreaks"
work from the first build instead of blocking the module on a guessed weapon name; the
true fixed kit arrives by setting the two dvars once names are confirmed in-game.

**Two bypass sites to close.** `_class::giveloadout` is also called *directly*,
ignoring `level.custom_giveloadout`, at `_menus.gsc:182` and `_menus.gsc:598` — the
class-change paths, both gated on `level.ingraceperiod && !self.hasdonecombat`. The
window is narrow but it is exactly when players sit in the class menu, and a Resurgence
player who spawns at match start and never dies would keep that vanilla kit, killstreaks
included, for the whole match. `_menus.gsc` is a local overlay, so both sites get a
marked edit mirroring the guard at `_playerlogic.gsc:696-699`:
call `level.custom_giveloadout` when defined, else the stock function. (The alternative,
`replacefunc` on `_class::giveloadout` itself, would cover all three call sites with one
cross-script hook and no edits; rejected because it discards a stock function whose
internals we cannot read, where the guard keeps vanilla behaviour intact whenever the
mod is off.)

**No death hook anywhere.** `level.onplayerkilled` is called unconditionally at
`_damage.gsc:852`, and `dm.gsc` assigns it for scoring, so using it would mean chaining
through dm's handler and would add a fourth callback to ADR-5's overwrite exposure.
Nothing in this design needs it: `_win`'s watcher detects wipes by polling, and the
redeploy decision is made inside `mayspawn` at spawn time. The grace-period rule is
likewise enforced in the watcher, which skips wipe flagging while `level.ingraceperiod`
is set.

**`_win.gsc`** — a 0.5s watcher thread. When a squad transitions to wiped it announces
the wipe and marks members eliminated. When exactly one squad remains it announces the
winning squad with `iprintlnbold` and calls
`maps\mp\gametypes\_gamelogic::endgame( <a living member>, game["end_reason"]["enemies_eliminated"] )`.

That `end_reason` key is populated outside `data/`, so it cannot be confirmed locally.
It is very likely present under `dm`: `_gamelogic.gsc:134` passes it from the
**non-teambased** branch of `default_ononeleftevent`, which is dm's own last-player-alive
path, so vanilla FFA would already be broken if it were unset. `_win.gsc` guards it
anyway and falls back to `game["end_reason"]["ended_game"]`, since the cost is one
`isdefined`.

### Callback installation order

Three callbacks are at risk: `level.getspawnpoint`, `level.onspawnplayer` and
`level.onrespawndelay`, all assigned by `_spawning` and `_redeploy`.
`dm.gsc` lives in a fastfile and assigns its own values to those same pointers from
`[[ level.onstartgametype ]]()`, called at `_gamelogic.gsc:1660`. Whether
`scripts/mp/` loads before or after that is not documented and not observable from
`data/`, and if the gametype wins, three of six modules die **silently** — no script
error, no log line.

Rather than discover the ordering empirically and depend on it, installation is made
order-independent by doing it twice:

1. `_resurgence.gsc`'s `init()` assigns the callbacks directly.
2. A marked hook in `callback_startgametype`, immediately after
   `[[ level.onstartgametype ]]()` at `_gamelogic.gsc:1660`, calls
   `level.rsg_install_callbacks` if it is defined.

If our script loads *after* the gametype, step 1 already won. If it loads *before*,
step 2 re-asserts over the gametype's assignments. Both orders land correctly, and
step 2 runs before `startgame()` is threaded at `:1667`, so it is always in place
before play begins. The hook is three lines in a file we already override, wrapped in
`// RESURGENCE BEGIN` / `// RESURGENCE END`.

`replacefunc` (used for `mayspawn` and the friendly-fire gate) is unaffected by load
order; only plain pointer assignments have this problem.

`level.custom_giveloadout` is **not** part of the risk this defends against: it is a
loader extension point, undefined by default, and `dm.gsc` has no reason to assign it —
the only thing that reads it is the `isdefined` guard at `_playerlogic.gsc:696`. The
re-assert covers it anyway because doing so is free, but its inclusion should not be read
as evidence that the overwrite risk extends to loader extension points. The three
callbacks above are the actual exposure.

### Friendly fire

Lives in `_friendlyfire.gsc`.

`replacefunc( maps\mp\_utility::attackerishittingteam, ::rsg_hitting_squad )`, which
returns true when attacker and victim are in the same squad (and otherwise reproduces
vanilla's team check). Because `_damage.gsc` funnels every friendly-fire decision
through that one value (`var_13`, `_damage.gsc:1602`), one hook covers all damage
paths — including those in stock files we do not have locally. Requires
`scr_friendlyfire 0`.

**Fallback** if that stock function cannot be hooked: a marked two-line edit at
`_damage.gsc:1602` ORing in the squad check. Any such edit to a dumped overlay file is
wrapped in `// RESURGENCE BEGIN` / `// RESURGENCE END` comments so it survives a future
re-dump by being easy to find and re-apply.

## Configuration

| Dvar | Default | Meaning |
| --- | --- | --- |
| `scr_resurgence_enabled` | `0` | master switch; everything is inert at 0 |
| `scr_resurgence_squadsize` | `2` | players per squad (duos; 18 players ⇒ 9 squads) |
| `scr_resurgence_redeploydelay` | `15` | seconds from death to redeploy |
| `scr_resurgence_zone_enabled` | `1` | ring on/off, for isolating redeploy bugs |
| `scr_resurgence_zone_phases` | `5` | number of shrink phases |
| `scr_resurgence_zone_radius_start` | `4000` | units, first phase |
| `scr_resurgence_zone_radius_end` | `400` | units, final phase |
| `scr_resurgence_zone_hold` | `45` | seconds the ring holds before shrinking |
| `scr_resurgence_zone_shrink` | `30` | seconds a shrink takes |
| `scr_resurgence_zone_damage` | `5` | damage per second outside the ring |
| `scr_resurgence_debug` | `0` | log squad tables, redeploy decisions, zone phases |

Required server config: `g_gametype dm`, `scr_friendlyfire 0`,
`scr_dm_numlives 0`, `scr_dm_playerrespawndelay 0` (ours overrides it anyway).

## Error handling

- Every module guards every entity and array access with `isdefined`; a player who
  disconnects mid-loop must never abort a watcher thread.
- Watcher and zone threads use `level endon( "game_ended" )`; per-player threads use
  `self endon( "disconnect" )`.
- Each module's wiring is independently guarded in `_resurgence.gsc`, so one failed
  hook degrades that feature rather than the match.
- `scr_resurgence_enabled 0` restores stock FFA without removing files.

## Verification

GSC has no test harness here, so verification is explicit and manual:

0. **Spike: same-file `replacefunc`** — before any module is built, a throwaway script
   replaces `_playerlogic::mayspawn` with a stub that logs and returns 1, and we confirm
   the log appears on spawn. `mayspawn` is called from `spawnclient()` at
   `_playerlogic.gsc:122`, i.e. **within the same script file**, and whether this
   loader patches same-file direct calls or only cross-script resolution decides
   whether `_redeploy` can work at all. If the stub never fires, `_redeploy` switches
   to a marked edit of `mayspawn` in the local overlay instead, and the spike has cost
   five minutes rather than a module. The same spike confirms the
   `attackerishittingteam` hook, which is cross-script and expected to work.

1. **Parse pass** — every new file loads without a script error on server start.
2. **Squad assignment** — with `scr_resurgence_debug 1`, join with several clients and
   confirm the logged squad table matches join order and `squadsize`.
3a. **Grace-period deaths** — during the grace period, switch team from the menu
   (`setteam`, `_menus.gsc:362`) and confirm no life is spent and no squad is reported
   wiped, including when the switcher is the squad's only living member.
3. **Redeploy** — die with a squadmate alive: redeploy after the delay, near that
   squadmate. Die with no squadmate alive: permanent spectate, squad announced wiped.
4. **Friendly fire** — shoot a squadmate: no damage. Shoot a non-squadmate: damage.
5. **Loadout** — spawn and confirm the preset kit with no killstreaks available, then
   change class *during the grace period* and confirm the kit survives it (this is the
   `_menus.gsc:182` / `:598` bypass; before the guard is added, expect it to fail).
6. **Zone** — with `scr_resurgence_zone_enabled 1`, confirm phase announcements, that
   standing outside deals damage, and that spawns stay inside the ring.
7. **Win** — reduce to one squad and confirm the match ends naming that squad.

Each step is runnable in isolation because the zone and the mod itself are
dvar-gated. No success claim is made for any step without the console output or
in-game observation that backs it.

## Decisions

**ADR-1 — ride `dm` instead of registering a `resurgence` gametype.**
Gametype refs come from `mp/gameTypesTable.csv` inside a fastfile, and the lobby and
class-select LUA branch on `GameX.GetGameMode()`. Registering a new ref risks a
dead-end before any gameplay exists. Riding `dm` works on stock clients today; the
server browser will show the mode as Free-For-All. Renaming is a separate later phase.

**ADR-2 — our own watcher thread rather than vanilla's alive-count events.**
`updategameevents` (`_gamelogic.gsc:278`, early return at `:346`) returns early unless `numlives` is nonzero or
spawning is disabled, and enabling `numlives` pulls in `pers["lives"]` bookkeeping,
latecomer rules (`mayspawn`, `_playerlogic.gsc:81-105`) and lobby UI we would then
have to fight. A dedicated 0.5s thread is more code and far fewer side effects, and
keeps `numlives` at 0.

**ADR-3 — FFA with virtual squads rather than two teams or multiteam.**
Chosen for squad count: duos scale to 9 squads, which two-team mode cannot express and
IW6's lightly-tested multiteam path would strain. Accepted costs, carried knowingly
into v1: squadmates render as enemies (no blue names, no compass blips), the
scoreboard stays per-player, and FFA's end screen can crown only one player, so the
winning **squad** is announced by text alongside it. v1 compensates with text only —
squad roster on spawn, "squadmate down", "squad wiped".

**ADR-4 — depend only on local files plus `replacefunc`.**
No stock GSC source is available locally and the usual mirror was down. Every hook in
this design either targets a file already present in `data/` or goes through
`replacefunc`, which needs the stock function's signature and semantics but not its
source.

**ADR-5 — install callbacks twice rather than rely on load order.**
See Callback installation order. The alternative was to establish empirically whether
`scripts/mp/` loads before or after `[[ level.onstartgametype ]]()` and depend on the
answer. Rejected: the failure mode is silent (three modules inert, no script error),
the ordering is undocumented and could change with a server update, and a three-line
hook in a file we already override makes the question moot. Cost is one more marked
edit to a dumped overlay file.

## Deferred

- **Squadmate blips / blue names** — needs the stock objective API verified against a
  script dump. Deferred rather than guessed at.
- **Squad-aware scoreboard and end screen** — client LUA work.
- **A registered `resurgence` gametype ref** — revisit whether this loader can override
  `mp/gameTypesTable.csv`.
- **Warzone parity** — buy stations, loot, contracts, gulag. Entirely new systems.

## Repository

The repo is `~/ws/personal/resurgence_mod_ghost`, kept entirely separate from the game
install (which holds gigabytes of fastfiles and video and is not versioned).

```
docs/superpowers/specs/   this spec and later design docs
src/data/                 mod sources, mirroring the game's data/ layout
deploy.sh                 copy src/data/ into the game install
```

`deploy.sh` copies rather than symlinks: the game is a Windows process reading an NTFS
path, and WSL symlinks are not followed by Windows applications. It takes the install
path from `GHOSTS_DIR`, defaulting to
`/mnt/d/games/cod_cbservers/ghosts_game_files`, copies only files under `src/data/`,
never deletes anything in the install, and prints what it wrote.

Any edit this project makes to an **existing** overlay file in the install is also
committed here as a copy of that file under `src/data/`, so the change is versioned
rather than living only in the game folder. Four such edits are foreseen:

- `_gamelogic.gsc` — the `callback_startgametype` re-assert hook (ADR-5, certain)
- `_menus.gsc` ×2 — the `custom_giveloadout` guard at `:182` and `:598` (certain)
- `_damage.gsc` — the friendly-fire fallback, only if `replacefunc` on
  `attackerishittingteam` fails

All are wrapped in `// RESURGENCE BEGIN` / `// RESURGENCE END`.
