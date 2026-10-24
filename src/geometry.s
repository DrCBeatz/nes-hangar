; E1M1 room with an enclosed rectangular recess and horizontal floor strips.
; Explicit finite segments retain full signed32 inverse-depth interpolation.
; This variant evaluates the original projector at even screen columns only.
; Each sample retains its nearest opaque outer crossing, then the validated
; rectangular exit/entry crossings. Topological rim order cannot be reversed
; by rounded inverse depths. Validated opaque-plane halfspaces hide the recess.
.macpack longbranch
.importzp render_x, render_z, render_angle, render_eye, overflow_flag
.importzp render_zombie_x, render_zombie_z, render_buffer, render_mode
.import opening_candidate, opening_cache, opening_plane0
.import prg_render, prg_map
; Candidate/cache storage is dead until opening_render clears its cache,
; after geometry_begin returns. Coverage and exact-visibility probes run
; sequentially and share its contiguous 16+128 bytes. The compact strip
; arrays must not spill into the persistent audio workspace beside them.
visibility_scratch = opening_candidate
.assert opening_cache = visibility_scratch+16, lderror, "Visibility scratch layout changed"
.include "slime-memory.inc"
.include "door-memory.inc"
.include "door-config.inc"
.include "inner-visibility-config.inc"
.exportzp render_slime_palette
.include "coordinate-memory.inc"
.export geometry_begin, geometry_column, geometry_zombie_transform
.export slime_visibility_coverage, slime_visibility_exact, slime_column_visible
.export transform_vertex, geometry_vertex_cache_hits, geometry_vertex_cache_misses
.exportzp room_zone, candidate_count
.export geometry_pair_cache_init, geometry_pair_cache_ready
.export geometry_inner_visibility_begin
.exportzp g_inner_face_mask
.import zombie_begin, zombie_occlude, medkit_begin, medkit_occlude
.exportzp g_camera_x, g_camera_z, g_acc, g_mul_a, g_mul_b, g_value, g_den, g_rem
.exportzp g_num, g_ray_x, g_ray_z, g_step_x, g_step_z, g_project, g_left, g_right
.exportzp g_endpoint, g_front, g_delta_sign, g_sign, g_multiplicand, g_base, g_step
.exportzp g_column, g_top, g_bottom
.export scaled_division
.include "zombie-config.inc"
.export span_count, span_top, span_bottom, span_material
.ifndef COMPACT_SPANS
.export span_segment
.export span_depth0, span_depth1, span_depth2, span_depth3
.endif
.exportzp geometry_scratch_begin, geometry_scratch_end
.export geometry_bss_begin, geometry_bss_end

.segment "ZEROPAGE"
geometry_scratch_begin:
g_s: .res 2
g_c: .res 2
g_ray_x: .res 3
g_ray_z: .res 3
g_step_x: .res 2
g_step_z: .res 2
g_mul_a: .res 2
g_mul_b: .res 2
g_multiplicand: .res 4
g_acc: .res 4
g_sign: .res 1
g_step: .res 4
g_value: .res 3
g_num: .res 4
g_den: .res 3
g_rem: .res 4
g_segment: .res 1
g_vertex: .res 1
g_delta_sign: .res 1
g_camera_x: .res 4
g_camera_z: .res 4
g_endpoint: .res 1
g_front: .res 1
g_project: .res 2
g_left: .res 2
g_right: .res 2
g_quotient: .res 1
g_material: .res 1
g_half: .res 1
g_coefficient: .res 1
g_base: .res 4
g_column: .res 1
g_top: .res 1
g_bottom: .res 1
g_boundary_sign: .res 1
g_factor: .res 1
g_scaled: .res 3
g_cursor: .res 1
g_floor_top: .res 1
; Floor clipping starts only after begin-frame projection finishes. Reuse this
; producer-only byte for the two inner-face allow bits during that setup loop.
g_inner_face_mask = g_floor_top
room_zone: .res 1
candidate_count: .res 1
g_candidate_ptr: .res 2
g_candidate_cursor: .res 1
; Cursor dies after begin; retain this palette decision for the entire producer.
render_slime_palette = g_candidate_cursor
; Endpoint tag cache and trigonometry are dead once both actors are projected.
slime_indices = g_projected_tags
slime_count = g_s
slime_cursor = g_s+1
slime_slot = g_c
slime_floor_clip = g_projected_tags+31
geometry_scratch_end:


.segment "BSS"
geometry_bss_begin:
g_projected_low: .res 32
g_projected_high: .res 32
; Global vertex IDs map directly to32 projection slots. Collisions recompute
; the affected endpoint; they cannot alter its projection or truncate the map.
g_projected_tags: .res 32
geometry_vertex_cache_hits: .res 1
geometry_vertex_cache_misses: .res 1
g_visible_count: .res 1
g_visible_segments: .res 36
g_cached_left: .res 36
g_cached_right: .res 36
g_cached_value0: .res 36
g_cached_value1: .res 36
g_cached_value2: .res 36
g_cached_value3: .res 36
g_cached_step0: .res 36
g_cached_step1: .res 36
g_cached_step2: .res 36
g_cached_step3: .res 36
.ifdef STRIP_ACTIVE
; Only planes whose projected interval overlaps the current eight columns.
; Bit7 marks full-strip coverage; low7bits retain the segment ID. Original
; visible-list order is preserved, including its stable equal-depth tie rule.
g_active_count: .res 1
g_active_segments: .res 36
.endif
; Slot0 nearest outer closure, slot1 recess exit, slot2 recess entry.
g_selected: .res 3
span_count: .res 1
span_top: .res 16
span_bottom: .res 16
span_material: .res 16
.ifndef COMPACT_SPANS
; Diagnostics only: the raster consumes count/top/bottom/material. Keep these
; in instrumented builds to compare exact crossing IDs and inverse depths.
span_segment: .res 16
span_depth0: .res 16
span_depth1: .res 16
span_depth2: .res 16
span_depth3: .res 16
.endif
geometry_bss_end:

.segment "CODE"
; Select potentially visible room geometry before transforming any endpoint.
; Cache at most36 admitted planes, independent of total authored wall count.
; Camera inputs remain immutable throughout a complete candidate frame.
.proc geometry_begin
    lda #0
    sta g_visible_count
    sta geometry_vertex_cache_hits
    sta geometry_vertex_cache_misses
    lda #255
    ldx #31
clear_vertex_tags:
    sta g_projected_tags,x
    dex
    bpl clear_vertex_tags
    jsr select_candidates
    jsr inner_visibility_begin
    ldy render_angle
    lda geom_sine_low,y
    sta g_s
    lda geom_sine_high,y
    sta g_s+1
    tya
    clc
    adc #64
    tay
    lda geom_sine_low,y
    sta g_c
    lda geom_sine_high,y
    sta g_c+1
    jsr initial_rays
    lda #0
    sta g_candidate_cursor
    lda candidate_count
    jeq finished
