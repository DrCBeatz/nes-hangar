# Final prototype performance assessment

The door-reach and alias-credit candidate preserves the previous renderer and
transfer schedule. No additional rendering optimization is included in this
release. The [portable comparison report](../verification/final-performance.json)
identifies both binaries and the measurement scope.

- Baseline: `867f9ae9999f895bea3b68f5ca13f8a2ff73047fee0b9f2a696fdb542dc4e249`.
- Candidate: `db258e4c9c57ff3ef9f4bc8eb732f31b65eec85a1a639e7a9787a90dde1722a9`.

## What was compared

Eighteen linked 6502 producer fixtures cover the opening, square room, slime
views and open/closed door, including selected live encounters. They produce
identical CPU cycle counts, world pixels, complete staging bytes, pattern
counts and dirty upload lists in both builds. These fixtures suppress
interrupts and inject camera/gameplay state. They measure CPU work, not FPS.
Some live-encounter fixtures place the actor outside the view.

Separate stock-NTSC Mesen trials cover walking and turning from both an idle
renderer and an already-busy renderer in the opening room, slime room and
near the closed door. Music ON and OFF are tested. All 19,204 measured
refreshes across both builds pass legal-position, floor-support, settled-view
and release checks; there are 48 settled input onsets. Recorded camera states
and timing match exactly between builds for these scenarios. Each run uses
zero extra scanlines, no run-ahead and normal sprite limits, and preserves
personal emulator settings.

These camera trials remove enemies and collect both items during setup to
isolate presentation delay. Subsequent movement uses controller input. They
are not a normal combat-throughput benchmark; the full gameplay route and
PPU deadline checks are documented separately in [VERIFICATION.md](VERIFICATION.md).

## Where the time goes

Representative fixed-pose producer costs, with actors removed:

| View | CPU cycles | Geometry setup | Per-column surfaces | Raster/tile composition |
| --- | ---: | ---: | ---: | ---: |
| Opening room | 1,034,063 | 20.3% | 27.7% | 49.3% |
| Slime entry | 1,060,300 | 28.4% | 29.6% | 39.1% |
| Slime middle | 882,729 | 25.1% | 28.3% | 43.5% |
| Close closed door | 319,899 | 28.3% | 24.0% | 44.4% |

Remaining work includes actor visibility checks, palette probes and producer
bookkeeping. In these slime poses the exact palette probe is only about
1.4–1.5% of producer CPU time. The larger costs are distributing surfaces
across the view and constructing their tile patterns, rather than the green
palette decision alone.

The moving-camera measurements also include NMI work and hidden-buffer
transfer. Their mean pipeline times are:

| Scene | Music | Produce picture, refreshes | Ready to displayed, refreshes |
| --- | --- | ---: | ---: |
| Opening | ON | 35.5 | 17.4 |
| Opening | OFF | 34.1 | 17.5 |
| Slime | ON | 29.7 | 15.2 |
| Slime | OFF | 28.4 | 15.3 |
| Closed door | ON | 13.6 | 3.8 |
| Closed door | OFF | 13.3 | 4.1 |

One NTSC refresh is approximately 16.64 ms. These are pipeline-latency
measurements across changing views, **not frame-rate estimates** or exact
same-pose music comparisons. Buffer work can overlap, and input phase changes
which pictures complete. Transfer time includes waiting for publication, not
only CPU cycles spent writing PPU memory.

Live movement responds within one or two refreshes in these trials and stops
changing after button release. The displayed camera can still lag while
previously sampled pictures finish rendering and uploading. Physical input
device and display latency are outside these measurements. Music OFF reduces
producer elapsed time here but does not remove the presentation delay.

## Release recommendation

Keep the current renderer for this release. It already uses paired horizontal
samples, visibility filtering, solid-span shortcuts, a tile-pattern cache and
changed-block nametable transfers. This assessment found no new UI or door
work that warrants a late renderer rewrite. The two door-distance constants
change eligibility; they add no renderer instructions. Credits run outside
gameplay.

A later performance experiment should target span/tile composition or prove
that additional hidden geometry can be skipped. Pattern-transfer reductions
also remain worth studying, but require tracking the actual content of the
destination CHR bank and rechecking upload deadlines. Keep the optional music
setting; these measurements give no reason to shorten the soundtrack.

The scripts and full diagnostic captures are retained locally under
`analysis/final-perf/`; the portable JSON above retains the release evidence.
No physical-console performance result is claimed.
