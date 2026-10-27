; Experimental same-destination-buffer world reuse. All geometry/occlusion
; still runs, and uploads are unchanged. Only world tile construction is skipped.
.setcpu "6502"
.macpack longbranch
.include "coordinate-memory.inc"
.include "audio-memory.inc"
.import prg_select, prg_map, pattern_base_hi
.importzp render_buffer, render_x, render_z, render_angle, render_mode
.importzp render_floor, render_eye, tile_count, tile_ptr
.import render_door, buffer_door, buffer_floor, buffer_eye, buffer_angle, buffer_mode
.import buffer_x, buffer_z, music_disabled
.export world_reuse_begin, world_reuse_reset
.export world_reuse_valid, world_reuse_count, world_reuse_active
.export world_reuse_hit, world_reuse_miss

; Explicitly occupy five of the eleven unused bytes at the tail of the existing
; audio reservation. Audio never reads/writes this segment; boot clears it.
.segment "WORLD_REUSE_RAM"
world_reuse_valid: .res 2
world_reuse_count: .res 2
world_reuse_active: .res 1
.assert world_reuse_valid = music_disabled+1, lderror, "Reuse state overlaps music"
.assert world_reuse_active < AUDIO_WORKSPACE_LIMIT, lderror, "Reuse exceeds RAM reserve"

; This small gateway must remain visible through the serial mapper writes.
.segment "CODE"
.proc world_reuse_begin
 lda #5
 jsr prg_select
 jsr world_reuse_begin_banked
 jmp prg_map
.endproc

.segment "RODATA"
.proc world_reuse_reset
 lda #0
 sta world_reuse_valid
 sta world_reuse_valid+1
 rts
.endproc

; Existing spare bank5, no cartridge size or mapper change. Compare BEFORE the
; caller overwrites the bank's metadata. Scene/actor/item versions intentionally
; aren't keys: they do not change the room. Any future moving world geometry
; must add its state to this key or explicitly invalidate both banks.
.segment "WORLD_REUSE_CODE"
.proc world_reuse_begin_banked
 lda #0
 sta world_reuse_active
 ldx render_buffer
 lda world_reuse_valid,x
 jeq miss
 lda render_angle
 cmp buffer_angle,x
 jne miss
 lda render_mode
 cmp buffer_mode,x
 jne miss
 lda render_floor
 cmp buffer_floor,x
 jne miss
 lda render_eye
 cmp buffer_eye,x
 jne miss
 lda render_door
 cmp buffer_door,x
 jne miss
 lda render_x_hi
 cmp buffer_x_hi,x
 jne miss
 lda render_z_hi
 cmp buffer_z_hi,x
 jne miss
 txa
 asl a
 tay
 lda render_x
 cmp buffer_x,y
 bne miss
 lda render_x+1
 cmp buffer_x+1,y
 bne miss
 lda render_z
 cmp buffer_z,y
 bne miss
 lda render_z+1
 cmp buffer_z+1,y
 bne miss
hit:
 lda #1
 sta world_reuse_active
 lda world_reuse_count,x
 jmp pointer
miss:
 lda #0
pointer:
 sta tile_count
 ; Pattern source = $6000/$7000 + retained world count * 16.
 asl a
 asl a
 asl a
 asl a
 sta tile_ptr
 lda tile_count
 lsr a
 lsr a
 lsr a
 lsr a
 clc
 adc pattern_base_hi,x
 sta tile_ptr+1
 ; No partially rendered, aborted or overflowed attempt is reusable. Only
 ; render_done's final accepted path may validate this bank again.
 lda #0
 sta world_reuse_valid,x
 rts
.endproc
world_reuse_hit = world_reuse_begin_banked::hit
world_reuse_miss = world_reuse_begin_banked::miss