next_segment:
    ; Positive inward plane distance means this exposed face is visible
    ; from the player's side. The signed24 plane distance retains all eight
    ; fractional bits of the supported 0..1023 world coordinates.
    lda g_candidate_cursor
    and #7
    tax
    lda geometry_candidate_bits,x
    sta g_half
    lda g_candidate_cursor
    lsr a
    lsr a
    lsr a
    tay
    lda (g_candidate_ptr),y
    and g_half
    jeq skip_segment
    ldx g_candidate_cursor
    jsr door_face_enabled
    jcc skip_segment
    stx g_segment
    lda #0
    sta g_acc
    sec
    sbc segment_plane_lo,x
    sta g_acc+1
    lda #0
    sbc segment_plane_hi,x
    sta g_acc+2
    lda render_x
    sta g_value
    lda render_x+1
    sta g_value+1
    lda render_x_hi
    sta g_value+2
    lda segment_nx,x
    jsr add_normal
    lda render_z
    sta g_value
    lda render_z+1
    sta g_value+1
    lda render_z_hi
    sta g_value+2
    ldx g_segment
    lda segment_nz,x
    jsr add_normal
    lda g_acc+2
    jmi skip_segment
    ora g_acc+1
    ora g_acc
    jeq skip_segment
    lda g_acc
    sta g_den
    lda g_acc+1
    sta g_den+1
    lda g_acc+2
    sta g_den+2

    ldx g_segment
    lda segment_material,x
    sta g_material
    lda #0
    sta g_endpoint
    sta g_front
    lda segment_vertex1,x
    jsr project_endpoint
    lda g_project
    sta g_left
    lda g_project+1
    sta g_left+1
    inc g_endpoint
    ldx g_segment
    lda segment_vertex2,x
    jsr project_endpoint
    lda g_project
    sta g_right
    lda g_project+1
    sta g_right+1
    lda g_front
    jeq skip_segment
    lda g_left+1
    jne skip_segment
    lda g_right+1
    bne visible_span
    lda g_left
    cmp g_right
    jcs skip_segment
visible_span:
    jsr calculate_plane
    ; Keep the entire signed32 intermediate. A short finite segment may
    ; be almost edge-on while its infinite plane passes through the room;
    ; neither plane distance nor interpolation step has a safe16bit bound.
    jsr advance_to_left
    lda g_acc
    clc
    adc g_base
    sta g_acc
    lda g_acc+1
    adc g_base+1
    sta g_acc+1
    lda g_acc+2
    adc g_base+2
    sta g_acc+2
    lda g_acc+3
    adc g_base+3
    sta g_acc+3
    ; The original cache begins at its integer projected left edge. Advance
    ; one original step if that edge is odd, then double the interpolation
    ; step. Therefore its first active even column has exactly base+x*step,
    ; including one-pixel spans and intervals beginning inside a strip.
pair_cache_init:
    lda g_left
    and #1
    beq even_start
    lda g_acc
    clc
    adc g_step
    sta g_acc
    lda g_acc+1
    adc g_step+1
    sta g_acc+1
    lda g_acc+2
    adc g_step+2
    sta g_acc+2
    lda g_acc+3
    adc g_step+3
    sta g_acc+3
even_start:
    asl g_step
    rol g_step+1
    rol g_step+2
    rol g_step+3
pair_cache_ready:
    ldx g_visible_count
    cpx #36
    bcc :+
    lda #1
    sta overflow_flag
    jmp skip_segment
:
    lda g_segment
    sta g_visible_segments,x
    inc g_visible_count
    lda g_left
    sta g_cached_left,x
    lda g_right
    sta g_cached_right,x
    ; Start one doubled interpolation step early: active samples advance before
    ; selecting. The subtract/add pair is modulo32; this temporary value
    ; is never interpreted as a signed depth until its first restoring add.
    lda g_acc
    sec
    sbc g_step
    sta g_cached_value0,x
    lda g_acc+1
    sbc g_step+1
    sta g_cached_value1,x
    lda g_acc+2
    sbc g_step+2
    sta g_cached_value2,x
    lda g_acc+3
    sbc g_step+3
    sta g_cached_value3,x
    lda g_step
    sta g_cached_step0,x
    lda g_step+1
    sta g_cached_step1,x
    lda g_step+2
    sta g_cached_step2,x
    lda g_step+3
    sta g_cached_step3,x
skip_segment:
    inc g_candidate_cursor
    lda g_candidate_cursor
    cmp #WALL_COUNT
    jne next_segment
finished:
    jsr slime_palette_begin
    jsr medkit_begin
    jsr zombie_begin
    rts
.endproc

; C=1 admits X's face for this immutable camera/door snapshot. The inner
; enclosure uses a conservative portal-cone gate before any plane transform.
; g_half is the existing bitmap bit for this candidate (bits6/7 at IDs86/87).
; The door crosscut remains the sole connection between its map partitions.
.proc door_face_enabled
.ifndef ROOMS_UNFILTERED
    cpx #INNER_VISIBILITY_FIRST
    bcc door
    cpx #INNER_VISIBILITY_END
    bcs door
    lda g_inner_face_mask
    and g_half
    beq hidden
door:
.endif
    cpx #DOOR_FIRST
    bcc ordinary
    cpx #DOOR_END
    bcs ordinary
    lda render_door
    bne hidden
    sec
    rts
ordinary:
    lda render_door
    bne enabled
    lda render_z_hi
    bne north
    lda render_z+1
    cmp #DOOR_Z
    bcc south
    bne north
    lda render_z
    beq enabled             ; retain all faces for illegal on-plane debug poses
north:
    cpx #DOOR_SOUTH_FIRST
    bcc enabled
    cpx #DOOR_SOUTH_END
    bcc hidden
    bcs enabled
south:
    cpx #DOOR_SOUTH_FIRST
    bcc hidden
    cpx #DOOR_SOUTH_END
    bcs hidden
enabled:
    sec
    rts
hidden:
    clc
    rts
.endproc

; Compute once per immutable render snapshot. Each table entry is a guarded
; lower bound on the X coordinate needed to see the enclosure through the
; slime-room portal for the complete closed integer-Z slab. If even floor(X)
; is below that cutoff, both exposed enclosure faces are certainly hidden.
; All out-of-domain positions and diagnostic unfiltered builds retain them.
.proc inner_visibility_begin
    lda #$C0
    sta g_inner_face_mask
.ifndef ROOMS_UNFILTERED
    lda render_x_hi
    cmp #INNER_VISIBILITY_X_PAGE
    bne done
    lda render_x+1
    cmp #<INNER_VISIBILITY_X_MAX
    bcs done
    lda render_z+1
    sec
    sbc #<INNER_VISIBILITY_Z_MIN
    tax
    lda render_z_hi
    sbc #>INNER_VISIBILITY_Z_MIN
    bne done
    cpx #INNER_VISIBILITY_ROWS
    bcs done
    lda render_x+1
    cmp inner_visibility_x_cut,x
    bcs done
    lda #0
    sta g_inner_face_mask
.endif
done:
    rts
.endproc
geometry_inner_visibility_begin = inner_visibility_begin

geometry_pair_cache_init = geometry_begin::pair_cache_init
geometry_pair_cache_ready = geometry_begin::pair_cache_ready

