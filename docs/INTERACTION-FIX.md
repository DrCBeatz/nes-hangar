# Door, exit and ammo interaction changes

The preserved `prototype-2026-10-22-interactions` candidate followed the
[interaction repros](INTERACTION-REPRO.md) on the approved optional-music build.
It changes the interaction thresholds without changing the level, graphics,
rendering schedule, music data or sound effects.

## Door and exit

Both targets now accept facing within **±45° of the wall normal**, including
both endpoints. The door previously allowed ±22.5°, and the exit ±28.125°.
The door's usable lateral range now covers its complete panel, `288 ≤ X < 304`.
The narrower interaction rectangle could previously reject a legal position
near the side of the panel.

| Baseline reproduction | Previous behavior | Adjusted behavior |
| --- | --- | --- |
| Door at `(300,124)`, angle 160, aimed at its center | No prompt | Door prompt |
| Door at `(302.5,116)`, angle 0, within the panel span | No prompt | Door prompt |
| Exit at `(288,32)`, angle 160, aimed at its center | No prompt | Exit prompt |

Angles use the engine's 0–255 circle. Eligibility still compares facing to the
wall normal; this change does not introduce a target-vector calculation or
unrestricted proximity activation.

The existing distance and wall-side limits remain. For the door, the north
side uses `122 < Z ≤ 128` and angles 96–160; the south side uses
`112 ≤ Z < 118` and angles 224–255 or 0–32. These exclude the closed panel's
collision band. Door state, player health and completed-level checks remain
in force. The exit's position rectangle is unchanged.

A fresh **A** press is still required. Holding A while approaching does not
activate a target, and A+Left/Right continues to strafe. The door still becomes
physically open when its matching rendered view is published. Widening the
interaction allowance does not change that timing or physical collision.

## Ammo pickup

The clip's strict radius increases from **3 to 3.5 world units**. Each absolute
axis distance still rounds upward to an eighth before comparison. In the
integer squared-distance test, the threshold changes from `24² = $0240` to
`28² = $0310`; equality remains outside.

This accepts more close lateral and diagonal passes. For example, the earlier
2.8984375-unit near-edge rejection is inside the new circle, as is a 3.375-unit
centerline pass. A 3.5-unit pass remains outside, and the earlier 3.75-unit
wall-side bypass remains rejected. The medkit keeps its six-unit radius.

The pickup center, artwork, ten-round refill, 99-round cap, collection sound
and once-only collection are unchanged. Full ammunition still leaves the clip
on the floor. The [earlier radius-tightening notes](AMMO-PICKUP.md) retain the
history of the original four-to-three-unit adjustment.

This is a partial usability improvement. The clip can still move completely
below the viewport before collection, including the settled 3.5-unit frontal
fixture from the original repro. Solving that appearance would require a
separate projection or placement decision. A larger circular trigger alone
cannot distinguish an equal-distance frontal approach from a sideways pass.

## Timing and verification scope

Interaction uses the current player position and facing. A world view can
still show an older camera state while a new view is being rendered. Prompt
updates were already timely in the baseline repro; this change does not alter
the HUD upload schedule or claim an input-to-picture latency improvement.

The combined candidate changes 29 ROM bytes relative to the optional-music
baseline: eight door/exit immediates and three ammo-table bytes copied into
seven lower PRG banks. Every linked label address and segment size is unchanged;
there is no additional RAM allocation. The ROM remains 131,088 bytes.

The final candidate passes 51,662 linked door/exit routine calls. A separate
door/exit-only intermediate passed 2,632 stock-NTSC Mesen refreshes with music
ON and another 2,632 with it OFF; ten matched world images are identical to
the baseline. The final combined candidate retains identical door/exit code.
These Mesen fixtures inject legal starting states and then use controller
input; they are not controller-only whole-level routes.

The matched baseline/candidate ammo comparison passes 441,000 native-position
range calls across all seven lower PRG banks, plus 8,214 candidate-only
translated-position calls. Coverage includes
110,250 unchanged-medkit comparisons, 21 scratch-ownership cases and 18
lifecycle cases. The helper's
observed maximum remains 413 CPU cycles. Nineteen stock-NTSC Mesen cases cover
3,183 refreshes with no observer errors or nested NMI. A direct approach now
collects at 3.25 units instead of 2.75; a 2.8984375-unit lateral pass collects,
while 3.5- and 3.75-unit side passes still do not. The 3.5-unit frontal fixture
still hides the clip below the viewport before pickup.

Thirty controller-driven JSNES checks pass on the final candidate: 1,486
refreshes in the ON branch and 19,748 in the OFF branch, including a complete
151-phase OFF route. Coverage includes natural death, completion retries and
cold reset. The final controller-only stock-NTSC Mesen route passes 26 checks
and 44 rendered-view oracle comparisons over 15,121 refreshes / 161 phases.
It covers all three kills, both pickups, slime, the door, pause, completion
and restart. No observer errors or nested NMI were observed. The smallest
observed final PPU-write margin was 56.67 CPU cycles before pre-render; this
is measured route coverage, not proof of every possible timing case.

A fresh isolated `python3 -I -S -B tools/build.py --verify` run reproduces the
release ROM exactly from the packaged inputs, without prior generated output
or external Python packages. The build record retains 78 source-file hashes.

Results are recorded separately in
[interaction-fix.json](../verification/interaction-fix.json), with the final
ROM identity and build evidence in the
[interaction release record](../verification/interaction-release.json). The original
repro screenshots and measurements describe the preceding ROM. No browser
deployment or physical-console test is part of this change.

### Repeating focused tests

The door test now follows the later [close-angle fix](DOOR-APPROACH.md).
Use the test version matching the archived interaction build when repeating
its original 45-degree assertions; the command below targets current sources.

After building, point `--core` at the JSNES module used by the test harness:

```sh
node tests/door-exit-interactions.mjs --build build --core /path/to/jsnes/src/index.js --output build/door-exit-interactions.json
node tests/ammo-interactions.mjs --build build --baseline artifacts/interaction-baseline --core /path/to/jsnes/src/index.js --output build/ammo-interactions.json
```

The ammo comparison requires a separate **baseline build directory**, containing
matching `hangar-ntsc.nes`, `hangar.lbl` and `map.json` files for the three-unit
pickup baseline. The local research directory `artifacts/interaction-baseline`
is not included in a fresh checkout; the archived baseline ROM alone does not
supply its linked symbols and generated map. Use the retained matching build
artifacts when repeating that comparison, rather than pairing old ROM bytes
with the current build's metadata. The ammo harness checks the pinned JSNES
CPU implementation before executing.
