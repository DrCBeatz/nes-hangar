; NMI-owned ranged combat, independent of producer/world publication cadence.
; The pending state cannot deal damage. Its timer starts only when the amber
; palette has actually reached a currently published, same-life actor sprite.
.setcpu "6502"
.include "audio-write.inc"
.import pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.include "coordinate-memory.inc"
.macpack longbranch
.import coordinate_abs_delta
.importzp player_x, player_z, zombie_x, zombie_z, zombie_epoch, visible_zombie_epoch
.import zombie_hp, zombie_hit_flash, zombie_visible, zombie_dirty
.import zombie_delta, zombie_square, zombie_coord, zombie_square_lo, zombie_square_hi
.import zombie_line_of_sight, pistol_health, pistol_flash_timer, player_damage
.exportzp zombie_attack_state, zombie_attack_timer, zombie_audio_timer, zombie_attack_shots
.exportzp zombie_fire_flash
.export zombie_attack_hits, zombie_attack_warnings
.export zombie_attack_reset, zombie_attack_cancel, zombie_attack_tick
.export zombie_attack_consider, zombie_attack_warning_uploaded, zombie_attack_in_range
.export zombie_attack_fire, zombie_attack_damage
.export zombie_attack_firing_uploaded, zombie_attack_noise_stop

ZOMBIE_ATTACK_RANGE = 24
ZOMBIE_WINDUP_FRAMES = 60
ZOMBIE_COOLDOWN_FRAMES = 90
ZOMBIE_ATTACK_DAMAGE = 10
ZOMBIE_FIRE_FLASH_FRAMES = 6
ZOMBIE_NOISE_FRAMES = 5

.segment "ZEROPAGE"
zombie_attack_state: .res 1     ; 0 idle, 1 cue pending, 2 windup, 3 cooldown
zombie_attack_timer: .res 1
zombie_audio_timer: .res 1      ; state2 pulse warning; state3 owned noise tail
zombie_attack_shots: .res 1
zombie_fire_flash: .res 1       ; $80 awaiting palette upload, else visible timer
.segment "BSS"
zombie_attack_hits: .res 1
zombie_attack_warnings: .res 1
.segment "RODATA"
zombie_noise_volume: .byte 0,1,3,6,10,15
.segment "CODE"

.proc zombie_attack_reset
 jsr zombie_attack_cancel
 lda #0
 sta zombie_attack_shots
 sta zombie_attack_hits
 sta zombie_attack_warnings
 sta zombie_attack_state
 sta zombie_attack_timer
 sta zombie_audio_timer
 sta zombie_fire_flash
 lda #$30
 sta pause_sound_pulse1
 AUDIO_SFX_WRITE $4000
 lda #$08
 AUDIO_SFX_WRITE $4001
 rts
.endproc

.proc zombie_attack_cancel
 lda zombie_attack_state
 ora zombie_audio_timer
 ora zombie_fire_flash
 beq done
 lda zombie_attack_state
 cmp #3
 bne clear
 lda zombie_audio_timer
 jeq clear
 jsr zombie_attack_noise_stop
clear:
 lda #0
 sta zombie_attack_state
 sta zombie_attack_timer
 sta zombie_audio_timer
 sta zombie_fire_flash
 lda #$30                      ; silence pulse 1; preserve pistol noise enable
 sta pause_sound_pulse1
 AUDIO_SFX_WRITE $4000
 lda #1
 sta zombie_dirty
 done:
 rts
.endproc

; The pistol owns the shared noise channel whenever its flash timer is live.
; Never silence or alter that envelope when cancelling an enemy sound.
.proc zombie_attack_noise_stop
 lda pistol_flash_timer
 bne done
 lda #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #3                       ; preserve warning pulse1 and pickup pulse2
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
done:
 rts
.endproc

; Called only by an AI decision with fresh, successful live line of sight.
.proc zombie_attack_consider
 lda zombie_attack_state
 bne done
 lda pistol_health
 beq done
 lda zombie_hp
 beq done
 lda zombie_hit_flash
 bne done
 lda zombie_visible
 beq done
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne done
 jsr zombie_attack_in_range
 bcc done
 lda #1
 sta zombie_attack_state
 sta zombie_dirty
 done:
 rts
.endproc

; The shot is generated after this refresh's PPU work. Start the flash lifetime
; only once its pale palette is installed. The same-NMI decrement and the
; following overlay restore together make exactly six visible refreshes.
.proc zombie_attack_firing_uploaded
 lda zombie_fire_flash
 bpl done
 lda #ZOMBIE_FIRE_FLASH_FRAMES
 sta zombie_fire_flash
done:
 rts
.endproc

