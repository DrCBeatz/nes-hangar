# Tighter ammo pickup

This change is included in the current release and followed the inner-structure
experiment. It changes the ammo clip's
pickup radius from four to three world units. The medkit remains at six.
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
The packaged [current-release report](../verification/current-release.json)
records the final ROM's pickup regression checks and controller-route evidence.

Historical pickup-only candidate (`hangar-ammo-tight-ntsc.nes`):

```text
31c137470615dda0285569cd2e7785b282bc368df8a5d17de01d448578ac76f4
```

Build and compare the current cumulative release with
`python3 tools/build.py --verify`; the output is `build/hangar-ntsc.nes`.
Its hash is recorded in the [release notes](RELEASE-NOTES.md), rather than
the intermediate hash above.
