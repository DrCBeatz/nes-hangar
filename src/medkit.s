; Two persistent pickups share the existing active-encounter item slot.
; Live state and range scratch are NMI-owned; the renderer snapshots the
; selected collected flag/type under its existing NMI seqlock.
.setcpu "6502"
.import pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.include "coordinate-memory.inc"
.macpack longbranch
.import coordinate_abs_delta
.importzp player_x, player_z, button_edges, scene_version, exit_flags
.importzp medkit_state
.import medkit_dirty, pistol_health, pistol_ammo, player_heal, player_add_ammo
.import active_encounter
.import zombie_delta, zombie_square, zombie_coord
.import zombie_square_lo, zombie_square_hi
.export medkit_reset, medkit_tick, medkit_in_range, medkit_collect
.export medkit_sound_stop, medkit_sound_tick
.export medkit_selected_state, ammo_collect
.export medkit_collect_commit, ammo_collect_commit
.export pickup_x_lo, pickup_x_hi, pickup_z_lo, pickup_z_hi
.include "medkit-config.inc"
.include "ammo-config.inc"
; Squared radii must be whole high bytes for the comparison below. Keep the
; quantized axes inside the existing 256-entry square tables.
.assert MEDKIT_PICKUP_RADIUS > 0 .and MEDKIT_PICKUP_RADIUS < 32, error, "Medkit radius exceeds square table"
.assert AMMO_PICKUP_RADIUS > 0 .and AMMO_PICKUP_RADIUS < 32, error, "Ammo radius exceeds square table"
.assert <((MEDKIT_PICKUP_RADIUS*8)*(MEDKIT_PICKUP_RADIUS*8)) = 0, error, "Medkit squared radius needs a low-byte comparison"
.assert <((AMMO_PICKUP_RADIUS*8)*(AMMO_PICKUP_RADIUS*8)) = 0, error, "Ammo squared radius needs a low-byte comparison"

; bit7 health collected, bit6 ammo collected, bit5 ammo sound type;
; low five bits count the independent pulse2 sound, regardless of active area.
MEDKIT_COLLECTED = $80
AMMO_COLLECTED = $40
MEDKIT_SOUND_FRAMES = 16
AMMO_SOUND_FRAMES = 12

.segment "RODATA"
pickup_x_lo: .byte <MEDKIT_X, <AMMO_X
pickup_x_hi: .byte >MEDKIT_X, >AMMO_X
pickup_z_lo: .byte <MEDKIT_Z, <AMMO_Z
pickup_z_hi: .byte >MEDKIT_Z, >AMMO_Z
pickup_radius: .byte MEDKIT_PICKUP_RADIUS, AMMO_PICKUP_RADIUS
pickup_radius_squared_hi:
 .byte >((MEDKIT_PICKUP_RADIUS*8)*(MEDKIT_PICKUP_RADIUS*8))
 .byte >((AMMO_PICKUP_RADIUS*8)*(AMMO_PICKUP_RADIUS*8))

.segment "CODE"
.proc medkit_reset
 lda #0
 sta medkit_state
 lda #1
 sta medkit_dirty
 lda #$30
 sta pause_sound_pulse2
 sta $4004
 rts
.endproc

; A bit7=selected item collected, bit6=item type; X=active encounter.
.proc medkit_selected_state
 lda medkit_state
 ldx active_encounter
 beq health
 asl a
 and #$80
 ora #$40
 rts
health:
 and #$80
 rts
.endproc

.proc medkit_tick
 ; Start wins over every possible pickup. The normal combat resets have
 ; already restored health, ammo and the enemy before this routine runs.
 lda button_edges
 and #$10
 beq active
 jmp medkit_reset
active:
 lda exit_flags
 bmi stop
 lda pistol_health
 beq stop                   ; fatal damage earlier this NMI wins over collection
 jsr medkit_sound_tick      ; finish a prior area's chime after a handoff
 jsr medkit_selected_state
 bmi done
 cpx #0
 bne ammo
 lda pistol_health
 cmp #100
 bcs done                   ; full health leaves the pack available on the floor
 bcc range
ammo:
 lda pistol_ammo
 cmp #AMMO_MAXIMUM
 bcs done                   ; full ammo leaves this independent pack available
range:
 jsr medkit_in_range
 bcc done
 jmp medkit_collect
