; E1M1 opening room with independent HUD timing and banked ROM storage.
; Preserve the accepted world renderer, art, movement and combat.
; Boot, input and stock-NTSC publication derived from our walkable prototype.
; Custom renderer. MMC1, 8 KiB CHR-RAM + 8 KiB WRAM.
.setcpu "6502"
.include "coordinate-memory.inc"
.include "slime-memory.inc"
.include "door-memory.inc"
.import door_tick, door_publish
.export BUFFER_SLIME0, BUFFER_SLIME1
.export player_x_hi, player_z_hi, render_x_hi, render_z_hi, visible_x_hi, visible_z_hi, buffer_x_hi, buffer_z_hi, freshness_last_x_hi, freshness_last_z_hi, move_x_hi, move_z_hi, g_mul_a_hi, coordinate_producer_scratch, zombie_x_hi, zombie_z_hi, render_zombie_x_hi, render_zombie_z_hi, visible_zombie_x_hi, visible_zombie_z_hi, buffer_zombie_x_hi, buffer_zombie_z_hi, freshness_last_zombie_x_hi, freshness_last_zombie_z_hi, coordinate_nmi_scratch
.macpack longbranch
.import music_init, music_tick
.import opening_render
.import prg_map, prg_art, prg_boot, mmc1_bootstrap
.import zombie_init, zombie_tick, zombie_upload_effects, zombie_publish, zombie_render
.import zombie_hp, zombie_dirty, corpse_state
.import encounters_tick
.import corpse_save_projection, corpse_prepare
.import corpse_fast_latch, corpse_fast_upload, quick_pending, quick_published
.importzp zombie_x, zombie_z, zombie_epoch, zombie_walk_counter
.export render_zombie_hp
.exportzp render_zombie_x, render_zombie_z, render_zombie_epoch, render_zombie_pose
.export buffer_zombie_x, buffer_zombie_z, buffer_zombie_epoch, buffer_zombie_hp
.exportzp visible_zombie_x, visible_zombie_z, visible_zombie_epoch, visible_zombie_hp
.ifdef HUD_PISTOL
.import pistol_init, pistol_tick, pistol_upload
.import pistol_dirty, pistol_health
.endif
.ifdef LATENCY_RESTART
.import latency_job_begin, latency_checkpoint, latency_record_abort, latency_observe_input
.import latency_epoch, latency_render_epoch
.ifdef LATENCY_HEIGHT_PRIORITY
.import latency_hard_epoch, latency_render_hard_epoch
.endif
.export latency_attempt_begin, latency_abort, latency_final_check, latency_render_complete
.exportzp button_edges, visible_control
.endif
.import movement_init, movement_tick
.importzp player_floor, player_eye
.import freshness_gate, freshness_begin, freshness_complete
.importzp freshness_valid
.import medkit_reset, medkit_tick, medkit_selected_state
.import medkit_init, medkit_render, medkit_upload_effects, medkit_dirty, render_medkit_state
.exportzp medkit_state
.import exit_tick, exit_sound_tick
.import results_reset, results_tick, results_screen_state, results_present
.import pause_init, pause_poll, pause_active, pause_cue_tick
.import title_present, title_state, title_loading_tick
.import music_disabled
.export cold_reset, read_controller
.export results_nmi_enter, results_nmi_blank, results_nmi_show, results_nmi_restart
.export results_main_enter, results_main_restart, results_nmi_return
.import slime_tick
.exportzp exit_flags, exit_sound_timer
.importzp scene_version, render_scene_version
.import movement_tick_ntsc
.import nt_dirty_fail, nt_dirty_reset, nt_dirty_name, nt_dirty_lower, nt_dirty_prepare, ntsc_upload
.export pattern_base_hi, name_base_hi, ppu_name_hi
.exportzp cell_col, cell_x, cell_y, cell_row, column_index, name_ptr, lower_name_ptr
.exportzp tile_ptr, tile_number, tile_count, copy_ptr, temp, temp2
.exportzp mask_wall, mask_ceiling, mask_floor, vertical0, vertical1
.exportzp upload_buffer, upload_blocks, upload_ptr, upload_vram, nmi_budget
.export reset, nmi, render_begin, render_done, publish_frame, publish_commit
.export publish_world_palette, publish_world_palette_end
.export producer_recover_discard, producer_idle, publish_discard_living
.export producer_recovery_begin, producer_drop_queued, producer_recovery_release
.export producer_discard_recovered
.export requested_mode, render_mode
.export render_buffer, buffer_state, buffer_angle, buffer_mode, buffer_tile_count
.export buffer_generation, visible_buffer, visible_angle, visible_mode
.export visible_generation, publish_count, nmi_count_hi
.exportzp overflow_flag
.export render_generation, upload_phase, upload_busy
.export buffer_x, buffer_z, visible_x, visible_z
.exportzp render_angle, render_x, render_z, player_x, player_z
.exportzp pending_angle, input_buttons, nmi_count
.exportzp render_floor, render_eye, visible_floor, visible_eye
.export buffer_floor, buffer_eye