.proc select_candidates
    ;16x16 logical-unit source cells. The offline PVS is conservative across
    ; the complete cell and all camera angles; exact column clipping follows.
    ; A bounded grid origin and row pointers avoid a full 64x64 world table.
    lda render_x+1
    sec
    sbc #<GEOMETRY_GRID_X_MIN
    sta room_zone
    lda render_x_hi
    sbc #>GEOMETRY_GRID_X_MIN
    jcc outside
    .repeat 4
    lsr a
    ror room_zone
    .endrepeat
    lda room_zone
    cmp #GEOMETRY_GRID_COLS
    jcs outside
    sta g_candidate_cursor
    lda render_z+1
    sec
    sbc #<GEOMETRY_GRID_Z_MIN
    sta room_zone
    lda render_z_hi
    sbc #>GEOMETRY_GRID_Z_MIN
    jcc outside
    .repeat 4
    lsr a
    ror room_zone
    .endrepeat
    lda room_zone
    cmp #GEOMETRY_GRID_ROWS
    bcs outside
    tax
    lda geometry_zone_row_lo,x
    sta g_candidate_ptr
    lda geometry_zone_row_hi,x
    sta g_candidate_ptr+1
    ldy g_candidate_cursor
    lda (g_candidate_ptr),y
    sta room_zone
.ifdef ROOMS_UNFILTERED
    jmp unfiltered
.else
    tax
    lda geometry_candidate_lo,x
    sta g_candidate_ptr
    lda geometry_candidate_hi,x
    sta g_candidate_ptr+1
    lda geometry_candidate_count,x
    sta candidate_count
    rts
.endif
outside:
    ; Diagnostic poses outside the authored grid must never index arbitrary
    ; ROM. The conservative full list remains safe for those linked tests.
    lda #255
    sta room_zone
unfiltered:
    lda #<geometry_all_candidates
    sta g_candidate_ptr
    lda #>geometry_all_candidates
    sta g_candidate_ptr+1
    lda #WALL_COUNT
    sta candidate_count
    rts
.endproc

; X is the next even column, sequential0,2,..254. Select crossings before projecting
; any heights. All outer walls share a floor and ceiling, so the nearest one
; closes the complete view below its ceiling edge. The enclosed rectangle
; has at most one far(exit) and one near(entry) crossing in each column.
; Both the raster and the exact slime-visibility probe select bank3 once
; around their entire column loop. NMI never calls this producer-only block.
.segment "RENDER_CODE"
.proc geometry_column
    stx g_column
.ifdef STRIP_ACTIVE
    txa
    and #7
    bne strip_ready
    jsr prepare_strip
strip_ready:
.endif
    lda #0
    sta span_count
    sta slime_count
    sta g_cursor
    lda #255
    sta g_selected
    sta g_selected+1
    sta g_selected+2
.ifdef STRIP_ACTIVE
    lda g_active_count
.else
    lda g_visible_count
.endif
    jne next
    rts
next:
    ldy g_cursor
.ifdef STRIP_ACTIVE
    lda g_active_segments,y
    bpl partial_interval
    and #$7F
    tax
    jmp active
partial_interval:
    tax
.else
    tya
    tax
.endif
    lda g_column
    cmp g_cached_left,x
    jcc skip
    lda g_cached_right,x
    beq active                 ; encoded right=0 means exclusive256
    cmp g_column
    jeq skip
    jcc skip
active:
    ; Keep current values in their caches through selection and emission.
    ; This avoids copying all active depths into scratch and then saving
    ; selected depths a second time. Every active plane advances once.
    lda g_cached_value0,x
    clc
    adc g_cached_step0,x
    sta g_cached_value0,x
    lda g_cached_value1,x
    adc g_cached_step1,x
    sta g_cached_value1,x
    lda g_cached_value2,x
    adc g_cached_step2,x
    sta g_cached_value2,x
    lda g_cached_value3,x
    adc g_cached_step3,x
    sta g_cached_value3,x
    jmi skip
    ora g_cached_value2,x
    ora g_cached_value1,x
    ora g_cached_value0,x
    jeq skip
    lda g_visible_segments,x
    cmp #SLIME_BEGIN
    bcc ordinary_face
    jsr slime_collect
    jmp skip
ordinary_face:
    cmp #OPAQUE_COUNT
    bcs rim
    ; Retain only the nearest outer closure. Equal depth uses the later
    ; segment, matching the original stable depth-sorted outer-wall result.
    ldy g_selected
    cpy #255
    beq select_outer
    lda g_cached_value3,x
    cmp g_cached_value3,y
    bcc skip
    bne select_outer
    lda g_cached_value2,x
    cmp g_cached_value2,y
    bcc skip
    bne select_outer
    lda g_cached_value1,x
    cmp g_cached_value1,y
    bcc skip
    bne select_outer
    lda g_cached_value0,x
    cmp g_cached_value0,y
    bcc skip
select_outer:
    stx g_selected
    jmp skip
rim:
    ldy #1
    cmp #RECESS_ENTRY_BEGIN
    bcc select
    iny
select:
    txa
    sta g_selected,y
skip:
    inc g_cursor
    lda g_cursor
.ifdef STRIP_ACTIVE
    cmp g_active_count
.else
    cmp g_visible_count
.endif
    jne next
    lda #0
    sta g_cursor              ; Collection is finished; reuse as fallback flag.
    ldx g_selected
    cpx #255
    beq no_outer
    jsr emit_selected
    lda g_floor_top
    sta slime_floor_clip
    jsr slime_emit
    ; Every opaque plane puts all recess vertices on the same side.
    ; An outward crossing with the whole recess outside its inward plane
    ; closes before all rim crossings; the opposite halfspace closes after
    ; them. This proof covers the passage and all four corner pillars.
    ldx g_selected
    ldy g_visible_segments,x
    lda segment_hides_recess,y
    beq no_outer
    cmp #1
    beq done
    lda #1                    ; Only a recess-straddling supporting plane.
    sta g_cursor
no_outer:
    ldx g_selected+1
    cpx #255
    beq no_exit
    lda g_cursor
    beq :+
    jsr rim_before_closure
    bcc no_exit
:
    jsr emit_selected
no_exit:
    ldx g_selected+2
    cpx #255
    beq done
    lda g_cursor
    beq :+
    jsr rim_before_closure
    bcc done
:
    jsr emit_selected
done:
    rts
.endproc

; X=local rim slot. Supporting-plane straddles occur only on distant passage
; bevels; compare that finite closure against each rim, retaining exit/entry
; topological order. Existing proven halfspace cases do not pay this cost.
.proc rim_before_closure
    ldy g_selected
    lda g_cached_value3,x
    cmp g_cached_value3,y
    bne done
    lda g_cached_value2,x
    cmp g_cached_value2,y
    bne done
    lda g_cached_value1,x
    cmp g_cached_value1,y
    bne done
    lda g_cached_value0,x
    cmp g_cached_value0,y
done:
    rts
.endproc

.ifdef STRIP_ACTIVE
; g_column is a multiple of8. Rebuild the exact interval-overlap list without
; advancing any plane depth. A partial first/last strip still uses the old
; column bounds checks, so every plane advances exactly once per active sample.
; g_right and g_cursor are begin-frame/column scratch, never persistent state.
.proc prepare_strip
    lda #0
    sta g_active_count
    sta g_cursor
    lda g_column
    clc
    adc #8
    sta g_right                 ; zero means the exclusive right edge256
    lda g_visible_count
    beq done
next:
    ldy g_cursor
    tya
    tax
    lda g_cached_right,x
    beq check_left              ; right256 always exceeds the strip start
    cmp g_column
    bcc skip
    beq skip
check_left:
    lda g_right
    beq overlaps                ; all cached left edges are less than256
    cmp g_cached_left,x
    bcc skip
    beq skip
overlaps:
    lda g_cached_left,x
    cmp g_column
    bcc check_full_right
    beq check_full_right
