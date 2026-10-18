; Reserved CPU-only nametable rows: never part of a viewport upload.
actor_kind = $6EE0
medkit_dirty = $6EE1
render_medkit_state = $6EE2 ; bit7 selected collected, bit6 selected ammo (snapshot)
visible_medkit_swap = $6EE3
buffer_medkit_swap = $6EE4 ; two banks
buffer_medkit_epoch = $6EE6
buffer_medkit_present = $6EE8
medkit_scratch = $6EEA ; six producer-only scratch bytes; NMI never uses them
MEDKIT_PROJECT0 = $6EA0
MEDKIT_PROJECT1 = $7EA0
MEDKIT_MASK0 = $6EF0
MEDKIT_MASK1 = $7EF0
