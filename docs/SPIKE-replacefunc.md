# Spike results — replacefunc and the debug channel

**Date:** 2026-10-02 · **Task 2** · server: iw6-mod dedicated, `mp_prisonbreak`, `g_gametype dm`, 18 autojoin bots

Observed, not predicted. Evidence is `logs/games_mp.log` unless stated otherwise.

| Question | Answer | Evidence |
| --- | --- | --- |
| Is `data/scripts/mp/*.gsc` auto-loaded? | **Yes** | `rsg_spike_main` and `rsg_spike_init` both set |
| Which entry point does the loader call? | **Both `main()` and `init()`** | both dvars set from one file — so defining both double-installs |
| Does `replacefunc` patch a **same-file** call? | **YES** | `RSG_SPIKE mayspawn stub reached` logged repeatedly as bots spawned (`_playerlogic.gsc:122` calls `mayspawn` in its own file) |
| Does `replacefunc` patch **cross-script**? | **YES** | `RSG_SPIKE attackerIsHittingTeam stub reached` logged as bots traded fire |
| Debug channel | **`logprint( "...\n" )`** | the only one of three that reached the log |
| `logstring()` | **Invisible** — writes nothing to `games_mp.log` | `setdvar` on the adjacent line worked, so the call ran |
| `println()` | **Invisible** in the log | same test |

## Consequences for the plan

1. **Task 5 proceeds as written.** Same-file `replacefunc` works, so `_redeploy` hooks
   `mayspawn` directly. The fallback (a marked edit to a copied `_playerlogic.gsc`, a
   fifth overlay edit) is **not needed** and should be dropped from the deviations list.

2. **`rsg_log()` must use `logprint`, not `logstring`.** The plan and Task 3's code
   specify `logstring`; that would have produced a completely silent mod and sent every
   later task hunting for a bug that was only ever in the logging. Note the explicit
   `\n` — `logprint` does not add one.

3. **Define `init()` only, never both.** The loader enters `main()` *and* `init()`, so a
   file defining both runs its wiring twice. `_resurgence.gsc` uses `init()` alone.

4. **ADR-5 is load-bearing, not insurance.** `level.teambased` is **undefined** when our
   script runs: `setdvar( "rsg_spike_teambased", level.teambased )` never executed while
   the line before it did, so the script died there. Our scripts load *before* the
   gametype initialises `level` state, which means the gametype **will** overwrite any
   callback we assign in `init()`. The re-assert hook after
   `[[ level.onstartgametype ]]()` is required for `_spawning`, `_loadout` and
   `_redeploy`'s delay to work at all.

   Corollary for Task 3: `init()` must not read gametype `level` state. Reading
   `level.teambased` or `level.gametype` there is a script error, not a value.

5. **`main()` re-runs on `map_restart`.** Two `logprint from main` lines appeared across a
   restart, so per-match setup must be idempotent or guarded.

## Bot commands — the plan was wrong

`spawn_bot` and `bot_team_join` **do not exist as console commands**. They were read out
of C++ symbol names (`bot_team_join@?A0x…@bots@@`), which is a mangled function, not a
registered command. Exact-match against the binary gives only `addbot`, `bot_team`,
`addtestclient`, `spawntestclient`.

And over rcon, **none of those four worked** — all returned nothing and added no players.
What does work:

```
+set sv_botsAutoJoin 1    # at LAUNCH only
```

Set at launch it fills every slot within seconds (18 here) and the bots fight with real
loadouts. Set at runtime over rcon, even followed by `map_restart`, it added nobody. The
four commands are likely console-only; they remain untested from the server's own window.

**Consequence for Task 4:** bot count is not controllable from rcon yet. Verifying duo
packing (`squadsize 2` → squads `0,0,1,1`) needs either a lower `sv_maxclients` at launch
or those commands typed in the server console. Decide before Task 4 Step 4.