.segment "HEADER"
.byte "NES",$1A, 8,0,$10,$08,0,0,$07,$07
.byte 0,0,0,0

.segment "ZEROPAGE"
pending_angle: .res 1
exit_flags: .res 1           ; reclaimed unused auto_enabled: bit0 near, bit7 complete
requested_mode: .res 1
render_angle: .res 1
render_x: .res 2
render_z: .res 2
render_floor: .res 1
render_eye: .res 1
; Main-thread actor snapshot, protected by the same NMI seqlock as the camera.
render_zombie_x: .res 2
render_zombie_z: .res 2
render_zombie_epoch: .res 1
render_zombie_pose: .res 1
player_x: .res 2
player_z: .res 2
snapshot_version: .res 1
render_mode: .res 1
render_buffer: .res 1
render_generation: .res 1
visible_buffer: .res 1
visible_angle: .res 1
visible_x: .res 2
visible_z: .res 2
visible_floor: .res 1
visible_eye: .res 1
; Source pose of the published actor picture, never its newer live AI position.
visible_zombie_x: .res 2
visible_zombie_z: .res 2
visible_zombie_epoch: .res 1
visible_zombie_hp: .res 1
visible_mode: .res 1
visible_generation: .res 1
publish_count: .res 1
overflow_flag: .res 1
nmi_count: .res 1
nmi_count_hi: .res 1
input_buttons: .res 1
previous_buttons: .res 1
button_edges: .res 1
exit_sound_timer: .res 1     ; reclaimed unused auto_direction; NMI-owned chime
visible_control: .res 1
upload_busy: .res 1
upload_phase: .res 1
upload_buffer: .res 1
upload_blocks: .res 1
upload_ptr: .res 2
upload_vram: .res 2
nmi_budget: .res 1
medkit_state: .res 1       ; bit7 health/bit6 ammo collected; bit5 chime kind, low5 timer
; Everything below is main-thread scratch; NMI never uses it.
name_ptr: .res 2
lower_name_ptr: .res 2
tile_ptr: .res 2
copy_ptr: .res 2
copy_dst: .res 2
cell_x: .res 1
cell_y: .res 1
cell_col: .res 1
cell_row: .res 1
column_index: .res 1
tile_count: .res 1
tile_number: .res 1
temp: .res 1
temp2: .res 1
mask_ceiling: .res 1
mask_floor: .res 1
mask_wall: .res 1
seam_candidate: .res 1
.ifndef HUD_PISTOL
decimal_value: .res 1
.endif
vertical0: .res 8
vertical1: .res 8

.segment "BSS"
render_zombie_hp: .res 1
buffer_state: .res 2      ; 0 free, 1 rendering, 2 queued, 3 uploading, 4 discarded
buffer_angle: .res 2
buffer_mode: .res 2
buffer_tile_count: .res 2
buffer_generation: .res 2
buffer_x: .res 4        ; two little-endian Q8.8 words, one per staging buffer
buffer_z: .res 4
buffer_floor: .res 2
buffer_eye: .res 2
buffer_zombie_x: .res 4       ; two packed little-endian Q8.8 words
buffer_zombie_z: .res 4
buffer_zombie_epoch: .res 2
buffer_zombie_hp: .res 2

.segment "WORK"
; Per-buffer: 192 dynamic patterns (3072 bytes), then a 1024-byte nametable.
; Viewport data stays immutable during upload. CPU-only rows24..31 hold
; staged OAM; the publisher fills its pistol prefix before dedicated DMA.
cpu_buffer0: .res $1000
cpu_buffer1: .res $1000
.assert cpu_buffer0 = $6000, lderror, "WRAM buffer 0 moved"
.assert cpu_buffer1 = $7000, lderror, "WRAM buffer 1 moved"

