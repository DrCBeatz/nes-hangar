; E1M1 recess with four solid pillars. Global positions are unsigned Q16.8.
; The exact radius-two square intersects finite line segments, not grid cells.
; X then Z collision preserves wall sliding. Every step is <=64/256 logical units,
; so a legal pose cannot tunnel through a wall. The riser is not a blocking edge:
; highest floor under the square supports the player; max-step and body clearance
; rules decide whether a candidate may be entered. Scratch belongs to NMI only.
.setcpu "6502"
.macpack longbranch
.include "coordinate-memory.inc"
.importzp player_x, player_z, pending_angle, input_buttons, nmi_count
.ifdef NTSC
.importzp simulation_count, movement_accumulator
.endif
.import zombie_candidate_blocked
.import door_candidate_blocked
.export movement_init, movement_tick, footprint_blocked, movement_candidate_blocked, floor_support
.exportzp movement_scratch_begin, movement_scratch_end, move_x, move_z
.export movement_blocked_x, movement_blocked_z
.exportzp player_floor, player_eye, move_floor

.segment "ZEROPAGE"
movement_scratch_begin:
move_angle:       .res 1
move_dx:          .res 2
move_dz:          .res 2
move_x:           .res 2
move_z:           .res 2
move_line:        .res 2
movement_blocked_x: .res 1
movement_blocked_z: .res 1
player_floor:      .res 1
player_eye:        .res 1
move_floor:        .res 1
move_collision_ptr: .res 2
move_collision_cursor: .res 1
move_collision_count: .res 1
movement_scratch_end:

.segment "RODATA"
; Generated from map.json by movement_reference.py; no view animation data.
.include "movement-data.inc"
.include "collision-visibility.inc"
; Index is UDLR bits. Opposite directions cancel. A enables LR strafing.
move_offsets: .byte 0,64,192,0,128,96,160,128,0,32,224,0,0,64,192,0
move_active:  .byte 0, 1,  1,0,  1, 1,  1,  1,1, 1,  1,1,0, 1,  1,0

.segment "CODE"
.proc movement_init
    lda #<SPAWN_X
    sta player_x
    lda #>SPAWN_X
    sta player_x+1
    lda #^SPAWN_X
    sta player_x_hi
    lda #<SPAWN_Z
    sta player_z
    lda #>SPAWN_Z
    sta player_z+1
    lda #^SPAWN_Z
    sta player_z_hi
    lda #SPAWN_ANGLE
    sta pending_angle
    lda #SPAWN_FLOOR
    sta player_floor
    clc
    adc #PLAYER_EYE_HEIGHT
    sta player_eye
    lda #0
    sta movement_blocked_x
    sta movement_blocked_z
.ifdef NTSC
    ; Start restarts the fractional cadence, but the diagnostics/simulation
    ; counter remains monotonic and supplies turn parity across resets.
    sta movement_accumulator
.endif
    rts
.endproc

.proc movement_tick
    lda input_buttons
    bmi @translation             ; A held: lateral buttons strafe.
.ifdef NTSC
    lda simulation_count
.else
    lda nmi_count
.endif
    and #1
    bne @translation
    lda input_buttons
    and #3
    cmp #1
    bne @left
    inc pending_angle
    jmp @translation
@left:
    cmp #2
    bne @translation
    dec pending_angle
@translation:
    lda input_buttons
    bmi @strafe
    and #$0C                    ; Without A, LR only affect turning.
    bpl @lookup
@strafe:
    and #$0F
@lookup:
    tax
    lda move_active,x
    bne @moving
    rts
@moving:
    lda move_offsets,x
    clc
    adc pending_angle
    sta move_angle
    tay
    ldx #0
    lda movement_sine,y
    sta move_dx
    bpl :+
    dex
:
    stx move_dx+1
    tya
    clc
    adc #64
    tay
    ldx #0
    lda movement_sine,y
    sta move_dz
    bpl :+
    dex
:
    stx move_dz+1

    lda player_z
    sta move_z
    lda player_z+1
    sta move_z+1
    lda player_z_hi
    sta move_z_hi
    lda player_x
    clc
    adc move_dx
    sta move_x
    lda player_x+1
    adc move_dx+1
    sta move_x+1
    lda player_x_hi
    adc move_dx+1           ; sign-extension of the unchanged Q8 movement step
    sta move_x_hi
    jsr movement_candidate_blocked
    bcs @blocked_x
    lda move_x
    sta player_x
    lda move_x+1
    sta player_x+1
    lda move_x_hi
    sta player_x_hi
    jsr commit_floor
    jmp @axis_z
