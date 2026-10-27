; One bounded hardware-sprite actor, aligned with each completed world view.
; The existing wall projector supplies exact per-column foreground coverage.
; New scratch aliases are producer-only geometry registers dead at each use.
.setcpu "6502"
.include "coordinate-memory.inc"
.macpack longbranch
.ifndef SPRITE_MASK
SPRITE_MASK = 0
.endif
.importzp render_buffer, render_eye, render_x, render_z, render_mode
.import render_zombie_hp
.importzp render_zombie_x, render_zombie_z, render_zombie_pose
.importzp render_zombie_epoch
.import zombie_size_history, zombie_size_epoch
.importzp tile_ptr, tile_count, tile_number
.import geometry_zombie_transform, scaled_division
.importzp g_camera_x, g_camera_z, g_acc, g_mul_a, g_mul_b, g_value, g_den, g_rem
.importzp g_num, g_ray_x, g_ray_z, g_step_x, g_step_z, g_project, g_left, g_right
.importzp g_endpoint, g_front, g_delta_sign, g_sign, g_multiplicand, g_base, g_step
.importzp g_column, g_top, g_bottom
.import opening_plane0
.import medkit_begin, medkit_save_metadata, medkit_render_done, medkit_admit_tile
.include "medkit-memory.inc"
.include "corpse-fast-memory.inc"
.export zombie_begin, zombie_occlude, zombie_render
.export buffer_zombie_visible, buffer_zombie_target
.export buffer_zombie_left, buffer_zombie_right, buffer_zombie_top, buffer_zombie_bottom
.export buffer_zombie_size, buffer_zombie_tile_start, buffer_zombie_tile_count
.exportzp z_left, z_top, z_center, z_foot, z_width, z_height, z_size, z_active
.exportzp z_depth_q8, z_inverse, z_mask_ptr, z_oam_ptr
.export zombie_palette, zombie_hit_palette
.exportzp z_cols, z_rows
.export zombie_render_shared, zombie_begin_shared, zombie_compare_inverse
.export medkit_widths, medkit_heights, medkit_cols, medkit_rows
.export medkit_art_lo, medkit_art_hi
.export corpse_widths, corpse_heights, corpse_cols, corpse_rows
.include "zombie-config.inc"
.include "medkit-config.inc"
.include "ammo-config.inc"
.assert MEDKIT_FLOOR = ZOMBIE_FLOOR, error, "Shared item/actor floor anchor must match"
.assert AMMO_FLOOR = MEDKIT_FLOOR, error, "Both pickup floor anchors must match"

; Persistent until the next geometry_begin. None is used by geometry_column,
; project_height, or its insert_span hook. g_acc/top/column remain read-only.
z_left = g_camera_x
z_top = g_camera_x+2
z_center = g_camera_z
z_foot = g_camera_z+2
z_depth_q8 = g_ray_x
z_inverse = g_step_x               ; four contiguous bytes (step_x,step_z)
z_width = g_project
z_height = g_project+1
z_size = g_endpoint
z_active = g_front
z_cols = g_delta_sign
z_rows = g_sign
z_mask_ptr = g_mul_a
z_oam_ptr = g_mul_b

; Projection scratch, before streaming world columns starts.
z_distance2 = g_ray_z             ; three bytes + first step byte; consumed before inverse
z_distance2_hi = g_step_x
z_proj_sign = g_left
z_proj_loop = g_left+1
z_proj_quotient = g_right
z_threshold_index = g_right+1
; Producer-only floor anchor, consumed before geometry columns begin. Keep
; this outside transform scratch; neither NMI nor geometry uses these bytes.
z_ground_radius = coordinate_producer_scratch
.export z_ground_radius, soldier_floor_anchor

; Only used by zombie_render, after all geometry and world raster work ends.
z_source_ptr = g_num
z_stride = g_num+2
z_source_col = g_num+3
z_row = g_value
z_tile_row = g_value+1
z_inner_row = g_value+2
z_tile_x = g_den
z_loop = g_den+2
z_tile_y = g_rem
z_oam_index = g_rem+2
z_bits = g_rem+3
.exportzp z_tile_x, z_tile_y, z_oam_index
z_plane0 = g_multiplicand
z_plane1 = g_multiplicand+1
z_opaque = g_multiplicand+2
z_shift = g_multiplicand+3
z_row_mask = g_base
z_column_source = g_base+1
.if ::SPRITE_MASK
; Two dead compositor bytes. NMI never uses producer geometry scratch.
; Positive cutoffs agree: mask is z_mask_bits before z_mask_cutoff, else zero.
; $FF selects the original eight-pixel loop for nonuniform positive cutoffs.
z_mask_cutoff = g_base+1
z_mask_bits = g_base+2
.exportzp z_mask_cutoff, z_mask_bits
.export classify_actor_mask
.endif
.export actor_row_mask, actor_row_mask_done
z_tile_opaque = g_base+3
z_row_limits = opening_plane0      ; eight dead streamed-raster bytes

