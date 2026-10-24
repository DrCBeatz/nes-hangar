# Optional E1M1 music

The published prototype uses **Dr C Beatz's new NES arrangement** of
Bobby Prince's "At Doom's Gate." It retains the controls-screen music choice
and sound-effect priority. The accepted music audition and subsequent ammo
placement test are integrated with the credits and HUD polish. The source,
ROM and browser version were published on October 24, 2026; the hosted ROM
matches the download. See the [deployment record](DEPLOYMENT.md).

## Player controls

After the bronze logo, the controls guide defaults to **MUSIC: ON**. Press
**Left for OFF**, **Right for ON**, then **Start** to begin. The guide also
states **MUSIC OFF: FASTER PLAY**. Death retries and completed-level restarts
preserve the choice; a console/emulator reset returns to the title sequence
and restores ON. This is a startup choice, not an in-game toggle.

OFF skips the music sequencer, silences its voices and keeps sound effects.
It reduces audio CPU cost rather than changing the rendering quality. Music
also stops advancing during pause, title/credits/results screens and player
death. Select opens credits from the logo; during gameplay it retains the
coarse-boundary rendering comparison.

## Track and credits

- Composition: **"At Doom's Gate"**, **Bobby Prince**, from Doom (1993).
- Current NES arrangement: **Dr C Beatz**, supplied
  October 24, 2026.
- Reference and earlier arrangement experiments: **rasteri / Andrew Tait**,
  from the PiPU project's
  [`music/DOOM.ftm`](https://github.com/rasteri/PiPU/blob/master/music/DOOM.ftm),
  song index 3. That export and the subsequent noise-drum remix are historical
  inputs, not the track compiled into the current ROM.
- Sound engine: **FamiStudio 4.5.0**, **Mathieu Gauthier**, based on
  **FamiTone2 by Shiru**; see the retained
  [engine notice](../vendor/famistudio/NOTICE.txt).

Dr C Beatz reports entering every note of the new arrangement from scratch,
listening to the original recording and consulting sheet music and rasteri's
version, with most harmonies transcribed by ear. This records the supplied
authorship account; it does not claim a new original composition or make a
legal determination about the consulted references.

The build reads
[`music/e1m1/e1m1-drcbeatz.s`](../music/e1m1/e1m1-drcbeatz.s) directly. The
supplied export is preserved verbatim, including its generated
`music_data_untitled` symbol. Its SHA-256 is:

```text
d5886648b0045e97de9172af06934dff190a873286a7aff62599c4667235427a
```

The song uses pulse 1, pulse 2, triangle and noise. No DPCM samples or expansion
audio are linked or played. The export uses native FamiStudio tempo, volume
track and vibrato; FamiTracker tempo and duty-cycle effects are disabled.

Further musical edits should be made in the new arrangement's FamiStudio
project and exported as ca65 sound-engine assembly to `e1m1-drcbeatz.s`.
The earlier `e1m1-four-channel.txt`, `.s` and `e1m1-drums.s` files are retained
only in local research history and are **not editable sources of this
arrangement**. Song features must remain compatible
with `src/music.s`; a different export requires fresh build, memory and audio
checks.

## Build and audio integration

The regular `python3 tools/build.py` command needs only Python and cc65.
FamiStudio is needed to edit/export music, not to rebuild the supplied ROM.
`python3 tools/build.py --no-music` produces a compile-time music-disabled
alternative with the same sound-effects mixer. Its guide stays OFF; it is
not byte-identical to the reference, so do not use `--verify` with that option.

FamiStudio writes to RAM register shadows. Hangar's mixer chooses the music or
sound effect for each channel and writes the APU registers. Effects take
priority on the channel they need; other music channels continue. Gunshots
and door effects therefore interrupt the noise percussion temporarily.

The engine, mixer and preference use **205 of the reserved 216 RAM bytes**:
135 for FamiStudio, 69 for the mixer and one for the saved choice. Eight
zero-page scratch bytes are shared with an existing temporary region. The
song data occupies **2,309 bytes**, 752 more than the previous remix.
ROM capacity remains **128 KiB PRG**, with MMC1, **8 KiB CHR-RAM** and
**8 KiB work RAM**. Rendering and audio remain NES CPU work; the cartridge
has no audio or graphics coprocessor.

The longer export required moving startup-only initialization into the boot
bank, and actor transform/occlusion helpers into the render bank their callers
already select. Music updates and song data remain in the fixed bank. NMI
never changes PRG banks, and these relocations add no gameplay bank switches.
The credits screen has separate startup storage; it does not add sequencer
work during play.

## Verification and performance

Before this UI pass, the separate music audition passed 19 linked audio checks,
30 JSNES controller checks and 26 stock-NTSC Mesen route checks. Its engine's
113,861 APU writes matched an independently assembled, unmodified FamiStudio
reference across three complete loops. The user subsequently auditioned the
ROM and confirmed the arrangement sounded correct. Those tests identify the
music audition ROM, not the later UI build; current integration checks and
artifact identities belong in [verification](VERIFICATION.md). The preserved
[audition summary](../verification/drcbeatz-music-summary.json) records the
original test identity.

A matched isolated audio comparison measured **1,692 CPU cycles per refresh**
with the new track, against about **1,597** for the earlier remix, with no
sound effects active. The extra **95 cycles** are approximately **0.32% of
the total NTSC CPU budget**, not a measured 0.32% change in gameplay frame
rate. Runtime OFF averaged about **508 cycles**. The full matched
[audio comparison](../verification/drcbeatz-music-performance.json) preserves
the harness scope and both ROM identities. Both exports had the same
measured loop duration: **5,632 NTSC refreshes**, about **93.7 seconds**.

A larger song mainly consumes more ROM space. Playback cost depends on the
active envelopes, decoded events and engine configuration. Because the tempo
mode also changed, these measurements do not attribute every extra cycle to
the musical arrangement itself. Shortening this song is not indicated by the
measured costs. The [latency investigation](LATENCY-TUNING.md) separately
records input-to-picture behavior; complex views remain expensive even with
music OFF.

These are emulator and linked-routine measurements, not a physical-console
verification or a claim that all gameplay situations have the same cost.

## Licensing scope

The original-code MIT license is unchanged. The FamiStudio engine retains its
own permissive notice. The composition and arrangement are separate from
those code grants. Historical music inputs are not part of this package.

Historical PiPU exports retain `UPSTREAM-LICENSE.txt` (GPL-3.0) and
`UPSTREAM-README.txt` (which describes GPL version 2 for the program). The
recorded review did not identify a music-specific license. Those notices and
unresolved questions remain attached to the historical files in local research
history; those files and their comparison ROMs are neither bundled here nor
compiled into the current ROM. Replacing the track is not a determination
of legal independence, nor does it grant rights to the underlying composition.
No whole-project relicensing is part of this integration.

See [content provenance](PROVENANCE.md), [license scope](../LICENSE-SCOPE.md),
and the supplied [arrangement record](../music/e1m1/DRCBEATZ-PROVENANCE.txt).
Hangar does not use PiPU's Raspberry Pi rendering hardware or game engine.