@blocked_x:
    inc movement_blocked_x
    lda player_x
    sta move_x
    lda player_x+1
    sta move_x+1
    lda player_x_hi
    sta move_x_hi
@axis_z:
    lda player_z
    clc
    adc move_dz
    sta move_z
    lda player_z+1
    adc move_dz+1
    sta move_z+1
    lda player_z_hi
    adc move_dz+1
    sta move_z_hi
    jsr movement_candidate_blocked
    bcs @blocked_z
    lda move_z
    sta player_z
    lda move_z+1
    sta player_z+1
    lda move_z_hi
    sta player_z_hi
    jsr commit_floor
    rts
@blocked_z:
    inc movement_blocked_z
    rts
.endproc

; Highest floor touched by the radius-two square. The recess supports the
; player only when the ENTIRE footprint is strictly inside its rectangle.
; Exact edge or corner contact still has upper-floor support. These Q8.8
; comparisons are independent of movement history, axis, and facing angle.
.proc floor_support
    lda #OUTER_FLOOR_HEIGHT
    sta move_floor
.if ::RECESS_DEPTH <> 0
    lda move_x_hi
    cmp #>(RECESS_X_MIN+PLAYER_RADIUS)
    jcc @done
    bne @x_lower_clear
    lda move_x+1
    cmp #<(RECESS_X_MIN+PLAYER_RADIUS)
    jcc @done
    bne @x_lower_clear
    lda move_x
    jeq @done
@x_lower_clear:
    lda move_x+1
    cmp #<(RECESS_X_MAX-PLAYER_RADIUS)
    lda move_x_hi
    sbc #>(RECESS_X_MAX-PLAYER_RADIUS)
    jcs @done
    lda move_z_hi
    cmp #>(RECESS_Z_MIN+PLAYER_RADIUS)
    jcc @done
    bne @z_lower_clear
    lda move_z+1
    cmp #<(RECESS_Z_MIN+PLAYER_RADIUS)
    jcc @done
    bne @z_lower_clear
    lda move_z
    beq @done
@z_lower_clear:
    lda move_z+1
    cmp #<(RECESS_Z_MAX-PLAYER_RADIUS)
    lda move_z_hi
    sbc #>(RECESS_Z_MAX-PLAYER_RADIUS)
    jcs @done
    lda #(OUTER_FLOOR_HEIGHT-RECESS_DEPTH)
    sta move_floor
@done:
.endif
    rts
.endproc

.proc movement_candidate_blocked
    jsr door_candidate_blocked
    bcs @done
    jsr zombie_candidate_blocked
    bcs @done
    jsr footprint_blocked
    bcs @done
    jsr floor_support
    lda move_floor
    clc
    adc #PLAYER_BODY_HEIGHT
    cmp #(SCENE_CEILING+1)        ; top at ceiling is legal; beyond is blocked.
    bcs @blocked
    lda move_floor
    sec
    sbc player_floor
    bcc @clear                  ; stepping down is permitted in this prototype.
    cmp #(MAX_STEP_HEIGHT+1)
    bcs @blocked
@clear:
    clc
@done:
    rts
@blocked:
    sec
    rts
.endproc

.proc commit_floor
    lda move_floor
    sta player_floor
    clc
    adc #PLAYER_EYE_HEIGHT
    sta player_eye
    rts
.endproc

; Carry set means the candidate footprint touches a wall. Finite segment vs
; square SAT: reject on X/Z projections, then on the wall normal. Generated
; primitive normals include the original room's (3,4), (3,-4) and (1,-2),
; normalized because only absolute line distance matters. Exact Q8.8 is kept
; through diagonal calculations; a diagonal does not become a staircase.
;
; All values reaching the normal check are within the segment's expanded
; bounds. Consequently signed line distance is below 128 world units even
; where the un-subtracted expression 2X-Z exceeds 16-bit unsigned Q8.8.
.proc footprint_blocked
    lda move_x+1
    cmp #<SCENE_MIN_X
    lda move_x_hi
    sbc #>SCENE_MIN_X
    jcc @outside
    lda move_x+1
    cmp #<SCENE_MAX_X
    lda move_x_hi
    sbc #>SCENE_MAX_X
    jcs @outside
    lda move_z+1
    cmp #<SCENE_MIN_Z
    lda move_z_hi
    sbc #>SCENE_MIN_Z
    jcc @outside
    lda move_z+1
    cmp #<SCENE_MAX_Z
    lda move_z_hi
    sbc #>SCENE_MAX_Z
    jcc @in_bounds
@outside:
    sec
    rts
