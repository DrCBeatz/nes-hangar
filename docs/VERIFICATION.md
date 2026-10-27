# Verification

## Current prepared release: v0.2.0

**v0.2.0 — Performance Update** was prepared on October 27, 2026, following
the author's successful playtest of the consolidated performance candidate.
The [reference ROM](../release/hangar-ntsc.nes) is 131,088 bytes, SHA-256:

```text
c100366ffc5b86e68ff441f2a2bd8d624a7c6f1e8d966c226f1894eeedd20977
```

The [release record](../verification/current-release.json) and
[build record](../verification/current-build.json) identify the final source
and binary. The title now reads **PROTOTYPE 0.2.0**, with a new period glyph
in its title-only assets. The
[title/startup record](../verification/v0.2.0-title.json) records the targeted
startup checks. The [binary comparison](../verification/v0.2.0-binary-scope.json)
compares this artifact with the accepted candidate and
finds 1,196 changed ROM bytes: 1,194 in the boot bank from the added eight-byte
packed glyph, caption and asset relocations, plus two fixed-bank cold-start
jump operand bytes. All other banks are identical; rendering and gameplay
logic/data are unchanged.

The targeted JSNES startup check passes 18 checks across 1,170 stock-NTSC
refreshes (583 with music ON, 587 with music OFF). It covers title PPU output,
credits and B/back, held-button suppression, music selection and entry into
gameplay in both modes. The actual
[v0.2.0 title screenshot](images/title-v0.2.0.png) was visually checked. These
are startup checks, not a new complete-level playthrough or audible/hardware
verification.

The repository build and a fresh standalone build reproduce the final ROM.
The standalone check used `python3 -I -S -B tools/build.py --verify` without
prior generated output, research-workspace dependencies or third-party Python
packages. All 77 source hashes are recorded in the build record; the only
build input changed from the accepted candidate is `tools/newtitle_logo.py`.

The prior rendering, timing and upload measurements below describe the
accepted October 26 candidate, not a newly benchmarked v0.2.0 build. Its
gameplay code is preserved in v0.2.0, so the title update introduces no new
rendering optimization or performance claim. The author's acceptance is
recorded separately from automated test results; no extra music-mode or
controller-route coverage is inferred from that report.

Browser deployment and itch.io publication have not been performed for this
version. Physical-console testing remains outstanding.

## Previous consolidated performance candidate

`prototype-2026-10-26-performance-rc1` consolidates the accepted rendering and
input-response experiments. Its historical ROM
is 131,088 bytes, SHA-256:

```text
70a7593068e3e73eec3f448627dc1e930867069aea08aa73a6bd90f54f087817
```

The [archived release record](../verification/performance-rc1-release.json) identifies the
candidate, and the [consolidation build record](../verification/build-consolidation-20261026.json)
records its source and binary identity. At consolidation, both the repository
build and a fresh standalone build outside the research workspace reproduced
that ROM exactly. The latter used `python3 -I -S -B tools/build.py --verify`,
with no previous generated files, sibling project or third-party Python
packages. That candidate retained the original October 24 title caption to
match the accepted experiment exactly. Running the standard verification
command in the current checkout instead checks v0.2.0.

The [performance summary](../verification/performance-update-20261026.json)
joins the already measured, matching CPU fixtures from release → sprite-response
→ 16-pixel lists → exact-position rejection. Intermediate cycle totals agree
for each case. Across 172 fresh renders, the accumulated reduction is **14.9%**;
the 90-row primary world-route subset is **14.0%**. These are completed-producer
CPU costs excluding interrupt, music and upload/display time. They do not
establish an equivalent frame-rate increase. Stationary retained-background
controls are reported separately. See [the readable comparison](PERFORMANCE-UPDATE-20261026.md).

The final exact-position rejection experiment passed 354 paired renders,
49,232 column depth/span comparisons, and exact meaningful world, sprite and
upload-output checks against its immediately preceding baseline. Fractional
positions, heading boundaries, normal/coarse modes, both staging buffers,
doors, recess, pickups and modeled abort/retry cases were covered. Relative
to the public release, the deliberate distant-soldier floor correction changes
some actor pixels and the final encounter activates earlier at the doorway;
world rendering remains unchanged in the comparison fixtures.

Linked initializer/gate checks cover 11,264 initializations, 88,264 gate calls
and 699 modeled interrupt-state interference cases. Upload deadline tests cover
4,878 cases and 358 complete jobs, including title transfers. The worst final
PPU access is 2,254 of 2,273 available CPU cycles after the suite's instruction
and DMA allowances: a **19-cycle margin**. This is bounded test evidence,
not a reason to raise transfer limits further.

The final experiment's matched live Mesen comparison covers 18 primary trial
pairs and two reversal pairs, totaling 24,824 refreshes. It uses stock NTSC,
zero extra scanlines, normal sprite limits and music ON/OFF. The actual bank
state is checked at 358 initializer returns and 10,715 setup checkpoints;
no observed out-of-window PPUDATA write, overflow, stale terminal camera or
post-release simulation movement occurs. The archived
[final experiment report](../verification/performance-20261026/axis-verification.txt)
and [live timing report](../verification/performance-20261026/live-report.txt)
retain their original baseline/candidate identities and detailed scope. Input-to-picture timing can still
vary by a refresh or two; measured regressions are retained in the report.
These are seeded scene routes, **not a new controller-only end-to-end playthrough**.

