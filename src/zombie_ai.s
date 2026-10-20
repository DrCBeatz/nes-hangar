; NMI-owned slow pursuit. Geometry is read only; all scratch is NMI-private.
; Live movement is 50 Hz, steering/LOS every 8 ticks. No pathfinding.
.setcpu "6502"
.include "coordinate-memory.inc"
.import coordinate_abs_delta
.macpack longbranch
.importzp player_x, player_z, simulation_count, movement_scratch_begin
.import zombie_hp, zombie_hit_flash, zombie_delta, zombie_square, zombie_coord, zombie_palette_offset
.import zombie_square_lo, zombie_square_hi
.importzp zombie_attack_state
.import zombie_attack_consider, pistol_health
.import active_encounter, encounter_line_of_sight, encounter_next_epoch
.exportzp zombie_x, zombie_z, zombie_epoch, zombie_alert
.exportzp zombie_ai_last_tick, zombie_ai_count, zombie_step_x, zombie_step_z
.exportzp zombie_walk_counter
.export zombie_ai_reset, zombie_ai_handoff, zombie_ai_tick, zombie_line_of_sight, zombie_steer, zombie_separated
.include "zombie-config.inc"
.segment "ZEROPAGE"
zombie_x: .res 2
zombie_z: .res 2
zombie_epoch: .res 1
zombie_ai_last_tick: .res 1
zombie_ai_count: .res 1
zombie_step_x: .res 1
zombie_step_z: .res 1
zombie_alert: .res 1
; Bit 5 chooses the walk pose: 32 successful 50 Hz steps per pose. Advance
; once per actual move, never for a blocked axis or a paused simulation tick.
zombie_walk_counter: .res 1

; Preserve movement diagnostic counters and live floor/eye at offsets11..14.
ai_sign = movement_scratch_begin
ai_dx = movement_scratch_begin+1
ai_dz = movement_scratch_begin+3
ai_a = movement_scratch_begin+5       ; four-byte shifted multiplicand
ai_b = movement_scratch_begin+9       ; two-byte multiplier
ai_result = movement_scratch_begin+15 ; four-byte result
ai_loop = movement_scratch_begin+19
ai_first = zombie_delta              ; four contiguous delta/square bytes
ai_index = zombie_coord
ai_first_sign = zombie_palette_offset
; NMI-exclusive aliases: LOS localization and movement candidate high bytes
; have disjoint lifetimes. Close-range absolute delta uses only scratch+2.
ai_candidate_x_hi = coordinate_nmi_scratch
ai_candidate_z_hi = coordinate_nmi_scratch+1
ai_player_ix = coordinate_nmi_scratch
ai_player_iz = coordinate_nmi_scratch+1
ai_zombie_ix = coordinate_nmi_scratch+2
ai_zombie_iz = coordinate_nmi_scratch+3

.segment "RODATA"
.include "zombie-ai-data.inc"
.segment "RODATA"
.proc zombie_ai_reset
 lda #0
 sta zombie_x
 sta zombie_z
 lda #<ZOMBIE_X
 sta zombie_x+1
 lda #>ZOMBIE_X
 sta zombie_x_hi
 lda #<ZOMBIE_Z
 sta zombie_z+1
 lda #>ZOMBIE_Z
 sta zombie_z_hi
 jsr zombie_ai_handoff
 jsr encounter_next_epoch
 rts
.endproc

.proc zombie_ai_tick
 lda simulation_count
 cmp zombie_ai_last_tick
 jeq done
 sta zombie_ai_last_tick
 lda zombie_hp
 jeq done
 lda pistol_health
 jeq done
 lda zombie_attack_state
 jne done
 lda zombie_hit_flash
 jne done
 lda zombie_ai_count
 beq decide
 dec zombie_ai_count
 jmp advance
decide:
 lda #7
 sta zombie_ai_count
 jsr zombie_line_of_sight
 lda #0
 rol a
 sta zombie_alert
 beq idle
 jsr zombie_attack_consider
 lda zombie_attack_state
 jne done
 jsr zombie_steer
 jmp advance
idle:
 lda #0
 sta zombie_step_x
 sta zombie_step_z
