; Fixed-screen weapon and live HUD, owned exclusively by reset/NMI.
; The world producer never reads or modifies this state. PPU work happens only
; in pistol_init (rendering disabled) or a dedicated pistol_upload VBlank.
.setcpu "6502"
.include "audio-write.inc"
.import pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.macpack longbranch
.importzp input_buttons, button_edges, zombie_oam_ptr
.importzp exit_flags
.import zombie_damage
.import slime_reset, pause_active
.export player_message_upload
.include "door-memory.inc"
.export pistol_prepare_oam
.export pistol_init, pistol_tick, pistol_reset, pistol_upload
.export pistol_shot_accepted, pistol_upload_done
.export pistol_dry_fire_accepted
.export pistol_state_begin, pistol_state_end
.export player_damage, player_heal, player_add_ammo, player_defeat, player_feedback_tick
.exportzp player_hurt_timer
.export pistol_health, pistol_ammo, pistol_cooldown, pistol_flash_timer
.export pistol_pose, pistol_dirty, pistol_shot_count, pistol_digits

PISTOL_COOLDOWN = 15          ; four shots/second at normal NTSC timing
PISTOL_FLASH_FRAMES = 6       ; independently timed 100 ms flash/recoil
PISTOL_DRY_FRAMES = 8         ; 133 ms low empty-gun buzz, only on a fresh B press
.include "ammo-config.inc"
.include "balance-config.inc"

.segment "ZEROPAGE"
player_hurt_timer: .res 1     ; NMI-owned; zero health keeps the HUD red

.segment "BSS"
pistol_state_begin:
pistol_health: .res 1
pistol_ammo: .res 1
pistol_cooldown: .res 1
pistol_flash_timer: .res 1    ; bit7 = sound-only empty-gun cue; low7 = noise frames
pistol_pose: .res 1           ; 0 idle, 1 firing art
pistol_dirty: .res 1          ; bit0 OAM, bit1 digits, bit2 status line, bit3 HUD color
pistol_shot_count: .res 2
pistol_digits: .res 6         ; health then ammo; already encoded font tiles
pistol_decimal_value: .res 1  ; NMI-private conversion scratch
pistol_state_end:

.segment "RODATA"
.include "pistol-assets.inc"
.segment "CODE"
.include "player-feedback.inc"
.segment "RODATA"
pistol_sprite_x:
.repeat 16, I
 .byte PISTOL_X + (I .mod 4)*8
.endrepeat
pistol_sprite_y:
.repeat 16, I
 .byte PISTOL_Y + (I / 4)*8
.endrepeat
; All 64 sprite Y values start hidden. No DMA shadow or main-thread scratch.
pistol_hidden_oam:
.repeat 64
 .byte $FF,0,0,0
.endrepeat
; Index is remaining fire frames after decrement; constant-volume white noise.
pistol_noise_volume: .byte 0,3,5,7,9,12,15

; Reset-only setup: bank2 selected, rendering and NMI disabled.
.segment "BOOTDATA"
.proc pistol_init
 lda #0
 sta $2003
 ldx #0
@hide:
 lda pistol_hidden_oam,x
 sta $2004
 inx
 bne @hide
 lda #0
 sta $2003
 ; Palette zero is the gun; palette one gives the flash amber and white.
 ; Universal background entries remain $0F, matching the world palette.
 lda #$3F
 sta $2006
 lda #$10
 sta $2006
 ldx #0
@palette:
 lda pistol_palette,x
 sta $2007
 inx
 cpx #8
 bne @palette
 jsr pistol_reset
 jmp pistol_upload
.endproc

.segment "CODE"
.proc pistol_reset
 jsr slime_reset
 lda #100
 sta pistol_health
 lda #PISTOL_STARTING_AMMO
 sta pistol_ammo
 lda #0
 sta pistol_cooldown
 sta pistol_flash_timer
 sta pistol_pose
 sta pistol_shot_count
 sta pistol_shot_count+1
 sta player_hurt_timer
 lda #1                    ; reset drops either gun's noise; enemy reset owns pulse
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda #15
 sta pistol_dirty
 ldx #0
 lda pistol_health
 jsr pistol_decimal
 ldx #3
 lda pistol_ammo
 jmp pistol_decimal
.endproc

