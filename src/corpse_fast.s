; NMI-only cache and two-refresh corpse overlay. Reserved CHR tiles 248..255
; are never ordinary world/pistol/item patterns. Producer scratch is separate.
.setcpu "6502"
.macpack longbranch
.include "corpse-memory.inc"
.include "medkit-memory.inc"
.importzp visible_buffer, visible_zombie_hp, visible_zombie_epoch, zombie_epoch
.import zombie_hp, zombie_visible, zombie_visible_target, zombie_dirty
.export corpse_fast_reset, corpse_fast_request, corpse_fast_latch, corpse_fast_upload
.export corpse_fast_shown, corpse_fast_upload_end, corpse_fast_upload_done
.export quick_ready, quick_pending, quick_published, quick_cull, quick_patterns0, quick_patterns1, quick_oam
quick_patterns0 = $6C00
quick_patterns1 = $7C00
quick_oam = $7C20
quick_ready = $7C40
quick_pending = $7C41
quick_published = $7C42
quick_cull = $7EB8

.segment "CODE"
.proc corpse_fast_reset
 lda #0
 sta quick_ready
 sta quick_pending
 sta quick_published
 rts
.endproc

.proc corpse_fast_request
 lda quick_ready
 beq done
 lda #1
 sta quick_pending
done:
 rts
.endproc

; Called after the final timing-critical PPU write, before gameplay. At this
; point main cannot overwrite the just-published bank's prepared CPU image.
.proc corpse_fast_latch
 lda quick_published
 beq done
 lda #0
 sta quick_published
 sta quick_ready
 lda visible_zombie_hp
 beq done
 bmi done
 lda visible_zombie_epoch
 cmp zombie_epoch
 bne done
 lda zombie_hp
 beq done
 lda visible_buffer
 bne bank1
 .repeat 2,B
 .if B = 1
bank1:
 .endif
 lda $6EBE+B*$1000
 beq done
 ldx #95
@pattern0:
 lda $6B80+B*$1000,x
 sta quick_patterns0,x
 dex
 bpl @pattern0
 ldx #31
@pattern1:
 lda $6BE0+B*$1000,x
 sta quick_patterns1,x
 lda $6EC0+B*$1000,x
 sta quick_oam,x
 dex
 bpl @pattern1
 lda $6EBF+B*$1000
 sta quick_cull
 lda $6EBE+B*$1000
 sta quick_ready
 rts
 .endrepeat
done:
 rts
.endproc

; Dedicated VBlank. The previous refresh applied pistol feedback and hid the
; standing body. No world upload or OAM DMA shares this refresh.
.proc corpse_fast_upload
 lda visible_buffer
 asl a
 asl a
 asl a
 asl a
 ora #$0F
 sta $2006
 lda #$80
 sta $2006
 ldx #0
@patterns0:
 .repeat 16,I
 lda quick_patterns0+I,x
 sta $2007
 .endrepeat
 txa
 clc
 adc #16
 tax
 cpx #96
 bne @patterns0
 ldx #0
@patterns1:
 .repeat 16,I
 lda quick_patterns1+I,x
 sta $2007
 .endrepeat
 txa
 clc
 adc #16
 tax
 cpx #32
 bne @patterns1
 lda visible_medkit_swap
 beq normal
 lda #192
 bne first
normal:
 lda #64
first:
 sta $2003
 ldx #0
 jsr oam16
 lda #80
 sta $2003
 ldx #16
 jsr oam16
 ; Hide only item entries which would exceed eight sprites on a scanline.
 ; Depth sorting may exchange the first four zombie and item entries.
 lda visible_medkit_swap
 beq kit_normal
 ldx #64
 bne kit_begin
kit_normal:
 ldx #192
kit_begin:
 ldy #4
@kit:
 lsr quick_cull
 bcc @next
 stx $2003
 lda #$FF
 sta $2004
@next:
 txa
 clc
 adc #4
 tax
 dey
 bne @kit
 lda #$3F
 sta $2006
 lda #$19
 sta $2006
 lda #$0F
 sta $2007
 lda #$18
 sta $2007
 lda #$37
 sta $2007
 lda #$80
 sta visible_zombie_hp
 lda #(CORPSE_DISPLAY_FRAMES+1)
 sta corpse_state
 lda #1
 sta zombie_visible
 lda #0
 sta zombie_visible_target
 sta zombie_dirty
 sta quick_pending
 sta quick_ready
 sta $2003
shown:
 rts
.endproc
corpse_fast_shown = corpse_fast_upload::shown
corpse_fast_upload_end = corpse_fast_upload::shown
corpse_fast_upload_done = corpse_fast_upload::shown

.proc oam16
 .repeat 16,I
 lda quick_oam+I,x
 sta $2004
 .endrepeat
 rts
.endproc