.segment "BOOTDATA"
; Read only while rendering/NMI are disabled; bank2 is selected explicitly.
fixed_patterns: .incbin "fixed-patterns.bin"
name_template: .incbin "nametable.bin"
.segment "RODATA"
.ifndef HUD_PISTOL
pixel_title: .byte "PIXEL BOUNDARIES "
coarse_title: .byte "COARSE 8PX TILES "
.endif
; Palette 0: build-selected world colours; identical layout in every variant.
; Palette 1: bright text remains legible independently of world materials.
palette: .incbin "world-palette.bin"
 .byte $0F,$30,$10,$2D
ceiling_masks: .byte $00,$01,$03,$07,$0F,$1F,$3F,$7F,$FF
floor_masks: .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00
mirror_solid: .byte 3,1,2,0
pattern_base_hi: .byte $60,$70
name_base_hi: .byte $6C,$7C
ppu_name_hi: .byte $20,$28
; Background AND 8x8 sprite patterns switch to the same completed CHR bank.
control_values: .byte $80,$9A

.segment "CODE"
.proc reset
 ldy #0                 ; internal retry bypasses the cold-start title
 beq common
cold:
 ldy #1
common:
 sei
 cld
 ldx #$40
 stx $4017
 ldx #$FF
 txs
 tya
 pha                    ; boot_scene_init clears RAM, but not the stack page
 inx
 stx $2000
 stx $2001
 stx $4010
 stx $4015
 ; boot_scene_init clears gameplay RAM but leaves the stack page intact.
 ; Cold boot defaults to music on; an internal level restart retains choice.
 lda #(1-::MUSIC_ENABLED)
 cpy #0
 bne save_music_choice
 lda music_disabled
save_music_choice:
 pha
 ; MMC1 reset then horizontal mirroring, fixed last PRG bank, 8 KiB CHR mode.
 lda #$80
 sta $8000
 lda #$0F
 ldx #5
@mmc:
 sta $8000
 lsr a
 dex
 bne @mmc
 lda #0
 ldx #5
@banks:
 sta $A000
 sta $C000
 sta $E000
 dex
 bne @banks
 bit $2002
@v1: bit $2002
 bpl @v1
@v2: bit $2002
 bpl @v2
 jsr prg_boot
 jsr boot_scene_init
 pla
 sta music_disabled
 pla
 beq ready
 jsr title_present       ; NMI off, bank2 selected; returns with rendering off
 lda music_disabled
 pha
 jsr boot_scene_init     ; restore both CPU and PPU names, palettes and state
 pla
 sta music_disabled
ready:
 jsr prg_boot             ; boot-only initializers; music_init restores map bank
 jsr movement_init
.ifdef HUD_PISTOL
 jsr pause_init
 jsr pistol_init
 jsr zombie_init
 jsr medkit_init
 jsr medkit_reset
 jsr results_reset
 jsr music_init          ; NMI off; initialise both audio shadows last
.endif
 lda #2
 sta title_state         ; no gameplay/clock until the first completed picture
 lda #1
 sta render_buffer
 lda #$80
 sta visible_control
 sta $2000
 lda #0
 sta $2005
 sta $2005
 lda #0                 ; title_loading_tick reveals the completed first view
 sta $2001
 cli
main:
 lda results_screen_state
 beq gameplay
results_enter:
 jsr prg_boot
 jsr results_present
results_restart:
 jmp reset
gameplay:
 lda pause_active
 bne main
 ; A death may discard the hidden upload while this producer finishes the
 ; other CPU bank. Recover only here, after all producer calls have returned.
 lda buffer_state
 ora buffer_state+1
 and #4
 beq @ready
 jsr producer_recover_discard
@ready:
 ldx render_buffer
 lda buffer_state,x
 bne main
 jsr freshness_gate
 bcc main
 jsr render_begin
 ; Failed producer work retries the same inactive bank.
 ldx render_buffer
 lda buffer_state,x
 beq main
 lda render_buffer
 eor #1
 sta render_buffer
 jmp main
.endproc
cold_reset = reset::cold
producer_idle = reset::main
results_main_enter = reset::results_enter
results_main_restart = reset::results_restart

; State4 is an NMI-to-producer handoff. The uploader cannot select that bank,
; so the visible bank stays fixed throughout this main-thread-only recovery.
; Drop an unuploaded picture in the visible CPU bank before forcing a fresh
; picture into the discarded hidden bank. Otherwise freshness can wait on an
; identical queued picture that the uploader can never select, or publish it
; later after the camera has moved again.
.proc producer_recover_discard
 ldx #0
 lda buffer_state
 cmp #4
 beq found
 inx
 lda buffer_state+1
 cmp #4
 bne unmarked