The author subsequently playtested this consolidated candidate and accepted
it for the next version. The report did not specify a new test protocol or
music settings, so no additional automated coverage is inferred. Browser
deployment and an itch.io update remain separate steps. No physical-console
test is claimed. Historical evidence below retains its original ROM identity
and is not presented as newly run coverage.

## Previous door-reach and alias-credit release

The October 24 published release was `prototype-2026-10-24-door-reach`,
131,088 bytes; the browser still serves this historical version:

```text
db258e4c9c57ff3ef9f4bc8eb732f31b65eec85a1a639e7a9787a90dde1722a9
```

It extends door use reach from eight to twelve units and uses **Dr C Beatz**
as the public author credit. Only 25 ROM bytes change from the preceding
credits/HUD build: two door-distance immediates and 23 credits nametable
bytes. Linked addresses, segment sizes and RAM allocations are unchanged.
The [release record](../verification/door-reach-release.json) identifies the
release and its evidence.

The [door report](../verification/door-center.json) reproduces a settled,
centered view at 8.25 units where the door nearly fills the screen but the
old reach rejects use. The candidate repairs those visually close cases on
both sides and with both music settings. True physical-contact cases passed
in both builds; no separate intermittent rejection at contact was reproduced.
See [DOOR-REACH.md](DOOR-REACH.md) for the before/after images and limits.

The focused comparison covers 16,636 stock-NTSC Mesen refreshes, 40 identical
world-image fixtures and 120 before/after JSNES controller approaches from
legal injected starting poses. Extended-range boundary checks retain facing,
wall-side, fresh-A, strafe, death, completion and collision/publication guards.
The linked distance regression passes 63,366 calls; the historical facing-angle
regression passes 63,102. These focused fixtures clear enemies to isolate use.

The [controller/UI suite](../verification/door-reach-controller.json) passes
44 checks: music ON startup/pause, the complete OFF level route, credits
navigation, alias-only author text, both HUD pages, death/retry, completion,
restart and reset. It covers 1,823 ON refreshes and 20,007 OFF refreshes.
The [updated credits screenshot](images/credits.png) was captured from the
actual ROM and visually checked; its provenance is in the
[UI screenshot record](../verification/door-reach-screenshots.json).

The final controller-only [Mesen route](../verification/door-reach-mesen.json)
passes all 26 route checks and 44 independent rendered-world comparisons in
14,963 refreshes / 161 phases with music ON, stock NTSC timing, zero extra
scanlines and normal sprite limits. All three kills, both pickups, slime,
the door, exit, pause and restart pass. No observer errors or nested NMI were
observed. The minimum observed final PPU-write margin is 62.67 CPU cycles
before pre-render. This is measured coverage, not a proof of all execution
paths. Personal Mesen settings were preserved.

The [performance comparison](../verification/final-performance.json) finds
identical CPU cycles, world/staging data and upload work in 18 producer
fixtures. Both music modes also retain the baseline's measured camera states
and timing across 19,204 stock-NTSC refreshes / 48 settled input onsets across
the two builds. Those camera trials remove actors during setup to isolate
latency. The [assessment](FINAL-PERFORMANCE.md) explains why the renderer is
retained for release; no new rendering-speed gain is claimed.

A [fresh standalone build](../verification/door-reach-build.json) outside the
research workspace reproduces the ROM byte for byte with
`python3 -I -S -B tools/build.py --verify`. All 75 source hashes match, with
no prior generated files, sibling project, WAD or third-party Python package
required. Source publication and browser deployment completed on October 24,
2026; their separate checks are recorded in [deployment](DEPLOYMENT.md).
No physical-console test is claimed. Historical evidence below retains its
original ROM identity.

## Previous credits, HUD and soundtrack candidate

The previous local candidate was `prototype-2026-10-24-credits-hud`,
131,088 bytes:

```text
867f9ae9999f895bea3b68f5ca13f8a2ff73047fee0b9f2a696fdb542dc4e249
```

It integrates the user-tested Dr. C Beatz arrangement and ammo position
(282, 250), then adds the optional credits page, revised title/guide captions
and static WEAPON / PISTOL HUD label. The
[archived release record](../verification/release-ui-release.json) identifies
this exact binary and separates it from the earlier experiments below.

A fresh temporary checkout outside the research workspace reproduced this ROM
byte for byte using `python3 -I -S -B tools/build.py --verify`. It contained
only the packaged build inputs and release reference: no previous generated
output, WAD, sibling project or third-party Python packages. All 82 input
hashes match the working sources; see the
[archived build record](../verification/release-ui-build.json). Desktop metadata
such as `.DS_Store` is excluded from the source manifest.