.segment "BSS"
buffer_zombie_visible: .res 2
buffer_zombie_target: .res 2
buffer_zombie_left: .res 2
buffer_zombie_right: .res 2
buffer_zombie_top: .res 2
buffer_zombie_bottom: .res 2
buffer_zombie_size: .res 2
buffer_zombie_tile_start: .res 2
buffer_zombie_tile_count: .res 2

.segment "RODATA"
.include "zombie-assets.inc"
.include "medkit-assets.inc"
.include "ammo-assets.inc"
.include "corpse-assets.inc"
zombie_bits: .byte $80,$40,$20,$10,$08,$04,$02,$01
; Exact squared Q8.8 radial thresholds, derived from the artwork sizes.
.include "zombie-size.inc"
.assert CORPSE_VARIANT_COUNT = ZOMBIE_VARIANT_COUNT, error, "Corpse size tiers must match living actors"

.import prg_map, prg_render

.segment "CODE"
.proc zombie_begin
 lda #0
 sta actor_kind
.endproc
.proc zombie_begin_shared
 ; Both callers enter from map0; all projection inputs are RAM/COMMON.
 ; The bank3 copy retains medkit_save_metadata at its original address.
 jsr prg_render
 jsr zombie_begin_banked
 jmp prg_map
.endproc

.segment "RENDER_CODE"
.proc zombie_begin_banked
 lda #0
 sta z_active
 lda actor_kind
 bne medkit_start
 ldx render_buffer
 sta buffer_zombie_visible,x
 sta buffer_zombie_target,x
 sta buffer_zombie_left,x
 sta buffer_zombie_right,x
 sta buffer_zombie_top,x
 sta buffer_zombie_bottom,x
 sta buffer_zombie_size,x
 sta buffer_zombie_tile_start,x
 sta buffer_zombie_tile_count,x
medkit_start:
 lda render_zombie_hp
 jeq done
 jsr choose_radial_size
 jcs done
 lda actor_kind
 bne :+
 jsr ground_radius
:
 jsr geometry_zombie_transform
 ; Positive camera depth, rounded from Q16 to Q8.8. This depth is used only
 ; for center, occlusion and distant floor contact. Nearby soldiers retain
 ; radial anchoring; medium distances blend smoothly into camera depth.
 lda g_camera_z+3
 jmi done
 lda g_camera_z
 cmp #128
 lda g_camera_z+1
 adc #0
 sta z_depth_q8
 lda g_camera_z+2
 adc #0
 sta z_depth_q8+1
 lda g_camera_z+3
 adc #0
 sta z_depth_q8+2
 jne done                 ; real scene depth fits below256 world units
 lda z_depth_q8+1
 bne depth_ready
 lda z_depth_q8
 cmp #64
 jcc done                 ; at most a quarter-unit forward sliver is irrelevant
 depth_ready:
 lda g_camera_x+3
 sta z_proj_sign
 bpl absolute_x
 lda #0
 sec
 sbc g_camera_x
 sta g_camera_x
 lda #0
 sbc g_camera_x+1
 sta g_camera_x+1
 lda #0
 sbc g_camera_x+2
 sta g_camera_x+2
 lda #0
 sbc g_camera_x+3
 sta g_camera_x+3
absolute_x:
 lda g_camera_x
 cmp #128
 lda g_camera_x+1
 adc #0
 sta g_rem
 lda g_camera_x+2
 adc #0
 sta g_rem+1
 lda g_camera_x+3
 adc #0
 sta g_rem+2
 lda #0
 sta z_proj_quotient
 jsr compare_camera_depth
 bcc fractional
 jsr subtract_camera_depth
 inc z_proj_quotient
 jsr compare_camera_depth
 jcs done                 ; |X|>=2Z is well outside a <=32px actor
fractional:
 lda #7
 sta z_proj_loop
project_bit:
 asl z_proj_quotient
 asl g_rem
 rol g_rem+1
 rol g_rem+2
 jsr compare_camera_depth
 bcc project_next
 jsr subtract_camera_depth
 inc z_proj_quotient
project_next:
 dec z_proj_loop
 bne project_bit
 asl g_rem
 rol g_rem+1
 rol g_rem+2
 jsr compare_camera_depth
 bcc center
 inc z_proj_quotient
 jeq done                 ; rounded ratio2 is also wholly outside
center:
 lda z_proj_sign
 bmi center_left
 lda #128
 clc
 adc z_proj_quotient
 sta z_center
 lda #0
 adc #0
 sta z_center+1
 jmp inverse
center_left:
 lda #128
 sec
 sbc z_proj_quotient
 sta z_center
 lda #0
 sbc #0
 sta z_center+1
inverse:
 lda z_depth_q8
 sta g_den
 lda z_depth_q8+1
 sta g_den+1
 lda z_depth_q8+2
 sta g_den+2
 lda #0
 sta g_value
 sta g_value+1
 lda #1
 sta g_value+2
 jsr scaled_division       ; round(65536*2048/depthQ8)
 ldx #3