advance:
 lda zombie_alert
 jeq done
 lda #0
 sta ai_sign                  ; movement-only flag; LOS/steering are finished
 ; X then Z permits sliding along the encounter rectangle and player circle.
 lda zombie_step_x
 jeq axis_z                   ; a zero velocity is not a successful move
 lda zombie_x
 clc
 adc zombie_step_x
 sta ai_a
 lda #0
 ldx zombie_step_x
 bpl :+
 lda #$FF
:
 adc zombie_x+1
 sta ai_a+1
 lda #0
 ldx zombie_step_x
 bpl :+
 lda #$FF
:
 adc zombie_x_hi
 sta ai_candidate_x_hi
 lda zombie_z
 sta ai_a+2
 lda zombie_z+1
 sta ai_a+3
 lda zombie_z_hi
 sta ai_candidate_z_hi
 ldy active_encounter
 lda ai_candidate_x_hi
 cmp zombie_ai_x_min_hi,y
 jcc axis_z
 bne x_min_ok
 lda ai_a+1
 cmp zombie_ai_x_min_lo,y
 jcc axis_z
x_min_ok:
 lda ai_candidate_x_hi
 cmp zombie_ai_x_max_hi,y
 jcc try_x
 jne axis_z
 lda ai_a+1
 cmp zombie_ai_x_max_lo,y
 jcc try_x
 jne axis_z
 lda ai_a
 jne axis_z
try_x:
 jsr zombie_separated
 bcc axis_z
 lda ai_a
 sta zombie_x
 lda ai_a+1
 sta zombie_x+1
 lda ai_candidate_x_hi
 sta zombie_x_hi
 lda #1
 sta ai_sign
axis_z:
 lda zombie_step_z
 jeq finish_walk
 lda zombie_x
 sta ai_a
 lda zombie_x+1
 sta ai_a+1
 lda zombie_x_hi
 sta ai_candidate_x_hi
 lda zombie_z
 clc
 adc zombie_step_z
 sta ai_a+2
 lda #0
 ldx zombie_step_z
 bpl :+
 lda #$FF
:
 adc zombie_z+1
 sta ai_a+3
 lda #0
 ldx zombie_step_z
 bpl :+
 lda #$FF
:
 adc zombie_z_hi
 sta ai_candidate_z_hi
 ldy active_encounter
 lda ai_candidate_z_hi
 cmp zombie_ai_z_min_hi,y
 jcc finish_walk
 bne z_min_ok
 lda ai_a+3
 cmp zombie_ai_z_min_lo,y
 jcc finish_walk
z_min_ok:
 lda ai_candidate_z_hi
 cmp zombie_ai_z_max_hi,y
 jcc try_z
 jne finish_walk
 lda ai_a+3
 cmp zombie_ai_z_max_lo,y
 jcc try_z
 jne finish_walk
 lda ai_a+2
 jne finish_walk
try_z:
 jsr zombie_separated
 bcc finish_walk
 lda ai_a+2
 sta zombie_z
 lda ai_a+3
 sta zombie_z+1
 lda ai_candidate_z_hi
 sta zombie_z_hi
 lda #1
 sta ai_sign
finish_walk:
 lda ai_sign
 beq done
 inc zombie_walk_counter
done:
 rts
.endproc

; Candidate ai_a[4] versus live player. C=1 if quantized radius9 is clear.
; Quantization rounds distance down, so accepted candidates are never too close.
.proc zombie_separated
 .if ::AI_INNER_ENABLED
 jsr ai_inner_separated
 bcs :+
 rts
:
 .endif
 lda ai_a
 sec
 sbc player_x
 sta zombie_delta
 lda ai_a+1
 sbc player_x+1
 sta zombie_delta+1
 lda ai_candidate_x_hi
 sbc player_x_hi
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs clear
 jsr normalized_stop
 jcs clear
 tax
 lda zombie_square_lo,x
 sta zombie_square
 lda zombie_square_hi,x
 sta zombie_square+1
 lda ai_a+2
 sec
 sbc player_z
 sta zombie_delta
 lda ai_a+3
 sbc player_z+1
 sta zombie_delta+1
 lda ai_candidate_z_hi
 sbc player_z_hi
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs clear
 jsr normalized_stop
 jcs clear
 tax
 lda zombie_square_lo,x
 clc
 adc zombie_square
 lda zombie_square_hi,x
 adc zombie_square+1
 jcs clear
 cmp #$51                    ; 144 squared =20736, fractional axes floor Q4
 rts
clear:
 sec
 rts
.endproc
.proc negate_delta
 lda #0
 sec
 sbc zombie_delta
 sta zombie_delta
 lda #0
 sbc zombie_delta+1
 sta zombie_delta+1
 rts
.endproc
.proc normalized_stop
 lda zombie_delta+1
 cmp #9
 bcs done
 asl a
 asl a
 asl a
 asl a
 sta zombie_coord
 lda zombie_delta
 lsr a
 lsr a
 lsr a
 lsr a
 ora zombie_coord
 clc
done:
 rts
.endproc

; Rounded integer displacement determines an eight-direction-like proportional
; velocity: major8, minor floor(8*minor/major), with at most1/256 step quantization.
.proc zombie_steer
 lda #8
 sta zombie_step_x
 sta zombie_step_z
 lda player_x
 sec
 sbc zombie_x
 sta zombie_delta
 lda player_x+1
 sbc zombie_x+1
 sta zombie_delta+1
 lda player_x_hi
 sbc zombie_x_hi
 sta coordinate_nmi_scratch+2
 bcs :+
 lda #$F8
 sta zombie_step_x
:
 jsr coordinate_abs_delta
 lda zombie_delta
 cmp #128
 lda zombie_delta+1
 adc #0
 sta ai_dx
 lda coordinate_nmi_scratch+2
 adc #0
 sta ai_dx+1
 lda player_z
 sec
 sbc zombie_z
 sta zombie_delta
 lda player_z+1
 sbc zombie_z+1
 sta zombie_delta+1
 lda player_z_hi
 sbc zombie_z_hi
 sta coordinate_nmi_scratch+2
 bcs :+
 lda #$F8
 sta zombie_step_z
:
 jsr coordinate_abs_delta
 lda zombie_delta
 cmp #128
 lda zombie_delta+1
 adc #0
 sta ai_dz
 lda coordinate_nmi_scratch+2
 adc #0
 sta ai_dz+1
scale_ratio:
 lda ai_dx+1
 ora ai_dz+1
 beq scaled
 lsr ai_dx+1
 ror ai_dx
 lsr ai_dz+1
 ror ai_dz
 jmp scale_ratio
scaled:
 lda #0
 sta ai_sign
 lda ai_dx
 cmp ai_dz
 bcs x_major
 lda #1
 sta ai_sign
 lda ai_dx
 sta ai_b
 lda ai_dz
 sta ai_b+1
 jmp divide
x_major:
 lda ai_dz
 sta ai_b
 lda ai_dx
 sta ai_b+1
divide:
 lda ai_b+1
 beq zero
 lda #0
 sta ai_a
 sta ai_a+1
 sta ai_result
 lda #8
 sta ai_loop
loop_bit:
 lda ai_a
 clc
 adc ai_b
 sta ai_a
 lda ai_a+1
 adc #0
 sta ai_a+1
 bne subtract
 lda ai_a
 cmp ai_b+1
 jcc next
subtract:
 lda ai_a
 sec
 sbc ai_b+1
 sta ai_a
 lda ai_a+1
 sbc #0
 sta ai_a+1
 inc ai_result
next:
 dec ai_loop
 bne loop_bit
 lda ai_sign
 bne set_x
 lda ai_result
 ldx zombie_step_z
 bpl :+
 eor #$FF
 clc
 adc #1
:
 sta zombie_step_z
 rts
set_x:
 lda ai_result
 ldx zombie_step_x
 bpl :+
 eor #$FF
 clc
 adc #1
:
 sta zombie_step_x
 rts
zero:
 lda #0
 sta zombie_step_x
 sta zombie_step_z
 rts
.endproc

; Exact LOS inside the preserved legacy sight polygon. ai_localize first
; rejects the new passage/room east ofx240, including fractional crossings.
; Every admitted legal position with x>=120 lies in the old convex encounter
; rectangle. Else actor is
; to the right; the X-monotone polygon becomes lower/upper corner inequalities.
; F=(actorZ-cornerZ)*(actorX-playerX)+(playerZ-actorZ)*(actorX-cornerX).
; Every complete piecewise-linear boundary is bounded by these vertices.
.proc zombie_line_of_sight
 lda active_encounter
 beq primary
 jmp encounter_line_of_sight
