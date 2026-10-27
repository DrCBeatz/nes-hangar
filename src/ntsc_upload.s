; NTSC graphics scheduling: compare against the SAME destination bank's previous
; CPU nametable, then upload only changed 16-byte blocks. Pattern bytes are all
; uploaded, because an unchanged tile number can still have new pattern data.
; Main-thread dirty flags are never read by NMI. Each completed buffer owns its
; immutable dirty list until publication; no partial picture becomes visible.
.setcpu "6502"
.if ::GUARDED_PATTERN8
.assert ::STREAM_PATTERN_UPLOAD, error, "Eight-pattern batches require the streaming uploader"
.endif
.importzp name_ptr, lower_name_ptr, render_buffer, visible_buffer
.importzp upload_busy, upload_phase, upload_buffer, upload_blocks
.importzp upload_ptr, upload_vram, nmi_budget
.import buffer_state, buffer_tile_count, pattern_base_hi, name_base_hi, ppu_name_hi
.import publish_frame
.export nt_dirty_reset, nt_dirty_name, nt_dirty_lower, nt_dirty_prepare, nt_dirty_fail, ntsc_upload
.export nt_dirty_flags, nt_dirty_list, nt_dirty_count
.export slime_timer
.export door_state, door_near, door_sound_timer, render_door, buffer_door, visible_door
.exportzp nt_upload_index

.segment "ZEROPAGE"
; Main-thread scratch only.
nt_dirty_low: .res 1
nt_dirty_high: .res 1
nt_dirty_length: .res 1
; NMI-owned: offset within the current buffer's immutable list.
nt_upload_index: .res 1

.segment "BSS"
; Only the first 48 sixteen-byte blocks are nametable data in this build.
; The last 256 bytes are staged OAM, never a dirty nametable destination.
; Reclaim the unused flags for persistent encounter records in internal RAM.
.ifndef COMBAT_GROUNDED
.error "Compact dirty flags require the grounded combat/OAM layout"
.endif
NT_DIRTY_BLOCK_COUNT = 48
nt_dirty_flags: .res NT_DIRTY_BLOCK_COUNT
nt_dirty_list: .res 48       ; bank0 list, at most48 entries
; Entries48..63 are outside either upload list; preserve every later address.
door_state: .res 1           ; NMI:0 closed,1 requested,2 open picture published
door_near: .res 1            ; NMI:current live pose may use the closed door
door_sound_timer: .res 1     ; NMI:mechanical noise tail, guns/exit take priority
render_door: .res 1          ; producer:immutable desired-open snapshot
buffer_door: .res 2          ; immutable desired-open bit per render bank
visible_door: .res 1         ; NMI:state represented by the committed world
.res 72                     ; pad to127, including bank1 list atoffset64
; encounters.s aliases unused offsets55..63 for three saved Z/HP arrays.
.assert door_state = nt_dirty_list+48, error, "Door state overlaps dirty data"
.assert visible_door < nt_dirty_list+64, error, "Door state overlaps bank1 list"
; The last 16 entries of either stride are never written/read as dirty data.
; Reclaim the last byte for the NMI-owned hazard timer without moving any RAM.
slime_timer: .res 1
.assert NT_DIRTY_BLOCK_COUNT <= 48, error, "Slime timer overlaps dirty-list entries"
.assert slime_timer = nt_dirty_list+127, error, "Slime timer moved"
nt_dirty_count: .res 2
nt_failed_banks: .res 2

.segment "CODE"
.proc nt_dirty_fail
 ldx render_buffer
 lda #1
 sta nt_failed_banks,x
 rts
.endproc

.proc nt_dirty_reset
 lda #0
 ldx #(NT_DIRTY_BLOCK_COUNT-1)
clear:
 sta nt_dirty_flags,x
 dex
 bpl clear
 ldx render_buffer
 lda nt_failed_banks,x
 beq done
 lda #0
 sta nt_failed_banks,x
 lda #1
 ldx #6
resync:
 sta nt_dirty_flags,x
 inx
 cpx #42
 bne resync
done:
 rts
.endproc

; Called only when a tile ID changes. Preserve A, X and Y, so all callers retain
; the value being stored and any font-loop/decimal-conversion state.
.proc nt_dirty_name
 pha
 txa
 pha
 tya
 clc
 adc name_ptr
 sta nt_dirty_low
 lda name_ptr+1
 adc #0
 jmp nt_dirty_mark
.endproc

.proc nt_dirty_lower
 pha
 txa
 pha
 tya
 clc
 adc lower_name_ptr
 sta nt_dirty_low
 lda lower_name_ptr+1
 adc #0
 jmp nt_dirty_mark
.endproc

.proc nt_dirty_mark
 and #3
 asl a
 asl a
 asl a
 asl a
 sta nt_dirty_high
 lda nt_dirty_low
 lsr a
 lsr a
 lsr a
 lsr a
 ora nt_dirty_high
 tax
 lda #1
 sta nt_dirty_flags,x
 pla
 tax
 pla
 rts
.endproc

.proc nt_dirty_prepare
 lda render_buffer
 lsr a
 ror a
 lsr a                   ; buffer 0/1 becomes list offset 0/64
 tay
 lda #0
 sta nt_dirty_length
 ldx #0
