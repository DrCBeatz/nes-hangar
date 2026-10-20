; NMI-owned persistent encounter records; only one existing actor slot runs.
; Inactive records retain their last position and HP. The active record is a
; checkpoint, not a per-tick mirror: zombie_x/z/hp are authoritative while live.
.setcpu "6502"
.include "coordinate-memory.inc"
.include "corpse-memory.inc"
.include "zombie-config.inc"
.include "encounters-config.inc"
.assert ENCOUNTER_COUNT = 3, error, "Encounter memory layout requires three actors"
.importzp button_edges, exit_flags, scene_version
.importzp zombie_x, zombie_z, zombie_epoch, render_zombie_epoch, visible_zombie_epoch
.import buffer_zombie_epoch
.import zombie_hp, zombie_hit_flash, zombie_visible, zombie_visible_target, zombie_dirty
.import pistol_health, zombie_attack_cancel, corpse_fast_reset, zombie_ai_handoff
.import encounter_select
.import nt_dirty_list, visible_door
.export encounters_reset, encounters_tick, encounters_save, encounters_load, encounter_next_epoch
.export encounter_switch_begin, encounter_switch_commit
.export active_encounter, encounter_visual_pending, encounter_x_frac, encounter_x_lo, encounter_x_hi
.export encounter_z_frac, encounter_z_lo, encounter_z_hi, encounter_hp

.segment "BSS"
active_encounter: .res 1
; Four three-element arrays stay in the original sixteen-byte allocation.
; The remaining three arrays reclaim the unused first dirty-list tail. All
; arrays are indexed directly by encounter ID0/1/2, including HP on return.
encounter_x_frac: .res 3
encounter_x_lo: .res 3
encounter_x_hi: .res 3
encounter_z_frac: .res 3
.res 2                     ; preserve later BSS addresses; available for future state
.assert encounter_z_frac+3-active_encounter = 13, error, "Encounter coordinate arrays moved"
encounter_visual_pending: .res 1 ; retain old pixels until the new world commits
.assert encounter_visual_pending+1-active_encounter = 16, error, "Encounter storage must stay16 bytes"

; NMI-owned persistent state. Dirty preparation writes offsets0..47 and
; 64..111 only; upload reads those lists with counts<=48. Door state occupies
; 48..54. These nine bytes are never producer scratch or upload destinations.
encounter_z_lo = nt_dirty_list+55
encounter_z_hi = nt_dirty_list+58
encounter_hp = nt_dirty_list+61
.assert encounter_z_lo = visible_door+1, lderror, "Encounter tail overlaps door state"
.assert encounter_z_lo >= nt_dirty_list+48, lderror, "Encounter tail overlaps first dirty list"
.assert encounter_hp+3 = nt_dirty_list+64, lderror, "Encounter tail overlaps second dirty list"

.segment "RODATA"
encounter_initial:
 .byte 0,0,0
 .byte <ZOMBIE_X,<ENCOUNTER1_X,<ENCOUNTER2_X
 .byte >ZOMBIE_X,>ENCOUNTER1_X,>ENCOUNTER2_X
 .byte 0,0,0
 .byte <ZOMBIE_Z,<ENCOUNTER1_Z,<ENCOUNTER2_Z
 .byte >ZOMBIE_Z,>ENCOUNTER1_Z,>ENCOUNTER2_Z
 .byte 3,3,3

.segment "CODE"
; zombie_reset has already restored the existing active slot to encounter0.
.proc encounters_reset
 ldx #11
copy:
 lda encounter_initial,x
 sta encounter_x_frac,x
 dex
 bpl copy
 ldx #8
copy_tail:
 lda encounter_initial+12,x
 sta encounter_z_lo,x
 dex
 bpl copy_tail
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