primary:
 jsr ai_localize
 jcc hidden
 ; Exact empty visibility regions: the doorway constraints require slope<1
 ; and z>x+40 for x<=104. Reaching x<=72 would also require crossing z<=104
 ; at x72, contradicting z>112. Legal player footprints are assumed.
 lda ai_player_ix
 cmp #72
 jcc hidden
 bne wedge_gate
 lda player_x
 jeq hidden
wedge_gate:
 lda ai_player_ix
 cmp #104
 bcc wedge
 bne room_gate
 lda player_x
 bne room_gate
wedge:
 lda ai_player_ix
 clc
 adc #40
 cmp ai_player_iz
 bcc room_gate
 jne hidden
 lda player_z
 cmp player_x
 jcc hidden
 jeq hidden
room_gate:
 lda ai_player_ix
 cmp #120
 jcs visible
 lda zombie_x
 sec
 sbc player_x
 sta ai_dx
 lda ai_zombie_ix
 sbc ai_player_ix
 sta ai_dx+1
 lda player_z
 sec
 sbc zombie_z
 sta ai_dz
 lda ai_player_iz
 sbc ai_zombie_iz
 sta ai_dz+1
 lda #0
 bcs dz_ready
 lda #0
 sec
 sbc ai_dz
 sta ai_dz
 lda #0
 sbc ai_dz+1
 sta ai_dz+1
 lda #$80
dz_ready:
 sta ai_sign
 lda #0
 sta ai_index
corner:
 ldx ai_index
 lda zombie_ai_corner_x,x
 cmp ai_player_ix
 jcc next
 bne test
 lda player_x
 bne next
test:
 lda zombie_x
 sta ai_a
 lda ai_zombie_ix
 sec
 sbc zombie_ai_corner_x,x
 sta ai_a+1
 lda ai_dz
 sta ai_b
 lda ai_dz+1
 sta ai_b+1
 jsr multiply
 .repeat 4,I
 lda ai_result+I
 sta ai_first+I
 .endrepeat
 lda ai_sign
 sta ai_first_sign
 ldx ai_index
 lda zombie_z
 sta ai_a
 lda ai_zombie_iz
 sec
 sbc zombie_ai_corner_z,x
 sta ai_a+1
 lda #0
 bcs corner_z_ready
 lda #0
 sec
 sbc ai_a
 sta ai_a
 lda #0
 sbc ai_a+1
 sta ai_a+1
 lda #$80
corner_z_ready:
 pha
 lda ai_dx
 sta ai_b
 lda ai_dx+1
 sta ai_b+1
 jsr multiply
 pla
 jsr sum_sign
 beq hidden
 sta ai_b
 ldx ai_index
 ldy zombie_ai_corner_upper,x
 bne upper
 lda ai_b
 bmi hidden
 jmp next
upper:
 lda ai_b
 bpl hidden
next:
 inc ai_index
 lda ai_index
 cmp #ZOMBIE_AI_CONSTRAINTS
 jne corner
visible:
 .if ::AI_INNER_ENABLED
 jmp ai_inner_line_of_sight
 .else
 sec
 rts
 .endif
hidden:
 clc
 rts
.endproc

; A gives sign of ai_result; ai_first_sign gives sign of ai_first. Return
; A=$80 negative,1 positive,0 exactly zero; only comparison, no overflow risk.
.proc sum_sign
 sta ai_b
 eor ai_first_sign
 bmi opposite
 lda ai_result
 ora ai_result+1
 ora ai_result+2
 ora ai_result+3
 ora ai_first
 ora ai_first+1
 ora ai_first+2
 ora ai_first+3
 beq done
 lda ai_b
 ora #1
 rts
opposite:
 ldx #3
compare:
 lda ai_result,x
 cmp ai_first,x
 bne different
 dex
 bpl compare
 lda #0
 rts
different:
 bcc first_larger
 lda ai_b
 ora #1
 rts
first_larger:
 lda ai_first_sign
 ora #1
done:
 rts
.endproc

