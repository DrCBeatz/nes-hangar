# Flat inner-structure experiment

The current release includes this simple enclosure in the first soldier room.
This note preserves the initial experiment's measurements and intermediate
ROM hash; later ammo, visibility and encounter changes are covered in the
[release notes](RELEASE-NOTES.md).

The block uses the original E1M1 chamber's outer footprint at X184–212,
Z300–340. It is deliberately sealed: the original west entrance, walkable
interior, steps and lower ceiling are omitted. Four opaque wall faces share
the surrounding floor height 2 and ceiling height 10. The existing soldier,
medkit, room entrances and onward route retain their positions.

There are paths around all four sides, with 28 world units between the block
and the north, south and east room walls. The player has radius two. The
existing alternating wall materials distinguish its faces.

## Runtime changes

- The visibility compiler can use the static, full-height enclosure to prove
  other faces hidden. It still requires complete finite-segment coverage of
  each camera cell; sampled visibility never removes a wall.
- The soldier cannot enter the expanded enclosure bounds. Its sight and
  attack checks use an exact segment/rectangle test, including corner contacts.
  This adds obstacle awareness, not pathfinding: it may lose sight of the
  player behind the block rather than find a route around it.
- Player collision uses the existing finite-wall checks. Player shots retain
  the existing published-image target test, so an occluded soldier cannot be
  hit through the enclosure.
- Door face indices are derived from the authored map, allowing the four new
  opaque faces to precede the door without changing its behavior.

No art, sound, RAM allocation, mapper, cartridge size or floor height changes
are needed. The 64 KiB PRG build uses 8 KiB CHR RAM and 8 KiB cartridge work RAM,
as before. It does not require extra-scanline overclocking.

## Performance comparison

The linked 6502 audit uses identical camera poses in the accepted and candidate
builds. These are **producer CPU cycles**, excluding NMI, upload waiting and
display timing; they are not FPS measurements. Lower is better.

| View | Before | With enclosure | Change |
| --- | ---: | ---: | ---: |
| Room entrance, live soldier | 603,619 | 628,729 | +4.2% |
| Facing west side of enclosure | 831,963 | 627,330 | −24.6% |
| North-west view | 718,482 | 537,769 | −25.2% |
| Close oblique corner | 488,586 | 631,373 | +29.2% |
| Toward onward passage | 874,576 | 878,242 | +0.4% |
| Slime-room exit control | 644,947 | 648,606 | +0.6% |

This is a layout experiment, not an across-the-board optimization. Broad
nearby faces can replace complex distant geometry with solid tiles; oblique
corners require more dynamically drawn edge tiles. The entry camera cell's
candidate count can also increase despite reductions closer to the block.

The 19 linked render fixtures match the unfiltered scene reference pixel for
pixel, including the hidden soldier, coarse mode and close corners. The
unchanged opening, slime and exit control views retain identical world pixels.
Measured fixture maxima are 30 planes, 91 patterns and six spans, below the
respective budgets of 36, 184 and 16. A separate sampled room sweep covers
61,184 poses and reaches 34 planes; it is not exhaustive fractional coverage.

Geometry checks include 6,109 quarter-unit route samples, 8,980 connected
integer room positions, exact collision contact boundaries and the source
WAD footprint. Detailed research reports, paired images and old ROM baselines
are retained separately, outside the standalone repository. Running
`tools/inner_structure.py` generates the top-down layout at
`build/inner-structure/layout.svg`. The packaged
[current-release report](../verification/current-release.json) records evidence
for the final cumulative ROM.

The assembled AI tests pass 9,429 sight calls across all three bank mappings,
936 movement cases and blocked/clear corner attack cases. They also check
scratch ownership and absence of PPU writes from these helpers.

Two controller-only Mesen runs at stock NTSC timing pass 22,069 refreshes in
total. The full route circles the block, pushes against each face, completes
both combats and pickups, crosses slime, opens the door, exits and restarts.
The cover run leaves the first soldier alive behind the block: neither enemy
attacks nor six player shots penetrate it. All 38 captured backgrounds match
the unfiltered pixel/palette oracle. No illegal rendering-time PPU writes,
NMI nesting, bank-window access or resource overflow was observed. The full
route peaks at 33 planes, 113 patterns and eight spans. Mesen's personal
settings are unchanged. This is emulator evidence, not a physical NES test.

Historical enclosure-only candidate SHA-256:

```text
2faf2559fcd8fe149de1bfc714c299d455e3e87f7e1ef8d307677c6591786c42
```

## Build and test

Use the normal Python and cc65 requirements from the README:

```sh
python3 tools/build.py --verify
python3 tools/inner_structure.py
```

The output is `build/hangar-ntsc.nes`; `--verify` compares the current cumulative
build with the committed `release/hangar-ntsc.nes`, rather than the historical
enclosure-only hash above. No WAD is needed to build. To verify source-map provenance separately, pass
the supplied WAD path to `tools/inner_structure.py --wad /path/to/Doom1.WAD`.

The deeper comparison and Mesen drivers currently depend on the surrounding
research workspace and are intentionally separate from the standalone build.
They do not establish physical-console verification.

For playtesting, enter the first soldier room, circle the enclosure in both
directions, try using it as cover, collect the medkit, and continue to the
slime room and exit. Compare entry, broad-face and close-corner views when
judging whether the layout and performance tradeoff feel worthwhile.