.proc pistol_tick
 ; Reset wins over a simultaneously held fire button.
 lda button_edges
 and #$10
 beq @timers
 jmp pistol_reset
@timers:
 lda exit_flags
 jmi done
 jsr player_feedback_tick
 lda pistol_cooldown
 beq :+
 dec pistol_cooldown
:
 lda pistol_flash_timer
 beq @input
 bpl @flash
 ; Keep the existing shared-noise ownership byte nonzero during the cue,
 ; without selecting firing art, touching HUD/OAM dirty bits or firing a shot.
 dec pistol_flash_timer
 lda pistol_flash_timer
 cmp #$80
 bne @input
 lda #0
 sta pistol_flash_timer
 lda #$30
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #$07                   ; stop noise; retain both pulse cues and triangle
 AUDIO_SFX_WRITE $4015
 jmp @input
@flash:
 dec pistol_flash_timer
 beq @idle
 ldx pistol_flash_timer
 lda pistol_noise_volume,x
 ora #$10
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 jmp @input
@idle:
 lda #0
 sta pistol_pose
 lda #3                    ; enemy cannot own noise; preserve the pickup pulse2
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda pistol_dirty
 ora #1
 sta pistol_dirty
@input:
 lda pistol_health
 jeq done
 lda input_buttons
 and #$40
 beq done
 lda pistol_cooldown
 bne done
 lda pistol_ammo
 beq dry_fire
accepted:
 jsr zombie_damage
 dec pistol_ammo
 inc pistol_shot_count
 bne :+
 inc pistol_shot_count+1
:
 lda #PISTOL_COOLDOWN
 sta pistol_cooldown
 lda #PISTOL_FLASH_FRAMES
 sta pistol_flash_timer
 lda #1
 sta pistol_pose
 lda pistol_dirty
 ora #3
 sta pistol_dirty
 ldx #3
 lda pistol_ammo
 jsr pistol_decimal
 ; Player shots take the shared noise channel immediately. The later enemy
 ; tick observes pistol_flash_timer and drops any old enemy tail permanently.
 ; The pulse warning can coexist. Bit 7 clear selects white noise.
 lda #$0B                  ; both pulse cues remain enabled alongside gun noise
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda #$1F
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #$06
 AUDIO_SFX_WRITE $400E
 lda #$F8
 AUDIO_SFX_WRITE $400F
done:
 rts
dry_fire:
 lda button_edges
 and #$40
 beq done                   ; holding an empty trigger never repeats the cue
dry_accepted:
 lda #PISTOL_COOLDOWN
 sta pistol_cooldown
 lda #($80 | PISTOL_DRY_FRAMES)
 sta pistol_flash_timer
 ; Short-mode noise is a low, sustained buzz, distinct from either gun's
 ; long-mode white-noise blast. Existing player priority also cancels a door
 ; or enemy noise tail; warning/pickup pulse channels remain independent.
 lda #$0F
 AUDIO_SFX_WRITE $4015
 lda #$1A                   ; constant volume10, no length-counter halt
 sta pause_sound_noise
 AUDIO_SFX_WRITE $400C
 lda #$8C                   ; short LFSR, period12: deep empty-trigger buzz
 AUDIO_SFX_WRITE $400E
 lda #$F8
 AUDIO_SFX_WRITE $400F
 rts
.endproc
pistol_shot_accepted = pistol_tick::accepted
pistol_dry_fire_accepted = pistol_tick::dry_accepted

; A=damage. Saturate health at zero; schedule graphics for a later VBlank.
; Called after player input/weapon processing, never from the PPU upload path.
.proc player_damage
 ldx exit_flags
 bmi done
 sta pistol_decimal_value
 lda pistol_health
 beq done
 sec
 sbc pistol_decimal_value
 bcs :+
 lda #0
:
 sta pistol_health
 beq defeat
 lda #12
 sta player_hurt_timer
 lda pistol_dirty
 ora #10                   ; live digits + brief red HUD/title feedback
 sta pistol_dirty
 jmp digits
defeat:
 lda #0
 sta player_hurt_timer
 sta pistol_flash_timer
 sta pistol_pose
 sta pistol_cooldown
 lda #1
 ora #$04                  ; retain the independent pause-cue triangle
 AUDIO_SFX_WRITE $4015
 lda #15                   ; status text uses its own following overlay VBlank
 sta pistol_dirty
