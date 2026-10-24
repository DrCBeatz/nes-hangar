; Optional cold-start credits. The complete page lives in PRG bank4; only
; its eleven-byte gateway occupies COMMON, identically mirrored in all banks.
; The title caller has NMI/rendering disabled and bank2 selected. X returns
; zero for B/back or one for Start/guide; the mapper helpers preserve X/Y.
.setcpu "6502"
.import prg_select, prg_boot, read_controller
.importzp input_buttons, button_edges, copy_ptr
.export title_credits_gateway, credits_present
.export credits_copy_begin, credits_copy_end
.export credits_wait_start, credits_back, credits_start

.segment "RODATA"
.proc title_credits_gateway
 lda #4
 jsr prg_select
 jsr credits_present
 jmp prg_boot             ; restore the caller's bank before its RTS
.endproc

.segment "CREDITSDATA"
credits_name: .incbin "credits-nametable.bin"
credits_palette: .incbin "credits-palette.bin"

.proc credits_present
 lda #0
 sta $2000               ; no NMI; this page owns only the pre-game interval
 sta $2001
copy_begin:
 bit $2002
 lda #$20
 sta $2006
 lda #0
 sta $2006
 lda #<credits_name
 sta copy_ptr
 lda #>credits_name
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
 lda credits_palette,x
 sta $2007
 inx
 cpx #32
 bne palette
copy_end:
 lda #0
 sta $2000               ; clear nametable bits left by the palette upload
 sta $2005
 sta $2005
 lda #$0A
 sta $2001               ; fixed font only, with sprites disabled
 lda #$70
 sta input_buttons       ; require fresh B/Select/Start edges on entry
wait_start:
 bit $2002
 bpl wait_start
 jsr read_controller
 lda button_edges
 and #$10
 bne start               ; Start takes priority over a simultaneous B edge
 lda button_edges
 and #$40
 beq wait_start
back:
 ldx #0
 beq done
start:
 ldx #1
done:
 lda #0
 sta $2001               ; both possible next pages upload while blank
 rts
.endproc
credits_copy_begin = credits_present::copy_begin
credits_copy_end = credits_present::copy_end
credits_wait_start = credits_present::wait_start
credits_back = credits_present::back
credits_start = credits_present::start
