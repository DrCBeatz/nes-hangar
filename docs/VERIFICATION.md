# Verification

The accepted release is `release/hangar-ntsc.nes`, 65,552 bytes, with SHA-256:

```text
644d047c07fe9ade8c14b87c42faa5720b026e0a13c017c4326be604adebbc87
```

## Standalone build

On 2026-10-18, the source package was copied to a temporary directory outside
the research workspace and built with Python 3.13.5 and cc65's `ca65`/`ld65`
V2.18. The copy contained no prior build output. Python ran with `-I -S -B`,
disabling site packages and user Python configuration. A file-access audit
rejected Python reads outside the copied package and standard library; only
the assembler and linker were permitted as build subprocesses. Assembly
include paths were checked separately for references outside the package.
No WAD or sibling project was needed.

The generated ROM matched the included release byte for byte. Source inputs
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

## Gameplay and timing evidence

Before packaging, the title-screen build passed 89 full-route checks, 29
death/retry checks and 19 loading-input checks in Mesen at stock NTSC timing.
Coverage included combat, pickups, slime, the door, completion counts,
pause/resume, held Start, and direct retries. The linked instruction checks
covered 512 title/controller cases, 768 loading/controller/bank cases and 912
NMI calls. Across 68 upload/publication timing fixtures, the latest PPU write
was at cycle 2,218, leaving a conservative 48.33-cycle VBlank margin. These are
specific tested paths, not a proof of every possible execution.

The packaged ROM differs from that tested title build in exactly 12 heading
glyph bytes: the boot HUD heading and the same heading restored after pause.
All other ROM bytes are identical. The byte comparison, previous report
checksums and test counts are recorded in
[runtime-evidence.json](../verification/runtime-evidence.json). The historical
emulator traces and linked test harnesses remain outside this standalone
package; the build command does not rerun those gameplay tests.

The [opening-room](images/opening-room.png) and [encounter](images/encounter.png)
screenshots were subsequently captured from this exact release in Mesen,
using controller input, zero extra scanlines and the original sprite limits.
They are lossless conversions of the emulator's 256×240 screen buffers,
without compositing or retouching.

## README gameplay preview

The opening animation is a six-second, controller-driven capture of this exact
release using the same pinned JSNES core as the browser app. It starts at the
first gameplay view and preserves normal NTSC timing, including repeated
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

The exact release was subsequently tested in the pinned JSNES core and in
desktop Safari at the live browser link; see [DEPLOYMENT.md](DEPLOYMENT.md)
for that check’s scope. No physical NES or flash-cartridge test is claimed.
Mesen timing and build verification support further hardware testing; they
do not replace it. Content origins and license scope are
documented separately in [PROVENANCE.md](PROVENANCE.md) and
[LICENSE-SCOPE.md](../LICENSE-SCOPE.md).
