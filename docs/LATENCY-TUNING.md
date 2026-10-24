# Input response and picture latency

`prototype-2026-10-22-latency` targets the delay before a new movement or turn
appears when the renderer was already busy. It also reduces a small repeated
cost in tile generation. It preserves the level, geometry quality, movement,
collision, interaction ranges and optional music.

Accepted latency-build SHA-256 (`hangar-latency-ntsc.nes`, retained in the
local research archive and not bundled):

```text
0dbee1ad5765bc00ac10e1736902ee381a88c3c539b8c68de12f24f887260d89
```

The comparison baseline is the accepted interaction ROM, SHA-256
`0ecf59bf29efb03e5619a30d8bf890500a96e505a18f661920ab02fdbc9bd086`, preserved as
`hangar-interactions-ntsc.nes` (local research archive; not bundled).
The machine-readable results are in
[latency-tuning.json](../verification/latency-tuning.json). The source changes
are limited to `src/latency_restart.s` and `src/raster.s`.

## What the two tests distinguish

**Live controls.** Controlled starting, stopping and turning fixtures run in
stock-NTSC Mesen with music ON and OFF. Controller input changes the live
player position or angle within one to three refreshes in these samples.
After release, the live player state stops changing. This rules out continued
simulation movement as the cause of the reported drifting sensation in the
tested cases.

**Displayed response.** The same observations track the immutable camera
used to draw a picture, the producer, the transfer state and the picture that
is finally published. That displayed camera can lag behind live movement.
After release, older pictures can still arrive before the final stopped view.
Draw time and staged uploads therefore remain visible even when the live
controls have already responded.

The fixtures inject initial camera/game state and then use controller input.
The aggregate comparison covers 44,268 measured refreshes and 128 settled
start trials. All recorded positions/floors remain legal and every final
view settles. These are diagnostic emulator measurements, not a
physical-console test or a whole-level FPS benchmark. Publication timing
comes from the coherent visible camera at the PPUCTRL commit and excludes physical display delay. The candidate prepares its first
boot picture one refresh earlier, so matched button durations begin at
slightly different phases of the 50 Hz movement cadence. Single-refresh
differences should not be interpreted as meaningful speed gains.

A refresh here is approximately 16.6 ms. Music costs CPU time every refresh, but disabling it does not remove the underlying
rendering and presentation delay.

## Scheduling change

The previous input observer could invalidate unfinished work on a stop or
reversal, but did not treat starting a direction from rest as the same kind
of change. If an actor or scene update had already started a stationary
picture, new movement could wait behind that picture and its upload.

The observer now compares the old and new normalized directional intents.
Starting, stopping, reversing or adding a direction can make the producer
retry with a newer snapshot. Switching between turning and strafing remains
covered. Opposite inputs still normalize according to the movement rules;
firing does not invalidate the world render.

The existing safety bounds remain:

- At most one attempt is abandoned per acquired buffer. The retry completes,
  preventing rapid input changes from indefinitely starving publication.
- Work whose complete snapshot still matches live state can be retained.
- A useful first view of a new floor height keeps its existing presentation
  priority while that height still matches the player.
- Queued or uploading pictures remain immutable and are not cancelled.

This changes producer scheduling, not player speed or collision behavior.
The seven-block NTSC transfer budget is unchanged. The earlier full-route
timing report had only 56.7 CPU cycles of minimum final PPU-write margin, so
increasing that budget would require a separate timing redesign and proof.

## Matched movement starts

The following diagnostic deliberately starts an otherwise unchanged render
by incrementing the scene version, then presses a direction while the
producer is busy. This isolates the scheduling case; it does **not** model
the CPU or presentation cost of an actual moving enemy. Numbers are rounded
NTSC refreshes from input to the first published picture that responds.

| Busy-render start | Music ON, before → after | Music OFF, before → after |
| --- | ---: | ---: |
| Opening room, walk | 83 → 57 | 81 → 56 |
| Opening room, turn | 91 → 57 | 86 → 56 |
| Slime room, walk | 68 → 47 | 67 → 46 |
| Slime room, turn | 74 → 48 | 71 → 46 |

These selected cases improve by 21–34 refreshes with music ON and 21–30 OFF.
Starting from an idle renderer changes very little: there is no older
unfinished picture to replace. The remaining first-picture wait is still
substantial; this update does not make a complex room render at the refresh
rate of the display.

Release behavior is mixed. In the onset fixtures, several final stopped views
arrive sooner, some are unchanged, and individual cases arrive later. The
largest observed regression in that sample is nine refreshes with music OFF.
Changing when one picture starts also changes where a later release lands
relative to drawing and uploading. The retry budget and immutable upload
ownership deliberately limit how much work can be discarded. Do not interpret
the onset improvement as a promise that every stop or short movement improves.

Short movement/reversal stress tests retain that tradeoff. In the controlled
busy-render sample, mean time to the final stopped picture falls from 58.75
to 48.5 refreshes with music ON and from 55 to 48.75 OFF. Maximum tails fall
from 70 to 56 and from 66 to 54 respectively. A separate idle-start short-input
sample has an ON median of 41.5 → 43 and an OFF median of 41.5 → 40.5.
Individual comparisons can regress by as much as 12 refreshes: a faster first
render can become immutable just before the next reversal, while the slower
baseline was still able to abandon it. Earlier initial feedback and final
settling time are separate outcomes. Across all 64 matched release trials,
34 improve, 17 are unchanged and 13 regress. The measured differences range
from 15 refreshes sooner to 12 later; these are targeted comparisons, not a
statistical estimate for an ordinary playthrough.

## Less work per changed tile

The raster previously called a generic helper to mark each changed nametable
tile's 16-byte upload block. That helper preserves registers and computes an
address suitable for several callers. In this specific raster loop, X is
already dead, Y is zero, and the block is exactly:

```text
6 + 2 * viewport_tile_row + (viewport_tile_column >= 16)
```

A specialized inline sequence preserves the tile ID in A and marks that same
block in 26 cycles, replacing an 84-cycle call including JSR. The generated
picture and upload list stay identical. Alignment makes the banked render
segment grow by 16 bytes; no RAM or additional fixed-bank space is needed.

The portable [raster test](../tests/raster-dirty.mjs) checks 294,912 linked CPU
cases: every tile ID, all 576 viewport positions and both buffers. It also
compares 32 complete renders at 16 poses, including walls, recess boundaries,
slime, closed/open doors, close soldiers and coarse mode. All 1,179,648
background pixels, complete staging buffers and dirty upload lists match the
accepted baseline.

Those cold-template producer fixtures save approximately 19,000–33,000 CPU
cycles; the slime cases save 1.75–4.78%. Repeating an unchanged view gives
essentially no benefit because there are no changed tile IDs to mark. These
interrupt-free costs exclude uploading and music, and are not gameplay FPS.

## Acceptance and remaining work

The focused results above describe the accepted latency build. The subsequent
[door approach change](DOOR-APPROACH.md) retains these optimizations. Short-input and
controller-route evidence is recorded separately in [verification](VERIFICATION.md),
including its test scope and timing limits. A clean build from an isolated
source copy reproduced that revision's ROM byte for byte. The prior interaction
ROM remains in the local research archive for direct playtesting comparisons.

This build still has slow complex views, delayed presentation and
discrete sprite size steps. The ammo clip can pass below the viewport shortly
before collection. This pass does not change those rendering choices or
license/attribution status. These are historical optimization measurements;
the current cumulative release and its separate publication checks are linked
in [deployment](DEPLOYMENT.md).