partial:
    txa
    jmp store
check_full_right:
    lda g_cached_right,x
    beq full
    ldy g_right
    beq partial                 ; finite right edge cannot cover strip248..256
    cmp g_right
    bcc partial
full:
    txa
    ora #$80
store:
    ldy g_active_count
    sta g_active_segments,y
    inc g_active_count
skip:
    inc g_cursor
    lda g_cursor
    cmp g_visible_count
    bcc next
done:
    rts
.endproc
.endif

; X is a selected segment. Empty slots are filtered by the caller.
.proc emit_selected
    stx g_segment
    lda g_cached_value0,x
    sta g_acc
    lda g_cached_value1,x
    sta g_acc+1
    lda g_cached_value2,x
    sta g_acc+2
    lda g_cached_value3,x
    sta g_acc+3
    ldy g_visible_segments,x
    lda segment_floor,y
    jsr project_height
    sta g_floor_top
    ldx g_segment
    ldy g_visible_segments,x
    cpy #OPAQUE_COUNT
    bcs general_top
    lda render_eye
    cmp #6
    bne general_top
    ; Outside the recess, floor2 and ceiling10 are equidistant from eye6.
    ; Symmetric rounding and clipping make the opposite edge exactly the
    ; complement of the already projected floor. Avoid projecting it twice.
    lda #144
    sec
    sbc g_floor_top
    sta g_top
    jmp top_ready
general_top:
    lda segment_top,y
    cmp segment_bottom,y
    beq floor_span
    jsr project_height
    sta g_top
top_ready:
    ldx g_segment
    ldy g_visible_segments,x
    lda segment_bottom,y
    cmp segment_floor,y
    bne separate_bottom
    lda g_floor_top
    jmp bottom_ready
separate_bottom:
    jsr project_height
bottom_ready:
    sta g_bottom
    cmp g_top
    beq floor_span
    ldx g_segment
    ldy g_visible_segments,x
    lda segment_material,y
    jsr slime_remap_wall
    sta g_material
    jsr insert_span
floor_span:
    lda g_floor_top
    cmp #144
    beq done
    sta g_top
    lda #144
    sta g_bottom
    ldx g_segment
    ldy g_visible_segments,x
    lda segment_floor_material,y
    jsr slime_remap_floor
    sta g_material
    jsr insert_span
done:
    rts
.endproc

; Crossings already arrive in proven painter order. Append without shifting
; eight parallel span arrays or comparing nearly equal rounded rim depths.
.proc insert_span
    ; The palette visibility probe runs before actors are projected. Its bit7
    ; suppresses actor state writes while retaining identical world spans.
    lda render_slime_palette
    bmi without_occlusion
    jsr zombie_occlude
    jsr medkit_occlude
without_occlusion:
    ldx span_count
    cpx #16
    bcc place
    lda #1
    sta overflow_flag
    rts
place:
    lda g_top
    sta span_top,x
    lda g_bottom
    sta span_bottom,x
    lda g_material
    sta span_material,x
.ifndef COMPACT_SPANS
    ldy g_segment
    lda g_visible_segments,y
    sta span_segment,x
    lda g_acc
    sta span_depth0,x
    lda g_acc+1
    sta span_depth1,x
    lda g_acc+2
    sta span_depth2,x
    lda g_acc+3
    sta span_depth3,x
.endif
    inc span_count
    rts
.endproc

; A=world height in two-unit increments, eye4or6. Preserve the physical
; displacement round(abs(eye-height)*inverse/4096) after halving world units.
; Factors1/2/3 represent height differences2/4/6; never round inverse first.
.proc project_height
    sec
    sbc render_eye
    sta g_boundary_sign
    jeq horizon
    bpl magnitude
    eor #255
    clc
    adc #1
magnitude:
    lsr a
    sta g_factor
    lda g_acc+3
    jne clipped
    lda g_acc+2
    cmp #4
    jcs clipped                ; Even height difference2 is >=128 pixels.
    lda g_factor
    cmp #2
    beq quarter_height
    cmp #1
    beq eighth_height
    ; Height difference6: 3*inverse, then round/divide by2048.
    lda g_acc
    asl a
    sta g_scaled
    lda g_acc+1
    rol a
    sta g_scaled+1
    lda g_acc+2
    rol a
    sta g_scaled+2
    lda g_scaled
    clc
    adc g_acc
    sta g_scaled
    lda g_scaled+1
    adc g_acc+1
    sta g_scaled+1
    lda g_scaled+2
    adc g_acc+2
    sta g_scaled+2
    cmp #4
    bcs clipped
    asl a
    asl a
    asl a
    asl a
    asl a
    sta g_half
    lda g_scaled+1
    jmp round_eighth
quarter_height:
    lda g_acc+2
    cmp #2
    bcs clipped
    lda g_acc+1
    lsr a
    lsr a
    ldy g_acc+2
    beq :+
    ora #64
:
    adc #0
    jmp clamp
eighth_height:
    lda g_acc+2
    asl a
    asl a
    asl a
    asl a
    asl a
    sta g_half
    lda g_acc+1
round_eighth:
    lsr a
    lsr a
    lsr a
    ora g_half
    adc #0
clamp:
    cmp #72
    bcc signed
clipped:
    lda #72
signed:
    bit g_boundary_sign
    bmi below
    sta g_half
    lda #72
    sec
    sbc g_half
    rts
below:
    clc
    adc #72
    rts
horizon:
    lda #72
    rts
.endproc

; Transform the snapshotted moving actor with the identical full Q16
; camera basis used for wall endpoints. Only begin-frame scratch is touched.
; Called only from the bank3 actor projection phase.
.segment "RENDER_CODE"
.proc geometry_zombie_transform
    jsr zombie_delta_x
    lda g_c
    ldy g_c+1
    jsr transform_product
    ldx #3
save_x:
    lda g_acc,x
    sta g_camera_x,x
    dex
    bpl save_x
    jsr zombie_delta_z
    lda g_s
    ldy g_s+1
    jsr transform_product
    lda g_camera_x
    sec
    sbc g_acc
    sta g_camera_x
    lda g_camera_x+1
    sbc g_acc+1
    sta g_camera_x+1
    lda g_camera_x+2
    sbc g_acc+2
    sta g_camera_x+2
    lda g_camera_x+3
    sbc g_acc+3
    sta g_camera_x+3
    jsr zombie_delta_x
    lda g_s
    ldy g_s+1
    jsr transform_product
    ldx #3
save_z:
    lda g_acc,x
    sta g_camera_z,x
    dex
    bpl save_z
    jsr zombie_delta_z
    lda g_c
    ldy g_c+1
    jsr transform_product
    lda g_camera_z
    clc
    adc g_acc
    sta g_camera_z
    lda g_camera_z+1
    adc g_acc+1
    sta g_camera_z+1
    lda g_camera_z+2
    adc g_acc+2
    sta g_camera_z+2
    lda g_camera_z+3
    adc g_acc+3
    sta g_camera_z+3
    rts
.endproc
.proc zombie_delta_x
    lda render_zombie_x
    sec
    sbc render_x
    sta g_mul_a
    lda render_zombie_x+1
    sbc render_x+1
    sta g_mul_a+1
    lda render_zombie_x_hi
    sbc render_x_hi
    sta g_mul_a_hi
    jmp absolute_world_delta
