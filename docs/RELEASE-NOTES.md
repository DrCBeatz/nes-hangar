# Enclosure and third-encounter release

This release adds cover to the first soldier room and a final fight beyond
the openable door. It also tightens the ammo pickup and reduces unnecessary
rendering work in selected slime-room views.

- **Inner enclosure:** a sealed, full-height structure follows the original
  E1M1 chamber's outer footprint. All four sides remain walkable. It blocks
  movement and shots; the first soldier can lose sight of the player behind
  it. This adds cover, not general enemy pathfinding or a walkable interior.
- **Ammo pickup:** the gray clip's radius is three world units, down from
  four. Its placement, ten-round refill, artwork and sound are unchanged.
  The medkit retains its existing six-unit radius.
- **Visibility:** a conservative camera-position filter avoids transforming
  two enclosure faces when the passage hides them. Genuine through-passage
  views retain those faces. This is a modest, localized optimization; complex
  views and close sprites remain expensive.
- **Third soldier:** the flat room beyond the existing door now contains a
  moving, shooting soldier using the earlier enemies' behavior and artwork.
  Its movement bounds leave both entrances and side routes clear. The
  completion screen now counts kills out of three.

The player still starts with 100 health and six rounds. Collecting the clip
brings the available ammunition to 16 rounds. All three soldiers require nine
successful hits, leaving seven rounds for misses; killing every enemy remains
optional. The medkit, ammo and exit retain their existing locations.

Three enemy records persist, but only one encounter simulates and renders at
a time. Returning restores a surviving soldier's position and health; defeated
soldiers remain defeated. A visible outgoing enemy can disappear at a handoff,
and leaving its area cancels any pending attack or corpse presentation. There
is no new pickup in the final encounter room.

## Verification and limits

The final ROM passed two controller-only Mesen routes at normal NTSC timing,
with zero extra scanlines: a full clear and a route that left the second
soldier alive while damaging, leaving and revisiting the third. The runs
covered 23,062 display refreshes and 55 exact background/palette comparisons.
The full clear used nine shots, finished with seven rounds, reported 3/3 kills
and 2/2 items, and restored all three soldiers on restart. Linked checks also
covered state ownership, fractional handoff boundaries, collision, attacks,
pickups and completion counts.

The cartridge configuration is unchanged: **64 KiB PRG, MMC1, 8 KiB CHR-RAM
and 8 KiB work RAM**. There is no additional processor or requirement for
emulator overclocking. These are emulator and build checks, not a claim of
testing on a physical NES or flash cartridge. Rendering speed remains
scene-dependent, with noticeable control-to-picture latency.

The ROM is [`release/hangar-ntsc.nes`](../release/hangar-ntsc.nes), 65,552 bytes.
SHA-256:

```text
277422aa65613d5f1a581fece1e398c161948d473741b0aa2b47b2d11113e4a2
```

Rebuild and compare it with `python3 tools/build.py --verify`. See the
[README](../README.md#build-from-source) for requirements. Original-code
licensing and [content provenance](PROVENANCE.md) are unchanged.

The feature notes preserve the intermediate experiments and their separate
measurements: [inner structure](INNER-STRUCTURE.md), [ammo pickup](AMMO-PICKUP.md),
[visibility optimization](VISIBILITY-OPTIMIZATION.md) and
[third encounter](THIRD-ENCOUNTER.md).
