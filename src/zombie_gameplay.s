; Moving target state and publication. Live state/scratch is NMI-owned;
; the producer only snapshots HP and writes its own staged actor picture.
.setcpu "6502"
.include "coordinate-memory.inc"
.macpack longbranch
.import coordinate_abs_delta
.importzp button_edges, scene_version, upload_buffer, move_x, move_z
.importzp exit_flags
.import pistol_prepare_oam, zombie_ai_reset, zombie_ai_tick
.import zombie_attack_reset, zombie_attack_cancel, zombie_attack_tick
.import zombie_attack_warning_uploaded, zombie_attack_firing_uploaded, pistol_health
.importzp zombie_attack_state, zombie_fire_flash
.importzp zombie_x, zombie_z, zombie_epoch, visible_zombie_epoch, visible_zombie_hp
.importzp visible_zombie_x, visible_zombie_z
.import corpse_fast_reset, corpse_fast_request
.import encounters_reset, encounter_visual_pending
.import buffer_zombie_target, buffer_zombie_visible
.import medkit_prepare_publish, medkit_hide_zombie_live, medkit_hide_zombie_staged
.export zombie_init, zombie_reset, zombie_tick, zombie_damage
.export zombie_upload_effects, zombie_publish, zombie_candidate_blocked
.export zombie_hp, zombie_hit_flash, zombie_hits, zombie_kills, zombie_dirty
.export zombie_visible_target, zombie_visible, zombie_hit, zombie_defeat
.export zombie_collision_blocked, zombie_publication_done
.export encounter_visual_released
.export corpse_state, corpse_tick, corpse_expire, corpse_published
.exportzp zombie_oam_ptr
.export zombie_delta, zombie_square, zombie_coord, zombie_palette_offset, zombie_square_lo, zombie_square_hi

.include "zombie-config.inc"
.include "corpse-memory.inc"
ZOMBIE_CONTACT_RADIUS = 8
ZOMBIE_FLASH_FRAMES = 18

.segment "ZEROPAGE"
zombie_oam_ptr: .res 2       ; NMI private, never producer scratch

.segment "BSS"
zombie_hp: .res 1
zombie_hit_flash: .res 1
zombie_hits: .res 1
zombie_kills: .res 1
zombie_dirty: .res 1
zombie_visible_target: .res 1
zombie_visible: .res 1
zombie_delta: .res 2
zombie_square: .res 2
zombie_coord: .res 1
zombie_palette_offset: .res 1

.segment "RODATA"
zombie_palettes:
 .byte $0F,$0F,$18,$37       ; normal: black, olive, pale skin
 .byte $0F,$0F,$16,$30       ; hit: black, red, white
 .byte $0F,$0F,$28,$30       ; attack warning: black, amber, white
 .byte $0F,$0F,$30,$37       ; firing: black, white uniform, pale skin
zombie_square_lo:
.repeat 256,I
 .byte <(I*I)
.endrepeat
zombie_square_hi:
.repeat 256,I
 .byte >(I*I)
.endrepeat

; Reset-only setup: bank2 selected, rendering and NMI disabled.
.segment "BOOTDATA"
.proc zombie_init
 lda #$3F
 sta $2006
 lda #$18
 sta $2006
 ldx #0
@palette:
 lda zombie_palettes,x
 sta $2007
 inx
 cpx #8
 bne @palette
 jsr zombie_reset
 jmp zombie_upload_effects
.endproc

.segment "CODE"
.proc zombie_reset
 jsr corpse_fast_reset
 jsr zombie_attack_reset
 jsr zombie_ai_reset
 lda #3
 sta zombie_hp
 jsr encounters_reset
 lda #0
 sta zombie_hits
 sta zombie_kills
 sta zombie_hit_flash
 sta zombie_visible_target
 sta zombie_visible
 sta corpse_state
 lda #1
 sta zombie_dirty
 inc scene_version
 rts
.endproc

.proc zombie_tick
 lda button_edges
 and #$10
 beq @timer
 jmp zombie_reset
@timer:
 ; Corpse lifetime follows display refreshes, even after death/exit freezes AI.
 jsr corpse_tick
 lda exit_flags
 bmi @frozen
 lda zombie_hit_flash
 beq @done
 dec zombie_hit_flash
 bne @done
 lda #1
 sta zombie_dirty
@done:
 jsr zombie_attack_tick
 jmp zombie_ai_tick
@frozen:
 rts
.endproc

