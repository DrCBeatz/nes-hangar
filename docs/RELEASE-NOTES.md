# Bronze DOOM-logo title

`prototype-2026-10-21-bronze-title` adds the selected full-screen bronze title
to the accepted soldier-stability build. Press Start to open the unchanged
controls guide, then release and press Start again to begin. Holding Start
cannot skip either screen. Death/completion retries still return directly to
gameplay; hardware/emulator Reset returns to the logo.

The 192 × 94 logo uses brown, amber and cream against black, with white text.
It is derived from id Software's M_DOOM menu artwork in the supplied shareware
WAD, rather than original MIT-licensed project artwork. Normal builds use the
included indexed source and need no WAD. See the [provenance](PROVENANCE.md).

All new title code and assets run before gameplay in the boot bank. The guide
retains its font, and startup restores both CHR tables, nametables, palette
and gameplay state before the first world view. Gameplay rendering, map,
combat, NMI schedule and allocated RAM are unchanged from the sprite-stability
release. BOOTDATA uses 7,376 of 8,192 bytes; the ROM remains 64 KiB PRG with
MMC1, 8 KiB CHR RAM and 8 KiB work RAM.

The earlier grayscale title passed a full controller-only Mesen route and
restart; the bronze comparison differs from it only in three title-palette
bytes. Separate stock-NTSC startup comparisons verified fresh Start presses,
white text, controls and exact restoration of gameplay graphics for every
palette. Their scopes and historical ROM identities are retained in the
[title notes](TITLE-SCREEN-EXPERIMENT.md), [palette comparison](TITLE-PALETTE-COMPARISON.md)
and [verification record](VERIFICATION.md).

The current ROM is [`release/hangar-ntsc.nes`](../release/hangar-ntsc.nes),
65,552 bytes, with SHA-256:

```text
c715b34bd688927579d20d6c593dbddb8436ca4a38dab4b78f553a5d04afe251
```

`python3 tools/build.py --verify` rebuilds this bronze release. The other title
palettes remain build options; they intentionally produce different checksums.
The hosted browser game still uses the previous third-encounter release and
has not been updated by this integration. Use its **Open ROM** control to load
the current download.

# Previous soldier sprite-stability release

`prototype-2026-10-21-sprite-stability` improves close-range soldiers in all
three encounters. The map, combat behavior, collision and pickups are unchanged.

- Two intermediate sizes, **26 × 52** and **30 × 60**, reduce near-range
  height changes from eight pixels to four. A ±0.125-world-unit switching
  buffer prevents tiny movements from repeatedly toggling between sizes.
- Soldiers and corpses use radial distance for both size and vertical
  placement. Turning at a fixed position no longer moves the whole body down
  the screen. Feet move continuously with distance rather than jumping with
  each sprite tier.
- Existing artwork at the original sizes is preserved. Tight source-row
  storage makes room for the new art; the compositor writes transparent
  padding without reading beyond a source image.

Vertical placement is deliberately a stable billboard approximation. Exact
perspective floor contact away from the screen center is not claimed.
Horizontal projection and foreground depth masks retain their existing
camera-depth calculation. Pickups retain their previous positioning.
The maximum soldier remains 32 × 64 pixels with four sprite columns.

The cartridge configuration and allocated RAM are unchanged: **64 KiB PRG,
MMC1, 8 KiB CHR-RAM and 8 KiB work RAM**. The final vertical correction adds
about 0.44–0.75% producer CPU time in the twelve centered comparisons with
identical pixels. These fixed-pose measurements exclude NMI and uploading;
they are not gameplay frame rates or a claim that every view costs the same.

The final ROM passed linked size/lifecycle and radial-math checks, stock NTSC
Mesen projection/occlusion comparisons, and all 18 isolated emulator tests.
The controller-only JSNES route completed all three encounters, both pickups,
the door, completion and restart in 7,529 refreshes. See the
[sprite notes](SPRITE-STABILITY.md) and [verification record](VERIFICATION.md)
for the separate test scopes. No physical-console test is claimed.

The sprite-stability release is preserved in Git at commit `d2f2bbd`. Its
65,552-byte ROM has SHA-256:

```text
f342c5b83f75be92fdf476fab0b2c802afe06438e41e5b571d98b501c05de28e
```

Check out `d2f2bbd` to rebuild that release with `python3 tools/build.py --verify`.
The older third-encounter release is preserved at
[commit 0f31a394](https://github.com/DrCBeatz/nes-hangar/tree/0f31a3947b7d8a2bed63c64acc53ce8812ce3470),
with its evidence in
[third-encounter-release.json](../verification/third-encounter-release.json).

# Previous enclosure and third-encounter release

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

That ROM remains available at [source commit 0f31a394](https://github.com/DrCBeatz/nes-hangar/blob/0f31a3947b7d8a2bed63c64acc53ce8812ce3470/release/hangar-ntsc.nes), 65,552 bytes.
SHA-256:

```text
277422aa65613d5f1a581fece1e398c161948d473741b0aa2b47b2d11113e4a2
```

Check out that commit to rebuild the previous release with
`python3 tools/build.py --verify`. See the
[README](../README.md#build-from-source) for requirements. Original-code
licensing and [content provenance](PROVENANCE.md) are unchanged.

The feature notes preserve the intermediate experiments and their separate
measurements: [inner structure](INNER-STRUCTURE.md), [ammo pickup](AMMO-PICKUP.md),
[visibility optimization](VISIBILITY-OPTIMIZATION.md) and
[third encounter](THIRD-ENCOUNTER.md).
