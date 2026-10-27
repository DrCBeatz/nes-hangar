; Sample128even screen columns and duplicate each into its odd neighbour.
; Preserve every verticalpixel; only horizontal geometry/classification is reduced.
; Classify each8-pixel vertical cell before composing its pixels. Whole-cell
; spans store only material0..3; partial boundary cells hold two bitplane bytes
; and marker4. Four matching paired markers select a shared tile immediately.
; Only boundary/mixed tiles gather pixels, transpose and enter the pattern cache.
; Each paired column is gathered once; four transposed bits expand to eight
; with a16-byte table. Output patterns/cache order stay byte-identical.
; No full-height pixel-strip initialization or painting of solid interiors.
.setcpu "6502"
.macpack longbranch
.ifndef SETUP_CHECKPOINT
SETUP_CHECKPOINT = 0
.endif
.ifndef MASKED_PAINT
MASKED_PAINT = 0
.endif
.import prg_map, prg_render
.import world_reuse_active
.import geometry_begin, geometry_column, span_count, span_top, span_bottom, span_material
.import pattern_base_hi, name_base_hi, nt_dirty_flags
.importzp render_buffer, render_mode, overflow_flag
.importzp cell_col, cell_x, cell_y, cell_row, column_index, name_ptr
.importzp tile_ptr, tile_number, tile_count, copy_ptr, temp, temp2
.importzp mask_wall, mask_ceiling, mask_floor, vertical0, vertical1
.export opening_render, opening_spans_ready, opening_strip_ready
.ifdef LATENCY_RESTART
.import latency_checkpoint
.export latency_strip_checkpoint
.endif
.export opening_plane0, opening_plane1, opening_cell_color, opening_candidate, opening_cache
.export opening_cache_hits, opening_cache_misses
.export raster_dirty_begin, raster_dirty_end
.export audio_workspace, audio_workspace_end
.include "audio-memory.inc"

.segment "BSS"
; For each tile row, four paired-column markers: material0..3 or mixed4.
; Pixel bytes below are valid only for mixed markers. Solid cells never need
; initialization or full-span pixel writes.
opening_cell_color: .res 72
opening_plane0: .res 72
opening_plane1: .res 72
; Retain every later BSS address while reclaiming the duplicate odd samples.
; Audio owns this persistent block; no geometry/raster scratch may touch it.
audio_workspace: .res AUDIO_WORKSPACE_BYTES
audio_workspace_end:
.assert audio_workspace = AUDIO_WORKSPACE_BASE, lderror, "Audio workspace moved"
.assert audio_workspace_end = AUDIO_WORKSPACE_LIMIT, lderror, "Audio workspace size changed"
opening_candidate: .res 16
; Two ways per hash bucket: newest allocation at0..63, previous at64..127.
opening_cache: .res 128
.assert opening_cache = opening_candidate+16, error, "Pre-raster scratch must be contiguous"
opening_cache_hits: .res 2
opening_cache_misses: .res 2
span_index: .res 1
span_last: .res 1
span_last_mask: .res 1
; Retain these legacy scratch addresses even when direct material painting
; makes the two per-span fill bytes unnecessary.
span_color0: .res 1
span_color1: .res 1
cache_slot: .res 1
solid0: .res 1
solid1: .res 1
pattern_or: .res 1
transpose_kind: .res 1
previous_count: .res 1
previous_top: .res 16
previous_bottom: .res 16
previous_material: .res 16
; Conservative suffix coverage removes only rows wholly hidden by later spans.
clipped_bottom: .res 16
covered_top: .res 1
; Suffix clipping finishes before painting begins. Reuse its dead scratch as
; a conservative bound on every earlier painted interval, without extra RAM.
painted_bottom = covered_top

.segment "RODATA"
start_masks: .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80
end_masks: .byte $FF,$01,$03,$07,$0F,$1F,$3F,$7F
material_plane0: .byte $00,$FF,$00,$FF
material_plane1: .byte $00,$00,$FF,$FF

.segment "CODE"
; Setup needs bank0's visibility tables. Once it completes, bank3 supplies
; identical per-column map data plus producer code over those dead tables.
; Preserve the renderer's carry result across the bank restore on both the
; successful and latency-abort return paths. NMI never changes this mapping.
.proc opening_render
 jsr geometry_begin
