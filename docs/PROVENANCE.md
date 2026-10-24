# Source and content provenance

Hangar is a custom NES FPS prototype. Its assembly renderer, gameplay code and
offline build generators were developed for this project. The renderer began
as a newly written experiment in drawing solid surfaces and regenerating their
boundary tiles; it was not a modification of the NES Elite geometry routines.
Dr C Beatz directed the project and its playtesting, using
AI-assisted implementation, analysis and asset iteration. The music
arrangement has the separate authorship account recorded below.

The earlier research compared Stuck in Castle Nesenstein, Horror Hospital,
Slaughter and NES Elite. Elite was written by Ian Bell and David Braben; Mark
Moxon's [annotated NES reconstruction](https://github.com/markmoxon/elite-source-code-nes)
was a useful study reference. Slaughter is by Mindbleach. These are research
credits, not claims that those games' engines are bundled here. This package
does not contain their ROMs, their source distributions, or the Doom engine
source distribution.

## Level

`assets/map.json` contains a simplified adaptation of **E1M1 / Hangar from
Doom**, by id Software. The project originally read vertices, linedefs,
sidedefs, sectors and the player start from a user-supplied shareware
`Doom1.WAD` with SHA-256:

```text
bb449c7480e9a02a62012d041406e8e43daa51caa0650646d1307d8650b8f837
```

The adaptation scales and translates coordinates, simplifies several walls
and rooms, omits branches and decorative geometry, and supplies its own
gameplay placements and rules. Source sector and linedef identifiers retained
in the map document that relationship. The opening, pillars, recess, connecting
rooms, zigzag walkway and exit route are not presented as an unrelated original
level design.

The standalone build uses the frozen adapted map directly. It neither includes
nor requires a WAD file. Removing the WAD importer as a build dependency does
not change the map's origin. The [Doom source release](https://github.com/id-Software/DOOM)
licenses its engine code separately from the game data required to run it;
this package does not claim that release grants a new license to E1M1 content.

## Artwork and sound

| Content | Project source and origin |
| --- | --- |
| Title logo | `assets/newlogo-doom.json`, derived from id Software's M_DOOM menu-logo patch in the supplied shareware WAD. The source retains indexed shapes for a 192×94 NES conversion; the release uses a bronze palette. This is extracted and adapted Doom artwork, not original project art. |
| Pistol and hand | The user-edited two-frame `assets/pistol-sheet.png`, imported into NES patterns. Its design was developed using user-supplied Doom and Doom-like pistol references. It is not extracted from the WAD. |
| Soldier and corpse | Project-authored indexed pixel matrices in the asset generators, including small-distance variants and walking poses. Their design is Doom-inspired; the pixels are not extracted Doom sprites. |
| Medkit and ammunition | Authored pixel matrices redrawn for the NES palette and size limits, using user-supplied Doom item images as visual references. |
| Font and solid surfaces | Project-authored five-by-seven glyph matrices and four generated solid patterns. |
| Sound effects | NES APU register sequences and software timers in the assembly source. No sampled Doom audio is included. |
| Music | Bobby Prince's "At Doom's Gate," with a new NES arrangement supplied by Dr C Beatz in `music/e1m1/e1m1-drcbeatz.s`. Authorship and consulted references are recorded below. The underlying composition is not original to this project. |

The title importer, `tools/newtitle_logo.py`, reads the patch posts and first
PLAYPAL palette from the same WAD identified above. The M_DOOM lump has SHA-256
`16eb5ef3429a6cd8ffb09df432c5ccd1be4df2f9af1cfe6d4dceedc307f3bde1`.
Its palette-aware conversion preserves the dark blue letter faces and bronze
bevels in three indexed shades; the selected NES palette then displays those
indices as brown, amber and cream. The original logo colours are not exactly
reconstructed. The source WAD is not bundled or required for builds. See the
[title notes](TITLE-SCREEN-EXPERIMENT.md) for the conversion and storage details.

Generated pattern files, lookup tables and the ROM are outputs of these sources.
The original reference screenshots are not included in the standalone package.

## Music source and playback engine

The current build reads `music/e1m1/e1m1-drcbeatz.s` verbatim. Dr C Beatz
supplied this new NES arrangement on October 24, 2026
and reports entering every note from scratch, listening to the original
recording and consulting sheet music and rasteri's version, with most harmonies
transcribed by ear. The composition remains **"At Doom's Gate" by Bobby Prince**.
This is a record of the contributor's account and references, not a conclusion
about legal independence or distribution rights.

The export's SHA-256 is:

```text
d5886648b0045e97de9172af06934dff190a873286a7aff62599c4667235427a
```

It uses the two pulse channels, triangle and noise. No sample binary is linked
and DPCM remains disabled. See [music notes](MUSIC.md) and the supplied
[arrangement record](../music/e1m1/DRCBEATZ-PROVENANCE.txt).

The earlier soundtrack experiments used **rasteri / Andrew Tait's** NES
arrangement from
[`rasteri/PiPU/music/DOOM.ftm`](https://github.com/rasteri/PiPU/blob/master/music/DOOM.ftm),
song index 3, obtained on October 21, 2026. The first FamiStudio conversion
removed DPCM for a four-channel audition; the subsequent `e1m1-drums.s` export
added Dr C Beatz's noise-channel percussion. These historical exports are
retained locally with their download hashes, adaptation notes and upstream
notices, outside this published package. They are not the editable source
or compiled data for the current track; earlier comparison ROMs are also
kept only in the local research archive.

The vendored FamiStudio 4.5.0 sound engine is by **Mathieu Gauthier**, based on
**FamiTone2 by Shiru**. Its source, NTSC note tables and permissive notice are in
`vendor/famistudio/`. Local modifications redirect APU writes to RAM shadows
so Hangar's mixer can give sound effects priority, and permit startup-only
initialization code to use the boot bank. Playback and song data remain in
the fixed bank; NMI does not switch PRG banks. The
[engine notice](../vendor/famistudio/NOTICE.txt) applies separately from the
original project code. No PiPU graphics hardware or rendering code is used.

The historical PiPU source collection's license file contains GPL-3.0, while
its README describes GPL version 2 for the program. No music-specific license
was identified in the recorded source review. These records and their
unresolved scope are preserved with the older files in local research history,
not bundled here. The current track's new
credit does not grant rights to Bobby Prince's composition or determine the
rights associated with consulted references. This local integration does not
change `LICENSE` or establish a blanket content license.

## License scope

The [MIT license](../LICENSE) covers the project's original engine, gameplay
code, build tools, configuration and documentation within the boundaries in
[LICENSE-SCOPE.md](../LICENSE-SCOPE.md). The adapted level layout, sprite pixel
data, pistol sheet, derived DOOM title-logo artwork, screenshots and adapted
music are excluded from that grant. The vendored sound engine retains its
separate notice. The ROM combines code and content, so the code license does
not make the entire ROM an
MIT-licensed asset collection. This provenance record describes what was used
and created; it does not assign rights over third-party names or reference
designs.

The build tools `ca65` and `ld65` are supplied separately by
[cc65](https://github.com/cc65/cc65); their executables and source distribution
are not bundled here.
