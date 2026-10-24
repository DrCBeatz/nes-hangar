# Door reach and alias credit

`prototype-2026-10-24-door-reach` makes the door easier to use on centered
approaches and credits the project as **Dr C Beatz**.

- Door use reach increases from eight to twelve world units on both sides.
  At 8.25 units, the centered door can fill nearly the whole viewport while
  the previous build still rejects use. The new threshold covers that case.
- Physical collision, panel-width and facing guards, fresh A presses and
  A+Left/Right strafing are unchanged. Repeated true-contact approaches already
  worked in the baseline; a separate intermittent failure at contact was not
  reproduced. See [door reproduction and checks](DOOR-REACH.md).
- The credits page and public-facing author documentation use **Dr C Beatz**.
  Original-game, composition and third-party sound-engine credits remain.
- The final [performance assessment](FINAL-PERFORMANCE.md) retains the renderer:
  the measured remaining costs warrant a separate optimization iteration,
  rather than a last-minute structural change.

Only 25 ROM bytes change: two door-range constants and 23 credits nametable
bytes. Linked segment sizes and RAM allocations are unchanged. The current
[ROM](../release/hangar-ntsc.nes), [metadata](../release/release.json) and
[checksum](../release/SHA256SUMS) identify the local candidate. It has not been
pushed or deployed. Current test results are in [verification](VERIFICATION.md).

# Previous credits, HUD and accepted soundtrack

`prototype-2026-10-24-credits-hud` integrates the accepted **Dr C Beatz E1M1
arrangement** and **ammo placement**, then adds a small presentation pass:

- The bronze DOOM logo is identified as an unofficial Hangar NES prototype,
  with **BUILD 2026-10-24** beneath it.
- **Select** from the logo opens credits. **B** returns to the logo, and
  **Start** opens the controls guide. The credits distinguish the project,
  original Doom game, composition, new arrangement and playback engine.
- The guide makes **Left OFF / Right ON** explicit, notes **Music OFF: faster
  play**, and moves the Start prompt up for more bottom margin.
- The HUD replaces the unused **ARMOR 000** placeholder with **WEAPON / PISTOL**.
  Select still toggles the dynamic-boundary comparison during gameplay.

The soundtrack is the supplied `music/e1m1/e1m1-drcbeatz.s`, preserved verbatim.
The current credit is **NES arrangement by Dr C Beatz**, with **Bobby Prince**
credited for "At Doom's Gate." Rasteri is acknowledged in documentation for
the consulted reference and earlier music experiments; the older exports are
not compiled. The code license is unchanged and is separate from composition,
level and artwork rights. See [music](MUSIC.md) and [provenance](PROVENANCE.md).

The clip now sits at **(282, 250)**, farther out from the wall corner on dry
ground. Its strict **3.5-unit pickup radius**, ten-round refill, collection
sound and once-only behavior are unchanged. See [ammo notes](AMMO-PICKUP.md).

This is a local release candidate; it has not been pushed or deployed. The
current [ROM](../release/hangar-ntsc.nes), [release record](../release/release.json)
and [checksum](../release/SHA256SUMS) identify the same build. Build and compare
with `python3 tools/build.py --verify`. Current results and the earlier
music/placement evidence are distinguished in [verification](VERIFICATION.md).

# Previous close-angle door prompt

`prototype-2026-10-22-door-angle` fixes a remaining door interaction problem:
standing near a jamb and aiming into the door could still hide the use prompt.
The facing allowance increases from 45 to about 75 degrees on both sides.
Distance, collision and the fresh-A/strafe controls stay the same.

Only four ROM bytes change, with no additional code or RAM. The previous
latency improvements, optional soundtrack, ammo pickup and exit switch are
retained. See the [reproduction and fix](DOOR-APPROACH.md) and
[verification](VERIFICATION.md).

That historical door-angle candidate was 131,088 bytes, SHA-256:

```text
2e89760fcaa8175eacd400285d9887dce7e74fce8f5df126a13445cad55ab6a6
```

The current cumulative source retains this fix. Its ROM and checksum are
identified in the current release record above.

# Previous input-to-picture latency tuning

`prototype-2026-10-22-latency` helps new movement and turns become visible
sooner when the renderer was already busy. A small raster optimization also
reduces CPU work without changing the generated picture. The optional E1M1
remix, interaction fixes, level and artwork remain intact. This local candidate
has not been pushed or deployed to the browser game.

- New movement directions now invalidate an outdated, unfinished render,
  alongside the existing stop/reversal checks. The producer still permits
  only one abandoned attempt per acquired buffer, then completes the retry.
- The current-pose check and floor-height presentation protection remain.
  Queued/uploading pictures are not cancelled, and movement/collision rules
  and the seven-block NTSC upload budget are unchanged.
- Raster-only dirty-name marking takes **26 rather than 84 CPU cycles** per
  changed tile. It produces identical dirty flags and upload lists, using
  16 more banked code bytes after alignment and no additional RAM.