digits:
 ldx #0
 lda pistol_health
 jsr pistol_decimal
done:
 rts
.endproc
player_defeat = player_damage::defeat

; A=healing. A living player below100 gains health, capped at100. C=1 only
; when health actually changes, so a full-health pickup can remain available.
; Use the existing HUD digits; a recent damage flash retains its normal timer.
.proc player_heal
 ldx exit_flags
 bmi unchanged
 sta pistol_decimal_value
 cmp #0
 beq unchanged
 lda pistol_health
 beq unchanged
 cmp #100
 bcs unchanged
 clc
 adc pistol_decimal_value
 bcs maximum
 cmp #100
 bcc store
maximum:
 lda #100
store:
 sta pistol_health
 lda pistol_dirty
 ora #2
 sta pistol_dirty
 ldx #0
 lda pistol_health
 jsr pistol_decimal
 sec
 rts
unchanged:
 clc
 rts
.endproc

; A=ammo amount. Living/noncompleted players gain ammo, saturated at99.
; C=1 only on a real change; dirty digits preserve every other HUD/OAM flag.
.proc player_add_ammo
 ldx exit_flags
 bmi unchanged
 sta pistol_decimal_value
 cmp #0
 beq unchanged
 lda pistol_health
 beq unchanged
 lda pistol_ammo
 cmp #AMMO_MAXIMUM
 bcs unchanged
 clc
 adc pistol_decimal_value
 bcs maximum
 cmp #AMMO_MAXIMUM
 bcc store
maximum:
 lda #AMMO_MAXIMUM
store:
 sta pistol_ammo
 lda pistol_dirty
 ora #2
 sta pistol_dirty
 ldx #3
 lda pistol_ammo
 jsr pistol_decimal
 sec
 rts
unchanged:
 clc
 rts
.endproc

.proc player_feedback_tick
 lda player_hurt_timer
 beq done
 dec player_hurt_timer
 bne done
 lda pistol_dirty
 ora #8
 sta pistol_dirty
done:
 rts
.endproc

; A = byte value, X = first destination digit index (0 or 3).
; This runs after the final PPU write, never in the upload's VBlank budget.
.proc pistol_decimal
 sta pistol_decimal_value
 ldy #0
@hundreds:
 cmp #100
 bcc @hundred_digit
 sbc #100
 iny
 bne @hundreds
@hundred_digit:
 sta pistol_decimal_value
 tya
 clc
 adc #FONT_ZERO_TILE
 sta pistol_digits,x
 inx
 lda pistol_decimal_value
 ldy #0
@tens:
 cmp #10
 bcc @ten_digit
 sbc #10
 iny
 bne @tens
@ten_digit:
 sta pistol_decimal_value
 tya
 clc
 adc #FONT_ZERO_TILE
 sta pistol_digits,x
 inx
 lda pistol_decimal_value
 clc
 adc #FONT_ZERO_TILE
 sta pistol_digits,x
 rts
.endproc

.proc pistol_upload
 lda pistol_dirty
 and #3
 jeq secondary
 lda pistol_dirty
 and #1
 beq @hud
 lda #0
 sta $2003
 ldx #0
 lda pistol_pose
 bne @fire
@idle:
 lda pistol_sprite_y,x
 sta $2004
 lda pistol_idle_tiles,x
 sta $2004
 lda pistol_idle_attributes,x
 sta $2004
 lda pistol_sprite_x,x
 sta $2004
 inx
 cpx #16
 bne @idle
 jmp @oam_done
@fire:
 lda pistol_sprite_y,x
 sta $2004
 lda pistol_fire_tiles,x
 sta $2004
 lda pistol_fire_attributes,x
 sta $2004
 lda pistol_sprite_x,x
 sta $2004
 inx
 cpx #16
 bne @fire
@oam_done:
 ; OAMADDR must be zero when visible rendering resumes.
 lda #0
 sta $2003
@hud:
 lda pistol_dirty
 and #2
 beq @done
 ; Both nametables receive the same current counters. They are outside the
 ; producer's 18 viewport rows and cannot be overwritten by a stale view.
.repeat 2, BANK
 lda #>(HUD_HEALTH_ADDR + BANK*$800)
 sta $2006
 lda #<(HUD_HEALTH_ADDR + BANK*$800)
 sta $2006