; Called after the three actor palette bytes have reached PPU palette RAM.
; Guarding lifecycle and current visibility here prevents a cue for old OAM.
.proc zombie_attack_warning_uploaded
 lda zombie_attack_state
 cmp #1
 bne done
 lda zombie_hp
 beq cancel
 lda pistol_health
 beq cancel
 lda zombie_visible
 beq cancel
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne cancel
 lda #2
 sta zombie_attack_state
 ; This upload precedes zombie_tick in the same NMI. The first decrement leaves
 ; 60: damage cannot occur until 60 subsequent refreshes after the visible cue.
 lda #(ZOMBIE_WINDUP_FRAMES+1)
 sta zombie_attack_timer
 inc zombie_attack_warnings
 lda #9
 sta zombie_audio_timer
 lda #$BF                      ; half duty, constant volume 15
 sta pause_sound_pulse1
 AUDIO_SFX_WRITE $4000
 lda #$08                      ; disable sweep; negate avoids pulse sweep mute
 AUDIO_SFX_WRITE $4001
 lda #$90
 AUDIO_SFX_WRITE $4002
 lda #$F9
 AUDIO_SFX_WRITE $4003
 done:
 rts
 cancel:
 jmp zombie_attack_cancel
.endproc

.proc zombie_attack_tick
 lda zombie_hp
 jeq cancel
 lda pistol_health
 jeq cancel
 lda zombie_hit_flash
 jne cancel
 lda zombie_audio_timer
 beq flash
 lda zombie_attack_state
 cmp #3
 beq noise
 dec zombie_audio_timer
 bne flash
 lda #$30
 sta pause_sound_pulse1
 AUDIO_SFX_WRITE $4000
 jmp flash
noise:
 ; A player shot can preempt this tail. Drop it permanently rather than
 ; restarting the enemy sound when the player's own envelope finishes.
 lda pistol_flash_timer
 beq noise_tick
 lda #0
 sta zombie_audio_timer
 beq flash
noise_tick:
 dec zombie_audio_timer
 beq noise_done
 ldx zombie_audio_timer
 lda zombie_noise_volume,x
 ora #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 jmp flash
noise_done:
 jsr zombie_attack_noise_stop
flash:
 lda zombie_fire_flash
 beq state
 bmi state                    ; pending: wait for the actual palette upload
 dec zombie_fire_flash
 bne state
 lda #1
 sta zombie_dirty
state:
 lda zombie_attack_state
 cmp #1
 beq pending
 cmp #2
 beq windup
 cmp #3
 bne done
 dec zombie_attack_timer
 bne done
 lda #0
 sta zombie_attack_state
 rts
pending:
 ; A world publication can hide the actor before the dedicated overlay VBlank.
 ; In that case discard the pending attack and wait for a genuine visible cue.
 lda zombie_visible
 beq cancel
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne cancel
 rts
windup:
 dec zombie_attack_timer
 bne done
fire:
 ; Cooldown also ensures AI cannot perform another LOS evaluation this NMI.
 lda #3
 sta zombie_attack_state
 lda #ZOMBIE_COOLDOWN_FRAMES
 sta zombie_attack_timer
 lda #1
 sta zombie_dirty
 inc zombie_attack_shots
 lda #$80
 sta zombie_fire_flash
 ; Both guns use white noise. A currently sounding player shot wins, even
 ; when it missed the enemy and therefore did not interrupt this attack.
 lda pistol_flash_timer
 bne damage_check
 lda #ZOMBIE_NOISE_FRAMES
 sta zombie_audio_timer
 lda #$0B                      ; preserve both independent pulse cue channels
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda #$1F
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #$07                      ; bit7 clear: long-mode white noise, lower gun tone
 AUDIO_SFX_WRITE $400E
 lda #$F8
 AUDIO_SFX_WRITE $400F
damage_check:
 jsr zombie_attack_in_range
 bcc done
 jsr zombie_line_of_sight
 bcc done
damage:
 inc zombie_attack_hits
 lda #ZOMBIE_ATTACK_DAMAGE
 jsr player_damage
 lda pistol_health
 beq cancel
 done:
 rts
cancel:
 jmp zombie_attack_cancel
.endproc
zombie_attack_fire = zombie_attack_tick::fire
zombie_attack_damage = zombie_attack_tick::damage

; C=1 iff the player is conservatively inside the 24-unit circular range.
; Ceil each absolute Q8.8 axis to 1/8 unit, then compare squared Q3 distance.
; This never expands the hit range, and costs no multiply or divide routine.
.proc zombie_attack_in_range
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
 sbc zombie_z
 sta zombie_delta
 lda player_z+1
 sbc zombie_z+1
 sta zombie_delta+1
 lda player_z_hi
 sbc zombie_z_hi
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs outside
 jsr quantize_axis
 jcs outside
 tax
 lda zombie_square_lo,x
 clc
 adc zombie_square
 lda zombie_square_hi,x
 adc zombie_square+1
 jcs outside
 cmp #$90                      ; (24 * 8)^2 = 36864
 jcs outside
 sec
 rts
outside:
 clc
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
.proc quantize_axis
 lda zombie_delta+1
 cmp #ZOMBIE_ATTACK_RANGE
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