stop:
 jmp medkit_sound_stop
done:
 rts
.endproc

.proc medkit_collect
 lda active_encounter
 bne ammo_collect
 ; Independent collected guards let either pickup be collected first.
 lda medkit_state
 bmi done
 lda #MEDKIT_HEAL
 jsr player_heal
 bcc done
 ldx #(MEDKIT_COLLECTED+MEDKIT_SOUND_FRAMES)
 lda #$A9                   ; E5, followed by B5 after eight refreshes
 bne pickup_sound_start
done:
 rts
.endproc

.proc ammo_collect
 lda medkit_state
 and #AMMO_COLLECTED
 bne done
 lda #AMMO_AMOUNT
 jsr player_add_ammo
 bcc done
 ldx #(AMMO_COLLECTED+$20+AMMO_SOUND_FRAMES)
 lda #$54                   ; distinct shorter descending E6-to-G5 cue
 bne pickup_sound_start
done:
 rts
.endproc

.proc pickup_sound_start
 sta $4006
 lda medkit_state
 and #$C0
 sta medkit_state
 txa
 ora medkit_state
 sta medkit_state
 lda #1
 sta medkit_dirty
 inc scene_version          ; invalidate an in-flight picture containing the pack
commit:
 ; Pulse2 is independent of both gun noises and the pulse1 attack/exit cue.
 ; Enabling all three channels does not restart a noise length counter.
 lda #$0B
 ora #$04                  ; retain the independent pause-cue triangle
 sta $4015
 lda #$B8
 sta pause_sound_pulse2
 sta $4004
 lda #$08
 sta $4005
 lda #$F8
 sta $4007
 rts
.endproc
medkit_collect_commit = pickup_sound_start::commit
ammo_collect_commit = pickup_sound_start::commit

.proc medkit_sound_tick
 lda medkit_state
 and #$1F
 beq done
 dec medkit_state
 lda medkit_state
 and #$1F
 beq stop
 cmp #8
 bne done
 lda medkit_state
 and #$20
 beq health
 lda #$8E
 bne note
health:
 lda #$70
note:
 sta $4006
 lda #$F8
 sta $4007
done:
 rts
stop:
 jmp medkit_sound_stop
.endproc

.proc medkit_sound_stop
 lda medkit_state
 and #$C0
 sta medkit_state
 lda #$30
 sta pause_sound_pulse2
 sta $4004
 rts
.endproc

; C=1 iff ceil(|dxQ8|/32)^2 + ceil(|dzQ8|/32)^2 < (radius*8)^2.
; The conservative eighth-unit circle never expands beyond the selected
; radius: six for the medkit, four for the narrower ammo clip.
; Full unsignedQ16.8 subtraction precedes absolute magnitude and far rejection;
; only proven nearby deltas enter the original low-word square tables.
.proc medkit_in_range
 ldy active_encounter
 lda player_x
 sec
 sbc #0
 sta zombie_delta
 lda player_x+1
 sbc pickup_x_lo,y
 sta zombie_delta+1
 lda player_x_hi
 sbc pickup_x_hi,y
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs outside
 jsr quantize_axis
 jcs outside
 tax
 lda zombie_square_lo,x
 sta zombie_square
 lda zombie_square_hi,x
 sta zombie_square+1
 lda player_z
 sec
 sbc #0
 sta zombie_delta
 lda player_z+1
 sbc pickup_z_lo,y
 sta zombie_delta+1
 lda player_z_hi
 sbc pickup_z_hi,y
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs outside
 jsr quantize_axis
 jcs outside
 tax
 clc
 lda zombie_square_lo,x
 adc zombie_square
 lda zombie_square_hi,x
 adc zombie_square+1
 jcs outside
 cmp pickup_radius_squared_hi,y
 jcs outside                ; squared radii $0900/$0400 need no low-byte test
 sec
 rts
outside:
 clc
 rts
.endproc

.proc quantize_axis
 lda zombie_delta+1
 cmp pickup_radius,y
 bcs done
 lda zombie_delta
 clc
 adc #31
 sta zombie_coord
 lda zombie_delta+1
 adc #0
 asl a
 asl a
 asl a
 sta zombie_delta+1
 lda zombie_coord
 lsr a
 lsr a
 lsr a
 lsr a
 lsr a
 ora zombie_delta+1
 clc
done:
 rts
.endproc
