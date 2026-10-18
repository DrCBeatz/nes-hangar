; Single-actor area handoff across the original passage, with four-unit
; hysteresis. Outgoing actor/corpse visibility is an accepted prototype edge.
; All helpers are fixed CODE: NMI never accesses the changing PRG window.
.importzp player_x, player_z, zombie_x, zombie_z
.import active_encounter
.include "coordinate-memory.inc"
.include "encounters-config.inc"
.export encounter_select, encounter_line_of_sight

; Fractions are accepted at the lower bound and rejected above the exact
; upper bound. Retain the compact same-page form for three of four ranges.
.macro coordinate_range low, high, lower, upper, outside
 .local inside, lower_ok
 lda high
 cmp #>lower
 .if (>lower) = (>upper)
 bne outside
 .else
 bcc outside
 bne lower_ok
 .endif
 lda low+1
 cmp #<lower
 bcc outside
 .if (>lower) <> (>upper)
lower_ok:
 lda high
 cmp #>upper
 bcc inside
 bne outside
 lda low+1
 .endif
 cmp #<upper
 bcc inside
 bne outside
 lda low
 bne outside
inside:
.endmacro

.segment "CODE"
.proc encounter_select
 lda active_encounter
 beq from_first
 ; The pre-exit room reaches west of the old X gate. It remains encounter 1;
 ; returning to encounter 0 also requires being north of the old map's cap.
 lda player_z_hi
 cmp #>ENCOUNTER_GATE_REVERSE_Z_MIN
 bcc unchanged
 bne reverse_x
 lda player_z+1
 cmp #<ENCOUNTER_GATE_REVERSE_Z_MIN
 bcc unchanged
reverse_x:
 lda player_x_hi
 cmp #>ENCOUNTER_GATE_REVERSE_X
 bcc first
 bne unchanged
 lda player_x+1
 cmp #<ENCOUNTER_GATE_REVERSE_X
 bcc first
 bne unchanged
 lda player_x
 bne unchanged
first:
 lda #0
 rts
from_first:
 lda player_x_hi
 cmp #>ENCOUNTER_GATE_FORWARD_X
 bcc unchanged
 bne second
 lda player_x+1
 cmp #<ENCOUNTER_GATE_FORWARD_X
 bcc unchanged
second:
 lda #1
 rts
unchanged:
 lda active_encounter
 rts
.endproc

; Every point of the second movement box is in the main room's visibility
; kernel. A legal player center in that room therefore has wall-clear LOS.
; The passage is deliberately excluded, including attack-time rechecks.
.proc encounter_line_of_sight
 coordinate_range zombie_x,zombie_x_hi,::ENCOUNTER1_X_MIN,::ENCOUNTER1_X_MAX,outside
 coordinate_range zombie_z,zombie_z_hi,::ENCOUNTER1_Z_MIN,::ENCOUNTER1_Z_MAX,outside
 coordinate_range player_x,player_x_hi,::ENCOUNTER1_LOS_X_MIN,::ENCOUNTER1_LOS_X_MAX,outside
 coordinate_range player_z,player_z_hi,::ENCOUNTER1_LOS_Z_MIN,::ENCOUNTER1_LOS_Z_MAX,outside
 sec
 rts
outside:
 clc
 rts
.endproc
