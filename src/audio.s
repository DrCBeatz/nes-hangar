; Four-channel mixer for the original effects and lower-priority music.
; Reset runs from the boot bank with NMI disabled; the mixer always remains
; in fixed ROM. Neither routine changes the mapper or borrows ZP scratch. The music engine writes only audio_music_regs.
.setcpu "6502"
.include "door-memory.inc"
.import title_state, pause_active, pause_cue_timer, results_screen_state
.import pistol_health, pistol_flash_timer
.importzp exit_flags, exit_sound_timer, medkit_state
.importzp zombie_attack_state, zombie_audio_timer
.export audio_reset, audio_mix
.export audio_music_regs, audio_sfx_regs, audio_sfx_trigger, audio_music_active
.export audio_seen_trigger, audio_owner, audio_high
.export audio_driver_begin, audio_driver_end

; Music addresses retain their APU offsets, including the engine's init-only
; writes to $4015/$4017. SFX $4015 masks are retained for diagnostics but do not
; control hardware: an old effect must never disable an unrelated music voice.
.segment "AUDIO_DRIVER"
audio_driver_begin:
audio_music_regs: .res 24
audio_sfx_regs: .res 24
audio_sfx_trigger: .res 4
audio_seen_trigger: .res 4
audio_owner: .res 4          ; 0 silent,1 music,2 original effect
audio_high: .res 4           ; last high-register value sent to hardware
audio_music_active: .res 1   ; root music driver: initialized and eligible
audio_selected: .res 1
audio_transition: .res 1
audio_game_active: .res 1
audio_music_eligible: .res 1
audio_driver_end:
.assert audio_sfx_regs = audio_music_regs + 24, error, "Mixer shadows must be adjacent"
.assert audio_driver_end - audio_driver_begin <= 91, error, "Audio driver exceeds reserved workspace"

.segment "BOOTDATA"

; Called only by music_init with boot bank2 selected and rendering/NMI off.
; Initialization needs no permanently mapped ROM; the mixer below does.
; Existing effect timers were initialized earlier by their reset routines.
.proc audio_reset
 lda #0
 ldx #(audio_driver_end - audio_driver_begin - 1)
clear:
 sta audio_driver_begin,x
 dex
 bpl clear
 lda #$30
 sta audio_music_regs+$00
 sta audio_music_regs+$04
 sta audio_music_regs+$0C
 sta audio_sfx_regs+$00
 sta audio_sfx_regs+$04
 sta audio_sfx_regs+$0C
 sta $4000
 sta $4004
 sta $400C
 lda #$80
 sta audio_music_regs+$08
 sta audio_sfx_regs+$08
 sta $4008
 ; All existing effects and the minimal music engine disable sweep. Smooth
 ; vibrato/phase-reset features requiring $4017 writes are not enabled.
 lda #$08
 sta audio_music_regs+$01
 sta audio_music_regs+$05
 sta audio_sfx_regs+$01
 sta audio_sfx_regs+$05
 sta $4001
 sta $4005
 lda #$0F
 sta audio_music_regs+$15
 sta audio_sfx_regs+$15
 sta $4015                 ; enable four native channels; DPCM remains off
 rts
.endproc

.segment "AUDIO_CODE"

; A=desired owner, Y=channel. Returns X=shadow offset (0 music,24 effect),
; audio_selected=owner, audio_transition!=0 when a high write is required.
; Consume trigger counters even when an effect was cancelled before mixing.
.proc audio_choose
 sta audio_selected
 ldx #0
 stx audio_transition
 cmp audio_owner,y
 beq same_owner
 sta audio_owner,y
 inc audio_transition
same_owner:
 lda audio_sfx_trigger,y
 cmp audio_seen_trigger,y
 sta audio_seen_trigger,y
 beq selected
 lda audio_selected
 cmp #2
 bne selected
 inc audio_transition
selected:
 ldx #0
 lda audio_selected
 cmp #2
 bne done
 ldx #24
done:
 rts
.endproc

; All output paths share phase-safe high-register handling. Both music and
; the existing effects use constant-volume software envelopes, so writing a
; volume/linear register each refresh does not restart a hardware envelope.
.macro AUDIO_CHANNEL_OUTPUT volume, low, high, silence
 .local quiet, reload, done
 lda audio_selected
 beq quiet
 lda audio_music_regs+(volume-$4000),x
 sta volume
 lda audio_music_regs+(low-$4000),x
 sta low
 lda audio_transition
 bne reload
 lda audio_music_regs+(high-$4000),x
 cmp audio_high,y
 beq done
reload:
 lda audio_music_regs+(high-$4000),x
 sta audio_high,y
 sta high
 jmp done
quiet:
 lda #silence
 sta volume
done:
.endmacro

.proc audio_pulse1
 lda #0
 ldx title_state
 bne selected
 ldx exit_sound_timer
 bne effect
 lda audio_music_eligible
 ldx audio_game_active
 beq selected
 ldx zombie_attack_state
 cpx #2
 bne selected
 ldx zombie_audio_timer
 beq selected
effect:
 lda #2
selected:
 ldy #0
 jsr audio_choose
 AUDIO_CHANNEL_OUTPUT $4000,$4002,$4003,$30
 rts
.endproc

.proc audio_pulse2
 lda audio_game_active
 beq music
 lda medkit_state
 and #$1F
 beq music
 lda #2
 bne selected
music:
 lda audio_music_eligible
selected:
 ldy #1
 jsr audio_choose
 AUDIO_CHANNEL_OUTPUT $4004,$4006,$4007,$30
 rts
.endproc

.proc audio_noise
 lda audio_game_active
 beq music
 lda pistol_flash_timer
 bne effect
 lda zombie_attack_state
 cmp #3
 bne door
 lda zombie_audio_timer
 bne effect
door:
 lda door_sound_timer
 bne effect
music:
 lda audio_music_eligible
 jmp selected
effect:
 lda #2
selected:
 ldy #3
 jsr audio_choose
 AUDIO_CHANNEL_OUTPUT $400C,$400E,$400F,$30
 rts
.endproc

.proc audio_triangle
 lda pause_cue_timer
 beq music
 lda #2
 bne selected
music:
 lda audio_music_eligible
selected:
 ldy #2
 jsr audio_choose
 ; All triangle sources keep control/length-halt bit7 set. Once $400B sets
 ; the linear reload flag, that flag stays set; changing $4008 alone updates
 ; the reload value on the next quarter-frame. There is no need to rewrite
 ; $400B every frame, but takeover/resume must reload it after another owner.
 AUDIO_CHANNEL_OUTPUT $4008,$400A,$400B,$80
 rts
.endproc

.proc audio_mix
 lda #0
 sta audio_game_active
 sta audio_music_eligible
 lda title_state
 bne channels
 lda results_screen_state
 bne channels
 lda exit_flags
 bmi channels
 lda pistol_health
 beq channels
 inc audio_game_active
 lda pause_active
 bne channels
 lda audio_music_active
 beq channels
 lda #1
 sta audio_music_eligible
channels:
 lda pause_active
 beq normal
 ; Retain pulse/noise owner and high-register caches while paused. Existing
 ; pause_resume restores the SFX shadow volumes. Resuming the same source
 ; does not reset its pulse phase or paused hardware length counter.
 lda #$30
 sta $4000
 sta $4004
 sta $400C
 jmp triangle
normal:
 jsr audio_pulse1
 jsr audio_pulse2
 jsr audio_noise
triangle:
 jmp audio_triangle
.endproc