; Unsigned16x16->32. Inputs ai_a[0..1],ai_b[0..1]; high input cleared here.
.proc multiply
 lda #0
 sta ai_a+2
 sta ai_a+3
 sta ai_result
 sta ai_result+1
 sta ai_result+2
 sta ai_result+3
 lda #16
 sta ai_loop
loop_bit:
 lsr ai_b+1
 ror ai_b
 bcc shift
 clc
 .repeat 4,I
 lda ai_result+I
 adc ai_a+I
 sta ai_result+I
 .endrepeat
shift:
 asl ai_a
 rol ai_a+1
 rol ai_a+2
 rol ai_a+3
 dec ai_loop
 bne loop_bit
 rts
.endproc

; C=1 when both global positions fit the original authored AI domain after
; translation. The next passage and zigzag room lie strictly east ofx240;
; reject them conservatively so the old constraints cannot see through bends.
; The asset generator proves additions preserve this domain and its walls.
; This is an AI-local calculation, not the world's coordinate
; representation; all persistent positions/snapshots remain full Q16.8.
.proc ai_localize
 lda player_x+1
 sec
 sbc #<AI_ORIGIN_X
 sta ai_player_ix
 lda player_x_hi
 sbc #>AI_ORIGIN_X
 jne outside
 lda player_z+1
 sec
 sbc #<AI_ORIGIN_Z
 sta ai_player_iz
 lda player_z_hi
 sbc #>AI_ORIGIN_Z
 jne outside
 lda zombie_x+1
 sec
 sbc #<AI_ORIGIN_X
 sta ai_zombie_ix
 lda zombie_x_hi
 sbc #>AI_ORIGIN_X
 jne outside
 lda zombie_z+1
 sec
 sbc #<AI_ORIGIN_Z
 sta ai_zombie_iz
 lda zombie_z_hi
 sbc #>AI_ORIGIN_Z
 jne outside
 lda ai_player_ix
 cmp #8
 bcc outside
 cmp #240
 bcc :+
 bne outside
 lda player_x
 bne outside
:
 lda ai_player_iz
 cmp #8
 bcc outside
 cmp #208
 bcc :+
 bne outside
 lda player_z
 bne outside
:
 lda ai_zombie_ix
 cmp #132
 bcc outside
 cmp #238
 bcc :+
 bne outside
 lda zombie_x
 bne outside
:
 lda ai_zombie_iz
 cmp #114
 bcc outside
 cmp #206
 bcc :+
 bne outside
 lda zombie_z
 bne outside
:
 sec
 rts
outside:
 clc
 rts
.endproc

; Reset only transient pursuit state when changing the active persistent actor.
; Coordinates, HP, epoch and cumulative combat counters belong to the caller.
.segment "CODE"
.proc zombie_ai_handoff
 lda #0
 sta zombie_ai_count
 sta zombie_alert
 sta zombie_step_x
 sta zombie_step_z
 sta zombie_walk_counter
 lda simulation_count
 sta zombie_ai_last_tick
 rts
.endproc

; Fixed CODE keeps NMI-private obstacle tests out of the full common window.
; The only interior occluder is a sealed, full-height axis-aligned rectangle.
; ai_localize has already established the local 0..255-coordinate domain.
.segment "CODE"
.if ::AI_INNER_ENABLED
.export ai_inner_line_of_sight, ai_inner_separated

; Candidate ai_a Q16.8 center must stay outside the radius-two-expanded box.
; Do not alter candidate bytes, high bytes or the AI's successful-axis flag.
.proc ai_inner_separated
 lda active_encounter
 bne clear
 lda ai_candidate_x_hi
 cmp #>AI_INNER_MOVE_X_MIN
 bne clear
 lda ai_a+1
 cmp #<AI_INNER_MOVE_X_MIN
 bcc clear
 cmp #<AI_INNER_MOVE_X_MAX
 bcc x_inside
 bne clear
 lda ai_a
 bne clear
x_inside:
 lda ai_candidate_z_hi
 cmp #>AI_INNER_MOVE_Z_MIN
 bne clear
 lda ai_a+3
 cmp #<AI_INNER_MOVE_Z_MIN
 bcc clear
 cmp #<AI_INNER_MOVE_Z_MAX
 bcc blocked
 bne clear
 lda ai_a+2
 bne clear