.repeat 3, DIGIT
 lda pistol_digits+DIGIT
 sta $2007
.endrepeat
 lda #>(HUD_AMMO_ADDR + BANK*$800)
 sta $2006
 lda #<(HUD_AMMO_ADDR + BANK*$800)
 sta $2006
.repeat 3, DIGIT
 lda pistol_digits+3+DIGIT
 sta $2007
.endrepeat
.endrepeat
@done:
 lda pistol_dirty
 and #$FC                  ; status line deliberately deferred one refresh
 sta pistol_dirty
 jsr player_palette_upload
 jmp done
secondary:
 lda pistol_dirty
 and #4
 beq :+
 jsr player_message_upload
:
 jsr player_palette_upload
done:
 rts
.endproc
pistol_upload_done = pistol_upload::done

.proc player_palette_upload
 lda pistol_dirty
 and #8
 beq done
 lda #$3F
 sta $2006
 lda #$05
 sta $2006
 lda pistol_health
 beq red
 lda player_hurt_timer
 bne red
 lda #$30
 bne color
red:
 lda #$16
color:
 sta $2007
 lda pistol_dirty
 and #$F7
 sta pistol_dirty
done:
 rts
.endproc

; Both status rows are outside the producer-owned viewport. Install them in a
; separate overlay refresh so OAM/health/weapon work retains its VBlank budget.
.proc player_message_upload
 lda pause_active
 bne paused
 lda pistol_health
 beq dead
 lda exit_flags
 bmi complete
 and #1
 bne exit_prompt
 lda door_near
 bne door_prompt
 ldx #(player_alive_line-player_alive_line)
 beq copy
paused:
 ldx #(player_pause_line-player_alive_line)
 bne copy
dead:
 ldx #(player_dead_line-player_alive_line)
 bne copy
complete:
 ldx #(player_complete_line-player_alive_line)
 bne copy
exit_prompt:
 ldx #(player_exit_line-player_alive_line)
 bne copy
door_prompt:
 ldx #(player_door_line-player_alive_line)
copy:
 ; Eight-byte chunks retain a short dedicated VBlank upload while sharing
 ; the identical copier across all messages. X selects a32-byte row.
 .repeat 2, BANK
 lda #>(HUD_MESSAGE_ADDR + BANK*$800)
 sta $2006
 lda #<(HUD_MESSAGE_ADDR + BANK*$800)
 sta $2006
 ldy #4
 .scope
chunk:
 .repeat 8, I
 lda player_alive_line+I,x
 sta $2007
 .endrepeat
 txa
 clc
 adc #8
 tax
 dey
 bne chunk
 .endscope
 .if BANK = 0
 txa
 sec
 sbc #32
 tax
 .endif
 .endrepeat
finish:
 lda pistol_dirty
 and #$FB
 sta pistol_dirty
 rts
.endproc

; Merge the current independently-timed weapon into the staged publication.
; Fixed absolute stores avoid the index/indirect loop inside the tight NTSC
; publication VBlank. Each pose/bank copies precisely the same64 source bytes.
; This permanently mapped ROM bank can hold callable routines as well as data.
.segment "RODATA"
.macro PREPARE_WEAPON bank, tiles, attributes
 .repeat 16,I
 lda pistol_sprite_y+I
 sta bank+I*4
 lda tiles+I
 sta bank+I*4+1
 lda attributes+I
 sta bank+I*4+2
 lda pistol_sprite_x+I
 sta bank+I*4+3
 .endrepeat
 rts
.endmacro
.proc pistol_prepare_oam
 lda zombie_oam_ptr+1
 cmp #$6F
 jeq bank0
 lda pistol_pose
 jne bank1_fire
 PREPARE_WEAPON $7F00,pistol_idle_tiles,pistol_idle_attributes
bank1_fire:
 PREPARE_WEAPON $7F00,pistol_fire_tiles,pistol_fire_attributes
bank0:
 lda pistol_pose
 jne bank0_fire
 PREPARE_WEAPON $6F00,pistol_idle_tiles,pistol_idle_attributes
bank0_fire:
 PREPARE_WEAPON $6F00,pistol_fire_tiles,pistol_fire_attributes
.endproc
