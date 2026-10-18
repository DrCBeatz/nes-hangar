; Main-only static screen. Enter with bank2 selected after producer unwinds.
; NMI owns blank/show boundaries; state3 gives main exclusive PPU ownership.
.setcpu "6502"
.import results_screen_state, results_kills, results_items
.import results_minutes, results_seconds
.importzp copy_ptr, temp
.export results_present, results_copy_begin, results_copy_end, results_wait_start
.include "results-config.inc"

.segment "BOOTDATA"
results_name: .incbin "results-nametable.bin"
results_palette: .incbin "results-palette.bin"

.proc results_present
 lda #2
 sta results_screen_state
wait_blank:
 lda results_screen_state
 cmp #3
 bne wait_blank
copy_begin:
 bit $2002
 lda #$20
 sta $2006
 lda #0
 sta $2006
 lda #<results_name
 sta copy_ptr
 lda #>results_name
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
 lda results_palette,x
 sta $2007
 inx
 cpx #32
 bne palette
 lda #>RESULTS_KILLS_ADDR
 sta $2006
 lda #<RESULTS_KILLS_ADDR
 sta $2006
 lda results_kills
 clc
 adc #RESULTS_DIGIT_ZERO
 sta $2007
 lda #>RESULTS_ITEMS_ADDR
 sta $2006
 lda #<RESULTS_ITEMS_ADDR
 sta $2006
 lda results_items
 clc
 adc #RESULTS_DIGIT_ZERO
 sta $2007
 lda #>RESULTS_MINUTES_ADDR
 sta $2006
 lda #<RESULTS_MINUTES_ADDR
 sta $2006
 lda results_minutes
 jsr decimal_two
 lda #>RESULTS_SECONDS_ADDR
 sta $2006
 lda #<RESULTS_SECONDS_ADDR
 sta $2006
 lda results_seconds
 jsr decimal_two
copy_end:
 lda #4
 sta results_screen_state
wait_start:
 lda results_screen_state
 cmp #6
 bne wait_start
 rts
.endproc
results_copy_begin = results_present::copy_begin
results_copy_end = results_present::copy_end
results_wait_start = results_present::wait_start

.proc decimal_two
 ldx #RESULTS_DIGIT_ZERO
tens:
 cmp #10
 bcc ones
 sbc #10
 inx
 bne tens
ones:
 sta temp
 stx $2007
 lda temp
 clc
 adc #RESULTS_DIGIT_ZERO
 sta $2007
 rts
.endproc