save_inverse:
 lda g_acc,x
 sta z_inverse,x
 dex
 bpl save_inverse
 ; Close soldiers/corpses retain the accepted radial floor anchor. Distant
 ; ones share the exact physical floor projection already used by pickups.
 lda actor_kind
 bne pickup_floor
 lda z_ground_radius+1
 cmp #64
 bcs pickup_floor
 jsr soldier_floor_anchor
 jmp floor_ready
pickup_floor:
 lda render_eye
 sec
 sbc #ZOMBIE_FLOOR
 lsr a                    ; half-sized units: factor is deltaHeight/2
 sta g_den
 lda #0
 sta g_multiplicand
 sta g_multiplicand+1
 sta g_multiplicand+2
foot_product:
 lda g_multiplicand
 clc
 adc z_inverse
 sta g_multiplicand
 lda g_multiplicand+1
 adc z_inverse+1
 sta g_multiplicand+1
 lda g_multiplicand+2
 adc z_inverse+2
 sta g_multiplicand+2
 dec g_den
 bne foot_product
 lda g_multiplicand+1
 clc
 adc #4                  ; round(deltaHeight * inverse / 4096)
 sta g_multiplicand+1
 lda g_multiplicand+2
 adc #0
 sta g_multiplicand+2
 .repeat 3
 lsr g_multiplicand+2
 ror g_multiplicand+1
 .endrepeat
 lda g_multiplicand+1
 clc
 adc #96
 sta z_foot
 lda g_multiplicand+2
 adc #0
 sta z_foot+1
floor_ready:
 ldx z_size
 lda actor_kind
 beq zombie_dimensions
 lda medkit_widths,x
 sta z_width
 lda medkit_heights,x
 sta z_height
 lda medkit_cols,x
 sta z_cols
 lda medkit_rows,x
 jmp dimensions_ready
zombie_dimensions:
 lda render_zombie_hp
 bpl living_dimensions
 lda corpse_widths,x
 sta z_width
 lda corpse_heights,x
 sta z_height
 lda corpse_cols,x
 sta z_cols
 lda corpse_rows,x
 jmp dimensions_ready
living_dimensions:
 lda zombie_widths,x
 sta z_width
 lda zombie_heights,x
 sta z_height
 lda zombie_cols,x
 sta z_cols
 lda zombie_rows,x
dimensions_ready:
 sta z_rows
 lda z_width
 lsr a
 sta g_den
 lda z_center
 sec
 sbc g_den
 sta z_left
 lda z_center+1
 sbc #0
 sta z_left+1
 lda z_left
 clc
 adc z_width
 sta g_num
 lda z_left+1
 adc #0
 sta g_num+1
 bmi done
 bne right_visible
 lda g_num
 beq done
right_visible:
 lda z_left+1
 beq vertical
 bpl done
vertical:
 lda z_foot
 sec
 sbc z_height
 sta z_top
 lda z_foot+1
 sbc #0
 sta z_top+1
 bmi visible
 bne done
 lda z_top
 cmp #168
 bcs done
visible:
 lda #1
 sta z_active
 lda #$C0
 ldx actor_kind
 beq :+
 lda #$F0
:
 sta z_mask_ptr
 lda render_buffer
 asl a
 asl a
 asl a
 asl a
 clc
 adc #$6E
 sta z_mask_ptr+1
 lda #144
 ldy #31
 ldx actor_kind
 beq clear_clip
 ldy #15
clear_clip:
 sta (z_mask_ptr),y
 dey
 bpl clear_clip
 lda actor_kind
 beq :+
 jmp medkit_save_metadata
:
 jsr set_metadata
done:
 rts
.endproc

.proc compare_camera_depth
 lda g_rem+2
 cmp z_depth_q8+2
 bne done
 lda g_rem+1
 cmp z_depth_q8+1
 bne done
 lda g_rem
 cmp z_depth_q8
done:
 rts
.endproc
.proc subtract_camera_depth
 lda g_rem
 sec
 sbc z_depth_q8
 sta g_rem
 lda g_rem+1
 sbc z_depth_q8+1
 sta g_rem+1
 lda g_rem+2
 sbc z_depth_q8+2
 sta g_rem+2
 rts
.endproc

; Exact Q8 radius is needed for continuous floor placement, independent of
; pre-scaled artwork tiers. Keep it in the same producer-only two-byte reserve
; formerly occupied by the rounded radial foot. No new RAM is allocated.
.proc ground_radius
 lda #0
 sta g_value
 sta g_value+1
 sta g_rem
 sta g_rem+1
 sta g_rem+2
 ldx #16