The [controller/UI report](../verification/release-ui-controller.json) passes
44 checks in the pinned JSNES core: 1,823 refreshes with music ON and 20,007
with music OFF. Coverage includes exact logo/credits/guide data and scroll
state, held-button suppression, B/back and Start/continue, both music choices,
both HUD pages, firing, pause, natural death/retry, the complete OFF route,
completion/restart and reset. An initial credits-screen nametable-selection
fault was reproduced in actual emulator output, corrected, and covered by a
regression assertion. The [UI screenshots](../verification/release-ui-screenshots.json)
are unmodified emulator framebuffer captures and were visually inspected.
These are isolated-core checks, not a hosted website or mobile-browser test.

The final controller-only Mesen run uses stock NTSC timing, zero additional
scanlines, normal sprite limits and music ON. It passes all 26 route checks
and 44 independent rendered-world comparisons in 14,963 refreshes / 161
phases. It covers three kills, both pickups, slime, the door, exit, pauses,
completion and restart. No observer errors or nested NMI were observed. The
minimum observed final PPU-write margin is 62.67 CPU cycles before pre-render;
this measured coverage does not establish safety for every possible state.
The portable runner preserved personal Mesen settings. See the
[Mesen record](../verification/release-ui-mesen.json).

The credits page occupies 1,177 bytes in previously unused PRG bank 4, plus
an 11-byte mirrored COMMON gateway. It uses the existing font and temporary
storage, adds no RAM, and runs only before gameplay. BOOTDATA is 8,020/8,192
bytes; COMMON is 8,165/8,176 bytes below the reserved reset tail. The static
HUD substitution adds no gameplay update work. No rendering-speed improvement
is claimed for this UI pass. The cartridge remains MMC1 with 128 KiB PRG,
8 KiB CHR-RAM and 8 KiB work RAM. No physical-console test or live website
deployment is part of this update.

The earlier [music audition](../verification/drcbeatz-music-summary.json),
[music cost comparison](../verification/drcbeatz-music-performance.json) and
[ammo placement checks](../verification/ammo-placement-summary.json) retain
their own tested ROM identities. They are supporting history, not newly run
checks of the final UI binary.

## Previous close-angle door prompt

The following results describe the previous door-angle release, SHA-256
`2e89760fcaa8175eacd400285d9887dce7e74fce8f5df126a13445cad55ab6a6`,
preserved as `hangar-door-angle-ntsc.nes` (local research archive; not bundled).
Its [release record](../verification/door-angle-release.json) retains that identity.

That change widens the door facing allowance from 45 degrees to about
74.5 degrees. Legal close approaches beside either jamb can aim into the
panel at angles outside the old cone. Matched tests reproduce the missing
prompt in both the previous interaction and latency ROMs. Details are in
[DOOR-APPROACH.md](DOOR-APPROACH.md).

Only four immediate ROM bytes change from the accepted latency build;
`src/door.s` is the sole changed build input. All linked addresses and segment
sizes remain unchanged. The door's distance and physical collision checks,
fresh-A rule, strafe controls, renderer, ammo and exit rules are retained.

The linked 6502 regression passes 51,838 calls: exhaustive angle and range
boundaries, door lifecycle/collision, exit and input guards. Eight physically
legal close-contact poses run in both music modes. All sixteen accept the
prompt and fresh A in the candidate and reject both in the prior ROM. The
[portable test report](../verification/door-approach-linked.json) distinguishes
these injected-state routine checks from actual PPU/controller tests.

Stock-NTSC Mesen runs with zero extra scanlines confirm the six reproduced
close-angle failures now show the prompt and open the door, with music ON
and OFF. Turning then using the door also succeeds. Facing-away and
just-outside-cone guards still reject use; held-A approaches stay closed
until release and a new press. The candidate covers 9,184 refreshes and 94
screenshots. Thirty matched world-image comparisons (1,351,680 pixels) are
identical to the previous build; the changed prompt is checked separately
on both HUD pages. These fixtures inject legal starting poses and disable
enemies to isolate door behavior. Every run preserves personal Mesen settings.

The candidate also passes all 30 controller-driven JSNES checks, including
a complete level route with music OFF, all three kills, both pickups,
door/exit use, pause, death retry, completion/restart and cold reset. ON
startup/pause/retry coverage takes 1,485 refreshes; OFF coverage takes 19,787.
These use the pinned emulator core with no game-state injection, rather than
the hosted browser UI. See the [archived controller record](../verification/door-angle-browser.json).

The [door report](../verification/door-approach.json) records the stock-NTSC
Mesen comparison and the exact candidate identity. The [archived build record](../verification/door-angle-build.json)
records a fresh build outside the research workspace, with all 78 source
hashes and no prior generated output or third-party Python packages.
No physical-console test or live website deployment is part of this update.

## Previous input-to-picture latency tuning

