; Build the alternate death pose alongside a living actor's coherent world
; snapshot. No PPU work and no live/NMI state is changed by this module.
.setcpu "6502"
.macpack longbranch
.include "corpse-fast-memory.inc"
.include "medkit-memory.inc"
.importzp render_buffer, copy_ptr, tile_ptr, tile_count
.importzp z_left,z_foot,z_top,z_size,z_active,z_width,z_height,z_cols,z_rows
.importzp z_mask_ptr,z_oam_ptr,z_oam_index
.import render_zombie_hp, buffer_zombie_visible, zombie_render_shared
.import corpse_widths,corpse_heights,corpse_cols,corpse_rows
.export corpse_save_projection, corpse_prepare

c_med_index = corpse_prepare_scratch
c_med_bit = corpse_prepare_scratch+1
c_cull = corpse_prepare_scratch+2
c_med_base = corpse_prepare_scratch+3
c_row = corpse_prepare_scratch+4
c_rows = corpse_prepare_scratch+5
c_total = corpse_prepare_scratch+6
c_scan = corpse_prepare_scratch+7
c_temp = corpse_prepare_scratch+8

; Called only in the producer art phase; NMI never enters this bank.
.segment "ACTOR_ART"
.proc record_pointer
 lda #<CORPSE_PROJECT0
 sta copy_ptr
 lda render_buffer
 asl a
 asl a
 asl a
 asl a
 ora #>CORPSE_PROJECT0
 sta copy_ptr+1
 rts
.endproc

; Called immediately after zombie_render, before medkit restores its own
; projection registers. An invalid size tag prevents reuse of an older view.
.proc corpse_save_projection
 jsr record_pointer
 lda #0
 ldy #C_COUNT
 sta (copy_ptr),y
 iny
 sta (copy_ptr),y
 lda #$FF
 ldy #C_SIZE
 sta (copy_ptr),y
 lda render_zombie_hp
 beq done
 bmi done
 lda z_active
 beq done
 ldx render_buffer
 lda buffer_zombie_visible,x
 beq done
 ldy #C_LEFT
 lda z_left
 sta (copy_ptr),y
 iny
 lda z_left+1
 sta (copy_ptr),y
 iny
 lda z_foot
 sta (copy_ptr),y
 iny
 lda z_foot+1
 sta (copy_ptr),y
 iny
 lda z_size
 sta (copy_ptr),y
done:
 rts
.endproc

; Called after medkit_render. The world tile pointer/count and immutable
; actor HP are restored; all projection/compositor scratch is now dead.
.proc corpse_prepare
 jsr record_pointer
 ldy #C_SIZE
 lda (copy_ptr),y
 jmi done
 tax
 sta z_size
 lda corpse_widths,x
 sta z_width
 lda corpse_heights,x
 sta z_height
 lda corpse_cols,x
 sta z_cols
 lda corpse_rows,x
 sta z_rows
 ldy #C_LEFT
 lda (copy_ptr),y
 sta z_left
 iny
 lda (copy_ptr),y
 sta z_left+1
 iny
 lda (copy_ptr),y
 sta z_foot
 sec
 sbc z_height
 sta z_top
 iny
 lda (copy_ptr),y
 sta z_foot+1
 sbc #0
 sta z_top+1
 lda #$C0
 sta z_mask_ptr
 lda copy_ptr+1
 sta z_mask_ptr+1
 lda tile_count
 pha
 lda tile_ptr
 pha
 lda tile_ptr+1
 pha
 lda render_zombie_hp
 pha
 lda #$80
 sta render_zombie_hp
 sta tile_ptr
 lda copy_ptr+1
 sec
 sbc #3
 sta tile_ptr+1
 lda #CORPSE_NORMAL_PATTERN_CAPACITY
 sta tile_count
 lda #0
 sta actor_kind
 lda #1
 sta z_active
 sta corpse_preparing
 jsr zombie_render_shared
 lda tile_count
 sec
 sbc #CORPSE_NORMAL_PATTERN_CAPACITY
 ldy #C_COUNT
 sta (copy_ptr),y
 ; Each source column has consumed eight clip limits before it emits up to
 ; eight OAM bytes. Only now may the unused tail of the old mask be erased.
 ldy z_oam_index
 lda #$FF
pad:
 cpy #32
 beq padded
 sta (z_oam_ptr),y
 iny
 bne pad
padded:
 lda #0
 sta corpse_preparing
 pla
 sta render_zombie_hp
 pla
 sta tile_ptr+1
 pla
 sta tile_ptr
 pla
 sta tile_count
 jsr medkit_admission
done:
 rts
.endproc

; The normal medkit was admitted against the standing soldier. Recheck its
; hardware rows against the corpse: a wider prone silhouette can occupy more
; slots near the floor. Admit in existing medkit order, preserving depth/OAM
; priority. <=2 corpse columns plus <=2 medkit and four pistol slots are safe.
.proc medkit_admission
 lda z_cols
 cmp #3
 jcc done
 ldx render_buffer
 lda buffer_medkit_present,x
 jeq done
 lda buffer_medkit_swap,x
 beq normal
 lda #64
 bne med_base
normal:
 lda #192
med_base:
 sta c_med_base
 lda #0
 sta z_mask_ptr
 sta c_med_index
 sta c_cull
 lda z_oam_ptr+1
 clc
 adc #1
 sta z_mask_ptr+1
 lda #1
 sta c_med_bit
candidate:
 lda c_med_index
 jsr med_y
 cmp #239
 bcs next
 clc
 adc #1
 sta c_row
 lda #8
 sta c_rows
row:
 lda #1
 sta c_total
 lda c_row
 cmp #136
 bcc corpse
 cmp #168
 bcs corpse
 lda #5
 sta c_total
corpse:
 ldy #0
corpse_sprite:
 lda (z_oam_ptr),y
 jsr count_sprite
 bcs reject
 iny
 iny
 iny
 iny
 cpy #32
 bne corpse_sprite
 lda #0
 sta c_scan
previous:
 lda c_scan
 cmp c_med_index
 beq next_row
 tax
 lda bits,x
 and c_cull
 bne next_previous
 txa
 jsr med_y
 jsr count_sprite
 bcs reject
next_previous:
 inc c_scan
 bne previous
next_row:
 inc c_row
 dec c_rows
 bne row
 beq next
reject:
 lda c_cull
 ora c_med_bit
 sta c_cull
next:
 asl c_med_bit
 inc c_med_index
 lda c_med_index
 cmp #4
 jne candidate
 lda c_cull
 ldy #C_CULL
 sta (copy_ptr),y
done:
 rts
.endproc

; A=logical medkit index, return hardware Y byte, preserving X.
.proc med_y
 asl a
 asl a
 clc
 adc c_med_base
 tay
 lda (z_mask_ptr),y
 rts
.endproc

; Count a sprite on c_row, preserving X/Y; carry means ninth sprite found.
.proc count_sprite
 cmp #239
 bcs absent
 clc
 adc #1
 sta c_temp
 lda c_row
 sec
 sbc c_temp
 cmp #8
 bcs absent
 inc c_total
 lda c_total
 cmp #9
 rts
absent:
 clc
 rts
.endproc
bits: .byte 1,2,4,8
