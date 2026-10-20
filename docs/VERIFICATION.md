# Verification

The accepted release is `release/hangar-ntsc.nes`, 65,552 bytes, with SHA-256:

```text
277422aa65613d5f1a581fece1e398c161948d473741b0aa2b47b2d11113e4a2
```

## Enclosure, visibility and third encounter

The `prototype-2026-10-19-third-encounter` release combines the first room's
sealed inner enclosure, three-unit ammo pickup radius, conservative visibility
filter for selected slime-room views, and third soldier beyond the openable
door. The [release notes](RELEASE-NOTES.md) describe the gameplay changes.

[current-release.json](../verification/current-release.json) is the portable
evidence record for this exact ROM. It includes source and artifact hashes,
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

Rebuild and compare the current release with `python3 tools/build.py --verify`.
The [fresh standalone build](../verification/current-build.json) reproduced
this exact ROM with `python3 -I -S -B tools/build.py --verify`, in a new copy
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
node verification/gameplay-fixtures.mjs --core /path/to/jsnes/src/index.js
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
initial public release (`644d047c…`) using the same pinned JSNES core as the
browser app. Its artwork and opening level geometry also represent the current
build. It starts at the first gameplay view and preserves normal NTSC timing, including repeated
pictures while the world renderer works. No overclock, motion interpolation
or game-state injection was used. The GIF has no sound.

The 256×240 source frames are enlarged exactly 2× with nearest-neighbor pixels.
All 90 decoded GIF frames match their sampled source buffers; the linked PNG
is the native first frame. The ROM hash, input sequence, palette, duration and
artifact checksums are in [opening-gameplay.json](../verification/opening-gameplay.json).
This preview records emulated output, not measured browser/device performance.

## Package checks and limits

The public files were scanned for personal absolute paths, common credential
markers, symlinks, external game ROMs and WADs. The historical research name
appears only in documentation credits. These checks cover specified patterns;
they are not a general security certification. The only included `.nes` file
is the checksum-verified Hangar release. Generated `build/` files and local
Git metadata are excluded from the public-file scan.

The initial release was subsequently tested in the pinned JSNES core and in
desktop Safari at the live browser link; see [DEPLOYMENT.md](DEPLOYMENT.md)
for the original checks and subsequent release verification. No physical NES
or flash-cartridge test is claimed.
Mesen timing and build verification support further hardware testing; they
do not replace it. Content origins and license scope are
documented separately in [PROVENANCE.md](PROVENANCE.md) and
[LICENSE-SCOPE.md](../LICENSE-SCOPE.md).