root_bit:
 .repeat 2
 asl z_distance2
 rol z_distance2+1
 rol z_distance2+2
 rol z_distance2+3
 rol g_rem
 rol g_rem+1
 rol g_rem+2
 .endrepeat
 asl g_value
 rol g_value+1
 lda g_value
 asl a
 ora #1
 sta g_den
 lda g_value+1
 rol a
 sta g_den+1
 lda #0
 rol a
 sta g_den+2
 lda g_rem
 sec
 sbc g_den
 sta g_acc
 lda g_rem+1
 sbc g_den+1
 sta g_acc+1
 lda g_rem+2
 sbc g_den+2
 bcc root_next
 sta g_rem+2
 lda g_acc
 sta g_rem
 lda g_acc+1
 sta g_rem+1
 inc g_value               ; bit0 was cleared by the shift; cannot carry
root_next:
 dex
 bne root_bit
 lda g_value
 sta z_ground_radius
 lda g_value+1
 sta z_ground_radius+1
 bne done
 lda z_ground_radius
 cmp #64
 bcs done
 lda #64                  ; same quarter-unit overlap fallback as before
 sta z_ground_radius
done:
 rts
.endproc

; Use the exact old radial denominator through R=32, and transition toward
; true depth over 32<R<64. Farther actors take pickup_floor directly. Blend
; subpixel distances BEFORE the sole final pixel rounding; interpolating
; rounded feet or quantizing the weight caused one-pixel approach reversals.
;
; Q8 d = r - round((r-cameraDepth)*(r-32*256)/(32*256)). The full 13-bit
; weight and signed 32-bit product retain fractional camera positions.
; True depth/inverse stay untouched for wall/floor occlusion and targeting.
.proc soldier_floor_anchor
 lda z_ground_radius
 sta g_den
 lda z_ground_radius+1
 sta g_den+1
 sec
 sbc #32
 bcc project
 sta g_mul_b+1
 lda z_ground_radius
 sta g_mul_b
 ora g_mul_b+1
 beq project
 ; A signed difference also handles a camera basis rounding depth slightly
 ; beyond the radius. The existing angular pre-cull bounds this product.
 lda z_ground_radius
 sec
 sbc z_depth_q8
 sta g_multiplicand
 lda z_ground_radius+1
 sbc z_depth_q8+1
 sta g_multiplicand+1
 lda #0
 bcs :+
 lda #$FF
:
 sta g_multiplicand+2
 sta g_multiplicand+3
 lda #0
 sta g_acc
 sta g_acc+1
 sta g_acc+2
 sta g_acc+3
 ldx #13
 jsr zombie_multiply_bits ; shared shift/add multiply; no second square root
 ; Round by4096, then extract product bits13..28 as a signed16-bit result.
 lda g_acc+1
 clc
 adc #$10
 sta g_acc+1
 lda g_acc+2
 adc #0
 sta g_acc+2
 lda g_acc+3
 adc #0
 sta g_acc+3
 .repeat 5
 lsr g_acc+3
 ror g_acc+2
 ror g_acc+1
 .endrepeat
 lda z_ground_radius
 sec
 sbc g_acc+1
 sta g_den
 lda z_ground_radius+1
 sbc g_acc+2
 sta g_den+1
project:
 lda #0
 sta g_den+2
 sta g_value+1
 sta g_value+2
 lda render_eye
 sec
 sbc #ZOMBIE_FLOOR
 .repeat 4
 asl a
 .endrepeat
 sta g_value
 jsr scaled_division       ; same round(128*eyeHeight/distance) as before
 lda g_acc
 clc
 adc #96
 sta z_foot
 lda g_acc+1
 adc #0
 sta z_foot+1
 rts
.endproc

; Full global Q16.8 differences, then exact nearby Q8.8 radius squared. This changes
; neither orientation nor size while turning in place at one world position.
.proc choose_radial_size
 lda #0
 sta z_distance2
 sta z_distance2+1
 sta z_distance2+2
 sta z_distance2+3
 lda render_zombie_x_hi
 sta g_value+2
 lda render_x_hi
 sta g_mul_a_hi
 lda render_zombie_x
 sta g_value
 lda render_zombie_x+1
 ldx render_x
 ldy render_x+1
 jsr delta_magnitude
 jcs far
 jsr square_delta
 ldx #3
save:
 lda g_acc,x
 sta z_distance2,x
 dex
 bpl save
 lda render_zombie_z_hi
 sta g_value+2
 lda render_z_hi
 sta g_mul_a_hi
 lda render_zombie_z
 sta g_value
 lda render_zombie_z+1
 ldx render_z
 ldy render_z+1
 jsr delta_magnitude
 jcs far
 jsr square_delta
 lda z_distance2
 clc
 adc g_acc
 sta z_distance2
 lda z_distance2+1
 adc g_acc+1
 sta z_distance2+1
 lda z_distance2+2
 adc g_acc+2
 sta z_distance2+2
 lda z_distance2+3
 adc g_acc+3
 sta z_distance2+3
 ldx #0
 ; Explicit256-unit radial sprite limit: far actors must never wrap into
 ; a near size. World geometry has the full1024-unit coordinate range.
 jcs far
 lda actor_kind
 bne medkit_threshold
threshold:
 lda z_distance2+3
 cmp zombie_distance_threshold3,x
 bne decided
 lda z_distance2+2
 cmp zombie_distance_threshold2,x
 bne decided
 lda z_distance2+1
 cmp zombie_distance_threshold1,x
 bne decided
 lda z_distance2
 cmp zombie_distance_threshold0,x