.if ::SETUP_CHECKPOINT
 bcc setup_current
 rts                    ; C=1; geometry setup already left bank0 selected.
setup_current:
.endif
 jsr prg_render
 jsr opening_render_banked
 php
 jsr prg_map
 plp
 rts
.endproc

.segment "RENDER_CODE"
.proc opening_render_banked
 lda #0
 sta opening_cache_hits
 sta opening_cache_hits+1
 sta opening_cache_misses
 sta opening_cache_misses+1
 lda world_reuse_active
 jne reuse_world
 lda #0
 ldx #127
cache_clear:
 sta opening_cache,x
 dex
 bpl cache_clear
 sta cell_col
 sta cell_x
strip:
 lda #0
 sta column_index
column:
 ldx cell_x
 jsr geometry_column
spans_ready:
 ; Exact equal span lists imply identical sample pairs. Reuse material markers and
 ; copy pixel bytes only for the mixed cells that actually contain boundaries.
 lda column_index
 jeq remember_column
 lda span_count
 cmp previous_count
 jne remember_column
 tay
 beq reuse_column
 dey
compare_column:
 lda span_top,y
 cmp previous_top,y
 jne remember_column
 lda span_bottom,y
 cmp previous_bottom,y
 jne remember_column
 lda span_material,y
 cmp previous_material,y
 jne remember_column
 dey
 bpl compare_column
reuse_column:
 ldx column_index
 .repeat 18,I
 lda opening_cell_color+I*4-1,x
 sta opening_cell_color+I*4,x
 cmp #4
 bne :+
 lda opening_plane0+I*4-1,x
 sta opening_plane0+I*4,x
 lda opening_plane1+I*4-1,x
 sta opening_plane1+I*4,x
:
 .endrepeat
 jmp column_done
remember_column:
 lda span_count
 sta previous_count
 tay
 beq begin_spans
 dey
remember_spans:
 lda span_top,y
 sta previous_top,y
 lda span_bottom,y
 sta previous_bottom,y
 lda span_material,y
 sta previous_material,y
 dey
 bpl remember_spans
begin_spans:
 ; Initialize only compact material markers, never a complete pixel strip.
 ldx column_index
 lda #0
 .repeat 9,I
 sta opening_cell_color+I*4,x
 .endrepeat
 lda #3
 .repeat 9,I
 sta opening_cell_color+36+I*4,x
 .endrepeat
 ; Keep producer spans unchanged. Walking backward proves a covered suffix;
 ; clipping farther bottoms to it cannot change their eventual visible pixels.
 ; Any gaps conservatively leave extra painting instead of removing coverage.
 lda #144
 sta covered_top
 ldy span_count
 beq spans_clipped
 dey
clip_span:
 lda span_bottom,y
 cmp covered_top
 bcc keep_bottom
 lda covered_top
 sta clipped_bottom,y
 lda span_top,y
 cmp covered_top
 bcs clipped
 sta covered_top
 jmp clipped
keep_bottom:
 sta clipped_bottom,y
clipped:
 dey
 bpl clip_span
spans_clipped:
 ; Rows72..143 start as material3. No earlier paint can affect pixels at or
 ; below painted_bottom. Only skip gray spans wholly in that untouched region;
 ; overlapping gray restores take the normal path regardless of scene topology.
 lda #72
 sta painted_bottom
 lda #0
 sta span_index
span:
 ldy span_index
 cpy span_count
 jeq column_done
 lda span_top,y
 cmp clipped_bottom,y
 jcs next_span
 cmp painted_bottom
 bcc paint_span
 lda span_material,y
 cmp #3
 jeq next_span
paint_span:
 ; Empty and skipped spans never raise the bound. Updating before this paint
 ; is safe: the loop completes before any later span can inspect the bound.
 lda clipped_bottom,y
 cmp painted_bottom
 bcc :+
 sta painted_bottom
:
 lda span_top,y
 and #7
 tax
 lda start_masks,x
 sta mask_wall
 lda clipped_bottom,y
 and #7
 tax
 lda end_masks,x
 sta span_last_mask
 lda clipped_bottom,y
 sec
 sbc #1
 and #$F8
 lsr a
 ora column_index
 sta span_last
 lda span_material,y
 sta temp2
