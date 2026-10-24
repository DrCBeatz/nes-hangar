# License scope

The [MIT license](LICENSE) applies to this project's original engine and
gameplay code, build-tool algorithms, build configuration, workflow and
documentation. This includes the program code in `src/` and `tools/`.

Level, visual and musical content are documented separately in
[docs/PROVENANCE.md](docs/PROVENANCE.md). The MIT grant is not a blanket content
license for the adapted E1M1 map, derived DOOM title-logo data
(`assets/newlogo-doom.json`), pistol sheet, sprite artwork/data (including
pixel matrices embedded in generators), screenshots, adapted E1M1 music, or
third-party names and reference designs. A separate project content license
has not been assigned here.

The FamiStudio engine and note tables in `vendor/famistudio/` are third-party
code, governed by their retained [notice](vendor/famistudio/NOTICE.txt), not by
the project's MIT grant. The original integration and mixer code in `src/`
remain within the original-code grant.

The current E1M1 track is Bobby Prince's composition "At Doom's Gate," with a
new NES arrangement supplied by Dr C Beatz in
`music/e1m1/e1m1-drcbeatz.s`. The contributor reports entering every note from
scratch while consulting the original recording, sheet music and rasteri's
version. This records authorship and references; it is not a determination of
legal independence or a grant of rights to the underlying composition.

Earlier PiPU-derived music exports, their notices and comparison ROMs are
retained in the local research history, outside this published package. They
are neither bundled nor compiled into the current ROM. The earlier source
review and consulted reference remain documented in
[music notes](docs/MUSIC.md) and [provenance](docs/PROVENANCE.md).

This integration neither relicenses the whole project nor settles distribution
rights for musical or visual content. `LICENSE` is unchanged.

The bundled ROM combines the original program with that content; it should
not be described as an entirely MIT-licensed asset. No original WAD, commercial
ROM, reference screenshot or third-party game-engine source is bundled. The
FamiStudio sound-engine source and musical data described above are bundled
with their source credits and notices.
