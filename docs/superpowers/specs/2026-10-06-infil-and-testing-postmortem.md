# Parachute infil: problems, fixes, and why bot testing missed them

**Date:** 2026-10-06
**Status:** infil working; testing method corrected

This exists because a player asked a fair question — *how could you not get that
in the tests with bots?* — after a feature I had reported as working left every
player frozen in mid-air. The answer is that I measured the wrong things. This
spec records every failure, its fix, and the testing rules that would have caught
them.

## The feature

Every spawn is a parachute drop: freefall steered by looking, a chute that opens
near the ground, and a crouch to cut it. No parachute animation exists in Ghosts,
so the player falls in a falling pose — accepted deliberately.

## Failures, in the order they happened

### 1. Looking up made players fly

Freefall velocity was `-900 + pitch × 1100`. Pitch is **positive when looking
up**, so looking up produced upward thrust. Players flew instead of falling and
never landed — one observed airborne for nearly a minute on a twenty-second drop.

**Fix:** clamp vertical velocity so it is always downward
(`scr_resurgence_infil_min_descent`, default 220).

**Why bots missed it:** bots do not look up while falling. The bug needed a human
input pattern that no bot produces. The player's report — "i'm flying" — was the
first and only signal, and I initially read it as the feature working.

### 2. Landings logged one second into a twenty-second drop

`isonground()` returns **true** for the first iterations after `setorigin`,
before the engine has processed the teleport. The control loop exited instantly
and logged a landing while the player was still in the sky with nothing managing
their descent.

**Fix:** require real airtime (1.5s) before believing `isonground()`.

**Why bots missed it:** the log *said* `landed`, and I was counting landings.
A count cannot distinguish a real landing from a false one. The duration and
altitude were not being logged, so the data that would have exposed it did not
exist.

### 3. Rooftop landings stranded players

Landing additionally required being within 120 units of the ground the player
started on. Anyone who drifted over a tall building and landed on a roof never
satisfied it: three bots stuck, one at altitude 984, released only by the
timeout.

**Fix:** landing depends on airtime and `isonground()` alone. Altitude is
reported, never used as a condition.

**Why bots missed it:** they didn't — this one *was* in the bot logs. I saw
`stuck: 3` and treated the timeout as the safety net doing its job rather than as
evidence the feature was broken. A safety net firing is a failure, not a pass.

### 4. Indoor spawns teleported players into buildings

The drop lifted players straight up from their spawn point. Many Ghosts spawns
are indoors, so this teleported them into the building above, where they froze at
exactly the drop height. Measured ceilings of 49 and 72 units over some spawns.

**Fix:** stop lifting from the spawn. Drop from open sky above the map, at
`ceiling_height() + infil_height`, where the ceiling reference is the highest
spawn point on the map.

**Why bots missed it:** it is **map-dependent**. I validated on `mp_hashima`
only. The bug appears on maps with indoor spawns and not at all on open ones.

### 5. Scattered drop points landed over the void

Scattering ±1200 units around the ring centre put drop points outside the
playable volume on smaller maps. With nothing beneath them, players hung at the
drop altitude until the timeout — 6 of 11 drops stuck, one moving a single unit
in 45 seconds.

**Fix:** drop above a **spawn point**, which by definition sits on walkable
ground, with only a small jitter (default 400), and verify ground beneath with
`playerphysicstrace` before using the point.

**Why bots missed it:** also map-dependent, and the rotation had moved to a
smaller map between my test and the player's session. I validated on one map and
generalised.

### 6. Three self-inflicted script breakages

Three times a text substitution matched a function's **call site** before its
definition and spliced a function body into the middle of a statement. In GSC a
single syntax error silently kills the **entire** script — no message anywhere.
The only symptom is every `RSG:` line vanishing from the log.

**Fix:** non-trivial files are rewritten whole, never patched by string
substitution. Every deploy is followed by a check that `RSG:` lines still exist.

## Why the bot tests did not catch these

Four distinct reasons, all mine:

1. **I measured counts, not outcomes.** `started: 6 landed: 6` looks like success
   and says nothing about whether the drop worked. The decisive numbers were
   duration and altitude, which I only started logging after the third failure.
