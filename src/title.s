; Cold-start guide using existing fixed glyphs. This code and its assets are
; only accessed in bank2 while NMI is disabled. Internal retries skip it.
.setcpu "6502"
.include "title-memory.inc"
.import read_controller, ntsc_upload
.importzp input_buttons, button_edges, copy_ptr, nmi_budget
.importzp visible_control, publish_count
.export title_present, title_state, title_wait_start, title_start
.export title_loading_tick, title_first_visible, title_copy_begin, title_copy_end

.segment "BOOTDATA"
title_name: .incbin "title-nametable.bin"
title_palette: .incbin "title-palette.bin"

.proc title_present
 lda #1
 sta title_state
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
copy_end:
 lda #0                  ; nametable0/pattern0, NMI remains disabled
 sta $2000
 sta $2005
 sta $2005
 lda #$0A                ; background only, no uninitialized OAM
 sta $2001
 lda #$10
 sta input_buttons       ; require release before the first fresh Start
wait_start:
 bit $2002
 bpl wait_start
 jsr read_controller
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
