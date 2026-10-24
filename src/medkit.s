; Two persistent pickups share the existing active-encounter item slot.
; Live state and range scratch are NMI-owned; the renderer snapshots the
; selected collected flag/type under its existing NMI seqlock.
.setcpu "6502"
.include "audio-write.inc"
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
; Keep quantized axes inside the existing 256-entry square tables. The
; full 16-bit comparison also permits radii with a nonzero squared low byte.
.assert MEDKIT_PICKUP_RADIUS > 0 .and MEDKIT_PICKUP_RADIUS < 32, error, "Medkit radius exceeds square table"
.assert AMMO_PICKUP_RADIUS_EIGHTHS > 0 .and AMMO_PICKUP_RADIUS_EIGHTHS <= 31*8, error, "Ammo radius exceeds square table"

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
; Coarse whole-unit rejection rounds up; the squared threshold stays exact.
pickup_radius: .byte MEDKIT_PICKUP_RADIUS, ((AMMO_PICKUP_RADIUS_EIGHTHS+7)/8)
pickup_radius_squared_lo:
 .byte <((MEDKIT_PICKUP_RADIUS*8)*(MEDKIT_PICKUP_RADIUS*8))
 .byte <(AMMO_PICKUP_RADIUS_EIGHTHS*AMMO_PICKUP_RADIUS_EIGHTHS)
pickup_radius_squared_hi:
 .byte >((MEDKIT_PICKUP_RADIUS*8)*(MEDKIT_PICKUP_RADIUS*8))
 .byte >(AMMO_PICKUP_RADIUS_EIGHTHS*AMMO_PICKUP_RADIUS_EIGHTHS)

.segment "CODE"
.proc medkit_reset
 lda #0
 sta medkit_state
 lda #1
 sta medkit_dirty
 lda #$30
 sta pause_sound_pulse2
 AUDIO_SFX_WRITE $4004
 rts
.endproc

; A bit7=selected item collected/absent, bit6=item type; X=active encounter.
; The third encounter has no item; never index the two-item coordinate tables.
.proc medkit_selected_state
 lda medkit_state
 ldx active_encounter
 beq health
 cpx #2
 bcs absent
 asl a
 and #$80
 ora #$40
 rts
health:
 and #$80
 rts
absent:
 lda #$80
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
 cmp #2
 bcs done
 cmp #0
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
 AUDIO_SFX_WRITE $4006
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
 AUDIO_SFX_WRITE $4015
 lda #$B8
 sta pause_sound_pulse2
 AUDIO_SFX_WRITE $4004
 lda #$08
 AUDIO_SFX_WRITE $4005
 lda #$F8
 AUDIO_SFX_WRITE $4007
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
 AUDIO_SFX_WRITE $4006
 lda #$F8
 AUDIO_SFX_WRITE $4007
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
 AUDIO_SFX_WRITE $4004
 rts
.endproc

; C=1 iff ceil(|dxQ8|/32)^2 + ceil(|dzQ8|/32)^2 < (radius*8)^2.
; The conservative eighth-unit circle never expands beyond the selected
; radius: six for the medkit, three and a half for the narrower ammo clip.
; Full unsignedQ16.8 subtraction precedes absolute magnitude and far rejection;
; only proven nearby deltas enter the original low-word square tables.
.proc medkit_in_range
 ldy active_encounter
 cpy #2
 jcs outside
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
 sta zombie_square
 lda zombie_square_hi,x
 adc zombie_square+1
 jcs outside
 cmp pickup_radius_squared_hi,y
 bcc inside
 bne outside
 lda zombie_square
 cmp pickup_radius_squared_lo,y
 bcs outside
inside:
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
