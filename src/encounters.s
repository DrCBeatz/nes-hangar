; NMI-owned persistent encounter records; only one existing actor slot runs.
; Inactive records retain their last position and HP. The active record is a
; checkpoint, not a per-tick mirror: zombie_x/z/hp are authoritative while live.
.setcpu "6502"
.include "coordinate-memory.inc"
.include "corpse-memory.inc"
.include "zombie-config.inc"
.include "encounters-config.inc"
.importzp button_edges, exit_flags, scene_version
.importzp zombie_x, zombie_z, zombie_epoch, render_zombie_epoch, visible_zombie_epoch
.import buffer_zombie_epoch
.import zombie_hp, zombie_hit_flash, zombie_visible, zombie_visible_target, zombie_dirty
.import pistol_health, zombie_attack_cancel, corpse_fast_reset, zombie_ai_handoff
.import encounter_select
.export encounters_reset, encounters_tick, encounters_save, encounters_load, encounter_next_epoch
.export encounter_switch_begin, encounter_switch_commit
.export active_encounter, encounter_visual_pending, encounter_x_frac, encounter_x_lo, encounter_x_hi
.export encounter_z_frac, encounter_z_lo, encounter_z_hi, encounter_hp

.segment "BSS"
active_encounter: .res 1
; Seven two-element arrays, indexed directly by encounter ID0/1.
encounter_x_frac: .res 2
encounter_x_lo: .res 2
encounter_x_hi: .res 2
encounter_z_frac: .res 2
encounter_z_lo: .res 2
encounter_z_hi: .res 2
encounter_hp: .res 2
.assert encounter_hp+2-active_encounter = 15, error, "Encounter records must stay15 bytes"
encounter_visual_pending: .res 1 ; retain old pixels until the new world commits
.assert encounter_visual_pending+1-active_encounter = 16, error, "Encounter storage must stay16 bytes"

.segment "RODATA"
encounter_initial:
 .byte 0,0
 .byte <ZOMBIE_X,<ENCOUNTER1_X
 .byte >ZOMBIE_X,>ENCOUNTER1_X
 .byte 0,0
 .byte <ZOMBIE_Z,<ENCOUNTER1_Z
 .byte >ZOMBIE_Z,>ENCOUNTER1_Z
 .byte 3,3

.segment "CODE"
; zombie_reset has already restored the existing active slot to encounter0.
.proc encounters_reset
 ldx #13
copy:
 lda encounter_initial,x
 sta encounter_x_frac,x
 dex
 bpl copy
 lda #0
 sta active_encounter
 sta encounter_visual_pending
 rts
.endproc

.proc encounters_save
 ldx active_encounter
 lda zombie_x
 sta encounter_x_frac,x
 lda zombie_x+1
 sta encounter_x_lo,x
 lda zombie_x_hi
 sta encounter_x_hi,x
 lda zombie_z
 sta encounter_z_frac,x
 lda zombie_z+1
 sta encounter_z_lo,x
 lda zombie_z_hi
 sta encounter_z_hi,x
 lda zombie_hp
 sta encounter_hp,x
 rts
.endproc

; X identifies the selected persistent actor; never initialize HP on return.
.proc encounters_load
 lda encounter_x_frac,x
 sta zombie_x
 lda encounter_x_lo,x
 sta zombie_x+1
 lda encounter_x_hi,x
 sta zombie_x_hi
 lda encounter_z_frac,x
 sta zombie_z
 lda encounter_z_lo,x
 sta zombie_z+1
 lda encounter_z_hi,x
 sta zombie_z_hi
 lda encounter_hp,x
 sta zombie_hp
 rts
.endproc

; Called after exit_tick and before pistol_tick. A crossing made by this
; refresh's movement invalidates old aim metadata before a held shot can fire.
; The authored selector changes IDs in the original passage. This experiment
; permits an outgoing soldier/corpse to disappear if it is still in view.
.proc encounters_tick
 lda button_edges
 and #$10
 bne done                  ; zombie_tick performs the complete Start reset
 lda pistol_health
 beq done
 lda exit_flags
 bmi done
 jsr encounter_select
 cmp active_encounter
 beq done
begin:
 pha
 jsr encounters_save
 jsr zombie_attack_cancel  ; no warning/noise may belong to the next actor
 jsr corpse_fast_reset     ; discard prepared/pending fast death pictures
 jsr zombie_ai_handoff     ; stop velocity/alert/walk phase; preserve position/HP
 jsr encounter_next_epoch  ; exclude every outstanding picture identity, even on wrap
 pla
 sta active_encounter
 tax
 jsr encounters_load
 lda #0
 sta corpse_state          ; departed corpses are removed, never paused/replayed
 sta zombie_hit_flash
 sta zombie_visible_target
 sta zombie_visible
 lda #1
 sta zombie_dirty
 sta encounter_visual_pending
 inc scene_version         ; request a fresh view without touching producer state
commit:
 rts
done:
 rts
.endproc
encounter_switch_begin = encounters_tick::begin
encounter_switch_commit = encounters_tick::commit

; Allocate a tag different from every possibly outstanding actor picture.
; Even an indefinitely overlay-starved uploader cannot alias after256 resets.
; Four occupied tags mean at mostfive increments; no extra state is needed.
; NMI owns mutation; producer snapshot reads remain protected by its seqlock.
; Preserve A/X/Y because this replaces a plain INC at both lifecycle callers.
.proc encounter_next_epoch
 pha
next:
 inc zombie_epoch
 lda zombie_epoch
 cmp render_zombie_epoch
 beq next
 cmp visible_zombie_epoch
 beq next
 cmp buffer_zombie_epoch
 beq next
 cmp buffer_zombie_epoch+1
 beq next
 pla
 rts
.endproc