These results describe the accepted latency ROM, SHA-256
`0dbee1ad5765bc00ac10e1736902ee381a88c3c539b8c68de12f24f887260d89`, preserved as
`hangar-latency-ntsc.nes` (local research archive; not bundled).
Its [build record](../verification/latency-build.json),
[release record](../verification/latency-release.json) and
[JSNES record](../verification/latency-browser.json) retain that exact identity.
This candidate changes directional-input invalidation and raster
nametable dirty marking. It leaves physics, collision, uploaded image data,
artwork, music and NTSC transfer limits intact. The
[latency notes](LATENCY-TUNING.md) explain the implementation and limitations;
[latency-tuning.json](../verification/latency-tuning.json) records the
accepted evidence and exact ROM identity.

Two stock-NTSC diagnostic tests first distinguish live simulation response
from delayed pictures: starting/stopping/turning in several rooms, then
starting from an idle renderer versus an already-busy producer. Initial
states are injected, followed by real controller input. Music ON/OFF runs
use zero extra scanlines. The comparison covers 44,268 measured refreshes,
128 settled start trials and 64 matched release trials. All recorded
positions/floors remain legal and all final views settle. Live input responds
within one to three refreshes in these fixtures, and the player state does not continue changing after
release. The displayed camera can keep advancing as previously generated
pictures arrive. Publication timestamps exclude physical display delay. The
candidate boots its first picture one refresh earlier, changing the phase
against the 50 Hz movement cadence; single-refresh differences are not a
meaningful speed claim.

Matched busy-render onset tests improve first responsive publication by
21–34 refreshes with music ON and 21–30 OFF. Their controlled busy condition
increments the scene version to start an otherwise unchanged background
render; it is not a naturally moving-enemy benchmark. Idle starts are nearly
unchanged, while release tails remain mixed. The largest individual release
regression in this onset sample is nine refreshes with music OFF. Additional
short-input reversal tests show mixed idle-start results and as much as a
12-refresh regression in individual cases. Their controlled busy-render sample
reduces mean final-stop delay from 58.75 to 48.5 refreshes ON and from 55 to
48.75 OFF. The [latency notes](LATENCY-TUNING.md) retain the separate
measurement scopes and explain why upload phase can alter the result. Across
all 64 matched releases, 34 improve, 17 are unchanged and 13 regress.

The raster test passes 294,912 linked instruction fixtures spanning all
256 tile IDs, every viewport tile and both destination banks. It verifies
A/Y/stack preservation and identical dirty flags: the old call takes 84 cycles
including JSR, versus 26 for the specialized inline path. Another 32 complete
renders at 16 diagnostic poses compare 1,179,648 background pixels, all
staging bytes, actor/OAM data, palette metadata and dirty upload lists with
the baseline. Every comparison matches. These are interrupt-free producer
checks, not gameplay FPS or PPU deadline measurements.

Portable reproduction with an accepted-baseline build directory and the
pinned JSNES core:

```sh
node tests/latency-input.mjs --build build --core /path/to/jsnes/src/index.js --policy all --output build/latency-input.json
node tests/raster-dirty.mjs --baseline /path/to/interaction-build --build build --core /path/to/jsnes/src/index.js --output build/raster-dirty.json
```

The final candidate passes 30 controller-driven JSNES checks: 1,485 refreshes
with music ON and 19,787 with it OFF, including the complete OFF route. These
are isolated core tests, not a live browser/mobile UI test.

The complete stock-NTSC Mesen confirmation run with music ON passes all 26 route checks
and 44 rendered-view oracle comparisons in 15,110 refreshes / 161 phases.
The largest observed NMI is 18,667 CPU cycles; the minimum final PPU-write
margin is 55.67 CPU cycles. This coverage does not establish timing safety
for every possible gameplay state. This confirmation also passes the driver's
ROM, label and personal-settings preservation checks.

An earlier full-route capture completed with the same gameplay/image results,
but its final ambient personal-settings hash guard failed. The origin of that
settings change was not established. That earlier limitation is retained in
the provenance; no personal settings were restored or overwritten. Both runs
used isolated portable stock-NTSC settings.

A fresh temporary directory outside the research workspace reproduces this
ROM byte for byte with `python3 -I -S -B tools/build.py --verify`, without
prior build output or third-party Python packages. The
[archived latency build record](../verification/latency-build.json) retains the
78 source hashes and tool versions. No live website deployment or
physical-console test is part of this change.

## Previous door, exit and ammo interaction changes

These results describe the accepted interaction baseline, SHA-256
`0ecf59bf29efb03e5619a30d8bf890500a96e505a18f661920ab02fdbc9bd086`, preserved as
`hangar-interactions-ntsc.nes` (local research archive; not bundled).
It changed eligibility thresholds and the ammo pickup radius. Its behavior
and remaining presentation limits are described
in [INTERACTION-FIX.md](INTERACTION-FIX.md). Its focused results are recorded in
[interaction-fix.json](../verification/interaction-fix.json); the
[archived build](../verification/interaction-build.json),
[archived release](../verification/interaction-release.json) and
[archived JSNES](../verification/interaction-browser.json) records identify this
baseline separately from the earlier optional-music baseline.

That candidate passed 51,662 linked door/exit calls. The door/exit-only
intermediate passed 2,632 stock-NTSC Mesen refreshes per music mode and ten
matched world-image comparisons; its door/exit code is unchanged in the final
combined ROM. These focused fixtures use injected initial state, followed by
controller input.