@scan:
 lda nt_dirty_flags,x
 beq @next
 txa
 sta nt_dirty_list,y
 iny
 inc nt_dirty_length
@next:
 inx
.ifdef COMBAT_GROUNDED
 cpx #48                ; rows24..31 are static PPU data; CPU page is OAM.
.else
 cpx #64
.endif
 bne @scan
 ldx render_buffer
 lda nt_dirty_length
 sta nt_dirty_count,x
 rts
.endproc

.proc ntsc_upload
 lda upload_busy
 bne @continuing
 lda visible_buffer
 eor #1
 tax
 lda buffer_state,x
 cmp #2
 beq @start
 rts
@start:
 stx upload_buffer
 lda #3
 sta buffer_state,x
 lda #1
 sta upload_busy
 lda #0
 sta upload_phase
 sta nt_upload_index
 sta upload_ptr
 sta upload_vram
 lda pattern_base_hi,x
 sta upload_ptr+1
 txa
 asl a
 asl a
 asl a
 asl a
 ora #4
 sta upload_vram+1
 lda buffer_tile_count,x
 sta upload_blocks
 jmp @resume
@continuing:
.ifdef COMBAT
 lda upload_phase
 cmp #2
 bne :+
 jmp publish_frame       ; dedicated OAM DMA/commit NMI, no pattern/name writes
:
.endif
 lda upload_phase
 beq @resume
 ; Sparse nametable blocks need individual address setup. Reserve one of the
 ; seven transfer slots once per interrupt whenever that work is present.
 dec nmi_budget
@resume:
 lda upload_phase
 bne @names
 lda upload_blocks
.if ::GUARDED_PATTERN8
 beq @patterns_done
 ; Both callers start with seven slots. This point can be reached with
 ; remaining patterns only at the start of a batch: the streaming loop exits
 ; when the budget or pattern count is zero. Eight available patterns consume
 ; all eight slots, so this promotion can never spill into sparse name work.
 cmp #8
 bcc @address
 inc nmi_budget
 bne @address             ; seven -> eight, always nonzero
@patterns_done:
.else
 bne @address
.endif
 inc upload_phase
 dec nmi_budget
 bne @names
.if ::UPLOAD_COMPLETION_FAST
 jmp @done              ; an empty name list can complete at this boundary too
.else
 rts
.endif
@names:
 ldx upload_buffer
 lda nt_upload_index
 cmp nt_dirty_count,x
 bcc @next_name
.ifdef COMBAT
 lda #2                 ; defer publication, so OAM DMA has an entire VBlank
 sta upload_phase
 rts
.else
 jmp publish_frame
.endif
@next_name:
 txa
 lsr a
 ror a
 lsr a
 ora nt_upload_index
 tax
 lda nt_dirty_list,x
 pha
 and #15
 asl a
 asl a
 asl a
 asl a
 sta upload_ptr
 sta upload_vram
 pla
 lsr a
 lsr a
 lsr a
 lsr a
 ldx upload_buffer
 ora name_base_hi,x
 sta upload_ptr+1
 and #3
 ora ppu_name_hi,x
 sta upload_vram+1
 inc nt_upload_index
@address:
 lda upload_vram+1
 sta $2006
 lda upload_vram
 sta $2006
@copy:
 ldy #0
 .repeat 16
 lda (upload_ptr),y
 sta $2007
 iny
 .endrepeat
 lda upload_phase
 bne @budget
 clc
 lda upload_ptr
 adc #16
 sta upload_ptr
 bcc :+
 inc upload_ptr+1
:
.if ::STREAM_PATTERN_UPLOAD
 ; Pattern source/destination are consecutive. Keep the PPU's incrementing
 ; address through this batch, sharing the same byte kernel with sparse names.
 ; Advance the CPU pointer per block so the aligned16-byte read never crosses
 ; a page. No extra RAM, larger budget, or repeated PPUADDR write is required.
 dec upload_blocks
 dec nmi_budget
 beq @finish_patterns
 lda upload_blocks
 beq @finish_patterns
 jmp @copy
@finish_patterns:
 ; RAM$6000/$7000 -> PPU$0400/$1400: both banks differ by exactly$5C00.
 ; Synchronize the destination pointer once per pattern batch, retaining the
 ; original pointer state before a return or transition into sparse names.
 lda upload_ptr
 sta upload_vram
 lda upload_ptr+1
 sec
 sbc #$5C
 sta upload_vram+1
 lda nmi_budget
 beq @done
 jmp @resume
.else
 clc
 lda upload_vram
 adc #16
 sta upload_vram
 bcc :+
 inc upload_vram+1
:
 dec upload_blocks
.endif
@budget:
 dec nmi_budget
 beq @done
 jmp @resume
@done:
.if ::UPLOAD_COMPLETION_FAST
 ; If the last name block exactly used the final slot, acknowledge completion
 ; now rather than spending the next NMI discovering an already empty list.
 ; Publication still gets its own NMI: no DMA/commit joins this full batch.
 ; This is NMI-owned state and the completed buffer's immutable dirty count.
 lda upload_phase
 beq :+
 ldx upload_buffer
 lda nt_upload_index
 cmp nt_dirty_count,x
 bcc :+
 inc upload_phase          ; phase 1 -> 2; @continuing commits next interrupt
:
.endif
 rts
.endproc
