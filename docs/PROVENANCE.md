# Source and content provenance

Hangar is a custom NES FPS prototype. Its assembly renderer, gameplay code and
offline build generators were developed for this project. The renderer began
as a newly written experiment in drawing solid surfaces and regenerating their
boundary tiles; it was not a modification of the NES Elite geometry routines.

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
| Pistol and hand | The user-edited two-frame `assets/pistol-sheet.png`, imported into NES patterns. Its design was developed using user-supplied Doom and Doom-like pistol references. It is not extracted from the WAD. |
| Soldier and corpse | Hand-authored indexed pixel matrices in the asset generators, including small-distance variants and walking poses. Their design is Doom-inspired; the pixels are not extracted Doom sprites. |
| Medkit and ammunition | Authored pixel matrices redrawn for the NES palette and size limits, using user-supplied Doom item images as visual references. |
| Font and solid surfaces | Project-authored five-by-seven glyph matrices and four generated solid patterns. |
| Sound effects | NES APU register sequences and software timers in the assembly source. No sampled Doom audio is included. |

Generated pattern files, lookup tables and the ROM are outputs of these sources.
The original reference screenshots are not included in the standalone package.

## License scope

The [MIT license](../LICENSE) covers the project's original engine, gameplay
code, build tools, configuration and documentation within the boundaries in
[LICENSE-SCOPE.md](../LICENSE-SCOPE.md). The adapted level layout, sprite pixel
data, pistol sheet and screenshots are excluded from that grant. The ROM
combines code and content, so the code license does not make the entire ROM an
MIT-licensed asset collection. This provenance record describes what was used
and created; it does not assign rights over third-party names or reference
designs.

The build tools `ca65` and `ld65` are supplied separately by
[cc65](https://github.com/cc65/cc65); their executables and source distribution
are not bundled here.