; Pending corpses do not age until an actual visible OAM publication. Once
; displayed, removal keeps running independently of gameplay and camera work.
.proc corpse_tick
 lda corpse_state
 beq done
 bmi done
 dec corpse_state
 bne done
expire:
 lda #0
 sta zombie_visible_target
 sta zombie_visible
 lda #1
 sta zombie_dirty
 inc scene_version
done:
 rts
.endproc
corpse_expire = corpse_tick::expire

; Called only for a shot actually accepted by the pistol (ammo/cooldown pass).
; The published silhouette is authoritative: aim at what is currently shown.
; Its center column provides vertical autoaim across the two floor heights.
.proc zombie_damage
 lda exit_flags
 bmi done
 lda zombie_hp
 beq done
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne done
 lda zombie_visible_target
 beq done
hit:
 jsr zombie_attack_cancel
 dec zombie_hp
 inc zombie_hits
 lda #ZOMBIE_FLASH_FRAMES
 sta zombie_hit_flash
 lda #1
 sta zombie_dirty
 lda zombie_hp
 bne done
defeat:
 inc zombie_kills
 lda #CORPSE_PENDING
 sta corpse_state
 lda #0
 sta zombie_visible_target
 sta zombie_visible
 sta zombie_hit_flash      ; the corpse uses the ordinary olive/skin palette
 ; Preserve the position in the displayed image used to accept the hit.
 lda visible_zombie_x
 sta zombie_x
 lda visible_zombie_x+1
 sta zombie_x+1
 lda visible_zombie_x_hi
 sta zombie_x_hi
 lda visible_zombie_z
 sta zombie_z
 lda visible_zombie_z+1
 sta zombie_z+1
 lda visible_zombie_z_hi
 sta zombie_z_hi
 jsr corpse_fast_request
 inc scene_version          ; request a fresh corpse snapshot at the death pose
done:
 rts
.endproc
zombie_hit = zombie_damage::hit
zombie_defeat = zombie_damage::defeat

; Dedicated overlay VBlank, shared with the pistol's small OAM/HUD update.
; A live palette change flashes the already-published sprite immediately.
.proc zombie_upload_effects
 lda zombie_dirty
 jeq @done
 ; If the pending cue lost its displayed actor, cancel before choosing the
 ; palette. Otherwise the final dirty clear could preserve an orphan amber hue.
 lda zombie_attack_state
 cmp #1
 bne @palette_ready
 lda zombie_hp
 beq @cancel_pending
 lda pistol_health
 beq @cancel_pending
 lda zombie_visible
 beq @cancel_pending
 lda visible_zombie_epoch
 cmp zombie_epoch
 beq @palette_ready
@cancel_pending:
 jsr zombie_attack_cancel
@palette_ready:
 ; A shot can happen after the player has turned away from an already warned
 ; attack. Do not save its pending flash for a later, unrelated actor view.
 lda zombie_fire_flash
 bpl @choose_palette
 lda zombie_hp
 beq @discard_flash
 lda pistol_health
 beq @discard_flash
 lda zombie_visible
 beq @discard_flash
 lda visible_zombie_epoch
 cmp zombie_epoch
 beq @choose_palette
@discard_flash:
 lda #0
 sta zombie_fire_flash
@choose_palette:
 lda #0
 sta zombie_palette_offset
 lda zombie_fire_flash
 beq @attack_palette
 lda #12
 sta zombie_palette_offset
 bne @hit_palette
@attack_palette:
 lda zombie_attack_state
 cmp #1
 beq @warning_palette
 cmp #2
 bne @hit_palette
@warning_palette:
 lda #8
 sta zombie_palette_offset
@hit_palette:
 lda zombie_hit_flash
 beq :+
 lda #4
 sta zombie_palette_offset
:
 lda #$3F
 sta $2006
 lda #$19
 sta $2006
 ldx zombie_palette_offset
 lda zombie_palettes+1,x
 sta $2007
 lda zombie_palettes+2,x
 sta $2007
 lda zombie_palettes+3,x
 sta $2007
 jsr zombie_attack_warning_uploaded
 jsr zombie_attack_firing_uploaded
 lda visible_zombie_epoch
 cmp zombie_epoch
 beq @epoch_current
 ; A handoff invalidates interaction immediately, but the old sprite still
 ; belongs to the currently displayed old world. Retain its pixels until the
 ; matching new world commits. Start clears this exception before hiding.
 lda encounter_visual_pending
 bne @clear
 jmp @hide
