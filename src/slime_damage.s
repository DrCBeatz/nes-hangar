; Independent NMI-rate environmental damage, after gameplay and all PPU work.
; Tables conservatively admit only whole unit cells inside the green polygons.
; The player's center chooses the cell: gray walkway and edge slivers are safe.
.setcpu "6502"
.include "coordinate-memory.inc"
.importzp player_x, player_z, player_floor, button_edges, exit_flags
.import pistol_health, player_damage, slime_timer
.export slime_tick, slime_reset, slime_contains, slime_damage_commit
.include "slime-damage-data.inc"
.assert SLIME_Z_MIN >= 0, error, "hazard rows must fit the low Z page"
.assert SLIME_Z_END <= 256, error, "hazard rows must fit the low Z page"
.assert SLIME_X_HIGH = 1, error, "hazard X page changed"

.segment "CODE"
.proc slime_reset
 lda #0
 sta slime_timer
 rts
.endproc

.proc slime_tick
 ; Start wins even if its old live pose was inside slime this refresh.
 lda button_edges
 and #$10
 bne reset
 lda exit_flags
 bmi reset
 lda pistol_health
 beq reset
 jsr slime_contains
 bcc reset
 inc slime_timer
 lda slime_timer
 cmp #SLIME_PERIOD
 bcc done
 lda #0
 sta slime_timer
 lda #SLIME_DAMAGE
damage:
 jmp player_damage
reset:
 jmp slime_reset
done:
 rts
.endproc
slime_damage_commit = slime_tick::damage

; Carry set iff the live Q16.8 center is in a conservative damaging unit cell.
; No scratch, multiplication, map-bank reads, or frame-generation dependency.
.proc slime_contains
 lda player_floor
 cmp #SLIME_FLOOR
 bne safe
 lda player_x_hi
 cmp #SLIME_X_HIGH
 bne safe
 lda player_z_hi
 bne safe
 lda player_z+1
 cmp #SLIME_Z_MIN
 bcc safe
 cmp #SLIME_Z_END
 bcs safe
 sec
 sbc #SLIME_Z_MIN
 tay
 lda player_x+1
 cmp slime_west_first,y
 bcc east
 cmp slime_west_end,y
 bcc hazard
east:
 lda player_x+1
 cmp slime_east_first,y
 bcc safe
 cmp slime_east_end,y
 bcs safe
hazard:
 sec
 rts
safe:
 clc
 rts
.endproc