2. **I treated a safety net as a pass.** The 45-second timeout existed to stop a
   stuck player ruining a match. When it fired I recorded `stuck: 3` and moved
   on. Every one of those was the feature failing.
3. **I tested one map.** Four of the six failures are map-dependent — indoor
   spawns, map extent, building heights. A single-map test cannot find them, and
   the rotation guarantees other maps will be played.
4. **Bots cannot produce human inputs.** They do not look up, cut chutes, or
   stand still. Failure 1 was unreachable by bot testing in principle.

### 7. Cutting the chute did nothing, and the table said it worked

The altitude test re-opened the chute on the very next iteration, 50 ms after
every cut, so cutting was impossible anywhere below `chute_alt` — which is the
entire band where a chute exists. It only appeared to work above that altitude,
in the `chute_time` case.

**Fix:** a sticky `rsg_chute_cut` flag gates re-deployment, cleared at the start
of each drop.

**How it was found:** a code review, not testing. Nobody had cut a chute in any
bot run — bots do not crouch while descending — and I had listed the row as
working in this document's own status table on the strength of having written
the code. That is the failure mode this postmortem exists to stop, repeated
inside the postmortem itself.

### 8. `rsg_infil` leaked on death and could hang a match

`infil()` carries `endon( "death" )` and resets the flag *after* its loop, so
dying mid-drop skipped the reset. A stale `rsg_infil` makes `fall_immune()`
return true forever, and `_zone.gsc` consults it for gas damage — so a
permanently gas-immune player cannot be killed by the ring, last-squad-standing
never resolves, and the match hangs with no error anywhere. It self-healed on the
next completed drop, which hid it, but not if the next drop early-returned or
infil was disabled mid-match.

**Fix:** unconditional reset at the top of every spawn, before the enabled check.

**How it was found:** code review. No test would have caught it without someone
dying mid-drop and then watching a later match fail to end.

### 9. Diving bought time, not distance

Vertical speed came from pitch while horizontal was a flat value from stick input
alone — so looking straight down made you fall faster but travel no further, and
with no input at all `vectornormalize( ( 0, 0, 0 ) )` zeroed the horizontal
entirely and you dropped vertically however you were aimed. A real skydive trades
altitude for ground covered.

**Fix:** velocity follows the view vector in three dimensions, with stick input
adjusting on top.

Also: `infil_height` of 1600 at 900/s was a 1.8-second fall, and 0.8 seconds in a
dive — *under* the 1500 ms airtime gate, so a dive was punished rather than
rewarded. Height is now 5000 with the chute opening at 1400.

## Testing rules going forward

- **Log outcomes, not events.** Every drop logs duration and altitude, so a
  broken drop is visible in the log without anyone playing.
- **A safety net firing is a failure.** The timeout now logs
  `DROP IS BROKEN` rather than a neutral message, so it cannot be skimmed past.
- **Validate on at least two maps**, one with indoor spawns and one open, before
  calling anything working.
- **After every deploy, confirm `RSG:` lines exist.** A silent script death is
  otherwise indistinguishable from a quiet server.
- **State what was not tested.** Anything only a human can exercise — looking up,
  cutting a chute, feel — is reported as unverified rather than implied working.
- **Never put a row in a status table because the code looks right.** Failures 7,
  8 and 9 were all found by reading code, and failure 7 was listed as *working*
  in this very document. A table entry needs either an observation or an explicit
  "unverified".
- **Balanced braces prove nothing.** A spliced function body can leave the file
  perfectly balanced. The gate that actually catches a silent script death is
  confirming `RSG:` lines appear in the log after every deploy.

## Current state

| Piece | Status |
| --- | --- |
| Drop from open sky above real ground | working, 0 broken across a full bot match |
| Freefall, dive by looking down | working; clamped so looking up cannot lift |
| Chute auto-deploy | working; altitude OR time so high ground cannot block it |
| Crouch to cut the chute | **was broken, now fixed** — see failure 7 |
| Landing detection | working, including rooftops |
| Fall and gas immunity while descending | working |
| Feel: height, dive speed, steer, spread | **unverified** — needs a human |