found:
 jsr world_reuse_reset     ; conservative reset after discarded/queued uploads
 txa
 pha
 eor #1
 sta render_buffer
 tax
 lda buffer_state,x
 cmp #2
 bne select_hidden
drop_queued:
 ; This CPU nametable was changed without reaching its PPU bank. Preserve
 ; the existing full-viewport resync mechanism before releasing its picture.
 jsr nt_dirty_fail
 lda #0
 sta buffer_state,x
select_hidden:
 pla
 tax
 stx render_buffer
 lda #0
 sta freshness_valid
release:
 sta buffer_state,x         ; release state4 last; the next acquisition is fresh
recovered:
 rts
unmarked:
 rts
.endproc
producer_recovery_begin = producer_recover_discard::found
producer_drop_queued = producer_recover_discard::drop_queued
producer_recovery_release = producer_recover_discard::release
producer_discard_recovered = producer_recover_discard::recovered

.segment "BOOTDATA"
; Only reset calls this with bank2 selected, NMI/rendering disabled.
.proc boot_scene_init
 lda #0
 ldx #0
@clear:
 sta $0000,x
 sta $0200,x
 sta $0300,x
 sta $0400,x
 sta $0500,x
 sta $0600,x
 sta $0700,x
 inx
 bne @clear
 ; Initialize both complete CHR tables, then install identical fixed patterns.
 sta $2006
 sta $2006
 ldx #32
 ldy #0
@chr:
 sta $2007
 iny
 bne @chr
 dex
 bne @chr
 lda #<fixed_patterns
 sta copy_ptr
 lda #>fixed_patterns
 sta copy_ptr+1
 lda #0
 sta $2006
 sta $2006
 jsr boot_copy_1k
 lda #<fixed_patterns
 sta copy_ptr
 lda #>fixed_patterns
 sta copy_ptr+1
 lda #$10
 sta $2006
 lda #0
 sta $2006
 jsr boot_copy_1k
 ; Both nametables and CPU staging copies start from the same static HUD.
 ldx #0
@names:
 stx render_buffer
 lda #<name_template
 sta copy_ptr
 lda #>name_template
 sta copy_ptr+1
 lda ppu_name_hi,x
 sta $2006
 lda #0
 sta $2006
 sta copy_dst
 lda name_base_hi,x
 sta copy_dst+1
 ldx #4
 ldy #0
@namebytes:
 lda (copy_ptr),y
 sta $2007
 sta (copy_dst),y
 iny
 bne @namebytes
 inc copy_ptr+1
 inc copy_dst+1
 dex
 bne @namebytes
 ldx render_buffer
 inx
 cpx #2
 bne @names
 lda #$3F
 sta $2006
 lda #0
 sta $2006
 ldx #0
@pal:
 txa
 and #7
 tay
 lda palette,y
 sta $2007
 inx
 cpx #32
 bne @pal
 lda #0
 ldx #127
@quick_clear:
 sta $6B80,x
 sta $7B80,x
 dex
 bpl @quick_clear
 sta $7C43                 ; producer-only preparation flag, boot initialization
 sta BUFFER_SLIME0         ; no completed slime view at boot
 sta BUFFER_SLIME1
 ; Initialize all newly claimed CPU-only coordinate state/scratch after the
 ; static nametable copy, before any NMI, gameplay reset or producer snapshot.
 ldx #18
@coordinate_clear0:
 sta $7C4D,x
 dex
 bpl @coordinate_clear0
 ldx #15
@coordinate_clear1:
 sta $7EE0,x
 dex
 bpl @coordinate_clear1
 rts
.endproc

.proc boot_copy_1k
 ldx #4
 ldy #0
@loop:
 lda (copy_ptr),y
 sta $2007
 iny
 bne @loop
 inc copy_ptr+1
 dex
 bne @loop
 rts
.endproc

.segment "CODE"

.import world_reuse_begin, world_reuse_reset, world_reuse_count, world_reuse_valid
.proc render_begin
 ; A failed candidate must not poison later poses after the player moves.
 lda #0
 sta overflow_flag
 ldx render_buffer
 lda #1
 sta buffer_state,x
.ifdef LATENCY_RESTART
 ; One acquisition owns all attempts. Retain dirty-name union across retries:
 ; staging bytes changed by a rejected attempt may match the final attempt.
 jsr nt_dirty_reset
 jsr latency_job_begin
attempt_begin:
 lda #0
 sta overflow_flag
 ldx render_buffer
