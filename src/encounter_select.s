; Single-actor area handoffs across the two passages, with independent
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
 cmp #2
 beq from_third
 cmp #1
 bne from_first
 ; Encounter1 enters the third region at or below the exact Z threshold.
 ; Comparing the fraction prevents activation just above that boundary.
 lda player_z_hi
 cmp #>ENCOUNTER2_GATE_FORWARD_Z
 bcc third
 bne reverse_first
 lda player_z+1
 cmp #<ENCOUNTER2_GATE_FORWARD_Z
 bcc third
 bne reverse_first
 lda player_z
 beq third
reverse_first:
 ; The southern extension reaches west of the old X gate. Returning to
 ; encounter0 also requires being north of the old map's cap.
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
from_third:
 ; Any fractional position at Z>=136 crosses the reverse threshold. The
 ; eight-unit band prevents rapid actor swaps at the final passage entrance.
 lda player_z_hi
 cmp #>ENCOUNTER2_GATE_REVERSE_Z
 bcc unchanged
 bne second
 lda player_z+1
 cmp #<ENCOUNTER2_GATE_REVERSE_Z
 bcs second
 bcc unchanged
third:
 lda #2
 rts
unchanged:
 lda active_encounter
 rts
.endproc

; Each movement box is inside its room's visibility kernel. A legal player
; center in that room therefore has wall-clear LOS. Bounds deliberately
; exclude the connecting passages, including attack-time rechecks. In
; particular the third region ends at the exit door, so a player beyond the
; closed door cannot be seen or damaged. No mutable PRG/door data is needed.
.proc encounter_line_of_sight
 lda active_encounter
 cmp #2
 beq third
 coordinate_range zombie_x,zombie_x_hi,::ENCOUNTER1_X_MIN,::ENCOUNTER1_X_MAX,outside
 coordinate_range zombie_z,zombie_z_hi,::ENCOUNTER1_Z_MIN,::ENCOUNTER1_Z_MAX,outside
 coordinate_range player_x,player_x_hi,::ENCOUNTER1_LOS_X_MIN,::ENCOUNTER1_LOS_X_MAX,outside
 coordinate_range player_z,player_z_hi,::ENCOUNTER1_LOS_Z_MIN,::ENCOUNTER1_LOS_Z_MAX,outside
 sec
 rts
outside:
 clc
 rts
third:
 coordinate_range zombie_x,zombie_x_hi,::ENCOUNTER2_X_MIN,::ENCOUNTER2_X_MAX,outside_third
 coordinate_range zombie_z,zombie_z_hi,::ENCOUNTER2_Z_MIN,::ENCOUNTER2_Z_MAX,outside_third
 coordinate_range player_x,player_x_hi,::ENCOUNTER2_LOS_X_MIN,::ENCOUNTER2_LOS_X_MAX,outside_third
 coordinate_range player_z,player_z_hi,::ENCOUNTER2_LOS_Z_MIN,::ENCOUNTER2_LOS_Z_MAX,outside_third
 sec
 rts
outside_third:
 clc
 rts
.endproc