.endproc
.proc zombie_delta_z
    lda render_zombie_z
    sec
    sbc render_z
    sta g_mul_a
    lda render_zombie_z+1
    sbc render_z+1
    sta g_mul_a+1
    lda render_zombie_z_hi
    sbc render_z_hi
    sta g_mul_a_hi
    jmp absolute_world_delta
.endproc

.segment "CODE"
.proc transform_vertex
    jsr vertex_delta_x
    lda g_c
    ldy g_c+1
    jsr transform_product
    ldx #3
save_x:
    lda g_acc,x
    sta g_camera_x,x
    dex
    bpl save_x
    jsr vertex_delta_z
    lda g_s
    ldy g_s+1
    jsr transform_product
    lda g_camera_x
    sec
    sbc g_acc
    sta g_camera_x
    lda g_camera_x+1
    sbc g_acc+1
    sta g_camera_x+1
    lda g_camera_x+2
    sbc g_acc+2
    sta g_camera_x+2
    lda g_camera_x+3
    sbc g_acc+3
    sta g_camera_x+3
    jsr vertex_delta_x
    lda g_s
    ldy g_s+1
    jsr transform_product
    ldx #3
save_z:
    lda g_acc,x
    sta g_camera_z,x
    dex
    bpl save_z
    jsr vertex_delta_z
    lda g_c
    ldy g_c+1
    jsr transform_product
    lda g_camera_z
    clc
    adc g_acc
    sta g_camera_z
    lda g_camera_z+1
    adc g_acc+1
    sta g_camera_z+1
    lda g_camera_z+2
    adc g_acc+2
    sta g_camera_z+2
    lda g_camera_z+3
    adc g_acc+3
    sta g_camera_z+3
    jsr project_camera
    rts
.endproc

; Full three-byte subtraction, with sign separate from the unsigned magnitude.
; The supported world bound makes that magnitude at most18 bits (Q10.8).
.proc vertex_delta_x
    ldx g_vertex
    lda #0
    sec
    sbc render_x
    sta g_mul_a
    lda vertex_x,x
    sbc render_x+1
    sta g_mul_a+1
    lda vertex_x_hi,x
    sbc render_x_hi
    sta g_mul_a_hi
    jmp absolute_world_delta
.endproc
.proc vertex_delta_z
    ldx g_vertex
    lda #0
    sec
    sbc render_z
    sta g_mul_a
    lda vertex_z,x
    sbc render_z+1
    sta g_mul_a+1
    lda vertex_z_hi,x
    sbc render_z_hi
    sta g_mul_a_hi
    jmp absolute_world_delta
.endproc

; Carry is the unsigned comparison from the complete coordinate subtraction.
.proc absolute_world_delta
    lda #0
    sta g_delta_sign
    bcs done
    lda #128
    sta g_delta_sign
    lda #0
    sec
    sbc g_mul_a
    sta g_mul_a
    lda #0
    sbc g_mul_a+1
    sta g_mul_a+1
    lda #0
    sbc g_mul_a_hi
    sta g_mul_a_hi
done:
    rts
.endproc
.proc transform_product
    sta g_mul_b
    sty g_mul_b+1
    lda g_delta_sign
    eor g_mul_b+1
    sta g_sign
    lda g_mul_b+1
    bpl positive
    lda #0
    sec
    sbc g_mul_b
    sta g_mul_b
    lda #0
    sbc g_mul_b+1
    sta g_mul_b+1
positive:
    jsr unsigned_multiply
    jmp sign_product
.endproc

.proc advance_to_left
    ldx #3
    lda #0
clear:
    sta g_acc,x
    lda g_step,x
    sta g_multiplicand,x
    lda #0
    dex
    bpl clear
    lda g_left
    sta g_mul_b
    ldx #8
bit_loop:
    lsr g_mul_b
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

; Add signed small integer coefficient A times signed24 g_value to g_acc.
; Scene normals are reduced primitive integers, never length-scaled floats.
.proc add_normal
    sta g_coefficient
    beq done
    bpl positive
    eor #255
    clc
    adc #1
    sta g_coefficient
    jsr negate_value
positive:
    lda g_acc
    clc
    adc g_value
    sta g_acc
    lda g_acc+1
    adc g_value+1
    sta g_acc+1
    lda g_acc+2
    adc g_value+2
    sta g_acc+2
    dec g_coefficient
    bne positive
done:
    rts
.endproc
.proc negate_value
    lda #0
    sec
    sbc g_value
    sta g_value
    lda #0
    sbc g_value+1
    sta g_value+1
    lda #0
    sbc g_value+2
    sta g_value+2
    rts
.endproc

.proc calculate_plane
    lda #0
    sta g_acc
    sta g_acc+1
    sta g_acc+2
    lda g_ray_x
    sta g_value
    lda g_ray_x+1
    sta g_value+1
    lda g_ray_x+2
    sta g_value+2
    ldx g_segment
    lda segment_nx,x
    jsr add_normal
    lda g_ray_z
    sta g_value
    lda g_ray_z+1
    sta g_value+1
    lda g_ray_z+2
    sta g_value+2
    ldx g_segment
    lda segment_nz,x
    jsr add_normal
    jsr acc_to_negated_value
    jsr scaled_division
    lda g_acc
    sta g_base
    lda g_acc+1
    sta g_base+1
    lda g_acc+2
    sta g_base+2
    lda g_acc+3
    sta g_base+3
    lda #0
    sta g_acc
    sta g_acc+1
    sta g_acc+2
    lda g_step_x
    sta g_value
    lda g_step_x+1
    sta g_value+1
    lda #0
    bit g_value+1
    bpl :+
    lda #255
:
    sta g_value+2
    ldx g_segment
    lda segment_nx,x
    jsr add_normal
    lda g_step_z
    sta g_value
    lda g_step_z+1
    sta g_value+1
    lda #0
    bit g_value+1
    bpl :+
    lda #255
:
    sta g_value+2
    ldx g_segment
    lda segment_nz,x
    jsr add_normal
    jsr acc_to_negated_value
    jsr scaled_division
    lda g_acc
    sta g_step
    lda g_acc+1
    sta g_step+1
    lda g_acc+2
    sta g_step+2
    lda g_acc+3
    sta g_step+3
    rts
.endproc
.proc acc_to_negated_value
    lda g_acc
    sta g_value
    lda g_acc+1
    sta g_value+1
    lda g_acc+2
    sta g_value+2
    jmp negate_value
.endproc
.proc initial_rays
    ; Pixel-centered world rays, doubled and in Q8:
    ; R_x = 256*s - 255*c, R_z = 256*c + 255*s.
    ; They require signed 18 bits; keeping all bits avoids close-wall
    ; grazing errors caused by coarse trigonometric coefficients.
    lda #0
    sta g_ray_x
    sta g_ray_z
    lda g_s
    sec
    sbc g_c
    sta g_ray_x+1
    lda g_s+1
    sbc g_c+1
    sta g_ray_x+2
    lda g_c
    clc
    adc g_ray_x
    sta g_ray_x
    lda g_c+1
    adc g_ray_x+1
    sta g_ray_x+1
    lda #0
    bit g_c+1
    bpl :+
    lda #$ff