.endif
@snapshot:
 lda nmi_count
 sta snapshot_version
 lda pending_angle
 sta render_angle
 lda player_x
 sta render_x
 lda player_x+1
 sta render_x+1
 lda player_x_hi
 sta render_x_hi
 lda player_z
 sta render_z
 lda player_z+1
 sta render_z+1
 lda player_z_hi
 sta render_z_hi
 lda player_floor
 sta render_floor
 lda player_eye
 sta render_eye
 lda requested_mode
 sta render_mode
 lda door_state
 beq :+
 lda #1
:
 sta render_door
 lda scene_version
 sta render_scene_version
 jsr medkit_selected_state ; selected-collected bit7, immutable item kind bit6
 sta render_medkit_state
 lda zombie_hp
 bne @actor_snapshot
 lda corpse_state
 beq @actor_snapshot
 lda #$80                  ; corpse type; live combat HP remains zero
@actor_snapshot:
 sta render_zombie_hp
 lda zombie_x
 sta render_zombie_x
 lda zombie_x+1
 sta render_zombie_x+1
 lda zombie_x_hi
 sta render_zombie_x_hi
 lda zombie_z
 sta render_zombie_z
 lda zombie_z+1
 sta render_zombie_z+1
 lda zombie_z_hi
 sta render_zombie_z_hi
 lda zombie_epoch
 sta render_zombie_epoch
 lda zombie_walk_counter
 and #$20
 sta render_zombie_pose
.ifdef LATENCY_RESTART
 ; Same NMI seqlock as the complete camera snapshot, including floor/eye.
 lda latency_epoch
 sta latency_render_epoch
 lda latency_epoch+1
 sta latency_render_epoch+1
.ifdef LATENCY_HEIGHT_PRIORITY
 lda latency_hard_epoch
 sta latency_render_hard_epoch
 lda latency_hard_epoch+1
 sta latency_render_hard_epoch+1
.endif
.endif
 lda nmi_count
 cmp snapshot_version
 jne @snapshot
 jsr freshness_begin
 jsr world_reuse_begin     ; compare previous destination tags before replacing
 ldx render_buffer         ; item selection used X for the encounter, not this bank
 lda render_door
 sta buffer_door,x
 lda render_floor
 sta buffer_floor,x
 lda render_eye
 sta buffer_eye,x
 lda render_angle
 sta buffer_angle,x
 lda render_mode
 sta buffer_mode,x
 lda render_zombie_epoch
 sta buffer_zombie_epoch,x
 lda render_zombie_hp
 sta buffer_zombie_hp,x
 txa
 asl a
 tay
 lda render_x
 sta buffer_x,y
 lda render_x+1
 sta buffer_x+1,y
 lda render_x_hi
 sta buffer_x_hi,x
 lda render_z
 sta buffer_z,y
 lda render_z+1
 sta buffer_z+1,y
 lda render_z_hi
 sta buffer_z_hi,x
 lda render_zombie_x
 sta buffer_zombie_x,y
 lda render_zombie_x+1
 sta buffer_zombie_x+1,y
 lda render_zombie_x_hi
 sta buffer_zombie_x_hi,x
 lda render_zombie_z
 sta buffer_zombie_z,y
 lda render_zombie_z+1
 sta buffer_zombie_z+1,y
 lda render_zombie_z_hi
 sta buffer_zombie_z_hi,x
 inc render_generation
 lda render_generation
 sta buffer_generation,x
 ; world_reuse_begin initialized tile_count/tile_ptr to zero or retained prefix.
.ifndef LATENCY_RESTART
 jsr nt_dirty_reset
.endif
 jsr opening_render
.ifdef LATENCY_RESTART
 bcs abort
.endif
 ldx render_buffer
 lda tile_count
 sta world_reuse_count,x  ; actor/item patterns are appended after this prefix
.ifndef HUD_PISTOL
 jsr update_hud
.endif
 ; NMI code and its data are mirrored in every switchable PRG bank. Only
 ; the producer's raw art changes here, after all world geometry reads.
 jsr prg_art
 jsr zombie_render
 jsr corpse_save_projection
 jsr medkit_render
 jsr corpse_prepare
 jsr prg_map
 jsr nt_dirty_prepare
 jmp render_done
.ifdef LATENCY_RESTART
abort:
 ; All raster/HUD helper frames have unwound; only render_begin remains.
 ; This bank is still producer-owned state 1. Nothing queued is cancelled.
 jsr latency_record_abort
 jmp attempt_begin
.endif
.endproc
.ifdef LATENCY_RESTART
latency_attempt_begin = render_begin::attempt_begin
latency_abort = render_begin::abort
.endif

