; Exact-position geometry rejection, before expensive endpoint transforms.
; This helper is used only after the existing strict positive plane-side test.
.setcpu "6502"
.include "coordinate-memory.inc"
.importzp render_x, render_z, render_angle
.import opening_candidate, opening_cache, prg_select, prg_map
.import vertex_x, vertex_z, vertex_x_hi, vertex_z_hi
.import segment_vertex1, segment_vertex2
.importzp VERTEX_COUNT
.export axis_gate_begin, axis_gate_init, axis_gate_init_end
.export axis_gate, axis_gate_compare, axis_gate_end
.export gate_axis_offset, gate_threshold_lo, gate_threshold_hi, gate_polarity

; Dead tile-builder scratch, live only during geometry_begin's candidate loop.
; The palette probe reuses it after that loop. No persistent allocation.
gate_axis_offset = opening_candidate
gate_threshold_lo = opening_candidate+1
gate_threshold_hi = opening_candidate+2
gate_polarity = opening_candidate+3
.assert opening_cache >= opening_candidate+4, lderror, "Axis scratch exceeds candidate area"
.assert render_z = render_x+2, lderror, "Axis initializer requires adjacent camera words"
.assert render_z_hi = render_x_hi+1, error, "Axis initializer requires adjacent high bytes"
.assert VERTEX_COUNT <= 128, lderror, "Combined axis lookup exceeds 8-bit index"
.assert vertex_z = vertex_x+VERTEX_COUNT, lderror, "Axis low-coordinate arrays are not adjacent"
.assert vertex_z_hi = vertex_x_hi+VERTEX_COUNT, lderror, "Axis high-coordinate arrays are not adjacent"

; Remains visible during both mapper writes. NMI neither changes the mapper
; nor uses this phase-local scratch. Every return/retry sees map bank0 again.
.segment "CODE"
.proc axis_gate_begin
    lda #6
    jsr prg_select
    jsr axis_gate_init
    jmp prg_map
.endproc

; Existing unused bank6: initialized once per camera snapshot, including retries.
.segment "AXIS_INIT"
.proc axis_gate_init
    lda render_angle
    clc
    adc #32
    sta gate_polarity
    ldy #0
    and #$40
    bne axis_ready
    iny
axis_ready:
    lda axis_offsets,y
    sta gate_axis_offset
    lda render_x_hi,y
    sta gate_threshold_hi
    tya
    asl a
    tax
    lda render_x+1,x
    sta gate_threshold_lo
    ; Positive direction: vertex < floor(camera)+1.
    ; Negative direction: vertex >= ceil(camera), retaining fractional equality.
    lda render_x,x
    bne increment_threshold
    lda gate_polarity
    bmi threshold_ready
increment_threshold:
    inc gate_threshold_lo
    bne threshold_ready
    inc gate_threshold_hi
threshold_ready:
    lda gate_polarity
    asl a
    lda #0
    rol a
    eor #1
    sta gate_polarity
    rts
axis_offsets:
    .byte 0,<VERTEX_COUNT
.endproc
axis_gate_init_end:

; Appended to map bank0 by the builder. No mapper writes in the candidate loop.
; X=segment index, preserved. C=1 rejects; A/Y/flags are scratch. g_den is live
; and untouched. The first failing endpoint returns immediately.
.segment "MAPDATA"
.proc axis_gate
    lda segment_vertex1,x
    clc
    adc gate_axis_offset
    tay
    jsr axis_gate_compare
    bcc done
    lda segment_vertex2,x
    clc
    adc gate_axis_offset
    tay
    jsr axis_gate_compare
done:
    rts
.endproc
.proc axis_gate_compare
    lda vertex_x_hi,y
    cmp gate_threshold_hi
    bne compared
    lda vertex_x,y
    cmp gate_threshold_lo
compared:
    lda #0
    rol a
    eor gate_polarity
    lsr a
    rts
.endproc
axis_gate_end:
