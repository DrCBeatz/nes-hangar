; One permanent-open doorway at X288..304,Z120. Live state is NMI-owned.
; Requesting an opening does not release collision: the matching open world
; must actually publish first. Producer/private snapshot records are not reset.
.setcpu "6502"
.include "audio-write.inc"
.import pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.macpack longbranch
.include "coordinate-memory.inc"
.include "door-memory.inc"
.importzp player_x, player_z, pending_angle, button_edges, input_buttons
.importzp move_x, move_z, scene_version, exit_flags
.importzp zombie_attack_state, zombie_audio_timer
.import pistol_health, pistol_dirty, pistol_flash_timer
.export door_reset, door_tick, door_eligible, door_request, door_publish
.export door_candidate_blocked, door_sound_tick, door_sound_stop

DOOR_SOUND_FRAMES = 12

.segment "CODE"
.proc door_reset
 jsr door_sound_stop
 lda #0
 sta door_state
 sta door_near
 rts
.endproc

; Called after exit_tick and before encounters/pistol/zombie processing. Start,
; exit completion and death win; A+Left/Right continues to mean strafing.
.proc door_tick
 lda button_edges
 and #$10
 beq active
 jmp door_reset
active:
 lda exit_flags
 bmi inactive
 lda pistol_health
 beq inactive
 jsr door_sound_tick
 jsr door_eligible
 lda #0
 rol a
 cmp door_near
 beq input
 sta door_near
 lda pistol_dirty
 ora #4
 sta pistol_dirty
input:
 lda door_near
 beq done
 lda button_edges
 and #$80
 beq done
 lda input_buttons
 and #3
 bne done
 jmp door_request
inactive:
 jsr door_sound_stop
 lda door_near
 beq done
 lda #0
 sta door_near
 lda pistol_dirty
 ora #4
 sta pistol_dirty
done:
 rts
.endproc

; Exact Q16.8 rectangle on each legal side, across the full panel width.
; Allow +/-53 angle units (~75 degrees) from the panel normal. At close
; contact, aiming at the center from either jamb exceeds the old 45-degree
; cone. A centered panel already fills the view just beyond eight units,
; so allow twelve units of use reach. Collision and side guards are unchanged.
; North: X[288,304), Z(122,132], angle75..181.
; South: X[288,304), Z[108,118), angle203..255 or0..53.
.proc door_eligible
 lda door_state
 bne outside
 lda pistol_health
 beq outside
 lda exit_flags
 bmi outside
 lda player_x_hi
 cmp #1
 bne outside
 lda player_x+1
 cmp #32
 bcc outside
 cmp #48
 bcs outside
 lda player_z_hi
 bne outside
 lda player_z+1
 cmp #108
 bcc outside
 cmp #118
 bcc south
 cmp #122
 bcc outside
 bne north_max
 lda player_z
 beq outside
north_max:
 lda player_z+1
 cmp #132
 bcc north_angle
 bne outside
 lda player_z
 bne outside
north_angle:
 lda pending_angle
 cmp #75
 bcc outside
 cmp #182
 bcs outside
 sec
 rts
south:
 lda pending_angle
 cmp #203
 bcs inside
 cmp #54
 bcs outside
inside:
 sec
 rts
outside:
 clc
 rts
.endproc

.proc door_request
 lda door_state
 bne done
 lda #DOOR_REQUESTED
 sta door_state
 inc scene_version
 lda #0
 sta door_near
 lda pistol_dirty
 ora #4
 sta pistol_dirty
 ; Player/enemy gun tails always keep ownership of the shared noise channel.
 jsr door_sound_busy
 bcs done
 lda #DOOR_SOUND_FRAMES
 sta door_sound_timer
 lda #$0B
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda #$16
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #$0B
 AUDIO_SFX_WRITE $400E
 lda #$F8
 AUDIO_SFX_WRITE $400F
done:
 rts
.endproc

; The publisher calls this only after the matching PPU view becomes visible.
; A stale/open picture after Start cannot reopen a freshly closed live door.
.proc door_publish
 lda door_state
 cmp #DOOR_REQUESTED
 bne done
 lda visible_door
 beq done
 lda #DOOR_OPEN
 sta door_state
done:
 rts
.endproc

; C=1 exactly when the radius-two candidate square touches the closed finite
; panel, including contact at an endpoint. Reject all higher-page aliases.
.proc door_candidate_blocked
 lda door_state
 cmp #DOOR_OPEN
 bcs clear
 lda move_x_hi
 cmp #1
 bne clear
 lda move_x+1
 cmp #30
 bcc clear
 cmp #50
 bcc check_z
 bne clear
 lda move_x
 bne clear
check_z:
 lda move_z_hi
 bne clear
 lda move_z+1
 cmp #118
 bcc clear
 cmp #122
 bcc blocked
 bne clear
 lda move_z
 bne clear
blocked:
 sec
 rts
clear:
 clc
 rts
.endproc

; C=1 means a higher-priority effect owns the shared noise channel. The exit
; chime must never be interrupted, including by a stale door-tail stop.
.proc door_sound_busy
 lda exit_flags
 bmi busy
 lda pistol_flash_timer
 bne busy
 lda zombie_attack_state
 cmp #3
 bne clear
 lda zombie_audio_timer
 bne busy
clear:
 clc
 rts
busy:
 sec
 rts
.endproc

.proc door_sound_tick
 lda door_sound_timer
 beq done
 jsr door_sound_busy
 bcs drop
 dec door_sound_timer
 beq silence
 lda door_sound_timer
 lsr a
 ora #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda door_sound_timer
 lsr a
 lsr a
 ora #8
 AUDIO_SFX_WRITE $400E
done:
 rts
drop:
 lda #0
 sta door_sound_timer
 rts
silence:
 lda #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #3
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 rts
.endproc

.proc door_sound_stop
 lda door_sound_timer
 beq done
 lda #0
 sta door_sound_timer
 jsr door_sound_busy
 bcs done
 lda #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #3
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
done:
 rts
.endproc