.proc render_done
 ldx render_buffer
 lda tile_count
 sta buffer_tile_count,x
 lda overflow_flag
 bne failed
.ifdef LATENCY_RESTART
final_check:
 ; Reject a picture whose immutable door state changed during production.
 lda door_state
 beq :+
 lda #1
:
 cmp render_door
 bne render_begin::abort
 ; A handoff invalidates producer-owned actor work immediately. The normal
 ; abort path preserves dirty-name union and resnapshots the entire scene.
 ; Publication rechecks epoch for an NMI arriving after this comparison.
 lda render_zombie_epoch
 cmp zombie_epoch
 bne render_begin::abort
 ; Includes input edges during the last strip, HUD and dirty-list preparation.
 jsr latency_checkpoint
 bcs render_begin::abort
complete:
 ; NMI cannot be masked. An edge in the short validated-check -> state-2
 ; window can admit one coherent older view; never cancel a queued bank.
 lda #1
 sta world_reuse_valid,x
 lda #2
 sta buffer_state,x
 ; Record freshness only for an accepted complete frame. Doing this after
 ; state 2 keeps the final commit window small; no staging bytes change here.
 jsr freshness_complete
.else
 jsr freshness_complete
 ldx render_buffer
 lda #2                ; publish-ready is the final producer write
 sta buffer_state,x
.endif
 rts
failed:
 ; Keep the visible picture; repair CPU/PPU names on the next successful attempt.
 jsr nt_dirty_fail
 ldx render_buffer
 lda #0
 sta buffer_state,x
 rts
.endproc
.ifdef LATENCY_RESTART
latency_final_check = render_done::final_check
latency_render_complete = render_done::complete
.endif

.ifndef HUD_PISTOL
.proc update_hud
 ldx render_buffer
 lda name_base_hi,x
 clc
 adc #2
 sta name_ptr+1
 lda #$C8              ; row 22, column 8
 sta name_ptr
 ldy #0
@title:
 lda render_mode
 bne @coarse
 lda pixel_title,y
 jmp @letter
@coarse:
 lda coarse_title,y
@letter:
 sec
 sbc #28              ; font slots = ASCII - 32 + 4
 cmp (name_ptr),y
 beq :+
 jsr nt_dirty_name
:
 sta (name_ptr),y
 iny
 cpy #16
 bne @title
 ldx render_buffer
 lda name_base_hi,x
 clc
 adc #3
 sta name_ptr+1
 lda #$46             ; row26: FLOOR:004 EYE:012 POSTS:004
 sta name_ptr
 lda render_floor
 jsr decimal_three
 lda #$4E
 sta name_ptr
 lda render_eye
 jsr decimal_three
 lda #$75             ; row 27, column 21
 sta name_ptr
 lda tile_count
 jsr decimal_three
 lda #$82             ; row 28, column 2
 sta name_ptr
 lda render_x+1
 jsr decimal_three
 lda #$88             ; row 28, column 8
 sta name_ptr
 lda render_z+1
 jsr decimal_three
 lda #$92             ; row 28, column 18
 sta name_ptr
 lda render_angle
 jsr decimal_three
 rts
.endproc

.proc decimal_three
 sta decimal_value
 ldy #0
 ldx #0
@hundreds:
 cmp #100
 bcc @tens_start
 sbc #100
 inx
 bne @hundreds
@tens_start:
 sta decimal_value
 txa
 clc
 adc #20              ; font slot for '0'
 cmp (name_ptr),y
 beq :+
 jsr nt_dirty_name
:
 sta (name_ptr),y
 iny
 lda decimal_value
 ldx #0
@tens:
 cmp #10
 bcc @ones
 sbc #10
 inx
 bne @tens
@ones:
 sta decimal_value
 txa
 clc
 adc #20
 cmp (name_ptr),y
 beq :+
 jsr nt_dirty_name
:
 sta (name_ptr),y
 iny
 lda decimal_value
 clc
 adc #20
 cmp (name_ptr),y
 beq :+
 jsr nt_dirty_name
:
 sta (name_ptr),y
 rts
.endproc

.endif ; not HUD_PISTOL: producer never writes the live HUD

.proc nmi
 pha
 txa
 pha
 tya
 pha
 lda results_screen_state
 cmp #1
 jcs results_mode
 bit $2002
 inc nmi_count
 bne :+
 inc nmi_count_hi
:
 jsr read_controller
 lda title_state
 beq :+
 jsr title_loading_tick
 jmp restore