Matched baseline/candidate ammo tests pass 441,000 native range calls across
all seven lower PRG banks, plus 8,214 candidate-only translated-position calls.
Coverage includes 110,250 unchanged-medkit comparisons, 21 scratch-ownership
cases and 18 lifecycle cases. The range helper's observed maximum remained
413 CPU cycles. Nineteen focused stock-NTSC Mesen cases span
3,183 refreshes without observer errors or nested NMI. The new radius accepts
close lateral passes and retains the earlier wall-side rejection; the settled
3.5-unit frontal clipping case remains a documented presentation limitation.

That candidate also passed 30 controller-driven JSNES checks: 1,486
refreshes with music ON and 19,748 with it OFF, including a complete 151-phase
OFF route, natural death/retry, completion/restart and cold reset. These are
isolated emulator-core tests, not a live website or mobile UI test.

Its final controller-only Mesen route passed at stock NTSC timing with music
ON: 15,121 refreshes / 161 phases, all 26 route checks and 44 rendered-view
oracle comparisons. It includes all three kills, both pickups, slime, the
door, pause, completion and restart. No observer errors or nested NMI were
observed. The minimum observed final PPU-write margin is 56.67 CPU cycles
before pre-render; this does not establish safety for every possible scene.

A fresh temporary directory outside the research workspace reproduces the
ROM byte for byte using `python3 -I -S -B tools/build.py --verify`, with no
prior build output or third-party Python packages. The archived build record
retains the 78 source hashes and tool versions.

Only 29 ROM bytes change from the optional-music baseline, with every linked
label address and segment size retained. The ammo table contributes three
changed bytes in each of seven mirrored lower PRG banks; the door and exit
contribute eight changed immediate bytes.
The original interaction repros remain historical baseline evidence, not tests
of the adjusted thresholds. No latency improvement, browser deployment or
physical-console verification is claimed.

## Previous optional music integration

These results describe the unchanged optional-music baseline, SHA-256
`c2a913ddd057235e11936e4c212eb0d3a93e1c6f422315d03bd05baaea80ab1b`, preserved as
`hangar-optional-music-ntsc.nes` (local research archive; not bundled).

At integration, the main sources rebuilt the already tested Dr. C Beatz remix
ROM byte for byte. The [optional-music build record](../verification/optional-music-build.json) identifies
the packaged inputs and independent build; the
[optional-music release record](../verification/optional-music-release.json) connects that
artifact to the prior experiment's retained evidence. No emulator test is
claimed anew merely because the identical binary moved into this directory.

The [music validation report](../verification/music-validation.json) records
19 linked-audio groups / 31,810 calls, three full 5,632-frame loops, four active
voices, disabled DPCM and sound-effect priority/restoration. Audio RAM is
206/216 bytes; the original eight-byte scratch alias is unchanged.

Thirty controller-driven JSNES checks cover both menu options, firing, pause,
natural death/retry, a complete OFF route, completion/restart and cold reset.
The matching ON route in stock-NTSC Mesen completes 15,121 frames / 161 phases,
all three kills, both pickups, slime, door, pause, completion and restart.
All 26 route checks and 44 rendered-view checks pass. No nested NMI or late PPU
write was observed. The smallest observed final PPU-write margin was 56.7 CPU
cycles; this is measured coverage, not proof of every possible timing case.

The [optional-music JSNES record](../verification/optional-music-browser.json) refers to
isolated emulator-core tests of that binary. It is not a live website or mobile
UI test. No browser deployment or physical-console test is claimed.

These checks establish the earlier integrated baseline. The [interaction repros](INTERACTION-REPRO.md)
identify usability issues without altering gameplay rules; their measured
results are in [interaction-repro.json](../verification/interaction-repro.json).

## Previous bronze title integration

The `prototype-2026-10-21-bronze-title` release promotes the previously tested
bronze title ROM without changing its binary. The default build uses bronze;
`--title-palette` retains the alternate colours for intentional modified builds.
[bronze-title-release.json](../verification/bronze-title-release.json) records the
accepted artifact and its evidence, and
[bronze-title-build.json](../verification/bronze-title-build.json) records a fresh
standalone `python3 -I -S -B tools/build.py --verify` run.

The bronze candidate's 21 stock-NTSC Mesen startup checks and six binary/asset
checks are retained in
[title-palette-comparison.json](../verification/title-palette-comparison.json).
They verify both fresh-Start gates, frozen gameplay during title/loading,
the original controls guide, and complete restoration of the first gameplay
picture's CHR, PPU memory and RGB pixels. Bronze differs from the grayscale
title only in three palette bytes. The earlier grayscale title's complete
three-encounter route, pickups, results and direct restart are recorded in
[title-screen-experiment.json](../verification/title-screen-experiment.json).
That full route was not repeated for the palette-only change.

The bronze release's focused JSNES startup smoke is recorded separately in
[bronze-title-browser.json](../verification/bronze-title-browser.json). It does not
represent a full browser route, all app tests, or a hosted deployment.