.if !::MASKED_PAINT
 lsr a
 lda #0
 sbc #0                    ; C=1 material low bit:0, invert for set bits
 eor #$FF
 sta span_color0
 lda span_material,y
 and #2
 beq :+
 lda #$FF
:
 sta span_color1
.endif
 lda span_top,y
 and #$F8
 lsr a
 ora column_index
 tax
 cpx span_last
 bne :+
 lda mask_wall
 and span_last_mask
 sta mask_wall
:
 jsr masked_span_byte
 cpx span_last
 beq next_span
full_rows:
 txa
 clc
 adc #4
 tax
 cpx span_last
 beq last_row
 lda temp2
 sta opening_cell_color,x
 jmp full_rows
last_row:
 lda span_last_mask
 sta mask_wall
 jsr masked_span_byte
next_span:
 inc span_index
 jmp span
column_done:
 ; A single stored sample represents both pixels of the displayed pair.
 inc cell_x
 inc cell_x
 inc column_index
 lda column_index
 cmp #4
 jne column
strip_ready:
 ; Column-major traversal suits streamed geometry. Name writes still use
 ; the same dirty16-byte-block uploader and immutable staging ownership.
 lda cell_col
 clc
 adc #$60
 sta name_ptr
 ldx render_buffer
 lda name_base_hi,x
 sta name_ptr+1
 lda #0
 sta cell_y
 sta cell_row
tile:
 jsr strip_tile
 ldy #0
 cmp (name_ptr),y
 beq :+
dirty_begin:
 ; This loop visits viewport tile rows3..20, so the dirty16-byte block is
 ; 6 + 2*cell_row + (cell_col >=16). X is dead after strip_tile; Y stays0.
 ; Preserve only the tile ID in A instead of the generic helper's X too.
 pha
 lda cell_col
 cmp #16
 lda cell_row
 rol a
 tax
 lda #1
 sta nt_dirty_flags+6,x
 pla
dirty_end:
:
 sta (name_ptr),y
 clc
 lda name_ptr
 adc #32
 sta name_ptr
 bcc :+
 inc name_ptr+1
:
 clc
 lda cell_y
 adc #8
 sta cell_y
 inc cell_row
 lda cell_row
 cmp #18
 bne tile
 inc cell_col
.ifdef LATENCY_RESTART
strip_checkpoint:
 ; Finish all eighteen tile/name writes before abandoning this attempt.
 ; Normal RTS unwinds opening_render; geometry/cache reset on the retry.
 jsr latency_checkpoint
 bcs aborted
.endif
 lda cell_col
 cmp #32
 jne strip
.ifdef LATENCY_RESTART
 clc
.endif
 rts
.ifdef LATENCY_RESTART
aborted:
 sec
 rts
.endif
reuse_world:
 ; Keep all 128 ordered depth/occlusion samples and the same strip checkpoint
 ; cadence. Retain the exact world pattern prefix and viewport name bytes.
 lda #0
 sta cell_col
 sta cell_x
reuse_strip:
 lda #0
 sta column_index
reuse_geometry_column:
 ldx cell_x
 jsr geometry_column
 inc cell_x
 inc cell_x
 inc column_index
 lda column_index
 cmp #4
 bne reuse_geometry_column
 inc cell_col
 jsr latency_checkpoint
 bcs aborted
 lda cell_col
 cmp #32
 bne reuse_strip
 clc
 rts
.endproc
.ifdef LATENCY_RESTART
latency_strip_checkpoint = opening_render_banked::strip_checkpoint
.endif
opening_spans_ready = opening_render_banked::spans_ready
opening_strip_ready = opening_render_banked::strip_ready
raster_dirty_begin = opening_render_banked::dirty_begin
raster_dirty_end = opening_render_banked::dirty_end

.proc masked_span_byte
 lda mask_wall
 cmp #$FF
 bne partial
 ; An aligned whole cell requires only its material marker.
 lda temp2
 sta opening_cell_color,x
 rts
partial:
 lda opening_cell_color,x
 cmp #4
 beq compose
 ; Materialize the previous solid color only when a partial boundary needs it.
 tay
 lda material_plane0,y
 sta opening_plane0,x
 lda material_plane1,y
 sta opening_plane1,x
 lda #4
 sta opening_cell_color,x