:
 jsr pause_poll
 jcs restore
.ifdef HUD_PISTOL
 ; An overlay change gets its own VBlank. World staging/upload state remains
 ; untouched; the next ordinary NMI resumes its previous transfer budget.
 ; Item removal has its own short overlay pass, keeping the combat transfer
 ; budget intact even if a pickup coincides with a gunshot or enemy defeat.
 lda quick_pending
 beq @ordinary_overlay
 cmp #1
 bne @fast_corpse
 inc quick_pending
 jmp @ordinary_overlay
@fast_corpse:
 jsr corpse_fast_upload
 jmp @done
@ordinary_overlay:
 lda medkit_dirty
 beq @combat_overlay
 jsr medkit_upload_effects
 ; If pickup won the first death refresh, still remove the standing body.
 lda quick_pending
 cmp #2
 bne @item_done
 jsr zombie_upload_effects
@item_done:
 jmp @done
@combat_overlay:
 lda pistol_dirty
 ora zombie_dirty
 beq @world_upload
 jsr pistol_upload
 jsr zombie_upload_effects
 jmp @done
@world_upload:
.endif
 lda #7               ; Base budget; uploader can admit an eighth pattern-only block.
 sta nmi_budget
 jsr ntsc_upload
 jmp @done
@done:
 lda visible_control
publish_control:
 sta $2000
 lda #0
 sta $2005
 sta $2005
 ; Only a newly committed world can release the requested door collision.
 ; The corpse latch consumes this existing per-refresh publication flag.
 lda quick_published
 beq :+
 jsr door_publish
:
 jsr corpse_fast_latch
 ; Movement is regular PAL-rate work after the final timing-critical PPU write.
 ; It may use the rest of VBlank or visible CPU time without touching PPU state.
 jsr update_player
.ifdef HUD_PISTOL
 ; Exit completion wins over both a simultaneous pistol shot and an enemy's
 ; expiring windup. Start resets exit state before the two combat resets.
 jsr results_tick
 jsr exit_tick
 jsr door_tick
 ; Crossing an encounter boundary invalidates old aim/attack metadata
 ; before this refresh's pistol shot or zombie simulation can use it.
 jsr encounters_tick
 ; Sound and weapon timers run at the controller/NMI rate, independently of
 ; world rendering. Pending OAM/HUD data is installed on the next VBlank.
 jsr pistol_tick
 ; A shot on the final warning tick can interrupt the enemy attack.
 jsr zombie_tick
 ; Hazard time follows live movement/NMI, independent of world-render latency.
 ; Lethal slime damage wins over a pickup on the same tick.
 jsr slime_tick
 ; Damage/death on this tick precedes pickup; completed/dead players cannot heal.
 jsr medkit_tick
.endif
.ifdef LATENCY_RESTART
 ; Classify intent after PPU writes and simulation; no VBlank upload cost.
 jsr latency_observe_input
.endif
restore:
 jsr pause_cue_tick        ; UI sound only, after every mode's final PPU write
 jsr music_tick            ; borrowed movement ZP, after all simulation work
 pla
 tay
 pla
 tax
 pla
 rti
; Once state1 is captured, gameplay/reset remain frozen until the screen.
; This also prevents Start racing the main handoff.
; Main may access PPUDATA in state3. Do not even read PPUSTATUS here: doing
; so could split its two PPUADDR writes. No publisher, DMA or mapper writes.
results_mode:
 inc nmi_count
 bne :+
 inc nmi_count_hi
:
 jsr read_controller
 lda results_screen_state
 cmp #2
 beq results_blank
 cmp #4
 beq results_show
 cmp #5
 bne results_sound
 lda button_edges
 and #$10
 beq results_sound
results_restart:
 lda #6
 sta results_screen_state
 bne results_sound
results_blank:
 bit $2002
 lda #0
 sta $2001
 lda #3
 sta results_screen_state
 bne results_sound
results_show:
 bit $2002
 lda #$80
 sta $2000
 lda #0
 sta $2005
 sta $2005
 lda #$0A
 sta $2001
 lda #5
 sta results_screen_state
results_sound:
 jsr exit_sound_tick
 jmp restore
.endproc
results_nmi_enter = nmi::results_mode
results_nmi_blank = nmi::results_blank
results_nmi_show = nmi::results_show
results_nmi_restart = nmi::results_restart
results_nmi_return = nmi::restore

