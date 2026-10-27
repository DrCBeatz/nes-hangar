# October 26 performance candidate

`prototype-2026-10-26-performance-rc1` brings the accepted optimization
experiments into the repository for playtesting. It keeps the same level,
soundtrack, art, 256 × 144 viewport and 128 horizontal rendering samples.
The cartridge remains MMC1 with 128 KiB PRG, 8 KiB CHR-RAM and 8 KiB work RAM.
The hosted browser ROM remains the October 24 prototype pending this playtest.

## What changed

The producer does less repeated work. It can retain a valid background while
an actor changes, uses faster exact arithmetic and floor projection paths,
and avoids unnecessary partial-tile and sprite-mask operations. Geometry
candidates are grouped into 16-pixel lists; raster strips remain 8 pixels wide.
A new exact-position check skips eligible behind-camera walls before either
endpoint is transformed. Surviving geometry follows the same projection path.

The uploader streams pattern bytes and permits an eighth 16-byte pattern
block only when the interrupt's other work leaves room. It continues to
publish completed views. These are scheduling and CPU changes, not more
emulator scanlines or lower rendering resolution.

Input checkpoints now also run during geometry setup. A pending movement
change does not spend the one allowed render retry merely because an enemy
has moved or changed walking pose while the player camera is still unchanged.
Camera, scene, lifecycle and door guards remain in place. This helps useful
camera views reach the screen sooner; it does not eliminate rendering delay.

Two visual fixes accompany the performance work. Distant soldier feet use the
projected floor, blending into the accepted stable radial anchor up close.
The third encounter activates at the reachable doorway boundary, avoiding
the missing soldier when opening the door from its center.

## Fresh-render CPU comparison

These numbers compare the published October 24 ROM with the current candidate
at identical fixed camera and actor states, averaged across both staging
buffers. They count the actual linked 6502 producer instructions without
asynchronous interrupts. **They are not live frame times or FPS.**

| Representative view | October 24 cycles | Candidate cycles | Less CPU work |
| --- | ---: | ---: | ---: |
| Opening recess and pillars | 1,023,210 | 888,492 | 13.2% |
| Simple wall | 523,225 | 448,567 | 14.3% |
| First encounter room | 593,498 | 501,062 | 15.6% |
| Slime entrance, living soldier | 1,013,154 | 840,861 | 17.0% |
| Slime center, living soldier | 954,868 | 825,976 | 13.5% |
| Close soldier | 969,218 | 793,785 | 18.1% |

Across all **172 fresh render cases**, total producer work falls **14.9%**.
The primary world-route subset of 90 cases / 45 camera poses falls **14.0%**.
These are sums over specified fixtures, not estimates of how long a player
will spend in each room. Each representative row above is rounded to the
nearest cycle; percentages use the unrounded measurements.

The [machine-readable comparison](../verification/performance-update-20261026.json)
joins the existing matched release → sprite-response → 16-pixel-list →
exact-position-rejection measurements. Intermediate totals agree for every
joined case. This is a recombination of recorded CPU measurements, not a new
live capture comparing the final candidate directly against the release.

Stationary actor redraws are a different workload: when the same staging
buffer retains a valid world, the eight living-actor controls use **50.3% less
producer CPU** in aggregate. Do not apply that figure to walking or turning;
those usually require a new background.

## Responsiveness and tradeoffs

The earlier [release-to-sprite-response Mesen comparison](../verification/performance-20261026/released-vs-sprite-report.txt) found substantially
earlier first-visible turns at the slime entrance with a moving enemy.
The later [exact-position check](../verification/performance-20261026/live-report.txt) adds a smaller improvement: against the
16-pixel-list baseline, the median first changed view at that entrance
arrives about one NTSC refresh earlier with music ON and OFF, and the final
stopped view about two refreshes earlier.

Those experiments used different version pairs. Their live timing improvements
must not be added together as if they were a direct release-to-candidate run.
Timing starts at the emulator's controller poll and excludes physical input,
the operating system and monitor delay. The latest live tests use seeded
scenes with actual AI and music rather than a controller-only level playthrough.

Important remaining limits:

- The opening recess/pillars and slime room still take substantial time to
  draw. Music adds CPU work; OFF remains the faster option.
- Faster CPU work does not make every short-window display metric better.
  In the final experiment, one actor-free center onset was one refresh later,
  and one music-ON reversal's final stopped view was two refreshes later.
- Input checkpoints can discard unfinished work to show a newer camera.
  Better response and less total discarded work are not the same metric.
- The upload deadline suite has a worst-case **19-cycle margin** after its
  instruction/DMA allowances. The existing guarded budget is retained.
- Some code banks are nearly full: the final layout leaves eight map-bank
  bytes and 43 fixed-code/audio bytes. Future changes may require relocating
  code even though the cartridge's total capacity is unchanged.

World output matches in the fixed-camera comparison fixtures. The intentional
distant-soldier floor correction changes some sprite pixels; the doorway
activation change also affects when the final encounter appears. Neither is
counted as a rendering simplification.

## Playtest before deployment

Use [the candidate ROM](../release/hangar-ntsc.nes) with stock NTSC timing,
zero extra scanlines and normal sprite limits. Play through with music ON
and OFF, including the opening recess, all encounters, pickups, pause/retry,
the door and exit. Check the first soldier from the corridor and the third
soldier while opening the door from the center. Select still provides the
coarse-boundary comparison.

The title retains **BUILD 2026-10-24** to keep the accepted experimental binary
unchanged. Identify this candidate through [release metadata](../release/release.json)
and SHA-256 `70a7593068e3e73eec3f448627dc1e930867069aea08aa73a6bd90f54f087817`.
Build and emulator evidence, including its limits, are in
[verification](VERIFICATION.md). Physical-console testing remains outstanding.
