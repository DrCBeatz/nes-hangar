# Hangar — an NES FPS prototype

A playable 3D first-person shooter experiment for the **NTSC Nintendo
Entertainment System**, with angled walls, a recessed floor, moving enemies,
pickups and a complete route through a simplified adaptation of Doom's
E1M1 / Hangar.

The renderer constructs solid surfaces and their boundary tiles at runtime
on the NES CPU. This is a custom engine and a compact technical/gameplay
prototype, not a port of the Doom engine or the complete original level.

**[Play in browser](https://8bitpocket.app/?game=hangar)** ·
[Download the ROM](release/hangar-ntsc.nes) ·
[Build from source](#build-from-source) ·
[Technical notes](#how-it-renders) ·
[Latest changes](docs/RELEASE-NOTES.md) ·
[Provenance](docs/PROVENANCE.md)

<p align="center">
  <img src="docs/images/opening-gameplay.gif" width="512" alt="Six seconds of Hangar gameplay: walking and turning among the opening room’s pillars and recessed floor." />
</p>
<p align="center">
  ROM gameplay at normal NTSC timing in JSNES, music ON (GIF is silent) · <a href="docs/images/opening-gameplay.png">View the opening still</a> · <a href="docs/images/doom-title.png">Bronze title screen</a> · <a href="docs/images/title.png">Controls guide</a> · <a href="docs/images/credits.png">Credits</a>
</p>

## Play

Download `release/hangar-ntsc.nes` and open it in an NES emulator with MMC1
and CHR-RAM support. The development reference is
[Mesen](https://www.mesen.ca/), using **NTSC**, normal sprite limits and
**zero additional scanlines**. Those settings exercise the intended timing.
Optional emulator overclocking can make rendering faster, but it is not
required to finish the level.

Press **Start** on the bronze DOOM-logo title to open the controls guide, or
**Select** to view the credits. On the credits page, **B** returns to the logo
and **Start** opens the guide. Music defaults to **ON**; press **Left for OFF**
or **Right for ON**, then release and press Start again to play. Holding Start
cannot skip a page. The first room takes about 0.8 seconds to prepare at normal NTSC speed; the level
timer starts when that view appears.

For a browser trial, open [Play Hangar](https://8bitpocket.app/?game=hangar),
click **Play Hangar**, then press **Start** on the game title screen. Hangar is
also in the site’s hosted-game picker. A keyboard guide appears before Play;
use **Controls** to reopen it during gameplay. **Open ROM** still supports downloaded
files. Browser speed, palette and presentation may differ from Mesen. See
the [browser deployment notes](docs/DEPLOYMENT.md).

The current local candidate includes the bronze title screen, the latest soldier
size and positioning fixes, more forgiving door/exit and ammo interactions,
a targeted input-to-picture latency improvement, and Dr C Beatz's new optional
NES arrangement of E1M1. It also includes the accepted ammo repositioning,
a title-screen credits page, clearer music instructions and a pistol label
in place of the unused armor counter. These local changes have not been
pushed or deployed. The [door reach update](docs/DOOR-REACH.md) shows the prompt earlier on
centered approaches, retaining the earlier close-angle allowance.
The hosted browser game still uses the previous third-encounter release;
choose **Open ROM** to try the latest download there.

## Controls

| Input | Action |
| --- | --- |
| Up / Down | Walk forward / backward |
| Left / Right | Turn |
| Hold A + Left / Right | Strafe |
| B | Fire the pistol |
| A, while facing a nearby door or switch | Use when prompted; release and press again, without Left/Right |
| Start | Advance title → controls → play with separate presses; pause/resume during play; retry after death or completion |
| Select | View credits from the logo; during gameplay, compare precise dynamic boundaries with coarse tile boundaries |

On the controls guide, **Left selects music OFF** and **Right selects ON**.
The selection survives death and completed-level retries. Reset returns to
the title sequence with music ON. OFF preserves sound effects and skips music
sequencing to reduce CPU cost; it does not change the level or graphics.
See [music notes](docs/MUSIC.md).

The latency update lets a new movement or turn replace an outdated picture
that is still being drawn. This helps when rendering was already busy; it
does not remove the substantial delay needed to draw and upload complex
views. The geometry and movement rules are unchanged. See the measured
[latency improvements and limits](docs/LATENCY-TUNING.md) and the
[final performance assessment](docs/FINAL-PERFORMANCE.md).

Pausing displays a message at the top and plays a short descending cue.
Resuming restores the level heading and plays an ascending cue. Gameplay and
the completion timer stop during pause. Hardware/emulator Reset returns to
the logo and controls sequence; retries go directly back into the level.

The door prompt accepts facing within about ±75° of its normal, including
close diagonal approaches. The exit switch retains its ±45° allowance.
The door now accepts use within twelve world units of its panel on either
side. Release A before pressing it again. See the
[door reach notes](docs/DOOR-REACH.md).

With no ammunition, a fresh B press plays a brief, deep empty-gun buzz. Holding B
does not repeat the cue or count as a fired shot.

## The current level

Find the exit switch beyond the slime room and the openable door. The level
contains three soldier encounters, one medkit and one ammunition clip. You can
finish without killing every enemy or collecting every item; the completion
screen reports kills, items and elapsed time.

- Start with 100 health and **6 rounds**. Each soldier takes three hits.
- The gray clip supplies 10 rounds, for **16 available rounds** in total; it
  is on dry ground near the slime-room entrance. Defeating all three soldiers
  requires nine hits, so a full clear needs the clip and allows seven misses.
- The medkit restores up to 25 health and remains available at full health.
- Green slime costs 5 health after roughly one second, repeating while you
  remain on it. The gray zigzag walkway is safe.
- Soldiers pursue within authored encounter bounds, telegraph their shots,
  react to hits and leave a short-lived corpse.

Close soldiers now use smaller size steps and a small switching buffer to
avoid repeatedly changing size during tiny movements. Turning in place also
keeps their vertical placement stable. See the [sprite notes](docs/SPRITE-STABILITY.md)
for the visual tradeoff and verification.

The route passes the opening pillars and recess, a first encounter room with
a sealed inner enclosure, the zigzag slime room, and a third encounter beyond
the openable door before the exit chamber. The enclosure provides cover and
paths around all four sides; its interior is not accessible. The level omits
much of the original map's geometry, branches, lighting and decoration.

Only one soldier encounter is active at a time. Each soldier's position and
health persist when you leave and return, but an outgoing soldier can disappear
at a room handoff even if it is still in view. The last soldier stays within
its room and leaves space to pass on either side.

| Opening room | First encounter |
| --- | --- |
| ![Recessed floor and pillars](docs/images/opening-room.png) | ![Soldier encounter](docs/images/encounter.png) |

The opening still and six-second GIF were captured from the preceding
credits/HUD build, whose opening gameplay is unchanged. They use stock-NTSC
JSNES with music ON and native 256 × 240 output. The GIF preserves
the ROM's rendering cadence without interpolated motion, using exact 2× pixel
duplication. See the [capture record](verification/opening-gameplay.json).
The first-encounter still is a historical Mesen capture from the initial public
build and predates the inner enclosure.

## Build from source

The repository is self-contained. Building requires **Python 3.11 or newer**
and the **ca65 assembler / ld65 linker** from
[cc65](https://github.com/cc65/cc65). GNU Make is optional. No WAD, commercial
ROM, emulator, npm package or Python package installation is needed to build.

### macOS

With Homebrew installed:

```sh
brew install python cc65
```

[Homebrew's cc65 package](https://formulae.brew.sh/formula/cc65) supplies both
`ca65` and `ld65`. Open a terminal in this repository and run:

```sh
python3 tools/build.py
```

### Debian / Ubuntu and Windows with WSL

```sh
sudo apt-get update
sudo apt-get install python3 cc65 make
python3 tools/build.py
```

On Windows, WSL with Ubuntu is the documented build route. A native Windows
Python/cc65 setup may also work, but it has not been verified for this package.

### Output and verification

The output is **`build/hangar-ntsc.nes`**. The build also produces assembler
listings, linker/debug files, generated assets and a manifest under `build/`.
Generated files are ignored by Git. Asset generation includes geometric
visibility calculations, so allow a minute or more on the first build.

To rebuild and compare against the included release:

```sh
python3 tools/build.py --verify
```

Or use the Make targets:

```sh
make
make verify
make clean
```

`make clean` removes generated build output, not the ROM in `release/`.
Normal builds permit intentional source edits; verification is expected to
fail if those edits change the ROM relative to the committed release.

The included local candidate, `prototype-2026-10-24-door-reach`, is 131,088
bytes (a 16-byte header plus 128 KiB PRG). Its exact version, checksum and cartridge metadata are recorded in
[release/release.json](release/release.json); [SHA256SUMS](release/SHA256SUMS)
identifies the downloadable ROM.
[Verification notes](docs/VERIFICATION.md) distinguish isolated build checks,
emulator observations and hardware testing. The GitHub Actions workflow
rebuilds and compares the ROM on push or pull request; it does not deploy a
website or publish a release automatically.

The default title palette is **bronze**. Grayscale, blue/gold and steel
comparisons remain available through `--title-palette`; see the
[title palette notes](docs/TITLE-PALETTE-COMPARISON.md). These alternatives
intentionally differ from the accepted release, so build them without
`--verify`.

The normal build includes the music choice and Dr C Beatz's supplied E1M1 arrangement. It
requires no FamiStudio installation: the exported song data and sound engine
are bundled. To build with music sequencing disabled at compile time:

```sh
python3 tools/build.py --no-music
```

That alternative always displays music OFF and intentionally differs from the
reference ROM; do not combine it with `--verify`. The earlier bronze-title ROM
without the music integration is preserved as
`hangar-bronze-no-music-ntsc.nes` (local research archive; not bundled).

### Troubleshooting

- **ca65/ld65 not found:** install cc65, then check `ca65 --version` and
  `ld65 --version` in the same terminal used to run the build.
- **Missing Python modules:** the normal build uses the standard library.
  Run the documented Python version; there is no requirements.txt to install.
- **ROM mismatch after editing:** use the normal build while developing.
  Update the checked-in ROM and release metadata together only after testing
  an intentional new release.
- **Slow or corrupted emulator display:** confirm NTSC, mapper support and
  the ROM checksum. Compare with Mesen before treating a browser-only issue
  as a game regression.

## Source layout

| Path | Purpose |
| --- | --- |
| `src/` | 6502 assembly, RAM definitions and the cartridge linker configuration |
| `tools/` | Python build driver, geometry/visibility generators and art generators |
| `assets/map.json` | Editable, simplified level geometry and gameplay placement data |
| `assets/pistol-sheet.png` | Editable two-frame pistol/hand source image |
| `assets/newlogo-doom.json` | Indexed title artwork derived from Doom's M_DOOM logo; see provenance |
| `assets/` | Other source data used by the generators, including the font |
| `music/e1m1/e1m1-drcbeatz.s` | Supplied Dr C Beatz arrangement export used by the build |
| `music/e1m1/` | Song history, source provenance and retained upstream notices |
| `vendor/famistudio/` | FamiStudio sound engine, NTSC note tables and its separate notice |
| `release/` | Playable reference ROM, checksum and release metadata |
| `docs/` | Provenance, verification and proposed browser deployment |
| `build/` | Regenerated local output; excluded from Git |

Start with `src/walkable.s` for boot, controller polling, main/NMI coordination
and frame publication. `geometry.s` projects the scene; `raster.s` constructs
background patterns; `ntsc_upload.s` budgets PPU transfers. Movement,
encounters, shooting, pickups, doors, results, pause and the title screen have
their own modules.

Edit the map and generator inputs rather than generated `.inc` or `.bin`
files. The current map includes derived segments, visibility zones and floor
regions: editing it is a technical workflow, not yet a general map editor.
Changes to geometry can require corresponding visibility/collision changes.
The generators enforce capacity and geometric assumptions during a build.
In particular, the door, rectangular recess, inner enclosure, three saved
encounters and room handoff bounds are scene-specific. Changes there can require edits to
`tools/door_reference.py`, `ai_reference.py` and `encounter_reference.py`.
Enemy and item pixels are authored in `tools/zombie_assets.py`,
`medkit_assets.py`, `ammo_assets.py` and `corpse_assets.py`; the font is in
`assets/font.json`.

## How it renders

The world is defined by finite wall segments and horizontal floor regions.
Fixed-point camera transforms and depth calculations produce visible vertical
spans. The renderer evaluates **128 horizontal samples**, duplicates each
across two screen pixels and retains full vertical resolution in a
**256 × 144** viewport.

Uniform tile interiors reuse a few solid patterns. At edges and intersections,
the CPU constructs the required pixel patterns in RAM, reuses matching cached
patterns and uploads them to CHR-RAM. This is why angled walls can rotate
smoothly even though the NES background is tile-based. Select makes the
difference visible by switching to the coarse boundary comparison.

The main thread builds an immutable world view while NMI handles bounded PPU
uploads, controls, gameplay ticks and audio. Publication switches to a completed
view rather than exposing a partly uploaded picture. Visibility tables reduce
work for hidden rooms; a small camera-position filter also skips inner-enclosure
faces when the connecting passage proves them hidden from the slime room.
Enemies and pickups use distance-sized hardware sprites
with foreground masks derived from the world geometry.
Soldiers and corpses use radial distance for vertical placement as well as
size, keeping them stable when turning. This approximates ground contact
away from the screen center; horizontal projection and foreground masking
still use camera depth. Pickups retain their previous projection.

The cartridge uses **MMC1 banking, 128 KiB PRG, 8 KiB CHR-RAM and 8 KiB work
RAM**. Rendering is performed by the NES CPU; the mapper provides banking,
not a 3D processor. This is a cartridge configuration target, not a claim that
this release has already been tested on a physical console.

## Current limitations

- Rendering is scene-dependent and substantially slower than the display's
  refresh rate. The opening recess/pillars and views across the slime room
  are demanding; control-to-picture latency remains noticeable.
- Music shares CPU time with rendering. Select OFF on the controls guide for
  lower audio overhead. The four standard tonal/noise channels are used;
  there is no DPCM sample playback or expansion audio.
- Three encounters persist in the level, but only one enemy encounter is active
  at a time. Crossing a handoff can hide the outgoing soldier or corpse.
- Sprite size steps, very close actors and sprite-per-scanline pressure remain
  visible limitations. Soldier art stops at 32 × 64 pixels, and its stable
  vertical placement is a billboard approximation. This is not an engine for
  crowds of enemies.
- The ammo clip can disappear below the viewport before collection. Its
  placement farther out from the wall corner improves the entrance approach;
  its 3.5-unit pickup radius is unchanged. This does not change close-range
  sprite projection or delayed world views.
- The green slime palette shares a limited set of background colors; visible
  slime replaces one alternate wall shade.
- The HUD identifies the pistol as the current weapon. There are no armor
  pickups, extra weapons, additional levels, saves or general-purpose WAD loader.
- PAL is not the target for this packaged release. Physical-console and
  flash-cartridge testing remain separate from emulator verification.

When reporting a problem, include the ROM checksum, emulator/version, region,
overclock settings and a reproducible route or short recording.

## Sharing and browser deployment

The suggested repository name is **`nes-hangar`**; the display title is
**Hangar — an NES FPS prototype**. This directory is the repository root, so
only this folder needs to be published, not the surrounding research workspace.
See [publishing instructions](docs/PUBLISHING.md).

The maintained 8-Bit Pocket emulator hosts the previous third-encounter ROM
and supports the [direct Play Hangar link](https://8bitpocket.app/?game=hangar).
The newer soldier fixes, bronze title, optional music, interaction changes
and credits/HUD polish have not been deployed there; load
the current download with the emulator's **Open ROM** control to try them.
A dedicated landing page with download and play buttons can follow. The
[deployment notes](docs/DEPLOYMENT.md) describe the current integration,
remaining display work and options for a later custom domain.

## Credits and licensing

Hangar is a project by **Dr C Beatz**, developed through
iterative implementation, emulator testing and player feedback, with
AI-assisted coding, analysis and asset iteration. Its dynamic tile
approach was inspired in part by studying NES Elite's graphics technique;
this package uses a newly written renderer, not that game's engine code.

The included map is a simplified adaptation of Doom's E1M1 by id Software.
The title logo is derived from id Software's M_DOOM artwork in the supplied
shareware WAD and uses a bronze NES palette.
The current music is **"At Doom's Gate" by Bobby Prince**, with a new
**NES arrangement by Dr C Beatz**. Dr C Beatz reports entering
every note from scratch using the original recording, sheet music and
rasteri's version as references. **rasteri / Andrew Tait** is acknowledged for
that reference and the earlier PiPU-based soundtrack experiments; those
exports are not compiled into the current ROM. Playback uses
**Mathieu Gauthier's FamiStudio** sound engine, based on **FamiTone2 by Shiru**,
under its retained notice. See [music notes](docs/MUSIC.md) for the source
record and distinction between composition, arrangement and code.
The source and visual-reference history are recorded in
[PROVENANCE.md](docs/PROVENANCE.md). Code licensing and content provenance are
separate; no blanket license over the original game's level design or reference
artwork is implied.

Original engine code and build tools are licensed under [MIT](LICENSE).
See [LICENSE-SCOPE.md](LICENSE-SCOPE.md) for the distinction between that code
grant, the vendored engine's notice, and the bundled level, visual and musical
content. Crediting the new arrangement does not assign rights to the original
composition or establish a blanket license for the ROM. The project's
original-code license remains unchanged.
