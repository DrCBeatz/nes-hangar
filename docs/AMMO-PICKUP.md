# Ammo pickup behavior

The current candidate keeps the interaction update's strict
**3.5-world-unit radius** for ammo; the medkit remains at six. This is a modest
increase from the earlier three-unit setting described below, without
returning to the original four-unit radius.

Each absolute axis distance is rounded upward to an eighth of a world unit
before the squared-distance comparison. The radius is strict: equality is
rejected. This accepts a centerline pass at 3.375 units but rejects 3.5 units;
the earlier 3.75-unit wall-side pickup remains outside the circle. Rounding
still produces a narrow inward bias near the boundary.

The accepted placement update moves the clip from **(274, 252)** to
**(282, 250)**, farther out from the wall corner on dry ground and more visible
from the entrance. That experiment changes placement only: the pickup radius,
artwork, ten-round refill, ammo cap, collection sound and once-only collection
remain unchanged. A full inventory leaves the item available. The
clip's close-range appearance is a separate limitation: it can still disappear
below the viewport before collection, and the displayed camera can lag behind
the player position used by the pickup test. This change does not alter sprite
projection or rendering latency.

In the preceding straight-approach reproduction, the clip could disappear
below the viewport before the player reached its pickup circle. Continuing
forward collected it; the tested direct center crossings did not reveal a
missed pickup. Repositioning improves the approach without changing that
projection limitation. The placement experiment passed 17 stock-NTSC Mesen
fixtures and the 30-check JSNES controller suite before integration; see its
[preserved summary](../verification/ammo-placement-summary.json).

See [the interaction notes](INTERACTION-FIX.md) and
[verification](VERIFICATION.md). The following sections preserve the earlier
three-unit experiment and its original test results; they do not describe the
current radius.

# Earlier ammo-radius tightening

This historical change followed the inner-structure experiment. It reduced
the ammo clip's pickup radius from four to three world units. The medkit
remained at six.
Placement, artwork, the ten-round refill and collection sound are unchanged.

The pickup is a conservative circle around the player's center, with each
absolute axis distance rounded up to an eighth of a world unit. The clip's
visible width is approximately 1.25 world units, while the player's collision
footprint has half-width two. Radius three therefore gives a small allowance
around visual contact without the wider reach of radius four.

The nearest wall is eight units from the ammo center, so the previous pickup
circle did not reach through a wall. A legal center at (277.75,252) nevertheless
collected the item from 3.75 units to the side. The new radius rejects that
position and still accepts (276.75,252), 2.75 units away.

The assembly now compares both bytes of squared distance: radius three uses
the threshold $0240, which needs its low byte. This adds ten code bytes and
two table bytes, with no additional RAM. Generated world geometry, visibility
tables and background tile data are byte-identical to the inner-structure
baseline. These comparisons isolate the pickup change; the cumulative release
also includes the later visibility optimization and third encounter.

## Verification

Focused linked CPU tests pass fractional boundaries, coordinate carries,
all three mapper banks, unchanged medkit behavior, full-ammo retention,
once-only collection, refill capping, sound and completion counts. The existing
gameplay suite also passes its pickup, exit and sound checks.

Matched stock-NTSC Mesen tests inject a controlled starting pose, wait for a
published view, then use controller movement. They reproduce a wall-side pass
and diagonal bypass that collected the old clip; neither collects the new
clip. A direct approach collects at 2.75 units instead of 3.75, adds ten rounds
once, and leaves the item available when ammunition is already full.

These tests also demonstrate a separate visual limitation: pickup uses the
live player position, while the displayed picture can show an older camera
position. In the direct-approach fixture, that picture still showed the
six-unit starting distance at both collection events. The smaller trigger
does not eliminate the existing rendering latency.

Detailed research reports, reproduction scripts and historical ROM baselines
are retained separately and are not included in the standalone repository.
The packaged [third-encounter release report](../verification/third-encounter-release.json)
records the cumulative release's pickup regression checks and controller-route
evidence at that stage.

Historical pickup-only candidate (`hangar-ammo-tight-ntsc.nes`):

```text
31c137470615dda0285569cd2e7785b282bc368df8a5d17de01d448578ac76f4
```

Build and compare the current cumulative release with
`python3 tools/build.py --verify`; the output is `build/hangar-ntsc.nes`.
Its hash is recorded in the [release notes](RELEASE-NOTES.md), rather than
the intermediate hash above.