compose:
.if ::MASKED_PAINT
 ; Material bits are exactly the two plane fill bits. A set bit needs OR
 ; with the coverage mask; a clear bit needs AND with its complement.
 ; The second LSR keeps the high material bit in carry across LDA/AND/ORA/
 ; EOR/STA, all of which preserve carry. NMI/RTI also restores it.
 ; Keep the original solid-to-mixed conversion, even for an empty mask.
 ; X/temp2 stay live for the caller; no extra RAM or mutable code is used.
 lda temp2
 lsr a
 bcc low_clear
 lsr a
 lda opening_plane0,x
 ora mask_wall
 sta opening_plane0,x
 bcs high_set
high_clear:
 lda mask_wall
 eor #$FF
 and opening_plane1,x
 sta opening_plane1,x
 rts
low_clear:
 lsr a
 lda mask_wall
 eor #$FF
 and opening_plane0,x
 sta opening_plane0,x
 bcc high_clear
high_set:
 lda opening_plane1,x
 ora mask_wall
 sta opening_plane1,x
.else
 lda mask_wall
 eor #$FF
 sta mask_ceiling
 lda span_color0
 and mask_wall
 sta mask_floor
 lda opening_plane0,x
 and mask_ceiling
 ora mask_floor
 sta opening_plane0,x
 lda span_color1
 and mask_wall
 sta mask_floor
 lda opening_plane1,x
 and mask_ceiling
 ora mask_floor
 sta opening_plane1,x
.endif
 rts
.endproc

.proc strip_tile
 lda render_mode
 beq @precise
 lda cell_y
 lsr a
 ora #2
 tax
 lda opening_cell_color,x
 cmp #4
 bne @return_solid
 lda opening_plane0,x
 and #$10
 beq :+
 lda #1
:
 sta temp
 lda opening_plane1,x
 and #$10
 beq :+
 lda #2
:
 ora temp
@return_solid:
 rts
@precise:
 lda cell_y
 lsr a
 tax
 lda opening_cell_color,x
 cmp #4
 bcs @gather
 ; A whole tile's four distinct paired markers agree: select its pre-existing
 ; shared solid pattern without ever creating a pixel representation.
 .repeat 3,I
 cmp opening_cell_color+I+1,x
 bne @gather
 .endrepeat
 rts
@gather:
 ; Gather the sole stored source column for each displayed pixel pair.
 ; Compact scratch stores four vertical bytes per plane; no RAM layout change.
 .repeat 4,I
 lda opening_cell_color+I,x
 cmp #4
 beq :+
 tay
 lda material_plane0,y
 sta vertical0+I
 lda material_plane1,y
 sta vertical1+I
 jmp :++
:
 lda opening_plane0+I,x
 sta vertical0+I
 lda opening_plane1+I,x
 sta vertical1+I
:
 .endrepeat
@transpose:
 ; Two-colour boundary cells usually have a constant, identical or inverted
 ; second bitplane. Recognize those exact byte relationships before shifting
 ; the columns: every source byte must agree, with a generic fallback.
 lda #0
 sta transpose_kind
 lda vertical0
 beq @check_constant0
 cmp #$FF
 bne @try_constant1
@check_constant0:
 .repeat 3,I
 cmp vertical0+I+1
 bne @try_constant1
 .endrepeat
 ; A conservative mixed marker may become uniform after later overwrites.
 ; Reuse shared solid IDs here too, preserving the existing cache allocation
 ; semantics. This check reuses the already proved constant first plane.
 sta solid0
 lda vertical1
 sta solid1
 beq @check_solid1
 cmp #$FF
 bne @constant0_only
@check_solid1:
 .repeat 3,I
 cmp vertical1+I+1
 bne @constant0_only
 .endrepeat
 lda solid0
 and #1
 sta temp
 lda solid1
 and #2
 ora temp
 rts
@constant0_only:
 lda solid0
 .repeat 8,I
 sta opening_candidate+I
 .endrepeat
 ldy #8
 jmp @plane1
@try_constant1:
 lda vertical1
 sta solid1
 beq @check_constant1
 cmp #$FF
 bne @try_related
@check_constant1:
 .repeat 3,I
 cmp vertical1+I+1
 bne @try_related
 .endrepeat
 lda #1
 sta transpose_kind
 jmp @transpose0
@try_related:
 lda vertical0
 eor vertical1
 beq @check_related
 cmp #$FF
 jne @transpose0