:
    adc g_ray_x+2
    sta g_ray_x+2
    lda g_c
    asl a
    sta g_step_x
    lda g_c+1
    rol a
    sta g_step_x+1

    lda g_c
    clc
    adc g_s
    sta g_ray_z+1
    lda g_c+1
    adc g_s+1
    sta g_ray_z+2
    lda #0
    sec
    sbc g_s
    sta g_ray_z
    lda g_ray_z+1
    sbc g_s+1
    sta g_ray_z+1
    lda #0
    bit g_s+1
    bpl :+
    lda #$ff
:
    sta g_value
    lda g_ray_z+2
    sbc g_value
    sta g_ray_z+2
    lda g_s
    asl a
    sta g_value
    lda g_s+1
    rol a
    sta g_value+1
    lda #0
    sec
    sbc g_value
    sta g_step_z
    lda #0
    sbc g_value+1
    sta g_step_z+1
    rts
.endproc
.proc project_endpoint
    sta g_vertex
    and #31
    tax
    lda g_projected_tags,x
    cmp g_vertex
    beq cached
    ; Transform scratch does not alter the current wall denominator, endpoint
    ; direction, front counter, extent, material or global wall ID.
    inc geometry_vertex_cache_misses
    jsr transform_vertex
    lda g_vertex
    and #31
    tax
    lda g_project
    sta g_projected_low,x
    lda g_project+1
    sta g_projected_high,x
    lda g_vertex
    sta g_projected_tags,x
    jmp ready
cached:
    inc geometry_vertex_cache_hits
ready:
    lda g_projected_low,x
    sta g_project
    lda g_projected_high,x
    bmi behind
    sta g_project+1
    inc g_front
    rts
behind:
    lda #0
    sta g_project
    lda g_endpoint
    sta g_project+1
    rts
.endproc

; Project an admitted endpoint. Behind-camera vertices retain a
; sentinel: clipping to left/right must still depend on the directed endpoint.
; Move back into fixed code, making room for the expanded visibility bitmaps.
.segment "CODE"
; Only the producer calls this helper; it remains safe across NMI interrupts.
.proc project_camera
    lda g_camera_z+3
    jmi behind
    ora g_camera_z+2
    ora g_camera_z+1
    ora g_camera_z
    jeq behind
    ldx #3
copy_x:
    lda g_camera_x,x
    sta g_rem,x
    dex
    bpl copy_x
    lda g_rem+3
    sta g_sign
    bpl absolute_x
    lda #0
    sec
    sbc g_rem
    sta g_rem
    lda #0
    sbc g_rem+1
    sta g_rem+1
    lda #0
    sbc g_rem+2
    sta g_rem+2
    lda #0
    sbc g_rem+3
    sta g_rem+3
absolute_x:
    lda g_rem+3
    cmp g_camera_z+3
    bcc inside
    bne outside
    lda g_rem+2
    cmp g_camera_z+2
    bcc inside
    bne outside
    lda g_rem+1
    cmp g_camera_z+1
    bcc inside
    bne outside
    lda g_rem
    cmp g_camera_z
    bcc inside
outside:
    lda #0
    sta g_project
    lda g_sign
    bmi outside_left
    lda #1
    sta g_project+1
    rts
outside_left:
    lda #0
    sta g_project+1
    rts
behind:
    lda #0
    sta g_project
    lda #128
    sta g_project+1
    rts
inside:
    lda #0
    sta g_quotient
    sta g_project+1
    ldx #7
divide_bit:
    asl g_quotient
    asl g_rem
    rol g_rem+1
    rol g_rem+2
    rol g_rem+3
    lda g_rem+3
    cmp g_camera_z+3
    bcc next_bit
    bne subtract
    lda g_rem+2
    cmp g_camera_z+2
    bcc next_bit
    bne subtract
    lda g_rem+1
    cmp g_camera_z+1
    bcc next_bit
    bne subtract
    lda g_rem
    cmp g_camera_z
    bcc next_bit
subtract:
    lda g_rem
    sec
    sbc g_camera_z
    sta g_rem
    lda g_rem+1
    sbc g_camera_z+1
    sta g_rem+1
    lda g_rem+2
    sbc g_camera_z+2
    sta g_rem+2
    lda g_rem+3
    sbc g_camera_z+3
    sta g_rem+3
    inc g_quotient
next_bit:
    dex
    bne divide_bit
    asl g_rem
    rol g_rem+1
    rol g_rem+2
    rol g_rem+3
    lda g_rem+3
    cmp g_camera_z+3
    bcc no_round
    bne round
    lda g_rem+2
    cmp g_camera_z+2
    bcc no_round
    bne round
    lda g_rem+1
    cmp g_camera_z+1
    bcc no_round
    bne round
    lda g_rem
    cmp g_camera_z
    bcc no_round
round:
    inc g_quotient
no_round:
    lda g_sign
    bmi negative
    lda #128
    clc
    adc g_quotient
    sta g_project
    lda #0
    adc #0
    sta g_project+1
    rts
negative:
    lda #128
    sec
    sbc g_quotient
    sta g_project
    rts
.endproc
; Signed32 rounded(value24*2048/positive24 denominator).
.segment "CODE"
.proc scaled_division
    lda g_value+2
    sta g_sign
    bpl positive
    jsr negate_value
positive:
    lda #0
    sta g_num
    lda g_value
    sta g_num+1
    lda g_value+1
    sta g_num+2
    lda g_value+2
    sta g_num+3
    ldx #3
scale:
    asl g_num+1
    rol g_num+2
    rol g_num+3
    dex
    bne scale
    lda #0
    sta g_rem
    sta g_rem+1
    sta g_rem+2
    sta g_rem+3
    ldx #32
divide_bit:
    asl g_num
    rol g_num+1
    rol g_num+2
    rol g_num+3
    rol g_rem
    rol g_rem+1
    rol g_rem+2
    rol g_rem+3
    lda g_rem+3
    bne subtract
    lda g_rem+2
    cmp g_den+2
    bcc next_bit
    bne subtract
    lda g_rem+1
    cmp g_den+1
    bcc next_bit
    bne subtract
    lda g_rem
    cmp g_den
    bcc next_bit
subtract:
    lda g_rem
    sec
    sbc g_den
    sta g_rem
    lda g_rem+1
    sbc g_den+1
    sta g_rem+1
    lda g_rem+2
    sbc g_den+2
    sta g_rem+2
    lda g_rem+3
    sbc #0
    sta g_rem+3
    inc g_num
next_bit:
    dex
    bne divide_bit
    asl g_rem
    rol g_rem+1
    rol g_rem+2
    rol g_rem+3
    lda g_rem+3
    bne round
    lda g_rem+2
    cmp g_den+2
    bcc no_round
    bne round
    lda g_rem+1
    cmp g_den+1
    bcc no_round
    bne round
    lda g_rem
    cmp g_den
    bcc no_round
round:
    inc g_num
    bne no_round
    inc g_num+1
    bne no_round
    inc g_num+2
    bne no_round
    inc g_num+3
no_round:
    lda g_num
    sta g_acc
    lda g_num+1
    sta g_acc+1
    lda g_num+2
    sta g_acc+2
    lda g_num+3
    sta g_acc+3
    jmp sign_product
.endproc

.proc absolute_multiplicand
    lda g_mul_a+1
    bpl done
    lda #0
    sec
    sbc g_mul_a
    sta g_mul_a
    lda #0
    sbc g_mul_a+1
    sta g_mul_a+1
done:
    rts
