# Inner enclosure visibility optimization

This optimization is included in the current release. The measurements below
compare its original candidate with the preceding tighter-ammo build.
It removes unnecessary
work on two enclosure faces when the camera is in the slime room and the
passage definitely hides those faces. The enclosure, map, actors, artwork,
pickup rules and rendering quality are unchanged.

The ordinary visibility table covers 16-by-16 world-unit cells. Some of those
cells contain both positions that can see the enclosure through the passage
and positions that cannot, so the table must conservatively retain its faces.
The new gate refines this decision using the immutable render-camera position.

## Conservative rejection

For this layout, a line from the slime room to the enclosure must cross the
opening at Z260, X280–302. The enclosure's extreme corner gives the necessary
visibility condition `20*X + 17*Z - 10020 >= 0`. A generated 92-byte table
encodes conservative X cutoffs for complete one-unit Z slabs, with an extra
one-unit X safety margin. It is applied only at X256–352 and Z168–260 (upper
bounds exclusive), and only to enclosure faces 86 and 87. Outside that domain,
the existing decision is retained.

This is an exact geometric rejection rule, not a sampled visibility guess.
The generator validates the portal, opaque boundaries and enclosure geometry;
changing these assumptions requires revisiting the filter. The source-cut
proof covers all fractional positions in the rejected slabs. Independent
finite-wall witnesses cover 5,389 of the 9,236 face/cell pairs; the complete
portal/topology proof covers all pairs. Fixed-point raster preservation is
checked separately against an all-face reference.

The helper runs once per render snapshot, before plane and endpoint transforms.
It reuses a producer scratch byte whose floor-clipping lifetime starts later.
The final linked build adds 92 map bytes and 64 code bytes, with no RAM change.
The map bank now has 63 bytes free. The cartridge remains 64 KiB PRG, MMC1,
8 KiB CHR RAM and 8 KiB cartridge work RAM.

## Stock NTSC timing

Matched Mesen runs use controlled starting states and repeated rendering of
fixed camera poses, with ordinary producer, NMI and upload code. Four completed
picture intervals are measured per case. These are diagnostic samples, not
an end-to-end gameplay FPS benchmark or physical-console validation.

| Camera / condition | Producer CPU change | Refreshes per new picture, before → after |
| --- | ---: | ---: |
| (276,256), angle 224, soldier defeated | −4.73% | 23.50 → 22.50 |
| (276,256), angle 224, soldier alive | −4.70% | 23.75 → 22.75 |
| (276,256), angle 192, soldier alive | −4.31% | 23.25 → 22.25 |
| (310,240), angle 224, genuine enclosure view | +0.016% | 28.25 → 28.25 |
| (292,256), angle 128, entry control | +0.023% | 39.75 → 39.75 |
| (296,180), angle 128, exit control | −0.55% | 22.00 → 22.25 |

The targeted views recover approximately one NTSC refresh (16.6 ms) per new
picture. The small exit-control interval variation demonstrates why lower
producer cycles do not guarantee every short publication sample improves:
upload scheduling and refresh alignment also matter. This is a localized
optimization, not a general solution to the slime room's rendering cost.
Across the broader 48-pose slime-room linked-CPU sample, the mean reduction is
0.88% (median 0.61%; maximum 4.36%). These interrupt-free linked CPU numbers
are distinct from the Mesen producer measurements above.

## Verification and reproduction

- All 121 matched linked poses retain identical background and actor pixels
  and match the unfiltered oracle: 48 slime-room poses, 19 controls, and 54
  fractional or domain-boundary cases. Peak usage is 30/36 planes, 96/184
  total patterns and 7/16 spans.
- Linked helper fixtures pass 5,216 mask cases, including every cutoff row,
  fractional boundaries and coordinate carries. Another 2,712 out-of-domain
  cases across all three banks perform no table reads. The 1,180 face/door
  comparisons preserve all other door decisions.
- Scratch ownership, register preservation and the diagnostic
  `ROOMS_UNFILTERED` bypass pass.
- The gameplay regression passes 2,664 pickup and 2,808 exit boundary cases,
  plus sound checks. The accepted ammo radius remains three world units.
- Controller movement across six visibility boundaries passes in stock-NTSC
  Mesen. All 23 captured candidate backgrounds match the all-face oracle.
  No illegal rendering-time PPU writes or nested NMI was detected.

Detailed reports, diagnostic drivers and historical ROM baselines depend on
the research workspace and are not included in the standalone repository.
The packaged [current-release report](../verification/current-release.json)
records the final cumulative ROM's evidence. Build and compare that release:

```sh
python3 tools/build.py --verify
```

The output is `build/hangar-ntsc.nes`; its current hash is in the
[release notes](RELEASE-NOTES.md). To reproduce the geometric proof independently:

```sh
python3 tools/inner_visibility.py
```

Historical baseline (`hangar-ammo-tight-ntsc.nes`):

```text
31c137470615dda0285569cd2e7785b282bc368df8a5d17de01d448578ac76f4
```

Historical visibility-only candidate (`hangar-visibility-ntsc.nes`):

```text
f00e6258530db0261e1d52b0a0d0598b47c109d0f5a85ffd862035a87662581f
```

For playtesting, look back toward the enclosure while moving through the
slime room and its entrance. Check that wall edges remain present as the
passage opens and closes from view. Stock NTSC settings are useful for judging
the modest timing improvement.
