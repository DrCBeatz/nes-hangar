# Third soldier encounter

The current release adds a third zombie soldier to the small, flat room beyond
the existing openable door, before the final switch chamber. It builds on the
accepted enclosure, tighter ammo pickup and visibility optimization.

The soldier starts at (296,84) and pursues within X282–310, Z76–92. This leaves
room to pass on either side and keeps its contact bounds clear of both room
entrances. It shares the earlier soldiers' three-hit health, walking frames,
warning, gunshot, hit flash and temporary corpse. Sight and attacks are limited
to legal positions in this room; it cannot shoot through the closed door or
follow the player into the connecting passages.

The existing single active-enemy renderer is retained. Three separate records
remember position and health, while only the current encounter simulates and
renders. Advancing to Z128 activates the last encounter; returning to Z136
restores the slime-room encounter. The eight-unit separation prevents rapid
switching near the boundary. Leaving a room cancels its pending attack and
corpse presentation, and returning does not resurrect a defeated soldier.
As with the earlier handoff, an outgoing enemy can disappear if it remains in
view through an open passage. This is not simultaneous multi-enemy rendering.

The completion screen counts kills out of three. The player still starts with
six rounds and can collect ten more from the existing clip. Nine successful
shots defeat all three soldiers, leaving seven rounds for misses when the
clip is collected. The last room has no additional pickup; the two earlier
items retain their positions, collection flags and effects. Killing every
enemy is still optional for reaching the exit.

## Memory and build

No new artwork or cartridge hardware is required. Four three-entry coordinate
arrays occupy the previous encounter allocation. Three remaining arrays use
nine previously unused bytes at dirty-list offsets 55–63, between door state
and the second upload list. The uploader's two lists remain limited to 48
entries each. This adds seven bytes of live persistent state without expanding
the allocated internal RAM or cartridge RAM regions.

The linked build adds 189 fixed code bytes and 15 common bytes. Geometry,
visibility tables and artwork are byte-identical to the accepted visibility
build. It remains a 65,552-byte file with 64 KiB PRG, MMC1, 8 KiB CHR RAM and
8 KiB work RAM. Free linked space is 450 fixed-code bytes, 62 common bytes
and 63 map-bank bytes; other physical banks retain their earlier free space.

## Rendering comparison

Fourteen matched linked-CPU fixtures keep every background pixel identical to
the baseline and agree with the independent all-face reference. The closed
door occludes the third soldier, and front, side, close and coarse-mode views
render successfully. Peak fixture usage is 32/36 planes, 56/184 patterns and
4/16 spans.

| View | Baseline producer cycles | Third-encounter cycles | Change |
| --- | ---: | ---: | ---: |
| Slime room, looking back | 685,994 | 685,999 | +0.001% |
| Slime room, open door ahead | 691,824 | 691,829 | +0.001% |
| Outside closed door, third hidden | 364,557 | 382,592 | +4.95% |
| Just inside third room | 633,471 | 676,163 | +6.74% |
| Close to third soldier | 621,384 | 712,681 | +14.69% |
| Third defeated, no corpse | 633,986 | 633,987 | +0.0002% |

The earlier views retain the same active soldier in both builds. Last-room
baseline fixtures have no living soldier, so their increases measure the
cost of adding the encounter rather than a renderer regression. These counts
exclude interrupts and upload waiting; they are not gameplay FPS. The third
soldier still incurs projection/occlusion work when hidden by the nearby door.

## Verification

Linked tests cover save/load/reset in all three PRG mappings, exact fractional
handoff thresholds, movement and sight boundaries, attacks, death persistence,
all killed/alive combinations on the completion screen, and absence of a
third pickup. Maximum-length dirty-list preparation and upload preserve the
nine aliased record bytes. Existing pickup, exit and sound regression tests
also pass. Portable evidence is in the
[current-release report](../verification/current-release.json). Detailed
research traces, drivers and old ROM baselines are retained separately and
are not included in the standalone repository.

Two controller-only Mesen routes at stock NTSC timing pass 23,062 refreshes
and 55 exact background/palette comparisons. The full route defeats all three
soldiers with nine accepted shots, collects both items, retains seven rounds,
shows 3/3 kills and 2/2 items, and resets all three records on restart. The
second route leaves the slime-room soldier alive, damages the third, retreats
and returns to verify its remaining two HP, then kills it and walks through
the corpse. Both routes preserve independent encounter state. No illegal
rendering-time PPU writes, nested NMI, record-tail ownership violations or
resource overflows were observed. Runtime maxima are 33/36 planes, 113/184
patterns and 8/16 spans. These are emulator tests, not physical-console tests.

Historical baseline SHA-256 (`hangar-visibility-ntsc.nes`):

```text
f00e6258530db0261e1d52b0a0d0598b47c109d0f5a85ffd862035a87662581f
```

Current release SHA-256 (`release/hangar-ntsc.nes`):

```text
277422aa65613d5f1a581fece1e398c161948d473741b0aa2b47b2d11113e4a2
```

Build with the usual command:

```sh
python3 tools/build.py --verify
```

The output is `build/hangar-ntsc.nes`. The `--verify` option compares it with
the included `release/hangar-ntsc.nes`, which is byte-identical to the final
third-encounter playtest candidate described above.

For playtesting, open the door after the slime room, fight or evade the final
soldier, and finish at the switch. Also try leaving the second soldier alive,
damaging the third, returning to the slime room, then coming back: each enemy
should retain its own health. The results screen should report the correct
kill count out of three.