; The former set_upload_address/setup_upload_phase helpers were unreferenced
; leftovers from the full nametable uploader. ntsc_upload owns sparse transfer
; setup; reclaim their 124 fixed-bank bytes for exact, bounded optimizations.

.proc publish_frame
 ; A completed living snapshot must not replace the immediate death overlay.
 ; Uploads to the hidden bank have completed, so its name baseline is valid.
 ldx upload_buffer
 lda door_state
 beq :+
 lda #1
:
 cmp buffer_door,x
 bne discard_living
 lda buffer_zombie_epoch,x
 cmp zombie_epoch
 bne discard_living         ; the same state4 protocol repairs an old encounter
 lda zombie_hp
 bne accept
 lda buffer_zombie_hp,x
 beq accept
 bmi accept
discard_living:
 lda #4                   ; producer repairs bank order after its current render
 sta buffer_state,x
 lda #0
 sta upload_busy
 rts
accept:
 lda buffer_door,x
 sta visible_door
 ; Copy the immutable actor snapshot before gameplay checks its lifecycle.
 ; Epoch mismatch or live death may suppress OAM/aim; metadata still records
 ; which source snapshot produced this world's actor picture.
 ldx upload_buffer
 lda buffer_zombie_epoch,x
 sta visible_zombie_epoch
 lda buffer_zombie_hp,x
 sta visible_zombie_hp
 txa
 asl a
 tay
 lda buffer_zombie_x,y
 sta visible_zombie_x
 lda buffer_zombie_x+1,y
 sta visible_zombie_x+1
 lda buffer_zombie_x_hi,x
 sta visible_zombie_x_hi
 lda buffer_zombie_z,y
 sta visible_zombie_z
 lda buffer_zombie_z+1,y
 sta visible_zombie_z+1
 lda buffer_zombie_z_hi,x
 sta visible_zombie_z_hi
 jsr zombie_publish
 ldx upload_buffer
 stx visible_buffer
palette:
 ; Palette belongs to this completed world, not the newer live camera. The
 ; producer remaps dark-brown wall faces only when green floor is displayed.
 ; Commit the matching green only when that same world becomes visible.
 ldy #$07
 txa
 beq :+
 lda BUFFER_SLIME1
 jmp :++
:
 lda BUFFER_SLIME0
:
 beq :+
 ldy #$09
:
 lda #$3F
 sta $2006
 lda #$02
 sta $2006
 sty $2007
palette_end:
 lda buffer_floor,x
 sta visible_floor
 lda buffer_eye,x
 sta visible_eye
 lda buffer_angle,x
 sta visible_angle
 lda buffer_mode,x
 sta visible_mode
 lda buffer_generation,x
 sta visible_generation
 txa
 asl a
 tay
 lda buffer_x,y
 sta visible_x
 lda buffer_x+1,y
 sta visible_x+1
 lda buffer_x_hi,x
 sta visible_x_hi
 lda buffer_z,y
 sta visible_z
 lda buffer_z+1,y
 sta visible_z+1
 lda buffer_z_hi,x
 sta visible_z_hi
 lda control_values,x
 sta visible_control
 inc publish_count
 lda #1
 sta quick_published
 lda #0
 sta buffer_state,x
 sta upload_busy
 rts
.endproc
publish_discard_living = publish_frame::discard_living
publish_world_palette = publish_frame::palette
publish_world_palette_end = publish_frame::palette_end
; The final NMI PPUCTRL write applies both pattern and nametable bits at once.
publish_commit = nmi::publish_control

.proc read_controller
 lda input_buttons
 sta previous_buttons
 lda #1
 sta $4016
 lda #0
 sta $4016
 sta input_buttons
 ldx #8
@read:
 lda $4016
 lsr a
 rol input_buttons
 dex
 bne @read
 lda input_buttons
 eor previous_buttons
 and input_buttons
 sta button_edges
 rts
.endproc

.proc update_player
 lda exit_flags
 bpl @active
 lda button_edges
 and #$10
 beq @dead
 jsr movement_init
 rts
@active:
 lda button_edges
.ifdef HUD_PISTOL
 and #$20              ; Select owns edge/coarse mode; B is now fire
.else
 and #$40
.endif
 beq @reset
 lda requested_mode
 eor #1
 sta requested_mode
@reset:
 lda button_edges
 and #$10
 beq @move
 jsr movement_init
 rts
@move:
 lda pistol_health
 beq @dead
 jmp movement_tick_ntsc
@dead:
 rts
.endproc

.proc irq
 rti
.endproc

.segment "VECTORS"
.word nmi,mmc1_bootstrap,irq