BOOTDATA is 7,376/8,192 bytes; every other linked segment retains its previous
size. The matched opening producer costs the same 884,349 CPU cycles in the
grayscale and bronze title builds. This is a matched scene measurement;
the stronger structural result is that the colour change modifies only
palette data. That historical release contains no music engine; no physical-console test
is claimed.

## Previous soldier sprite stability

The `prototype-2026-10-21-sprite-stability` release combines intermediate
26 × 52 and 30 × 60 soldier sizes, near-size hysteresis, and radial vertical
placement for soldiers and corpses. It preserves the map, gameplay and
cartridge layout. The [sprite notes](SPRITE-STABILITY.md) explain the visual
tradeoff; stable vertical placement is not exact off-axis floor projection.

[sprite-stability-release.json](../verification/sprite-stability-release.json)
records that prior artifact and its evidence. Its
[fresh standalone build](../verification/sprite-stability-build.json) checked
that the packaged source reproduced that release with
`python3 -I -S -B tools/build.py --verify`.

The final ROM's linked helper checks include 3,537 size cases and 1,024 epoch
cases in [sprite-size-fixtures.json](../verification/sprite-size-fixtures.json),
plus 4,959 radial-anchor cases and twelve far-radius acceptance/rejection
checks in [sprite-radial-fixtures.json](../verification/sprite-radial-fixtures.json).
These execute assembled 6502 routines with injected state and interrupts
suppressed; they are not normal play or PPU timing tests.

After building, rerun the portable sprite helpers with the pinned JSNES core.
Their default reports go under `build/`, leaving accepted evidence intact:

```sh
node verification/sprite-size-fixtures.mjs --core /path/to/jsnes/src/index.js
node verification/sprite-radial-fixtures.mjs --core /path/to/jsnes/src/index.js
```

[sprite-render-comparison.json](../verification/sprite-render-comparison.json)
compares the final ROM against the preceding size-only candidate in stock
NTSC Mesen: 60 fixed-radius turns and 23 wall, pillar, recess, corpse, item
and culled-actor controls per ROM. The tests explicitly inject diagnostic
poses and hold the AI still. They verify stable vertical position, unchanged
world pixels and true-depth masks, unchanged item projection/pixels, and
coherent publication with no observed illegal PPU writes or nested NMI.
The observed maximum is eight sprites on a scanline. These are bounded
checks, not proof of every possible camera pose.

[sprite-size-comparison.json](../verification/sprite-size-comparison.json)
preserves the earlier sizing experiment: 423 ordered poses per ROM compare
the old `277422aa…` release to the intermediate `b5b1ec39…` candidate. They
show smaller steps and no repeated threshold toggling in the tested cases.
This report deliberately retains that intermediate ROM hash; it is not a
claim that the final radial-anchor ROM ran the same entire pose sequence.

All 18 isolated emulator tests passed for the final ROM. The controller-only
JSNES route completed 7,529 normal NTSC refreshes, including all three kills,
both pickups, pause, the empty-gun cue, the door, completion and restart.
It finished with twelve shots, nine hits, four rounds and 90 health; three
rounds were deliberately wasted to test the empty-gun cue. All 46 read-only
RAM symbols matched the new linker output. See
[sprite-stability-browser.json](../verification/sprite-stability-browser.json). The live site
still serves the previous release; these tests did not deploy an update.

The normal build does not rerun the research emulator harnesses. Detailed
traces remain in the research workspace rather than this standalone package.
No physical NES or flash-cartridge test is claimed.

## Previous enclosure, visibility and third encounter

The `prototype-2026-10-19-third-encounter` release combines the first room's
sealed inner enclosure, three-unit ammo pickup radius, conservative visibility
filter for selected slime-room views, and third soldier beyond the openable
door. The previous-release section of the [release notes](RELEASE-NOTES.md) describes those gameplay changes.

[third-encounter-release.json](../verification/third-encounter-release.json) is the portable
evidence record for that ROM (`277422aa…`). It includes source and artifact hashes,
cartridge and linked-memory sizes, geometry proofs, focused helper checks,
producer comparisons, and summaries of two controller-only Mesen routes.
Detailed research traces, old ROM baselines and workspace-specific harnesses
are retained separately; they are not part of the standalone source package.

The Mesen routes ran with normal NTSC timing, zero extra scanlines, the original
sprite limit and no run-ahead, with no writes to game RAM or ROM by the test
driver. Together they covered 23,062 refreshes and 55 exact background/palette
comparisons. The full-clear route finished with nine shots, seven rounds,
3/3 kills and 2/2 items, then checked restart state. The other route left the
second soldier alive and verified the third soldier's health and defeated
state across backtracking. No illegal rendering-time PPU writes, nested NMI,
record ownership violations or resource overflows were observed.

Separate linked fixtures inject controlled state to check fractional gates,
movement and sight, attacks, item absence in the third encounter, all eight
alive/dead combinations, and persistent-record ownership across the three
PRG mappings. Fourteen matched producer poses retain identical background
pixels and match the all-face reference. Their CPU-cycle measurements exclude
interrupts and uploading; they are not gameplay frame rates.