In controlled busy-render starts, the first responsive picture arrives
**21–34 NTSC refreshes earlier** with music ON, or **21–30 earlier** with it
OFF. These are targeted diagnostic results, not a whole-game frame-rate gain.
Idle starts barely change, and some long-hold release cases settle later
because the work reaches different points in the upload schedule. Substantial
presentation lag remains in complex views. See the [measurements and
limits](LATENCY-TUNING.md).

The preserved latency build is
`hangar-latency-ntsc.nes` (local research archive; not bundled),
131,088 bytes, with SHA-256:

```text
0dbee1ad5765bc00ac10e1736902ee381a88c3c539b8c68de12f24f887260d89
```

At that revision, a clean isolated build reproduced this ROM byte for byte.
The current `python3 tools/build.py --verify` command checks the current
release instead. Historical results and their test scopes are recorded in
[verification](VERIFICATION.md) and
[latency-tuning.json](../verification/latency-tuning.json).
The preceding interaction ROM and its evidence are preserved below.

# Previous door, exit and ammo interactions

`prototype-2026-10-22-interactions` makes the nearby door and exit switch easier
to use and modestly enlarges the ammunition clip's collection radius. It retains
the approved optional E1M1 remix. This accepted local baseline has not been
pushed or deployed to the browser game.

- Door and exit facing allowance increases to **±45°** from the wall normal.
  The door's usable width now covers the full panel. Distance, legal-side and
  collision checks remain in place.
- A **fresh A press** still activates a displayed prompt. Holding A while
  approaching does not activate it, and A+Left/Right remains strafe.
- Ammo uses a **strict 3.5-world-unit radius**, up from three. Conservative
  eighth-unit rounding is retained. This accepts more close passes while
  retaining the earlier rejection of the 3.75-unit wall-side pickup.
- Medkit collection, item positions, healing/refill amounts, music, artwork,
  geometry and rendering are unchanged. This is not a latency optimization.

The clip can still pass below the viewport before it is collected. The radius
change improves near-edge contact; it does not solve close-range presentation
or the difference between the current player position and the displayed view.
See [interaction changes and remaining limits](INTERACTION-FIX.md).

The preserved ROM is
`hangar-interactions-ntsc.nes` (local research archive; not bundled),
131,088 bytes, with SHA-256:

```text
0ecf59bf29efb03e5619a30d8bf890500a96e505a18f661920ab02fdbc9bd086
```

See [verification](VERIFICATION.md) and the
[archived interaction release record](../verification/interaction-release.json)
for its tested scope. The previous optional-music ROM and its original
evidence are preserved below.

# Previous optional music and Dr C Beatz E1M1 remix

`prototype-2026-10-22-optional-music` integrated the approved music experiment
into the main local development build. Its ROM is byte-identical to the tested
`hangar-e1m1-drums-ntsc.nes` candidate. This integration has not been pushed or
deployed to the browser game. The later interaction and input-to-picture
latency updates are described above.

The controls guide defaults to music ON. Left selects OFF, Right selects ON,
and Start begins the level. Retries retain the choice; a console reset returns
to the title and defaults to ON. OFF skips the sequencer while preserving all
sound effects. Music pauses with gameplay; gunshots and other cues retain
priority over their music channels.

The soundtrack is Bobby Prince's "At Doom's Gate," arranged for NES by
rasteri / PiPU and remixed with noise-channel percussion by Dr C Beatz.
That build used the supplied `e1m1-drums.s` export verbatim. The export and
its comparison ROM are now retained only in local research history, outside
the published package.
No DPCM samples or expansion audio are used. Attribution and unresolved music
license scope are documented in [provenance](PROVENANCE.md); this integration
does not relicense the project or publish the music.

The cartridge now uses **128 KiB PRG, MMC1, 8 KiB CHR-RAM and 8 KiB work RAM**.
The FamiStudio engine, mixer and preference use 206 of 216 reserved audio RAM
bytes. Rendering code placement changes make room for always-visible audio;
there are no mapper switches inside the music tick or NMI. Map, artwork and
interaction rules are unchanged from the accepted music experiment.

The preserved optional-music ROM is
`hangar-optional-music-ntsc.nes` (local research archive; not bundled),
131,088 bytes, with SHA-256:

```text
c2a913ddd057235e11936e4c212eb0d3a93e1c6f422315d03bd05baaea80ab1b
```

The integration evidence is preserved in
[optional-music-release.json](../verification/optional-music-release.json) and
[optional-music-build.json](../verification/optional-music-build.json). The earlier
no-music ROM remains reproducible from commit `b0cde0b`. See
[music controls and architecture](MUSIC.md) and [verification](VERIFICATION.md).

# Previous bronze DOOM-logo title

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

The preserved bronze ROM is `hangar-bronze-no-music-ntsc.nes` (local research archive; not bundled),
65,552 bytes, with SHA-256:

```text
c715b34bd688927579d20d6c593dbddb8436ca4a38dab4b78f553a5d04afe251
```

Check out commit `b0cde0b` to rebuild this bronze-only release with
`python3 tools/build.py --verify`. The other title
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