decided:
 bcs selected
 inx
 cpx #ZOMBIE_VARIANT_COUNT-1
 bcc threshold
 jmp selected
medkit_threshold:
 lda z_distance2+3
 cmp medkit_distance_threshold3,x
 bne medkit_decided
 lda z_distance2+2
 cmp medkit_distance_threshold2,x
 bne medkit_decided
 lda z_distance2+1
 cmp medkit_distance_threshold1,x
 bne medkit_decided
 lda z_distance2
 cmp medkit_distance_threshold0,x
medkit_decided:
 bcs selected
 inx
 cpx #MEDKIT_VARIANT_COUNT-1
 bcc medkit_threshold
selected:
 stx z_size
 lda actor_kind
 bne ready                 ; pickups never read or modify soldier history
 lda render_zombie_hp
 bmi ready                 ; ordinary corpses retain nearest-size selection
 jsr stabilize_size
ready:
 clc
 rts
far:
 sec
 rts
.endproc

; Producer-only hysteresis. The radius is still exact and the projection is
; unchanged. A large displacement accepts the new nearest tier immediately;
; only the small band around the previous near tier's boundary is retained.
.proc stabilize_size
 lda render_zombie_epoch
 cmp zombie_size_epoch
 bne remember
 cpx #ZOMBIE_NEAR_SIZE
 bcc remember
 lda zombie_size_history
 sec
 sbc #1
 cmp #ZOMBIE_NEAR_SIZE
 bcc remember
 cmp #ZOMBIE_VARIANT_COUNT
 bcs remember
 cmp z_size
 beq done
 tax                       ; previous tier
 bcc growing               ; previous < nearest: moving closer
 dex                       ; leaving previous toward a smaller tier
 lda z_distance2+3
 cmp zombie_shrink_threshold3-ZOMBIE_NEAR_SIZE,x
 bne shrink_decided
 lda z_distance2+2
 cmp zombie_shrink_threshold2-ZOMBIE_NEAR_SIZE,x
 bne shrink_decided
 lda z_distance2+1
 cmp zombie_shrink_threshold1-ZOMBIE_NEAR_SIZE,x
 bne shrink_decided
 lda z_distance2
 cmp zombie_shrink_threshold0-ZOMBIE_NEAR_SIZE,x
shrink_decided:
 bcs remember
 inx
 bne retain
growing:
 lda z_distance2+3
 cmp zombie_grow_threshold3-ZOMBIE_NEAR_SIZE,x
 bne grow_decided
 lda z_distance2+2
 cmp zombie_grow_threshold2-ZOMBIE_NEAR_SIZE,x
 bne grow_decided
 lda z_distance2+1
 cmp zombie_grow_threshold1-ZOMBIE_NEAR_SIZE,x
 bne grow_decided
 lda z_distance2
 cmp zombie_grow_threshold0-ZOMBIE_NEAR_SIZE,x
grow_decided:
 bcc remember
retain:
 stx z_size
remember:
 lda z_size
 clc
 adc #1
 sta zombie_size_history
 lda render_zombie_epoch
 sta zombie_size_epoch
done:
 rts
.endproc

; g_value low/A middle/g_value+2 high = actor; X/Y/g_mul_a_hi = camera.
; Return unsigned24 magnitude in g_mul_b[2]/g_value+2; C=1 if >=256 units.
; The nearby low-word square retains every fractional bit.
.proc delta_magnitude
 sty g_mul_a+1
 stx g_mul_a
 sta g_value+1
 lda g_value
 sec
 sbc g_mul_a
 sta g_mul_b
 lda g_value+1
 sbc g_mul_a+1
 sta g_mul_b+1
 lda g_value+2
 sbc g_mul_a_hi
 sta g_value+2
 bcs done
 lda #0
 sec
 sbc g_mul_b
 sta g_mul_b
 lda #0
 sbc g_mul_b+1
 sta g_mul_b+1
 lda #0
 sbc g_value+2
 sta g_value+2
done:
 lda g_value+2
 cmp #1
 rts
.endproc
.proc square_delta
 lda g_mul_b
 sta g_multiplicand
 lda g_mul_b+1
 sta g_multiplicand+1
 lda #0
 sta g_multiplicand+2
 sta g_multiplicand+3
 sta g_acc
 sta g_acc+1
 sta g_acc+2
 sta g_acc+3
 ldx #16
bit_loop:
 lsr g_mul_b+1
 ror g_mul_b
 bcc shift
 lda g_acc
 clc
 adc g_multiplicand
 sta g_acc
 lda g_acc+1
 adc g_multiplicand+1
 sta g_acc+1
 lda g_acc+2
 adc g_multiplicand+2
 sta g_acc+2
 lda g_acc+3
 adc g_multiplicand+3
 sta g_acc+3
