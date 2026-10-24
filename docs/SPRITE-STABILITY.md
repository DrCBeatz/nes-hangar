# Soldier size and vertical placement

The `prototype-2026-10-21-sprite-stability` release addresses two related
close-range artifacts shared by all three soldier encounters. Neither was
specific to the final room.

## Smaller size transitions

The previous art jumped directly from 24 × 48 to 28 × 56 and then 32 × 64
pixels. A tiny distance change across either threshold could move the head
eight pixels, and repeatedly crossing a threshold toggled the size.

The new 26 × 52 and 30 × 60 tiers halve those close-range height steps to
four pixels. Both walking poses and matching corpse tiers are included.
The original sizes retain their original pixels and the largest living
sprite remains 32 × 64 pixels. This is still discrete scaling, not continuous
pixel resampling.

The selector also retains its previous near tier within a small hysteresis
band: one eighth of a world unit on either side of the nearest-size boundary.
It accepts substantial distance changes immediately. Distant sizes, pickups
and ordinary corpse sizing do not acquire this living-soldier history.

Two previously unused internal-RAM bytes hold the producer's tier and
encounter epoch. Boot clears them; encounter changes use a different epoch,
including across byte wrap. Item projection cannot change the history.
Prepared death poses inherit the living picture's selected tier.

## Stable placement while turning

Previously, body size used radial distance while the feet used forward camera
depth. Turning reduced the forward depth without changing the selected size,
so the entire sprite moved down and eventually lost rows below the viewport.
At radius 8.125, a 33.75-degree turn moved a 32 × 64 soldier down thirteen
pixels in the controlled comparison.

Soldiers and corpses now use continuous radial distance for their vertical
anchor as well as size. A 32-bit integer square root and the existing rounded
division compute the anchor independently of the selected art tier. Turning
at the same position no longer changes its vertical placement, and switching
tiers does not move the feet. The root rounds down to Q8.8 precision; at the
eight-unit contact limit its distance error contributes less than 0.032 pixel
to the vertical calculation.

This is intentionally a stable billboard convention. Away from screen center,
the feet do not exactly match the perspective projection of the physical floor
point. Horizontal placement and foreground occlusion retain true camera
depth, so nearer walls and floors still mask the sprite. Pickups keep their
previous projection. The fixed maximum art size also remains a limitation
when approaching very closely.

## Resource use and timing

The mapper, ROM size and allocated RAM are unchanged. The two history bytes
and two producer-only anchor bytes use existing spare storage. Source art
stores only actual image rows; the compositor emits transparent padded rows
without reading past the image. This makes room for the additional sizes
without increasing the maximum of 32 soldier patterns or four sprite columns.

The vertical-anchor correction adds about 4,800–4,950 producer CPU cycles in
twelve centered, identical-pixel comparisons: roughly 0.44–0.75%. Across the
sixty turning comparisons the change is about 0.42–1.25%, including views
where the new placement draws rows previously cropped away. These are fixed
poses measured without NMI time, not gameplay frame rates. It introduces no
additional NMI routine or larger maximum sprite upload.

The final linked segments occupy 16,257 bytes of fixed code, 8,154 bytes of
common code/data and 8,065 bytes of actor art. Their respective remaining
capacities are 111, 22 and 127 bytes. Future additions will need attention to
bank placement; this change does not create spare rendering capacity.

## Verification

The [verification notes](VERIFICATION.md#previous-soldier-sprite-stability) distinguish
the final linked fixtures and Mesen comparisons from the preceding sizing
experiment. The final ROM also passed all 18 isolated emulator tests, including
the controller-only route through all three encounters, both pickups, the
door, completion and restart. No physical-console test is claimed.

The sprite-stability ROM preserved at commit `d2f2bbd` has SHA-256:

```text
f342c5b83f75be92fdf476fab0b2c802afe06438e41e5b571d98b501c05de28e
```

The current `prototype-2026-10-24-door-reach` release includes these sprite
fixes alongside the bronze title, optional music and subsequent gameplay/UI
changes. It is available both as a ROM download and in the hosted browser game
as of October 24, 2026; see [deployment](DEPLOYMENT.md). The measurements above
retain their historical sprite-stability ROM scope.
