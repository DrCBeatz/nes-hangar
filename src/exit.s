; Temporary exit interaction. All state is NMI-owned and occupies two formerly
; unused walkable ZP slots. Eligibility is based on the current live pose; the
; prompt and completion text use the existing independently refreshed HUD.
.setcpu "6502"
.import pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.include "coordinate-memory.inc"
.macpack longbranch
.importzp player_x, player_z, pending_angle, button_edges, input_buttons
.importzp exit_flags, exit_sound_timer, player_hurt_timer
.import pistol_health, pistol_dirty, pistol_cooldown, pistol_flash_timer, pistol_pose
.import zombie_attack_cancel, zombie_hit_flash, zombie_dirty
.import door_reset
.import results_capture
.export exit_tick, exit_eligible, exit_complete, exit_reset, exit_sound_tick
.include "exit-config.inc"

.segment "CODE"
.proc exit_reset
 jsr door_reset
 lda #0
 sta exit_flags
 sta exit_sound_timer
 lda #$30
 sta pause_sound_pulse1
 sta $4000
 rts
.endproc

.proc exit_tick
 ; Reset wins over an A/B press and clears the old chime before weapon/enemy
 ; resets execute later in this same NMI.
 lda button_edges
 and #$10
 beq active
 jmp exit_reset
active:
 lda exit_flags
 bpl eligible
 jmp exit_sound_tick
eligible:
 jsr exit_eligible
 lda #0
 rol a
 cmp exit_flags
 beq input
 sta exit_flags
 lda pistol_dirty
 ora #4
 sta pistol_dirty
input:
 lda exit_flags
 beq done
 lda button_edges
 and #$80                  ; fresh A, not an A held while approaching the switch
 beq done
 lda input_buttons
 and #3                    ; A+Left/Right remains strafe, never exit activation
 bne done
 jmp exit_complete
done:
 rts
.endproc

; C=1 only for a living player inside the activation rectangle, facing the
; configured wall. Inclusive z maximum is exact Q16.8, not the entire final unit.
.proc exit_eligible
 lda pistol_health
 jeq outside
 lda player_x_hi
 cmp #>EXIT_X_MIN
 jcc outside
 bne x_min_ok
 lda player_x+1
 cmp #<EXIT_X_MIN
 jcc outside
x_min_ok:
 lda player_x_hi
 cmp #>EXIT_X_MAX
 bcc x_max_ok
 jne outside
 lda player_x+1
 cmp #<EXIT_X_MAX
 jcs outside
x_max_ok:
 lda player_z_hi
 cmp #>EXIT_Z_MIN
 jcc outside
 bne z_min_ok
 lda player_z+1
 cmp #<EXIT_Z_MIN
 jcc outside
z_min_ok:
 lda player_z_hi
 cmp #>EXIT_Z_MAX
 bcc angle
 jne outside
 lda player_z+1
 cmp #<EXIT_Z_MAX
 bcc angle
 bne outside
 lda player_z
 bne outside
angle:
 lda pending_angle
 cmp #EXIT_ANGLE_MIN
 bcc outside
 cmp #(EXIT_ANGLE_MAX+1)
 bcs outside
 sec
 rts
outside:
 clc
 rts
.endproc

.proc exit_complete
 ; Called ahead of weapon and enemy tick. Existing health and ammunition are
 ; preserved. Clear every live attack effect before giving pulse1 to the chime.
 lda #$80
 sta exit_flags
 jsr results_capture        ; freeze complete counts before any later NMI ticks
 jsr zombie_attack_cancel
 lda #0
 sta pistol_cooldown
 sta pistol_flash_timer
 sta pistol_pose
 sta player_hurt_timer
 sta zombie_hit_flash
 lda #15                   ; idle pistol, existing counters, complete text, white HUD
 sta pistol_dirty
 lda #1
 sta zombie_dirty
 ora #$04                  ; retain the independent pause-cue triangle
 sta $4015                 ; stop either gun's noise, enable pulse1 only
 lda #$10
 sta pause_sound_noise
 sta $400C
 lda #32
 sta exit_sound_timer
 lda #$B8                  ; half duty, length halt, constant volume8
 sta pause_sound_pulse1
 sta $4000
 lda #$08
 sta $4001
 lda #$FD                  ; approximately A4 at stock NTSC CPU clock
 sta $4002
 lda #$F8
 sta $4003
 rts
.endproc

.proc exit_sound_tick
 lda exit_sound_timer
 beq done
 dec exit_sound_timer
 beq stop
 lda exit_sound_timer
 cmp #16
 bne done
 lda #$A9                  ; second note approximately E5
 sta $4002
 lda #$F8
 sta $4003
done:
 rts
stop:
 lda #$30
 sta pause_sound_pulse1
 sta $4000
 rts
.endproc