shift:
 asl g_multiplicand
 rol g_multiplicand+1
 rol g_multiplicand+2
 rol g_multiplicand+3
 dex
 bne bit_loop
 rts
.endproc

zombie_multiply_bits = square_delta::bit_loop

.segment "RENDER_CODE"

; Called only during bank3 column generation.
; Hooked immediately before a geometry span is appended. Read-only access to
; all live geometry scratch. A/X/Y are caller-clobbered here. The
; current scene's wall+floor spans form bottom suffixes; the closest crossing
; clips precisely where its projected surface begins, even on recess rims.
.proc zombie_occlude
 lda z_active
 beq done
 lda render_mode
 bne coarse
 ; World samples even X and duplicates it to X+1. Reject the whole pair
 ; only when neither pixel overlaps this full-resolution actor. In particular,
 ; an actor beginning on an odd X still receives that pair's foreground mask.
 lda g_column
 ora #1
 sec
 sbc z_left
 tay
 lda #0
 sbc z_left+1
 bne done
 tya
 cmp z_width
 bcc pair_overlaps
 bne done                   ; equality means only the even pixel overlaps
pair_overlaps:
 jsr nearer_than_actor
 bcc done
 tya
 cmp z_width
 bcs even_pixel             ; odd pixel is beyond the actor's right edge
 lda g_top
 cmp (z_mask_ptr),y
 bcs even_pixel
 sta (z_mask_ptr),y
even_pixel:
 tya
 beq done                   ; even pixel is before the actor's left edge
 dey
 lda g_top
 cmp (z_mask_ptr),y
 bcs done
 sta (z_mask_ptr),y
done:
 rts
coarse:
 ; The diagnostic renderer samples pixel(column4,row4) of each8x8cell.
 ; Broadcast that column's foreground depth and quantized boundary across
 ; its tile. Its centre need not itself lie within the actor's tight width.
 lda g_column
 and #7
 cmp #4
 bne done
 jsr nearer_than_actor
 bcc done
 lda g_top
 clc
 adc #3                   ; first tile whose centre row4 is >=span top
 and #$F8
 sta g_num                ; begin-frame division scratch, dead during columns
 lda g_column
 ora #7
 sta g_num+1
 lda g_column
 and #$F8
 tax
pixel:
 txa
 sec
 sbc z_left
 tay
 lda #0
 sbc z_left+1
 bne next
 tya
 cmp z_width
 bcs next
 lda g_num
 cmp (z_mask_ptr),y
 bcs next
 sta (z_mask_ptr),y
next:
 cpx g_num+1
 beq done
 inx
 jmp pixel
.endproc

.proc nearer_than_actor
 lda g_acc+3
 cmp z_inverse+3
 bne done
 lda g_acc+2
 cmp z_inverse+2
 bne done
 lda g_acc+1
 cmp z_inverse+1
 bne done
 lda g_acc
 cmp z_inverse
done:
 rts
.endproc

; World pattern generation has finished. Append <=32 masked actor patterns
; and stage OAM in the inactive bank; never write PPU memory in this routine.
; This compositor and its pixel/OAM helpers run only after prg_art.
; Store executable producer code beside its raw sprite artwork.
.segment "ACTOR_ART"
.proc zombie_render
 lda #0
 sta actor_kind
.endproc
.proc zombie_render_shared
 lda corpse_preparing
 beq ordinary_oam
 lda #$C0
 sta z_oam_ptr
 lda render_buffer
 asl a
 asl a
 asl a
 asl a
 ora #$6E
 sta z_oam_ptr+1
 jmp check_active
ordinary_oam:
 lda #0
 sta z_oam_ptr
 lda render_buffer
 asl a
 asl a
 asl a
 asl a
 clc
 adc #$6F
 sta z_oam_ptr+1
 lda #$FF
 ldy #64
 ldx actor_kind
 beq hide
 ldy #192
hide:
 sta (z_oam_ptr),y
 iny
 bne hide
check_active:
 lda z_active
 jeq done
 ldx z_size
 lda actor_kind
 beq zombie_count
 lda medkit_pattern_counts,x
 jmp count_ready
zombie_count:
 lda render_zombie_hp
 bpl living_count
 lda corpse_pattern_counts,x
 jmp count_ready
living_count:
 lda zombie_pattern_counts,x
count_ready:
 clc
 adc tile_count
 ldx corpse_preparing
 bne quick_capacity
 cmp #185
 jcs done
 jmp capacity_ready
quick_capacity:
 cmp #193
 jcs done
capacity_ready:                    ; omit the complete actor rather than half draw
 lda corpse_preparing
 beq ordinary_index
 lda #0
 beq index_ready
ordinary_index:
 lda actor_kind
 bne medkit_index
 ldx render_buffer
 lda tile_count
 sta buffer_zombie_tile_start,x
 lda #64
 bne index_ready
medkit_index:
 lda #192
index_ready:
 sta z_oam_index
 lda z_cols
 asl a
 sta z_stride
 lda z_left
 sta z_tile_x
 lda z_left+1
 sta z_tile_x+1
 lda #0
 sta z_source_col