.endproc
.proc unsigned_multiply
    lda #0
    sta g_acc+3
    lda g_mul_b+1
    beq normal
    ; The only 9-bit coefficient is abs(sin/cos)=256 at a cardinal angle.
    lda #0
    sta g_acc
    lda g_mul_a
    sta g_acc+1
    lda g_mul_a+1
    sta g_acc+2
    lda g_mul_a_hi
    sta g_acc+3
    rts
normal:
    lda g_mul_a
    sta g_multiplicand
    lda g_mul_a+1
    sta g_multiplicand+1
    lda #0
    sta g_multiplicand+3
    sta g_acc
    sta g_acc+1
    sta g_acc+2
    lda g_mul_a_hi
    sta g_multiplicand+2
    bne wide
    ; Preserve the original three-byte loop for all deltas below256 units.
    ldx #8
multiply_bit:
    lsr g_mul_b
    bcc no_add
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
no_add:
    asl g_multiplicand
    rol g_multiplicand+1
    rol g_multiplicand+2
    dex
    bne multiply_bit
    rts
wide:
    ; At most18 input bits times an8-bit coefficient needs26 product bits.
    ldx #8
wide_bit:
    lsr g_mul_b
    bcc wide_shift
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
wide_shift:
    asl g_multiplicand
    rol g_multiplicand+1
    rol g_multiplicand+2
    rol g_multiplicand+3
    dex
    bne wide_bit
    rts
.endproc
.proc sign_product
    lda g_sign
    bpl done
    lda #0
    sec
    sbc g_acc
    sta g_acc
    lda #0
    sbc g_acc+1
    sta g_acc+1
    lda #0
    sbc g_acc+2
    sta g_acc+2
    lda #0
    sbc g_acc+3
    sta g_acc+3
done:
    rts
.endproc

.segment "MAPDATA"
; These producer-only helpers normally execute with geometry bank0 selected;
; the exact probe temporarily selects bank3, using this mirrored prefix. No NMI
; may call them. All scratch is dead endpoint/trig storage; actor state aliases
; remain intact. Cosmetic flat spans deliberately bypass actor floor masks.
.proc slime_palette_begin
    lda #0
    sta render_slime_palette
    ldx g_visible_count
scan:
    dex
    bmi save
    ldy g_visible_segments,x
    cpy #SLIME_BEGIN
    bcs green
    cpy #OPAQUE_COUNT
    bcs scan
    lda segment_floor_material,y
    cmp #2
    bne scan
green:
    ; Angular admission alone does not prove visibility through intervening
    ; room walls. First reject samples hidden by proven separating planes.
    jsr slime_visibility_coverage
    beq save
    jsr slime_visibility_exact
save:
    lda render_slime_palette
    ldx render_buffer
    bne bank1
    sta BUFFER_SLIME0
    rts
bank1:
    sta BUFFER_SLIME1
    rts
.endproc

; Return A=0 only when every potential green sample is covered by an opaque
; face whose inward halfspace excludes both entire pools. The positive-depth
; test uses the same signed32 increments as geometry_column. Any uncertain
; sample falls through to exact span visibility; this never admits green.
; The raster has not started, so its candidate/cache storage is scratch.
.proc slime_visibility_coverage
    lda #0
    ldx #127
clear:
    sta visibility_scratch,x
    dex
    bpl clear
    ldx #0
mark_plane:
    cpx g_visible_count
    beq begin_cover
    ldy g_visible_segments,x
    cpy #SLIME_BEGIN
    bcs mark
    cpy #OPAQUE_COUNT
    bcs next_mark
    lda segment_floor_material,y
    cmp #2
    bne next_mark
mark:
    jsr interval
    cpy g_right
    beq next_mark
    lda #1
mark_sample:
    sta visibility_scratch,y
    iny
    cpy g_right
    bne mark_sample
next_mark:
    inx
    bne mark_plane
begin_cover:
    ldx #0
cover_plane:
    cpx g_visible_count
    beq inspect
    ldy g_visible_segments,x
    cpy #OPAQUE_COUNT
    bcs next_cover
    lda segment_hides_slime,y
    cmp #1
    bne next_cover
    ; A future low wall/opening must not become a visibility certificate.
    ; Rays from the eye to pool height2 stay inside this vertical interval.
    lda segment_top,y
    cmp render_eye
    bcc next_cover
    lda segment_bottom,y
    cmp #3
    bcs next_cover
    jsr interval
    cpy g_right
    beq next_cover
    lda g_cached_value0,x
    sta g_acc
    lda g_cached_value1,x
    sta g_acc+1
    lda g_cached_value2,x
    sta g_acc+2
    lda g_cached_value3,x
    sta g_acc+3
cover_sample:
    lda g_acc
    clc
    adc g_cached_step0,x
    sta g_acc
    lda g_acc+1
    adc g_cached_step1,x
    sta g_acc+1
    lda g_acc+2
    adc g_cached_step2,x
    sta g_acc+2
    lda g_acc+3
    adc g_cached_step3,x
    sta g_acc+3
    bmi next_sample
    ora g_acc+2
    ora g_acc+1
    ora g_acc
    beq next_sample
    lda #0
    sta visibility_scratch,y
next_sample:
    iny
    cpy g_right
    bne cover_sample
next_cover:
    inx
    bne cover_plane
inspect:
    ldx #127
inspect_sample:
    lda visibility_scratch,x
    bne done
    dex
    bpl inspect_sample
done:
    cmp #0                    ; Final DEX otherwise leaves Z clear on all-zero.
    rts
interval:
    ; [ceil(left/2),ceil(right/2)), with right0 encoding256.
    lda g_cached_right,x
    beq full_right
    lsr a
    adc #0
    bne right_ready
full_right:
    lda #128
right_ready:
    sta g_right
    lda g_cached_left,x
    lsr a
    adc #0
    tay
    rts
.endproc

; Probe the existing column/span producer, preserving its initial interpolants
; and all endpoint/trigonometric data needed by subsequent actor projection.
; No vertex transforms or raster/tile work is repeated. A surviving green pixel
; ends the probe immediately. Bit7 suppresses the actor occlusion callbacks.
.proc slime_visibility_exact
    ; This MAPDATA prefix is byte-identical in bank0 and bank3. Its endpoints
    ; and per-column map tables stay outside the setup-only overlay, allowing
    ; the shared column/projector routines to live in bank3 with the raster.
    jsr prg_render
    ldx #35
save_values:
    lda g_cached_value0,x
    sta visibility_scratch,x
    lda g_cached_value1,x
    sta visibility_scratch+36,x
    lda g_cached_value2,x
    sta visibility_scratch+72,x
    lda g_cached_value3,x
    sta visibility_scratch+108,x
    dex
    bpl save_values
    ldx #31
save_tags:
    lda g_projected_tags,x
    sta opening_plane0,x
    dex
    bpl save_tags
    ldx #3
save_trig:
    lda g_s,x
    sta opening_plane0+32,x
    dex
    bpl save_trig
    lda #$81
    sta render_slime_palette
    ldx #0
column:
    jsr geometry_column
    lda render_mode
    beq inspect
    lda g_column
    and #7
    cmp #4
    bne next_column
inspect:
    jsr slime_column_visible
    bcs found
next_column:
    ldx g_column
    inx
    inx
    bne column
    lda #0
    beq restore
found:
    lda #1
restore:
    sta render_slime_palette
    ldx #35