@in_bounds:
    ; Grid origins are 16-unit aligned. Subtract their cell coordinates from
    ; the complete integer position; retain the fractional byte unchanged.
    lda move_x+1
    lsr a
    lsr a
    lsr a
    lsr a
    sta move_line
    lda move_x_hi
    asl a
    asl a
    asl a
    asl a
    ora move_line
    sec
    sbc #(COLLISION_GRID_X_MIN / 16)
    sta move_collision_cursor   ; column, preserved while selecting the row
    lda move_z+1
    lsr a
    lsr a
    lsr a
    lsr a
    sta move_line
    lda move_z_hi
    asl a
    asl a
    asl a
    asl a
    ora move_line
    sec
    sbc #(COLLISION_GRID_Z_MIN / 16)
    tax
    lda collision_zone_row_lo,x
    sta move_collision_ptr
    lda collision_zone_row_hi,x
    sta move_collision_ptr+1
    ldy move_collision_cursor
    lda (move_collision_ptr),y
    tax
    lda collision_candidate_lo,x
    sta move_collision_ptr
    lda collision_candidate_hi,x
    sta move_collision_ptr+1
    lda collision_candidate_count,x
    sta move_collision_count
    jeq @clear
    lda #0
    sta move_collision_cursor
@segment:
    ldy move_collision_cursor
    lda (move_collision_ptr),y
    tax
    lda move_x+1
    cmp collision_xmin_lo,x
    lda move_x_hi
    sbc collision_xmin_hi,x
    jcc @next
    lda move_x_hi
    cmp collision_xmax_hi,x
    jcc @x_inside
    jne @next
    lda move_x+1
    cmp collision_xmax_lo,x
    jcc @x_inside
    jne @next
    lda move_x
    jne @next
@x_inside:
    lda move_z+1
    cmp collision_zmin_lo,x
    lda move_z_hi
    sbc collision_zmin_hi,x
    jcc @next
    lda move_z_hi
    cmp collision_zmax_hi,x
    jcc @z_inside
    jne @next
    lda move_z+1
    cmp collision_zmax_lo,x
    jcc @z_inside
    jne @next
    lda move_z
    jne @next
@z_inside:
    lda collision_mode,x
    cmp #2
    jcc @blocked                 ; Axis-aligned: X/Z SAT already suffices.
    jeq @sum
    cmp #5
    jeq @general
    cmp #4
    jeq @double_x
    lda move_x
    sta move_line
    lda move_x+1
    sta move_line+1
    jmp @subtract_z
@sum:
    lda move_x
    clc
    adc move_z
    sta move_line
    lda move_x+1
    adc move_z+1
    sta move_line+1
    jmp @subtract_plane
@double_x:
    lda move_x
    asl a
    sta move_line
    lda move_x+1
    rol a
    sta move_line+1
@subtract_z:
    lda move_line
    sec
    sbc move_z
    sta move_line
    lda move_line+1
    sbc move_z+1
    sta move_line+1
    jmp @subtract_plane
@general:
    ; Exact bounded integer normal for the source room's 3:4 chamfers and
    ; its simplified 1:2 northern edge. The expanded AABB gate above keeps
    ; the final signed line difference within128units, despite modular sums.
    lda #0
    sta move_line
    sta move_line+1
    ldy collision_nx,x
@general_x:
    lda move_line
    clc
    adc move_x
    sta move_line
    lda move_line+1
    adc move_x+1
    sta move_line+1
    dey
    jne @general_x
    lda collision_nz,x
    jmi @negative_z
    tay
@positive_z:
    lda move_line
    clc
    adc move_z
    sta move_line
    lda move_line+1
    adc move_z+1
    sta move_line+1
    dey
    jne @positive_z
    jmp @subtract_plane
@negative_z:
    eor #$FF
    clc
    adc #1
    tay
@general_sub_z:
    lda move_line
    sec
    sbc move_z
    sta move_line
    lda move_line+1
    sbc move_z+1
    sta move_line+1
    dey
    jne @general_sub_z
@subtract_plane:
    ; Plane constants are integral: no fractional subtraction is needed.
    lda move_line+1
    sec
    sbc collision_plane,x
    jpl @absolute_ready
    ; Two's complement the complete fixed-point difference.
    eor #$FF
    sta move_line+1
    lda move_line
    eor #$FF
    clc
    adc #1
    sta move_line
    lda move_line+1
    adc #0
@absolute_ready:
    cmp collision_support,x
    jcc @blocked
    jne @next
    lda move_line
    jeq @blocked
@next:
    inc move_collision_cursor
    lda move_collision_cursor
    cmp move_collision_count
    jcs @clear
    jmp @segment
@clear:
    clc
    rts
@blocked:
    sec
    rts
.endproc