column:
 jsr prepare_column_limits
 ldx z_size
 lda actor_kind
 beq zombie_art
 lda render_medkit_state
 and #$40
 bne ammo_art
 lda medkit_art_lo,x
 clc
 adc z_source_col
 sta z_source_ptr
 lda medkit_art_hi,x
 adc #0
 sta z_source_ptr+1
 jmp source_ready
ammo_art:
 lda ammo_art_lo,x
 clc
 adc z_source_col
 sta z_source_ptr
 lda ammo_art_hi,x
 adc #0
 sta z_source_ptr+1
 jmp source_ready
zombie_art:
 lda render_zombie_hp
 bpl living_art
 lda corpse_art_lo,x
 clc
 adc z_source_col
 sta z_source_ptr
 lda corpse_art_hi,x
 adc #0
 sta z_source_ptr+1
 jmp source_ready
living_art:
 lda render_zombie_pose
 bne walk_art
 lda zombie_art_lo,x
 clc
 adc z_source_col
 sta z_source_ptr
 lda zombie_art_hi,x
 adc #0
 sta z_source_ptr+1
 jmp source_ready
walk_art:
 lda zombie_walk_art_lo,x
 clc
 adc z_source_col
 sta z_source_ptr
 lda zombie_walk_art_hi,x
 adc #0
 sta z_source_ptr+1
source_ready:
 lda z_top
 sta z_tile_y
 lda z_top+1
 sta z_tile_y+1
 lda #0
 sta z_row
 sta z_tile_row
tile:
 lda #0
 sta z_inner_row
 sta z_tile_opaque
row:
.if ::SPRITE_MASK
 ldx #8                    ; Match the original loop's exit X.
 lda z_mask_cutoff
 cmp #$FF
 beq general_mask
 lda z_row
 cmp z_mask_cutoff
 lda #0
 bcs cached_mask
 lda z_mask_bits
cached_mask:
 sta z_row_mask
 jmp mask_ready
general_mask:
.endif
 lda #0
 sta z_row_mask
 ldx #0
mask_pixel:
 lda z_row
 cmp z_row_limits,x
 ; CMP carry is set for an occluded pixel; invert once after all eight bits.
 rol z_row_mask
 inx
 cpx #8
 bne mask_pixel
 lda z_row_mask
 eor #$FF
 sta z_row_mask
mask_ready:
 beq blank_row             ; fully masked/padded rows need no source ROM read
 ldy #0
 lda (z_source_ptr),y
 and z_row_mask
 sta z_plane0
 ldy z_cols
 lda (z_source_ptr),y
 and z_row_mask
 sta z_plane1
 ; Keep source pixels within the viewport even if a near foot is below it.
 lda z_tile_y+1
 bne blank_row
 lda z_tile_y
 clc
 adc z_inner_row
 bcs blank_row
 cmp #24
 bcc blank_row
 cmp #168
 bcs blank_row
 jmp row_visible
blank_row:
 lda #0
 sta z_plane0
 sta z_plane1
row_visible:
 lda z_shift
 beq shifted
 tax
shift_left:
 asl z_plane0
 asl z_plane1
 dex
 bne shift_left
shifted:
 lda z_plane0
 ora z_plane1
 ora z_tile_opaque
 sta z_tile_opaque
 lda actor_kind
 ora corpse_preparing
 bne :+
 jsr detect_target
:
 ldy z_inner_row
 lda z_plane0
 sta (tile_ptr),y
 tya
 clc
 adc #8
 tay
 lda z_plane1
 sta (tile_ptr),y
 lda z_source_ptr
 clc
 adc z_stride
 sta z_source_ptr
 bcc :+
 inc z_source_ptr+1
:
 inc z_row
 inc z_inner_row
 lda z_inner_row
 cmp #8
 jne row
 lda z_tile_opaque
 beq next_tile
 lda actor_kind
 beq admitted
 jsr medkit_admit_tile
 bcc next_tile
admitted:
 lda tile_count
 clc
 adc #64
 sta tile_number
 jsr write_actor_oam
 lda tile_ptr
 clc
 adc #16
 sta tile_ptr
 bcc :+
 inc tile_ptr+1
:
 inc tile_count
 lda actor_kind
 ora corpse_preparing
 bne next_tile
 ldx render_buffer
 inc buffer_zombie_tile_count,x
 lda #1
 sta buffer_zombie_visible,x
next_tile:
 lda z_tile_y
 clc
 adc #8
 sta z_tile_y
 bcc :+
 inc z_tile_y+1
:
 inc z_tile_row
 lda z_tile_row
 cmp z_rows
 jne tile
 lda z_tile_x
 clc
 adc #8
 sta z_tile_x
 bcc :+
 inc z_tile_x+1
:
 inc z_source_col
 lda z_source_col
 cmp z_cols
 jne column