@epoch_current:
 lda zombie_hp
 jne @clear
 ; A dead actor may retain only a published, unexpired corpse. Kill refreshes
 ; hide the old standing OAM before the slower producer creates the death pose.
 lda visible_zombie_hp
 bpl @hide
 lda corpse_state
 bne @clear
@hide:
 ; Suppress stale standing, reset or expired pixels independently of the
 ; slower room producer. The helper preserves any depth-swapped medkit slots.
 jsr medkit_hide_zombie_live
 lda #0
 sta $2003
@clear:
 lda #0
 sta zombie_dirty
@done:
 rts
.endproc

; Uploader phase 2 owns an entire VBlank: no CHR/nametable transfer shares DMA.
; Merge current weapon art with the actor prepared for this exact world view.
.proc zombie_publish
 lda #0
 sta zombie_oam_ptr
 lda upload_buffer
 asl a
 asl a
 asl a
 asl a
 ora #$6F
 sta zombie_oam_ptr+1
 jsr pistol_prepare_oam
 jsr medkit_prepare_publish
 ldx upload_buffer
 lda buffer_zombie_target,x
 sta zombie_visible_target
 lda buffer_zombie_visible,x
 sta zombie_visible
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne hide
 lda visible_zombie_hp
 beq hide
 bmi corpse
 lda zombie_hp
 bne dma
 beq hide
corpse:
 ; Snapshot type and live lifecycle must agree: queued living/corpse pictures
 ; can never resurrect a defeated, expired or restarted actor.
 lda zombie_hp
 bne hide
 lda corpse_state
 beq hide
 lda #0
 sta zombie_visible_target
 lda zombie_visible
 beq dma
 lda corpse_state
 bpl dma
published:
 ; DMA below installs the first visible corpse. This NMI's later tick leaves
 ; 120; expiry requests removal through the next dedicated overlay refresh.
 lda #(CORPSE_DISPLAY_FRAMES+1)
 sta corpse_state
 jmp dma
hide:
 lda #0
 sta zombie_visible_target
 sta zombie_visible
 jsr medkit_hide_zombie_staged
dma:
 lda #0
 sta $2003
 lda zombie_oam_ptr+1
 sta $4014
 lda #0
 sta $2003
 ; Only matching world publication releases the visual handoff. An old
 ; rejected epoch must not drop the exception while its world is still shown.
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne done
 lda #0
 sta encounter_visual_pending
visual_released:
done:
 rts
.endproc
zombie_publication_done = zombie_publish::done
encounter_visual_released = zombie_publish::visual_released
corpse_published = zombie_publish::published

; A conservative circular contact boundary, sampled at 1/32 world-unit
; precision. Global positions use Q16.8. Axis-separated movement can slide around
; the circle; its collision disappears as soon as the target is defeated.
.proc zombie_candidate_blocked
 lda zombie_hp
 jeq clear
 lda move_x
 sec
 sbc zombie_x
 sta zombie_delta
 lda move_x+1
 sbc zombie_x+1
 sta zombie_delta+1
 lda move_x_hi
 sbc zombie_x_hi
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs clear
 jsr absolute_coordinate
 jcs clear
 tax
 lda zombie_square_lo,x
 sta zombie_square
 lda zombie_square_hi,x
 sta zombie_square+1
 lda move_z
 sec
 sbc zombie_z
 sta zombie_delta
 lda move_z+1
 sbc zombie_z+1
 sta zombie_delta+1
 lda move_z_hi
 sbc zombie_z_hi
 sta coordinate_nmi_scratch+2
 jsr coordinate_abs_delta
 jcs clear
 jsr absolute_coordinate
 jcs clear
 tax
 clc
 lda zombie_square_lo,x
 adc zombie_square
 lda zombie_square_hi,x
 adc zombie_square+1
 jcs clear                  ; dxQ4^2 + dzQ4^2 >= 256^2
blocked:
 sec
 rts
clear:
 clc
 rts
.endproc
zombie_collision_blocked = zombie_candidate_blocked::blocked

; Return abs(deltaQ8)>>3 in A, C=0; C=1 if abs(delta)>=8 logical units.
; The normalized 256-unit radius preserves the existing circular sum test.
.proc absolute_coordinate
 ; Input already normalized by coordinate_abs_delta.
 lda zombie_delta+1
 cmp #ZOMBIE_CONTACT_RADIUS
 bcs @done
 asl a
 asl a
 asl a
 asl a
 asl a
 sta zombie_coord
 lda zombie_delta
 lsr a
 lsr a
 lsr a
 ora zombie_coord
 clc
@done:
 rts
.endproc
