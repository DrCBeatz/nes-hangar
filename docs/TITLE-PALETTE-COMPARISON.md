# Title palette comparison

The title can use different colours from the game. Its palette is loaded while
rendering is blank; the controls guide and gameplay subsequently load their
own palettes. A colour title therefore does not reduce the wall, floor, HUD,
weapon or enemy colour choices during play.

This experiment keeps the accepted 192×94 logo, its pixel indices, all 186
patterns, the font, and the title code unchanged. It substitutes only the
three visible logo colours in the existing 32-byte palette. Black remains the
background and the subtitle and Start prompt remain white.

| Build option | Logo palette (black, shadow/face, midtone, highlight) | Appearance |
| --- | --- | --- |
| `grayscale` | `$0F $00 $10 $30` | Original neutral gray reference |
| `bronze` | `$0F $17 $27 $37` | Brown, amber and cream |
| `blue-gold` | `$0F $11 $27 $37` | Blue faces with gold and cream bevels |
| `steel` | `$0F $11 $10 $30` | Blue faces with gray and white bevels |

Blue and gold is the closest to the original logo's broad colour scheme.
Bronze and steel offer more uniform material treatments. Grayscale is an
aesthetic option, not a requirement for fitting the title into this ROM.

## Build and compare

From this experimental checkout:

```sh
python3 tools/build.py --title-palette blue-gold
```

Choose any option in the table. The output is `build/hangar-ntsc.nes` and its
decoded previews are in `build/previews/`. Omitting the option retains
grayscale and reproduces the previously tested title ROM exactly. The normal
build requires no WAD or image library. Do not pass `--verify`: the separate
`release/hangar-ntsc.nes` reference intentionally remains the gameplay release
without the new logo page.

The locally packaged comparison ROMs, checksums, previews and gallery are in
`artifacts/title-palettes/`. Each full build is preserved in the corresponding
palette subdirectory. The main checkout and hosted game have not been changed.

## Cost and limits

Every option retains the 64 KiB PRG / 8 KiB CHR RAM / 8 KiB work RAM layout.
BOOTDATA remains 7,376 of 8,192 bytes, leaving 816 bytes. There is no increase
in ROM use, RAM use, tile count, upload size or gameplay CPU work compared with
the grayscale title. One selected palette would ship in a normal build; the
ROM does not contain a runtime palette menu or all four versions of the art.

The current indexed conversion deliberately merged the original blue letter
faces and some bronze shadows into index 1. A blue palette also colours those
shadow details blue. This is a palette experiment on identical artwork, not
an exact reconstruction of all the source logo's original colours.

The background hardware also permits different palettes in 16×16-pixel
regions. That could give parts of a future title additional colours, but a
simple horizontal palette split would put visible colour boundaries through
the diagonal lettering. The current variants avoid that change. More faithful
colour separation would require revisiting the indexed artwork and tile
budget, rather than merely replacing the palette.

Offline previews use representative RGB values. The ROM stores NES colour
indices; Mesen, JSNES and physical displays may show different shades. Use
the included Mesen captures or compare the ROMs in the same emulator to judge
the relative appearance consistently.

## Validation

`verification/title-palette-builds.json` records all four full builds. Bronze
and blue/gold each differ from the accepted grayscale title by three ROM
bytes; steel differs by one. All changes are inside its existing title palette.
The grayscale rebuild remains byte-identical to `8b24fd18…`. Source hashes
match every build manifest and every segment budget is identical.

`verification/title-palette-comparison.json` records 21 controller/PPU checks
and six binary/asset checks for each new colour variant. All passed over
1,440 stock-NTSC Mesen refreshes. Both fresh-Start transitions, unchanged white
title text, the original controls guide, and complete CHR/PPU/RGB restoration
for the opening game view were verified. The matched opening render took the
same 884,349 CPU cycles in every version.

The prior grayscale full-level/restart test remains recorded separately; the
palette-only variants were tested through startup rather than repeating that
full route. This is emulator verification, not a physical-console measurement.

Artwork provenance is unchanged; see [the title experiment notes](TITLE-SCREEN-EXPERIMENT.md).