blocked:
 clc
 rts
clear:
 sec
 rts
.endproc

; Separating-axis test for an exact finite sight segment and the closed box.
; First reject disjoint X/Z intervals. Only overlapping intervals need the
; two extreme corner orientations, reusing the existing exact 16x16 products.
; Touching an edge/corner blocks sight. No quantized sampling or divisions.
.proc ai_inner_line_of_sight
 .repeat 2,AXIS
 .if AXIS = 0
 INNER_MIN .set ::AI_INNER_X_MIN
 INNER_MAX .set ::AI_INNER_X_MAX
 .else
 INNER_MIN .set ::AI_INNER_Z_MIN
 INNER_MAX .set ::AI_INNER_Z_MAX
 .endif
 lda ai_player_ix+AXIS
 cmp #INNER_MIN
 bcs :+
 lda ai_zombie_ix+AXIS
 cmp #INNER_MIN
 jcc clear
:
 lda ai_player_ix+AXIS
 cmp #(INNER_MAX+1)
 bcc :+
 lda ai_zombie_ix+AXIS
 cmp #(INNER_MAX+1)
 jcs clear
:
 .endrepeat
 ; Absolute deltas and their signs, bit7=dx negative, bit6=dz negative.
 ldx #0
 ldy #0
 jsr delta
 sta ai_sign
 lda ai_a
 sta ai_dx
 lda ai_a+1
 sta ai_dx+1
 ldx #1
 ldy #2
 jsr delta
 lsr a
 ora ai_sign
 sta ai_sign
 lda ai_a
 sta ai_dz
 lda ai_a+1
 sta ai_dz+1
 lda #0
 sta ai_index
 jsr corner
 ; Minimum cross product >0 puts the entire rectangle above the line.
 beq opposite
 bpl clear
opposite:
 lda #$80
 sta ai_index
 jsr corner
 ; Maximum cross product <0 puts the entire rectangle below the line.
 bmi clear
 clc
 rts
clear:
 sec
 rts

; Absolute player-minus-actor displacement. X local-axis index, Y word offset.
delta:
 lda player_x,y
 sec
 sbc zombie_x,y
 sta ai_a
 lda ai_player_ix,x
 sbc ai_zombie_ix,x
 sta ai_a+1
 jmp absolute

; The sign of dx*(cornerZ-actorZ)-dz*(cornerX-actorX). Select the minimum
; corner for ai_index=0 and the opposite maximum corner for ai_index=$80.
corner:
 lda ai_sign
 eor ai_index
 bmi z_max
 lda #AI_INNER_Z_MIN
 bne z_ready
z_max:
 lda #AI_INNER_Z_MAX
z_ready:
 sta ai_a+1
 lda #0
 sec
 sbc zombie_z
 sta ai_a
 lda ai_a+1
 sbc ai_zombie_iz
 sta ai_a+1
 jsr absolute
 eor ai_sign
 and #$80
 sta ai_first_sign
 lda ai_dx
 sta ai_b
 lda ai_dx+1
 sta ai_b+1
 jsr multiply
 .repeat 4,I
 lda ai_result+I
 sta ai_first+I
 .endrepeat
 lda ai_sign
 asl a
 eor ai_index
 bmi x_min
 lda #AI_INNER_X_MAX
 bne x_ready
x_min:
 lda #AI_INNER_X_MIN
x_ready:
 sta ai_a+1
 lda #0
 sec
 sbc zombie_x
 sta ai_a
 lda ai_a+1
 sbc ai_zombie_ix
 sta ai_a+1
 jsr absolute
 pha
 lda ai_dz
 sta ai_b
 lda ai_dz+1
 sta ai_b+1
 jsr multiply
 pla
 sta ai_b
 lda ai_sign
 asl a
 eor ai_b
 eor #$80
 and #$80
 jmp sum_sign

; Carry describes the preceding subtraction. Return its sign in A and the
; unsigned magnitude in ai_a[0..1]. Neither X nor Y is changed.
absolute:
 lda #0
 bcs abs_done
 sec
 sbc ai_a
 sta ai_a
 lda #0
 sbc ai_a+1
 sta ai_a+1
 lda #$80
abs_done:
 rts
.endproc
.endif
