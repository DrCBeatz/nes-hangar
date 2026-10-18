; Completion statistics: a60-refresh clock independent of world rendering,
; with frozen results captured when the player activates the exit switch.
.setcpu "6502"
.include "results-memory.inc"
.importzp button_edges, exit_flags, medkit_state
.import pistol_health, encounters_save, encounter_hp
.export results_reset, results_tick, results_capture
.export results_frames, results_seconds, results_minutes, results_kills, results_items
.export results_screen_state

.segment "CODE"
.proc results_reset
 lda #0
 ldx #5
clear:
 sta results_frames,x
 dex
 bpl clear
 rts
.endproc

; Call once each NMI, after PPU work and before exit/combat simulation.
; The exit/death refresh counts; later refreshes freeze until a fresh Start.
; Start resets immediately and does not also advance the new run's clock.
.proc results_tick
 lda button_edges
 and #$10
 bne results_reset
 lda exit_flags
 bmi done
 lda pistol_health
 beq done
 lda results_minutes
 cmp #99
 bne count
 lda results_seconds
 cmp #59
 beq done                 ; saturate99:59, including its fractional phase
count:
 inc results_frames
 lda results_frames
 cmp #60
 bcc done
 lda #0
 sta results_frames
 inc results_seconds
 lda results_seconds
 cmp #60
 bcc done
 lda #0
 sta results_seconds
 inc results_minutes
done:
 rts
.endproc

; The persistent record for the active encounter is a checkpoint, not a live
; mirror. Save it before counting, so the last kill is included even without
; a subsequent room crossing. A corpse's remaining display time is irrelevant.
; Only the two persistent collection bits count; sound timers do not.
.proc results_capture
 jsr encounters_save
 lda #0
 sta results_kills
 sta results_items
 ldx #1
enemy:
 lda encounter_hp,x
 bne next_enemy
 inc results_kills
next_enemy:
 dex
 bpl enemy
 lda medkit_state
 bpl ammo
 inc results_items
ammo:
 and #$40
 beq captured
 inc results_items
captured:
 lda #1
 sta results_screen_state ; main thread will request a safe PPU handoff
 rts
.endproc
