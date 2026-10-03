# Resurgence for CoD: Ghosts (IW6)

Warzone-style **Resurgence** as a server-side GSC mod, layered on free-for-all:
squads fight on one map, a dead player redeploys while a squadmate lives, a wiped
squad is out for good, a shrinking ring forces contact, and the last squad standing
wins.

Built for CBServers' iw6-mod. **No client install, no map edits, no fastfile work** —
seven new GSC files dropped into `data/`, every hook via `replacefunc` or a `level.*`
callback.

## Status

All seven modules are implemented and verified on a live dedicated server.

| Module | Does | Verified |
| --- | --- | --- |
| `_squads` | squad membership, capacity packing | duo and quad packing, disconnect frees a seat |
| `_redeploy` | redeploy delay, elimination, the `mayspawn` gate | delay is ours, eliminated players stay out |
| `_spawning` | spawn near a living squadmate, inside the ring | `mp_dm_spawn`, 15 points, no stacking |
| `_friendlyfire` | squadmates cannot damage each other | human client: 25 blocked, 0 damage landed |
| `_loadout` | one fixed kit, no killstreaks, no class menu | kill log contains only the kit's weapons |
| `_zone` | shrinking ring, lethal outside | phases, damage, and ring deaths feed wipes |
| `_win` | wipes and last squad standing | match ends and cycles correctly |

Full results, including what is **not** verified and the known limitations:
[docs/VERIFICATION-v1.md](docs/VERIFICATION-v1.md).

## Running it

```bash
./deploy.sh                       # copies src/data/ into the install, and server.cfg into main/
cd /mnt/d/games/cod_cbservers/ghosts_game_files
./iw6x.exe -dedicated +set net_port 28960 +set rcon_password <yours> +exec server.cfg +map_rotate
```

Then connect a client to `127.0.0.1:28960`. Details, gotchas and the rcon tool:
[docs/RUNNING.md](docs/RUNNING.md).

To play against bots, launch with `+set sv_maxclients 4 +set sv_botsAutoJoin 1` — then
raise `sv_maxclients` over rcon to open a slot for yourself, since autojoin fills every
slot and bots cannot be added at runtime.

## Configuration

| Dvar | Default | Meaning |
| --- | --- | --- |
| `scr_resurgence_enabled` | `0` | master switch; everything is inert at 0 |
| `scr_resurgence_squadsize` | `2` | players per squad. `1` turns the mode into elimination FFA, since nobody ever has a squadmate to redeploy on |
| `scr_resurgence_redeploydelay` | `15` | seconds from death to redeploy |
| `scr_resurgence_spawn_min_dist` | `200` | how far from your squadmate you land, so partners are not stacked on one point |
| `scr_resurgence_primary` | `iw6_imbel_mp` | fixed primary; empty skips the kit |
| `scr_resurgence_secondary` | `iw6_p226_mp` | fixed secondary |
| `scr_resurgence_zone_enabled` | `1` | the ring |
| `scr_resurgence_zone_phases` | `5` | shrink phases |
| `scr_resurgence_zone_radius_start` | `2600` | tuned to mp_prisonbreak, measured |
| `scr_resurgence_zone_radius_end` | `250` | final circle |
| `scr_resurgence_zone_hold` | `35` | seconds held before each shrink |
| `scr_resurgence_zone_shrink` | `20` | seconds a shrink takes |
| `scr_resurgence_zone_damage` | `5` | damage per second outside |
| `scr_resurgence_debug` | `0` | log squads, spawns, redeploys and ring phases |

Required server config: `g_gametype dm`, `scr_friendlyfire 0`, `scr_dm_numlives 0`.

## How it works

The design, the hook points, and seven decision records (including why free-for-all,
and why nothing CBServers ships is ever modified) are in
[the spec](docs/superpowers/specs/2026-10-02-resurgence-design.md). There is also a
[visual walkthrough](https://claude.ai/code/artifact/b24fcf65-e0e9-4fca-a280-bfbefa68cf10).

## Not in v1

Squadmates render as enemies — no blue names or compass blips, which is the accepted
cost of building squads on free-for-all. Also absent: a squad-aware scoreboard, a
registered `resurgence` gametype entry, and anything Warzone-shaped beyond the core
loop (buy stations, loot, contracts, gulag).