@check_related:
 sta pattern_or
 .repeat 3,I
 lda vertical0+I+1
 eor vertical1+I+1
 cmp pattern_or
 bne @transpose0
 .endrepeat
 lda #2
 sta transpose_kind
@transpose0:
 ldy #0
@plane0:
 lda #0
 .repeat 4,I
 lsr vertical0+I
 rol a
 .endrepeat
 tax
 lda opening_pair_expand,x
 sta opening_candidate,y
 iny
 cpy #8
 bne @plane0
 lda transpose_kind
 beq @plane1
 cmp #1
 beq @fill_constant1
 .repeat 8,I
 lda opening_candidate+I
 eor pattern_or
 sta opening_candidate+I+8
 .endrepeat
 jmp @hashed_planes
@fill_constant1:
 lda solid1
 .repeat 8,I
 sta opening_candidate+I+8
 .endrepeat
 jmp @hashed_planes
@plane1:
 lda #0
 .repeat 4,I
 lsr vertical1+I
 rol a
 .endrepeat
 tax
 lda opening_pair_expand,x
 sta opening_candidate,y
 iny
 cpy #16
 bne @plane1
@hashed_planes:
.ifdef FLOOR_DITHER
 ; The marker/strip buffers retain semantic material colours, including the
 ; coarse centre sample. Only final mixed patterns receive floor shading.
 ; Material3 is the surrounding floor: clear its two set bits on alternating
 ; pixels, leaving materials0..2 untouched. Fixed tile3 uses the same phase.
 ; Every tile origin is a multiple of8 (viewport Y=24), so no position state
 ; is needed: row0 retains $AA, row1 retains $55, in both pattern planes.
 .repeat 8,I
 lda opening_candidate+I
 and opening_candidate+I+8
 and #($55 << (I & 1))
 eor #$FF
 sta temp
 and opening_candidate+I
 sta opening_candidate+I
 lda temp
 and opening_candidate+I+8
 sta opening_candidate+I+8
 .endrepeat
.endif
 ; Rotate-then-add avoids XOR cancellation for equal NES bitplanes.
 ; Hash selects a two-way bucket; all16bytes must match before ID reuse.
 lda #0
 ldy #15
@hash:
 asl a
 adc #0
 clc
 adc opening_candidate,y
 dey
 bpl @hash
 and #63
 sta cache_slot
 tax
 lda opening_cache,x
 beq @allocate
@probe:
 sta tile_number
 asl a
 asl a
 asl a
 asl a
 sta copy_ptr
 lda tile_number
 lsr a
 lsr a
 lsr a
 lsr a
 sec
 sbc #4
 ldx render_buffer
 clc
 adc pattern_base_hi,x
 sta copy_ptr+1
 ldy #15
@compare:
 lda opening_candidate,y
 cmp (copy_ptr),y
 bne @next_way
 dey
 bpl @compare
 inc opening_cache_hits
 bne :+
 inc opening_cache_hits+1
:
 lda tile_number
 rts
@next_way:
 lda cache_slot
 and #64
 bne @allocate
 lda cache_slot
 ora #64
 sta cache_slot
 tax
 lda opening_cache,x
 bne @probe
@allocate:
 lda tile_count
 cmp #184             ; tiles248..255 are reserved for immediate corpse
 bcc :+
 lda #1
 sta overflow_flag
 lda #0
 rts
:
 clc
 adc #64
 sta tile_number
 lda cache_slot
 and #63
 tax
 lda opening_cache,x
 sta opening_cache+64,x
 lda tile_number
 sta opening_cache,x
 ldy #15
@copy:
 lda opening_candidate,y
 sta (tile_ptr),y
 dey
 bpl @copy
 clc
 lda tile_ptr
 adc #16
 sta tile_ptr
 bcc :+
 inc tile_ptr+1
:
 inc tile_count
 inc opening_cache_misses
 bne :+
 inc opening_cache_misses+1
:
 lda tile_number
 rts
.endproc

; Four distinct column bits become the same horizontally doubled NES row.
; Align16 so indexed reads never cross a page. Fixed code has room; retain
; the remaining shared-ROM space and all existing data/RAM addresses.
.align 16
.export opening_pair_expand
opening_pair_expand:
.byte $00,$03,$0C,$0F,$30,$33,$3C,$3F,$C0,$C3,$CC,$CF,$F0,$F3,$FC,$FF
