; NTSC-only simulation clock. Movement remains at approximately PAL's 50 Hz
; while controller edges and graphics scheduling continue at NTSC's 60 Hz.
; All state is NMI-owned. Root calls this after time-critical PPU writes.
.setcpu "6502"
.import movement_tick
.export movement_tick_ntsc
.exportzp simulation_count, simulation_count_hi, movement_accumulator

.segment "ZEROPAGE"
simulation_count:     .res 1
simulation_count_hi:  .res 1
movement_accumulator: .res 1

.segment "CODE"
.proc movement_tick_ntsc
    lda movement_accumulator
    clc
    adc #5
    cmp #6
    bcc @skip
    sbc #6                   ; CMP supplied carry: exact sum minus six.
    sta movement_accumulator
    inc simulation_count
    bne :+
    inc simulation_count_hi
:
    ; The normal routine uses simulation_count parity in NTSC builds. Testing
    ; NMI parity here would alternate incorrectly whenever a frame is skipped.
    jmp movement_tick
@skip:
    sta movement_accumulator
    rts
.endproc
