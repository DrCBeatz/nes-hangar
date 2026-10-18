; Global world positions: unsigned 24-bit Q16.8, supported authored range
; 0..1023 (fractional positions through1023+255/256). Existing ZP low words
; retain their addresses. The third byte is here in CPU-only WRAM.
; $7C44..4C belongs to corpse_prepare; only its unused tail is reclaimed.
; $7EE0..EF is the unused bank1 counterpart of bank0 medkit globals.
.ifndef COORDINATE_MEMORY_INCLUDED
COORDINATE_MEMORY_INCLUDED = 1
WORLD_INTEGER_MAX = 1023
player_x_hi = $7C4D
player_z_hi = $7C4E
render_x_hi = $7C4F
render_z_hi = $7C50
visible_x_hi = $7C51
visible_z_hi = $7C52
buffer_x_hi = $7C53 ; two bytes, bank index0/1
buffer_z_hi = $7C55
freshness_last_x_hi = $7C57
freshness_last_z_hi = $7C58
move_x_hi = $7C59
move_z_hi = $7C5A
g_mul_a_hi = $7C5B ; producer-only multiply input extension
coordinate_producer_scratch = $7C5C ; four producer-only bytes
zombie_x_hi = $7EE0
zombie_z_hi = $7EE1
render_zombie_x_hi = $7EE2
render_zombie_z_hi = $7EE3
visible_zombie_x_hi = $7EE4
visible_zombie_z_hi = $7EE5
buffer_zombie_x_hi = $7EE6 ; two bytes each
buffer_zombie_z_hi = $7EE8
freshness_last_zombie_x_hi = $7EEA
freshness_last_zombie_z_hi = $7EEB
coordinate_nmi_scratch = $7EEC ; four NMI-only bytes
.assert coordinate_producer_scratch+4 = $7C60, error, "coordinate producer WRAM overlap"
.assert coordinate_nmi_scratch+4 = $7EF0, error, "coordinate NMI WRAM overlap"
.endif
