; Cold-start logo, then guide using existing fixed glyphs. This code and its assets are
; only accessed in bank2 while NMI is disabled. Internal retries skip it.
.setcpu "6502"
.include "title-memory.inc"
.include "title-config.inc"
.include "newtitle-logo-config.inc"
.import read_controller, ntsc_upload, music_disabled
.import title_credits_gateway
.importzp input_buttons, button_edges, copy_ptr, nmi_budget
.importzp visible_control, publish_count
.export title_present, title_state, title_wait_start, title_start
.export title_loading_tick, title_first_visible, title_copy_begin, title_copy_end
.export title_logo_present, title_logo_copy_begin, title_logo_copy_end
.export title_logo_wait_start, title_logo_start
.export title_music_refresh

.segment "BOOTDATA"
title_name: .incbin "title-nametable.bin"
title_palette: .incbin "title-palette.bin"
title_logo_patterns: .incbin "newtitle-logo-packed.bin"
title_logo_name: .incbin "newtitle-logo-nametable.bin"
title_logo_palette: .incbin "newtitle-logo-palette.bin"

; All work is confined to the boot-only bank while NMI/rendering are off.
; Appending tiles64+ leaves the fixed font intact for the following guide.
; Reset reloads both complete CHR tables before preparing the first world.
.proc title_logo_present
copy_begin:
 bit $2002
 lda #>NEW_TITLE_CHR_ADDR
 sta $2006
 lda #<NEW_TITLE_CHR_ADDR
 sta $2006
 lda #<title_logo_patterns
 sta copy_ptr
 lda #>title_logo_patterns
 sta copy_ptr+1
 ldx #NEW_TITLE_CHR_PATTERNS
copy_pattern:
 ldy #0
copy_pattern_rows:
 lda (copy_ptr),y        ; each stored byte represents two identical rows
 sta $2007
 sta $2007
 iny
 cpy #8                 ; four low-plane bytes, then four high-plane bytes
 bne copy_pattern_rows
 lda copy_ptr
 clc
 adc #8
 sta copy_ptr
 bcc pattern_next
 inc copy_ptr+1
pattern_next:
 dex
 bne copy_pattern
 lda #$20
 sta $2006
 lda #0
 sta $2006
 lda #<title_logo_name
 sta copy_ptr
 lda #>title_logo_name
 sta copy_ptr+1
 ldx #4
 jsr copy_pages
 lda #$3F
 sta $2006
 lda #0
 sta $2006
 ldx #0
palette:
 lda title_logo_palette,x
 sta $2007
 inx
 cpx #32
 bne palette
copy_end:
 lda #0
 sta $2000
 sta $2005
 sta $2005
 lda #$0A
 sta $2001
 lda #$30               ; held Start/Select cannot skip or reopen this page
 sta input_buttons
wait_start:
 bit $2002
 bpl wait_start
 jsr read_controller
 lda button_edges
 and #$10
 bne start              ; Start wins over a simultaneous Select edge
 lda button_edges
 and #$20
 beq wait_start
 lda #0
 sta $2001              ; the bank4 page copies only with rendering disabled
 jsr title_credits_gateway
 cpx #1
 beq start              ; credits Start continues to the existing guide
 jmp copy_begin         ; B restores the logo and its palette
start:
 lda #0
 sta $2001               ; following guide uploads only while blank
 rts
copy_pages:
 ldy #0
copy:
 lda (copy_ptr),y
 sta $2007
 iny
 bne copy
 inc copy_ptr+1
 dex
 bne copy
 rts
.endproc
title_logo_copy_begin = title_logo_present::copy_begin
title_logo_copy_end = title_logo_present::copy_end
title_logo_wait_start = title_logo_present::wait_start
title_logo_start = title_logo_present::start

.proc title_present
 lda #1
 sta title_state
 jsr title_logo_present
copy_begin:
 bit $2002
 lda #$20
 sta $2006
 lda #0
 sta $2006
 lda #<title_name
 sta copy_ptr
 lda #>title_name
 sta copy_ptr+1
 ldx #4
 ldy #0
copy:
 lda (copy_ptr),y
 sta $2007
 iny
 bne copy
 inc copy_ptr+1
 dex
 bne copy
 lda #$3F
 sta $2006
 lda #0
 sta $2006
 ldx #0
palette:
 lda title_palette,x
 sta $2007
 inx
 cpx #32
 bne palette
 jsr title_music_refresh  ; use the persisted setting before showing the guide
copy_end:
 lda #0                  ; nametable0/pattern0, NMI remains disabled
 sta $2000
 sta $2005
 sta $2005
 lda #$0A                ; background only, no uninitialized OAM
 sta $2001
 lda #$13
 sta input_buttons       ; require release before fresh Start/left/right presses
wait_start:
 bit $2002
 bpl wait_start
 jsr read_controller
.if ::MUSIC_ENABLED
 lda button_edges
 and #$03
 beq check_start
 cmp #$03                ; ignore contradictory simultaneous direction edges
 beq check_start
 lsr a                   ; right=$01 -> ON=0; left=$02 -> OFF=1
 cmp music_disabled
 beq check_start
 sta music_disabled
 jsr title_music_refresh ; three nametable bytes, only during polled vblank
check_start:
.endif
 lda button_edges
 and #$10
 beq wait_start
start:
 lda #0
 sta $2001               ; reset restores all normal templates while blank
 rts
.endproc
title_copy_begin = title_present::copy_begin
title_copy_end = title_present::copy_end
title_wait_start = title_present::wait_start
title_start = title_present::start

; Initial call is blanked; later calls follow the guide's vblank poll. NMI
; remains disabled throughout. Restoring both scroll writes prevents a
; nametable-address update from shifting the following visible frame.
.proc title_music_refresh
 bit $2002
 lda #>TITLE_MUSIC_STATE_ADDR
 sta $2006
 lda #<TITLE_MUSIC_STATE_ADDR
 sta $2006
 lda #TITLE_GLYPH_O
 sta $2007
.if ::MUSIC_ENABLED
 lda music_disabled
 beq music_on
.endif
 lda #TITLE_GLYPH_F
 sta $2007
 sta $2007
 jmp restore_scroll
.if ::MUSIC_ENABLED
music_on:
 lda #TITLE_GLYPH_N
 sta $2007
 lda #TITLE_GLYPH_SPACE
 sta $2007
.endif
restore_scroll:
 lda #0
 sta $2005
 sta $2005
 rts
.endproc

.segment "CODE"
; Called only during initial picture preparation, after controller polling.
; Main can render and NMI can upload, but no pause, simulation, gameplay audio,
; clock or latency-input history advances. The commit refresh remains frozen;
; regular play starts with the following refresh. NMI never changes PRG banks.
.proc title_loading_tick
 lda #7
 sta nmi_budget
 jsr ntsc_upload
 lda visible_control
 sta $2000
 lda #0
 sta $2005
 sta $2005
 lda publish_count
 beq done
first_visible:
 lda #$1E
 sta $2001
 lda #0
 sta title_state
done:
 rts
.endproc
title_first_visible = title_loading_tick::first_visible
