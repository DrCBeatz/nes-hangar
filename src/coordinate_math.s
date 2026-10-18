; NMI-only full-width absolute displacement, shared by close-range tests.
.setcpu "6502"
.include "coordinate-memory.inc"
.import zombie_delta
.export coordinate_abs_delta
.segment "RODATA"
; Input signed24: zombie_delta low word, coordinate_nmi_scratch+2 high byte.
; Output unsigned24 magnitude in same locations; carry set iff >=256 units.
; All callers reject far magnitudes before using their original square tables.
.proc coordinate_abs_delta
 lda coordinate_nmi_scratch+2
 bpl positive
 lda #0
 sec
 sbc zombie_delta
 sta zombie_delta
 lda #0
 sbc zombie_delta+1
 sta zombie_delta+1
 lda #0
 sbc coordinate_nmi_scratch+2
 sta coordinate_nmi_scratch+2
positive:
 lda coordinate_nmi_scratch+2
 cmp #1
 rts
.endproc