done:
 ; Clear corpse aim metadata once, after the shared pixel loop. This avoids
 ; a new life-state branch for every row of the living soldier. Staging is
 ; private until render_done; publication independently rejects dead targets.
 lda actor_kind
 ora corpse_preparing
 bne return
 lda render_zombie_hp
 bpl return
 ldx render_buffer
 lda #0
 sta buffer_zombie_target,x
return:
 rts
.endproc
actor_row_mask = zombie_render_shared::row
actor_row_mask_done = zombie_render_shared::mask_ready

; Convert each of this sprite column's screen clip boundaries into exclusive
; source-row limits. This is done once per8px column and reused for every row.
.proc prepare_column_limits
 lda #0
 sta z_shift
 lda z_tile_x+1
 bpl shift_ready
 lda #0
 sec
 sbc z_tile_x
 cmp #8
 bcc :+
 lda #8
:
 sta z_shift
shift_ready:
 ldx #0
pixel:
 lda #0
 sta z_row_limits,x
 txa
 clc
 adc z_tile_x
 sta z_bits
 lda z_tile_x+1
 adc #0
 bne next
 ; Partial rightmost source tiles and offscreen pixels remain transparent.
 lda z_bits
 sec
 sbc z_left
 cmp z_width
 bcs next
 tay
 lda (z_mask_ptr),y
 clc
 adc #24
 sec
 sbc z_top
 sta z_row_mask
 lda #0
 sbc z_top+1
 bmi next
 bne whole_column
 lda z_row_mask
 cmp z_height
 bcc store
whole_column:
 lda z_height
store:
 sta z_row_limits,x
next:
 inx
 cpx #8
 bne pixel
.if ::SPRITE_MASK
 jmp classify_actor_mask
.else
 rts
.endif
.endproc

.if ::SPRITE_MASK
; Eight source-row limits have just been finalized. Zero cutoffs describe
; padding or completely hidden pixels. If all other cutoffs agree, one mask
; and cutoff reproduce every row exactly. Otherwise retain the general loop.
; The builder checks every shared actor/item/corpse height is below $FF.
; Recomputed for every column/invocation, never cached across world frames.
.proc classify_actor_mask
 lda #0
 sta z_mask_cutoff
 sta z_mask_bits
 ldx #0
pixel:
 lda z_row_limits,x
 cmp #1
 rol z_mask_bits             ; Source pixel0 becomes bit7 after eight shifts.
 cmp #0
 beq next
 ldy z_mask_cutoff
 beq store
 cmp z_mask_cutoff
 beq next
 lda #$FF                   ; Once mismatched, positive limits cannot clear it.
store:
 sta z_mask_cutoff
next:
 inx
 cpx #8
 bne pixel
 rts
.endproc
.endif

; Doom-style vertical autoaim, still silhouette-tight horizontally. Any
; visible opaque source pixel at screenX128 makes this snapshot targetable.
.proc detect_target
 lda z_tile_x+1
 bne done
 lda z_tile_x
 cmp #129
 bcs done
 cmp #121
 bcc done
 lda #128
 sec
 sbc z_tile_x
 tax
 lda z_plane0
 ora z_plane1
 and zombie_bits,x
 beq done
 ldx render_buffer
 lda #1
 sta buffer_zombie_target,x
done:
 rts
.endproc

.proc write_actor_oam
 ldy z_oam_index
 lda z_tile_y
 sec
 sbc #1
 sta (z_oam_ptr),y
 iny
 lda tile_number
 sta (z_oam_ptr),y
 iny
 lda #2
 ldx actor_kind
 beq :+
 lda #3
:                          ; medkit uses its own stable palette
 sta (z_oam_ptr),y
 iny
 lda z_tile_x+1
 bmi clipped_left
 lda z_tile_x
 jmp store_x
clipped_left:
 lda #0
store_x:
 sta (z_oam_ptr),y
 iny
 sty z_oam_index
 rts
.endproc

.segment "CODE"
; Projection also calls this helper while map bank0 is selected.
.proc set_metadata
 ldx render_buffer
 lda z_size
 sta buffer_zombie_size,x
 lda z_left+1
 bmi left_zero
 lda z_left
 jmp left_store
left_zero:
 lda #0
left_store:
 sta buffer_zombie_left,x
 lda z_left
 clc
 adc z_width
 sta g_rem
 lda z_left+1
 adc #0
 sta g_rem+1
 lda g_rem
 sec
 sbc #1
 sta g_rem
 lda g_rem+1
 sbc #0
 beq right_value
 lda #255
 bne right_store
right_value:
 lda g_rem
right_store:
 sta buffer_zombie_right,x
 lda z_top+1
 bmi top_clip
 lda z_top
 cmp #24
 bcs top_store
top_clip:
 lda #24
top_store:
 sta buffer_zombie_top,x
 lda z_foot+1
 bne bottom_clip
 lda z_foot
 sec
 sbc #1
 cmp #168
 bcc bottom_store
bottom_clip:
 lda #167
bottom_store:
 sta buffer_zombie_bottom,x
 rts
.endproc

zombie_compare_inverse = nearer_than_actor