restore_values:
    lda visibility_scratch,x
    sta g_cached_value0,x
    lda visibility_scratch+36,x
    sta g_cached_value1,x
    lda visibility_scratch+72,x
    sta g_cached_value2,x
    lda visibility_scratch+108,x
    sta g_cached_value3,x
    dex
    bpl restore_values
    ldx #31
restore_tags:
    lda opening_plane0,x
    sta g_projected_tags,x
    dex
    bpl restore_tags
    ldx #3
restore_trig:
    lda opening_plane0+32,x
    sta g_s,x
    dex
    bpl restore_trig
    jmp prg_map              ; restore setup bank; result is render_slime_palette
.endproc

; Each suffix of this world's painter-ordered floor/rim spans has a contiguous
; covered tail. Match the raster's suffix clipping before testing green2, so
; a later recess floor or wall cannot falsely trigger the palette. Coarse mode
; retains only the exact y=4(mod8) tile-center samples that it will display.
.proc slime_column_visible
    lda #144
    sta g_right
    ldy span_count
    beq absent
    dey
span:
    lda span_bottom,y
    cmp g_right
    bcc keep_bottom
    lda g_right
    sta g_bottom
    lda span_top,y
    cmp g_right
    bcs clipped
    sta g_right
    jmp clipped
keep_bottom:
    sta g_bottom
clipped:
    lda span_material,y
    cmp #2
    bne next
    lda span_top,y
    cmp g_bottom
    bcs next
    lda render_mode
    beq present
    lda span_top,y
    clc
    adc #3
    and #$F8
    ora #4
    cmp g_bottom
    bcc present
next:
    dey
    bpl span
absent:
    clc
    rts
present:
    sec
    rts
.endproc

.proc slime_remap_wall
    cmp #2
    bne done
    pha
    lda render_slime_palette
    beq retain
    pla
    lda #1
    rts
retain:
    pla
done:
    rts
.endproc
.proc slime_remap_floor
    cpy #OPAQUE_COUNT
    bcc done                  ; New green perimeter floors remain material2.
    cpy #SLIME_BEGIN
    bcs done
    jmp slime_remap_wall       ; Only the old recess floor shares brown2.
done:
    rts
.endproc

; Insert local cache X in ascending signed-positive inverse depth. Equal
; depths retain authored segment order. At most one side of each of the ten
; paired seams is admitted, so ten slots bound the list for every column.
.proc slime_collect
    lda slime_count
    cmp #SLIME_EDGE_COUNT
    bcc capacity
    lda #1
    sta overflow_flag
    rts
capacity:
    sta slime_slot
compare:
    lda slime_slot
    beq place
    tay
    dey
    lda slime_indices,y
    tay
    lda g_cached_value3,x
    cmp g_cached_value3,y
    bne ordered
    lda g_cached_value2,x
    cmp g_cached_value2,y
    bne ordered
    lda g_cached_value1,x
    cmp g_cached_value1,y
    bne ordered
    lda g_cached_value0,x
    cmp g_cached_value0,y
ordered:
    bcs place
    dec slime_slot
    ldy slime_slot
    lda slime_indices,y
    sta slime_indices+1,y
    jmp compare
place:
    ldy slime_slot
    txa
    sta slime_indices,y
    inc slime_count
    rts
.endproc

.proc slime_emit
    lda slime_count
    jeq done
    lda g_selected
    cmp #255
    jeq done                  ; No enclosing wall means no safe floor clip.
    lda slime_floor_clip
    cmp #144
    jeq done                  ; No projected floor means nothing to recolor.
    lda #0
    sta slime_cursor
next:
    ldy slime_cursor
    ldx slime_indices,y
    stx g_segment
    ldy g_selected
    lda g_visible_segments,y
    tay
    lda segment_hides_slime,y
    beq visible
    cmp #1
    jeq skip
    jsr rim_before_closure
    jcc skip
visible:
    stx g_segment
    ; Every finite seam separates the same two floor materials. Toggle the
    ; partition parity rather than trusting nearly tied independently rounded
    ; depths to keep a near-side edge color in exact geometric order. Two
    ; opposite crossings at the same projected row cancel instead of creating
    ; an unbounded color stripe below the shared corner.
    ldy span_count
    dey
    lda span_material,y
    eor #1                    ; Gray3 <-> green2.
    sta g_material
    lda g_cached_value0,x
    sta g_acc
    lda g_cached_value1,x
    sta g_acc+1
    lda g_cached_value2,x
    sta g_acc+2
    lda g_cached_value3,x
    sta g_acc+3
    lda #2
    jsr project_height
    cmp slime_floor_clip
    bcs clipped
    lda slime_floor_clip
clipped:
    cmp #144
    jeq skip
    sta g_top
    ; Positive inverse depths were sorted far-to-near. All seams have floor2,
    ; so their projected rows are monotonic. End the previous floor interval
    ; here instead of repeatedly painting it to the viewport bottom. The
    ; original wall/floor actor masks already ran before this cosmetic edit.
    ldy span_count
    dey
    cmp span_top,y
    bne shorten
    dec span_count            ; Equal boundary: replace the now-empty tail.
    ldy span_count
    beq append
    dey
    lda span_material,y
    cmp g_material
    bne append
    lda #144                  ; Opposite same-row pair restores prior color.
    sta span_bottom,y
    jmp skip
shorten:
    sta span_bottom,y
append:
    lda #144
    sta g_bottom
    jsr insert_span::without_occlusion
skip:
    inc slime_cursor
    lda slime_cursor
    cmp slime_count
    jcc next
done:
    rts
.endproc

; Per-column map data is mirrored into the render bank. Visibility tables
; below are used only during geometry_begin with bank0 selected; their bank3
; addresses can safely hold raster/projection code after setup completes.
.include "geometry-data.inc"
.export map_render_overlay_start, map_render_overlay_end
map_render_overlay_start:
.include "visibility-data.inc"
.include "inner-visibility-data.inc"
map_render_overlay_end:
.import __RENDER_CODE_LOAD__, __RENDER_CODE_SIZE__
.assert slime_visibility_exact >= $8000 .and slime_visibility_exact < __RENDER_CODE_LOAD__, lderror, "Exact slime probe must stay in mirrored map prefix"
.assert slime_column_visible <= __RENDER_CODE_LOAD__, lderror, "Exact slime probe crosses render overlay"
.assert __RENDER_CODE_LOAD__ >= map_render_overlay_start, lderror, "Render overlay overwrites live map data before visibility tables"
.assert __RENDER_CODE_LOAD__+__RENDER_CODE_SIZE__ <= map_render_overlay_end, lderror, "Render overlay overwrites live map data after visibility tables"
.assert VERTEX_COUNT <255, error, "Vertex255 is reserved for the invalid cache tag"
.assert WALL_COUNT <256, error, "Global wall IDs must fit one byte"

.assert INNER_VISIBILITY_FIRST / 8 = (INNER_VISIBILITY_END-1) / 8, error, "Inner visibility mask spans bitmap bytes"
.assert (INNER_VISIBILITY_FIRST & 7) = 6 .and (INNER_VISIBILITY_END & 7) = 0, error, "Inner visibility mask requires bits6/7"
.assert INNER_VISIBILITY_X_MAX > INNER_VISIBILITY_X_PAGE*256 .and INNER_VISIBILITY_X_MAX < (INNER_VISIBILITY_X_PAGE+1)*256, error, "Inner X bound must share the guarded page"
