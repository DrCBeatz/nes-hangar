; NMI-owned pause. The producer may finish an acquired job, then parks.
; Pausing never changes buffer ownership, live state, mapper or sound timers.
.setcpu "6502"
.include "audio-write.inc"
.include "pause-memory.inc"
.importzp button_edges, input_buttons, visible_control
.import pistol_health, player_message_upload, results_screen_state
.export pause_active, pause_sound_pulse1, pause_sound_pulse2, pause_sound_noise
.export pause_init, pause_poll, pause_enter, pause_resume
.export pause_cue_tick, pause_cue_timer, pause_cue_direction
.export pause_cue_note, pause_cue_stop, pause_title_upload

.segment "CODE"
.include "pause-title.inc"
pause_cue_first: .byte 84,126
pause_cue_second: .byte 126,84

; Reset-only setup: bank2 selected, NMI disabled.
.segment "BOOTDATA"
.proc pause_init
 lda #0
 sta pause_active
 sta pause_cue_timer
 sta pause_cue_direction
 lda #$80                 ; triangle linear reload0, control/length halt set
 AUDIO_SFX_WRITE $4008
 lda #$30
 sta pause_sound_pulse1
 sta pause_sound_pulse2
 sta pause_sound_noise
 ; Treat Start as already held after power-on/full completion restart. The
 ; next controller read rearms it on release, so the restarting press cannot
 ; immediately pause the fresh level. Other buttons retain normal sampling.
 lda #$10
 sta input_buttons
 rts
.endproc

.segment "CODE"
; Called immediately after controller sampling, before any publication or tick.
; C=1 skips the entire ordinary NMI, including on the resume refresh. Start's
; edge is therefore never delivered to the legacy reset helpers while alive.
; The death screen retains those helpers; completion has its own NMI gateway.
.proc pause_poll
 lda button_edges
 and #$10
 beq held
 lda pistol_health
 beq running
 lda pause_active
 bne resume
enter:
 lda #1
 sta pause_active
 ; Constant volume zero + halt hardware length counters. Software envelopes
 ; and timers are untouched; do not disable channels through $4015.
 lda #$30
 AUDIO_SFX_WRITE $4000
 AUDIO_SFX_WRITE $4004
 AUDIO_SFX_WRITE $400C
 jmp message
resume:
 lda #0
 sta pause_active
 lda pause_sound_pulse1
 AUDIO_SFX_WRITE $4000
 lda pause_sound_pulse2
 AUDIO_SFX_WRITE $4004
 lda pause_sound_noise
 AUDIO_SFX_WRITE $400C
message:
 lda pause_active
 eor #1
 sta pause_cue_direction
 lda #13                  ; first/second notes at13/7, silence at1
 sta pause_cue_timer
 jsr pause_title_upload
 ; Only the static title and status rows change. Never drain an overlay, DMA or pending world
 ; on the pause/resume refresh, nor release a door/corpse publication latch.
 jsr player_message_upload
 lda visible_control
 sta $2000
 lda #0
 sta $2005
 sta $2005
 sec
 rts
held:
 lda pause_active
 beq running
 sec
 rts
running:
 clc
 rts
.endproc
pause_enter = pause_poll::enter
pause_resume = pause_poll::resume


; Both title rows are outside the renderer-owned viewport and already use the
; readable text palette. Restore the exact original row rather than rebuilding
; a title string in NMI; no new patterns, sprite slots or attribute writes.
.proc pause_title_upload
 ldx #0
 lda pause_active
 beq copy
 ldx #32
copy:
 .repeat 2, BANK
 lda #>(PAUSE_TITLE_ADDR + BANK*$800)
 sta $2006
 lda #<(PAUSE_TITLE_ADDR + BANK*$800)
 sta $2006
 ldy #4
 .scope
chunk:
 .repeat 8, I
 lda pause_title_normal+I,x
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
 rts
.endproc

; A tiny UI-only clock runs at the common NMI tail, even while gameplay is
; paused. The normal pulse/noise channels and their software timers are never
; borrowed. Ordinary $4015 masks retain bit2 so resumed firing/pickups cannot
; truncate the cue. A death or level completion takes priority over UI sound.
.proc pause_cue_tick
 lda pause_cue_timer
 beq done
 lda pistol_health
 beq stop
 lda results_screen_state
 bne stop
 lda pause_cue_timer
 cmp #1
 beq stop
 cmp #13
 beq first
 cmp #7
 bne count
 ldx pause_cue_direction
 lda pause_cue_second,x
 jmp note
first:
 ldx pause_cue_direction
 lda pause_cue_first,x
note:
 AUDIO_SFX_WRITE $400A               ; high timer bits are zero for both notes
 lda #$FF                ; halt length, continuously reload linear127
 AUDIO_SFX_WRITE $4008
 lda #$08                ; length254 and linear reload flag; triangle enabled
 AUDIO_SFX_WRITE $400B
count:
 dec pause_cue_timer
 rts
stop:
 lda #0
 sta pause_cue_timer
 lda #$80                ; linear reload0 silences on next APU quarter-frame
 AUDIO_SFX_WRITE $4008               ; never clock/reset all channels through $4017
done:
 rts
.endproc
pause_cue_note = pause_cue_tick::note
pause_cue_stop = pause_cue_tick::stop