At [source commit 0f31a394](https://github.com/DrCBeatz/nes-hangar/tree/0f31a3947b7d8a2bed63c64acc53ce8812ce3470), rebuild and compare that release with `python3 tools/build.py --verify`.
The [historical standalone build](../verification/third-encounter-build.json) reproduced
that exact ROM with `python3 -I -S -B tools/build.py --verify`, in a new copy
outside the research workspace with no prior build output. The portable
pickup/exit/sound helper suite also passed from that copy.
The normal build does not rerun the research emulator harnesses. The cartridge
remains MMC1 with 64 KiB PRG, 8 KiB CHR-RAM and 8 KiB work RAM. Only one of the
three enemy encounters simulates and renders at a time. No physical NES or
flash-cartridge test is claimed. Browser publication checks are recorded
separately in [DEPLOYMENT.md](DEPLOYMENT.md).

The following sections preserve earlier releases and their original evidence.

## Previous deep empty-gun buzz

The `prototype-2026-10-18-empty-buzz` release replaces the short click with
an eight-refresh (~133 ms) low buzz. Short-noise period index 12 runs at 762
CPU cycles, compared with the preceding index 4 at 64 cycles; constant volume
increases from 8 to 10. Fresh-press, cooldown and sound-channel ownership
rules are unchanged. It does not flash the weapon or count as a shot.

Its historical ROM SHA-256 is
`08ba1092db774a1c543345274f0835c8ca2413a725484a870286a746fa9c2462`.

[empty-buzz-change.json](../verification/empty-buzz-change.json) records
exactly three changed ROM bytes after a full source build: cue duration,
volume and period. Linked addresses, code size and RAM use are unchanged.
[empty-buzz-fixtures.json](../verification/empty-buzz-fixtures.json) records
10 passing helper checks, including the full eight-tick lifetime, pause,
cleanup, shared sound-channel ownership and unchanged pickup/exit boundaries.
All 18 browser tests and the production build passed; the controller-only
route completed 7,500 stock NTSC refreshes. Earlier reports below retain
their original release hashes and describe those preceding builds.

## Previous lower-pitched click

The `prototype-2026-10-18-low-click` release changes one byte relative to the
previous gameplay release (`fcc47032…`): the short-noise period written to
`$400E` changes from index 2 to index 4 (16 to 64 CPU cycles). This gives a
lower click while retaining volume 8, the two-refresh duration and all input
behavior. Code size, RAM use and linked addresses are identical.

[dry-fire-pitch-change.json](../verification/dry-fire-pitch-change.json)
records the exact byte comparison after rebuilding from source.
[dry-fire-pitch-fixtures.json](../verification/dry-fire-pitch-fixtures.json)
records the current ROM's 10 passing helper checks, including sound-channel
ownership, pause/resume and the unchanged pickup/exit boundaries. These use
the same controlled CPU/RAM fixtures described below. All 18 browser tests
and the production build also passed; the controller-only route again
completed 7,493 stock NTSC refreshes. Earlier reports retain
their original ROM and driver hashes; their tested source remains in Git.

## Previous gameplay update

The `prototype-2026-10-18-gameplay` release tightens the ammo clip's pickup
radius from six to four world units; the medkit stays at six. Both previously
used the same circle, but the clip's narrower visible artwork made its trigger
feel more generous. The exit now accepts X `[286,294)`, Z `[22,34]`, and heading
`172..212` on the 256-angle circle, while retaining fresh-A and no-strafe guards.
A fresh empty B press produces a two-refresh mechanical click without a shot,
muzzle flash, damage or enemy alert. Holding B does not repeat it.

A clean copy outside the research workspace rebuilt byte-for-byte with
`python3 -I -S -B tools/build.py --verify`; see
[gameplay-build.json](../verification/gameplay-build.json). The change adds
75 code bytes and four table bytes, with no added RAM or graphics storage.

[gameplay-tweaks.json](../verification/gameplay-tweaks.json) records execution
of the assembled pickup, exit and sound helpers using controlled CPU/RAM
fixtures. The old/new comparisons cover 5,328 fractional pickup cases and
5,616 exit boundary cases, plus input guards, dry-click lifetime, pause,
cleanup and shared sound-channel behavior. These are injected boundary tests,
not normal play. After building, run the candidate fixtures with an existing
installation of the pinned JSNES core:

```sh
node verification/gameplay-fixtures.mjs --core /path/to/jsnes/src/index.js --output build/gameplay-fixtures.json
```

The core is `taiyuuki/jsnes` commit `5b27c4243f1cb2528c54941e13c29c4ced7d5a45`,
also pinned by the browser app. Optional `--baseline /path/to/old-build`
compares the initial public ROM, its `hangar.lbl` and generated `map.json`.
No npm dependency is needed for the normal ROM build.

Separately, the browser repository's controller-only test completed 7,493
stock NTSC refreshes without state injection: title/loading, pause and edge
view, both soldiers, medkit, ammunition exhaustion, empty click and its
pause/resume, replenishment from zero to ten rounds, door, the widened exit,
completion counts and restart. All 18 browser repository tests and its
production build passed. The controller trace summary is in
[gameplay-browser.json](../verification/gameplay-browser.json); see
[DEPLOYMENT.md](DEPLOYMENT.md) for publication.

[gameplay-feedback-nmi.json](../verification/gameplay-feedback-nmi.json)
records 96 focused linked-instruction timing fixtures. The maximum world PPU
write remains at cycle 2,218, leaving the previous conservative 48.33-cycle
NTSC VBlank margin. The instruction model and historical adapters remain
outside this package; this is not an exhaustive timing proof or hardware test.

## Initial public build

The initial public ROM (`644d047c…`) is preserved in Git history. Its reports
below describe that baseline, not the revised gameplay ROM above.

On 2026-10-18, the source package was copied to a temporary directory outside
the research workspace and built with Python 3.13.5 and cc65's `ca65`/`ld65`
V2.18. The copy contained no prior build output. Python ran with `-I -S -B`,
disabling site packages and user Python configuration. A file-access audit
rejected Python reads outside the copied package and standard library; only
the assembler and linker were permitted as build subprocesses. Assembly
include paths were checked separately for references outside the package.
No WAD or sibling project was needed.

The generated ROM matched that initial release byte for byte. Source inputs
were unchanged by the build. The builder also checked the cartridge header,
linked segment capacities and the mirrored common-bank/reset-vector data.
The input hashes, tool versions and package scan results are recorded in
[standalone-build.json](../verification/standalone-build.json).

To reproduce the ROM check:

```sh
python3 tools/build.py --verify
```

Normal builds omit `--verify` to allow deliberate source or asset changes.
The initial [GitHub Actions build](https://github.com/DrCBeatz/nes-hangar/actions/runs/39169799691)
also passed on Linux after publication, reproducing the committed ROM.

## Initial gameplay and timing evidence

Before packaging, the title-screen build passed 89 full-route checks, 29
death/retry checks and 19 loading-input checks in Mesen at stock NTSC timing.
Coverage included combat, pickups, slime, the door, completion counts,
pause/resume, held Start, and direct retries. The linked instruction checks
covered 512 title/controller cases, 768 loading/controller/bank cases and 912
NMI calls. Across 68 upload/publication timing fixtures, the latest PPU write
was at cycle 2,218, leaving a conservative 48.33-cycle VBlank margin. These are
specific tested paths, not a proof of every possible execution.

The initial packaged ROM differs from that tested title build in exactly 12 heading
glyph bytes: the boot HUD heading and the same heading restored after pause.
All other ROM bytes are identical. The byte comparison, previous report
checksums and test counts are recorded in
[runtime-evidence.json](../verification/runtime-evidence.json). The historical
emulator traces and linked test harnesses remain outside this standalone
package; the build command does not rerun those gameplay tests.

The [opening-room](images/opening-room.png) and [encounter](images/encounter.png)
screenshots were subsequently captured from the initial public release in Mesen,
using controller input, zero extra scanlines and the original sprite limits.
They are lossless conversions of the emulator's 256×240 screen buffers,
without compositing or retouching.

## README gameplay preview

The opening animation is a six-second, controller-driven capture of the
preceding credits/HUD candidate (`867f9ae9…`), using the pinned JSNES core
with music ON at its default setting. Its opening gameplay is unchanged. It begins at the first published gameplay
picture and preserves normal NTSC timing, including repeated pictures while
the world renderer works. No overclock, interpolation or game-state injection
is used. The GIF has no sound, although music sequencing was active in the ROM.

The 360-refresh capture yields 90 samples over 5.99 seconds. Its 256×240 source
frames are enlarged exactly 2× with nearest-neighbor pixels. Every decoded
GIF frame matches its sampled source buffer, and both opening stills match
the native first frame. The input sequence, ROM/core hashes and artifact
checksums are in [opening-gameplay.json](../verification/opening-gameplay.json).
This records emulated output, not measured browser/device performance.
The [initial capture record](../verification/opening-gameplay-initial.json)
remains historical evidence; the encounter still also predates this release.

## Package checks and limits

At initial publication, the public files were scanned for personal absolute paths, common credential
markers, symlinks, external game ROMs and WADs. The historical research name
appears only in documentation credits. These checks cover specified patterns;
they are not a general security certification. That initial package included only the checksum-verified Hangar ROM.
The current package includes only the current Hangar ROM. Historical comparison
builds and superseded music exports/notices are preserved in ignored local
research history, outside the published package. Generated `build/` files and
local Git metadata are excluded from the public-file scan.

The initial release was subsequently tested in the pinned JSNES core and in
desktop Safari at the live browser link; see [DEPLOYMENT.md](DEPLOYMENT.md)
for the original checks and subsequent release verification. No physical NES
or flash-cartridge test is claimed.
Mesen timing and build verification support further hardware testing; they
do not replace it. Content origins and license scope are
documented separately in [PROVENANCE.md](PROVENANCE.md) and
[LICENSE-SCOPE.md](../LICENSE-SCOPE.md).
