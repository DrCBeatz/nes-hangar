; One static collectible. Reuse the actor projector/pixel compositor, retaining
; an independent, exact wall/floor mask during the streaming world pass.
.setcpu "6502"
.include "coordinate-memory.inc"
.macpack longbranch
.include "medkit-memory.inc"
.include "medkit-config.inc"
.importzp render_buffer, upload_buffer, copy_ptr, render_zombie_x, render_zombie_z
.importzp render_zombie_epoch, zombie_epoch, medkit_state, zombie_oam_ptr
.import render_zombie_hp, zombie_begin_shared, zombie_render_shared
.import medkit_selected_state, pickup_x_lo, pickup_x_hi, pickup_z_lo, pickup_z_hi
.import encounter_visual_pending
.importzp z_left,z_top,z_center,z_foot,z_depth_q8,z_inverse,z_width,z_height,z_size,z_active,z_cols,z_rows,z_mask_ptr,z_oam_ptr
.importzp z_tile_x,z_tile_y,z_oam_index
.importzp g_column,g_top,g_acc,render_mode,g_num
.export medkit_begin, medkit_occlude, medkit_render, medkit_save_metadata, medkit_render_done, medkit_admit_tile
.export medkit_init, medkit_prepare_publish, medkit_upload_effects
.export medkit_hide_zombie_live, medkit_hide_zombie_staged
.export medkit_dirty, render_medkit_state, visible_medkit_swap, buffer_medkit_swap, buffer_medkit_epoch, buffer_medkit_present
.export actor_kind

; Projection record offsets, same in both staging banks.
M_LEFT=0
M_TOP=2
M_CENTER=4
M_FOOT=6
M_DEPTH=8
M_INVERSE=11
M_WIDTH=15
M_HEIGHT=16
M_SIZE=17
M_ACTIVE=18
M_COLS=19
M_ROWS=20
M_MASK=21
M_BYTES=23
; Producer scratch; NMI helpers deliberately use only A/X/Y and their stack.
m_row=medkit_scratch
m_count=medkit_scratch+1
m_index=medkit_scratch+2
m_inner=medkit_scratch+3
m_nearer=medkit_scratch+4
m_temp=medkit_scratch+5

; This ROM bank contains read-only assets and callable code, permanently mapped.
.segment "RODATA"
medkit_state_addresses:
 .byte <z_left,<z_left+1,<z_top,<z_top+1,<z_center,<z_center+1,<z_foot,<z_foot+1
 .byte <z_depth_q8,<z_depth_q8+1,<z_depth_q8+2
 .byte <z_inverse,<z_inverse+1,<z_inverse+2,<z_inverse+3
 .byte <z_width,<z_height,<z_size,<z_active,<z_cols,<z_rows,<z_mask_ptr,<z_mask_ptr+1

; These producer-only helpers run before prg_art, with map bank0 selected.
; Keep project_pointer and medkit_state_addresses mirrored: the art compositor
; also reads them. NMI helpers below remain in the common window.
.segment "MAPDATA"
.proc medkit_begin
 ldx render_buffer
 lda #0
 sta buffer_medkit_swap,x
 sta buffer_medkit_present,x
 lda render_zombie_epoch
 sta buffer_medkit_epoch,x
 ; Clear active even when absent, avoiding the previous use of this bank.
 lda render_buffer
 beq bank0
 lda #0
 sta MEDKIT_PROJECT1+M_ACTIVE
 jmp eligible
bank0:
 lda #0
 sta MEDKIT_PROJECT0+M_ACTIVE
eligible:
 lda render_medkit_state
 jmi done
 ; Temporary producer-only actor coordinates; snapshot lifecycle is unchanged.
 lda render_zombie_hp
 pha
 lda render_zombie_x
 pha
 lda render_zombie_x+1
 pha
 lda render_zombie_x_hi
 pha
 lda render_zombie_z
 pha
 lda render_zombie_z+1
 pha
 lda render_zombie_z_hi
 pha
 lda #1
 sta actor_kind
 sta render_zombie_hp
 lda #0
 sta render_zombie_x
 sta render_zombie_z
 ldx #0
 lda render_medkit_state
 and #$40
 beq :+
 inx
:
 lda pickup_x_lo,x
 sta render_zombie_x+1
 lda pickup_x_hi,x
 sta render_zombie_x_hi
 lda pickup_z_lo,x
 sta render_zombie_z+1
 lda pickup_z_hi,x
 sta render_zombie_z_hi
 jsr zombie_begin_shared
 jsr project_pointer
 ldy #M_BYTES-1
save:
 ldx medkit_state_addresses,y
 lda $00,x
 sta (copy_ptr),y
 dey
 bpl save
 pla
 sta render_zombie_z_hi
 pla
 sta render_zombie_z+1
 pla
 sta render_zombie_z
 pla
 sta render_zombie_x_hi
 pla
 sta render_zombie_x+1
 pla
 sta render_zombie_x
 pla
 sta render_zombie_hp
done:
 rts
.endproc
.proc medkit_save_metadata
 rts
.endproc
.segment "RODATA"
.proc project_pointer
 lda #<MEDKIT_PROJECT0
 sta copy_ptr
 lda render_buffer
 asl a
 asl a
 asl a
 asl a
 clc
 adc #>MEDKIT_PROJECT0
 sta copy_ptr+1
 rts
.endproc

; No geometry scratch is written except dead g_num in coarse mode. The actor
; uses the same exact pair-column spans and reciprocal depths as the zombie.
.macro CLIP_BANK project,mask
.local done, odd,even,depth, near,coarse,pixel,next,pair,compare2,compare1,compare0
 lda project+M_ACTIVE
 jeq done
 lda render_mode
 jne coarse
 lda g_column
 ora #1
 sec
 sbc project+M_LEFT
 tay
 lda #0
 sbc project+M_LEFT+1
 jne done
 tya
 cmp project+M_WIDTH
 bcc pair
 jne done
pair:
 lda g_acc+3
 cmp project+M_INVERSE+3
 bne depth
 lda g_acc+2
 cmp project+M_INVERSE+2
 bne depth
 lda g_acc+1
 cmp project+M_INVERSE+1
 bne depth
 lda g_acc
 cmp project+M_INVERSE
depth:
 bcc done
 tya
 cmp project+M_WIDTH
 bcs even
 lda g_top
 cmp mask,y
 bcs even
 sta mask,y
even:
 tya
 beq done
 dey
 lda g_top
 cmp mask,y
 bcs done
 sta mask,y
done:
 rts
coarse:
 lda g_column
 and #7
 cmp #4
 bne done
 lda g_acc+3
 cmp project+M_INVERSE+3
 bne near
 lda g_acc+2
 cmp project+M_INVERSE+2
 bne near
 lda g_acc+1
 cmp project+M_INVERSE+1
 bne near
 lda g_acc
 cmp project+M_INVERSE
near:
 bcc done
 lda g_top
 clc
 adc #3
 and #$F8
 sta g_num
 lda g_column
 ora #7
 sta g_num+1
 lda g_column
 and #$F8
 tax
pixel:
 txa
 sec
 sbc project+M_LEFT
 tay
 lda #0
 sbc project+M_LEFT+1
 bne next
 tya
 cmp project+M_WIDTH
 bcs next
 lda g_num
 cmp mask,y
 bcs next
 sta mask,y
next:
 cpx g_num+1
 beq done
 inx
 jmp pixel
.endmacro
.segment "MAPDATA"
.proc medkit_occlude
 lda render_buffer
 jne bank1
 CLIP_BANK MEDKIT_PROJECT0,MEDKIT_MASK0
bank1:
 CLIP_BANK MEDKIT_PROJECT1,MEDKIT_MASK1
.endproc

.segment "RODATA"
.proc medkit_render
 jsr project_pointer
 lda #0
 sta m_nearer
 ; OAM priority follows camera depth. Equal depth retains zombie priority.
 lda z_active
 beq restore
 ldy #M_ACTIVE
 lda (copy_ptr),y
 beq restore
 ldy #M_INVERSE+3
 lda (copy_ptr),y
 cmp z_inverse+3
 bne nearer_decided
 dey
 lda (copy_ptr),y
 cmp z_inverse+2
 bne nearer_decided
 dey
 lda (copy_ptr),y
 cmp z_inverse+1
 bne nearer_decided
 dey
 lda (copy_ptr),y
 cmp z_inverse
 beq restore
nearer_decided:
 bcc restore
 inc m_nearer
restore:
 ldy #M_BYTES-1
load:
 ldx medkit_state_addresses,y
 lda (copy_ptr),y
 sta $00,x
 dey
 bpl load
 lda #1
 sta actor_kind
 jsr zombie_render_shared
 ; Count real staged tiles; discarded/fully clipped cases never become visible.
 ldy #192
 ldx #0
visible:
 lda (z_oam_ptr),y
 cmp #$FF
 beq next
 inx
next:
 iny
 iny
 iny
 iny
 cpy #208
 bne visible
 txa
 ldx render_buffer
 sta buffer_medkit_present,x
 cmp #0
 beq done
 lda m_nearer
 beq done
 lda #1
 sta buffer_medkit_swap,x
 ; Exchange only the first four zombie slots. Other zombie slots keep their
 ; original addresses; the two hide helpers account for these four moves.
 ldx #0
swap:
 txa
 clc
 adc #64
 tay
 lda (z_oam_ptr),y
 pha
 txa
 clc
 adc #192
 tay
 lda (z_oam_ptr),y
 pha
 txa
 clc
 adc #64
 tay
 pla
 sta (z_oam_ptr),y
 txa
 clc
 adc #192
 tay
 pla
 sta (z_oam_ptr),y
 inx
 cpx #16
 bne swap
done:
 lda #0
 sta actor_kind
 rts
.endproc
medkit_render_done = medkit_render::done

; Admit all eight hardware rows of a candidate tile, not only opaque rows:
; transparent sprite rows still consume the NES's eight-sprites-per-row limit.
; Reserve the four weapon sprites wherever their scanlines are present. The
; soldier's staged OAM and previously admitted medkit tiles are counted exactly.
.proc medkit_admit_tile
 lda z_tile_y+1
 bne reject
 lda z_tile_y
 sta m_row
 lda #0
 sta m_inner
row:
 lda m_row
 cmp #240
 bcs reject
 lda #1 ; candidate itself
 sta m_count
 lda m_row
 cmp #136
 bcc count
 cmp #168
 bcs count
 lda #5
 sta m_count
count:
 lda #64
 sta m_index
sprite:
 ldy m_index
 lda (z_oam_ptr),y
 cmp #239
 bcs next_sprite
 clc
 adc #1
 sta m_temp
 lda m_row
 sec
 sbc m_temp
 cmp #8
 bcs next_sprite
 inc m_count
 lda m_count
 cmp #9
 bcs reject
next_sprite:
 lda m_index
 clc
 adc #4
 sta m_index
 cmp z_oam_index
 bne sprite
 inc m_row
 inc m_inner
 lda m_inner
 cmp #8
 bne row
 sec
 rts
reject:
 clc
 rts
.endproc

.proc medkit_init
 lda #$3F
 sta $2006
 lda #$1C
 sta $2006
 lda #$0F
 sta $2007
 lda #$2D
 sta $2007
 lda #$16
 sta $2007
 lda #$10                  ; medium-gray medical case
 sta $2007
 lda #0
 sta actor_kind
 sta visible_medkit_swap
 sta buffer_medkit_swap
 sta buffer_medkit_swap+1
 sta buffer_medkit_present
 sta buffer_medkit_present+1
 rts
.endproc

; Called before publication DMA. Never revive collected or pre-restart art.
.proc medkit_prepare_publish
 ldx upload_buffer
 lda buffer_medkit_swap,x
 sta visible_medkit_swap
 jsr medkit_selected_state
 bmi hide
 ldx upload_buffer
 lda buffer_medkit_epoch,x
 cmp zombie_epoch
 bne hide
 rts
hide:
 ldx upload_buffer
 lda buffer_medkit_swap,x
 beq normal
 .repeat 4,I
 ldy #(64+I*4)
 lda #$FF
 sta (zombie_oam_ptr),y
 .endrepeat
 rts
normal:
 .repeat 4,I
 ldy #(192+I*4)
 lda #$FF
 sta (zombie_oam_ptr),y
 .endrepeat
 rts
.endproc

; A dedicated short overlay NMI, after collection/reset. It changes no world,
; weapon, or zombie OAM entries and writes no pattern/nametable memory.
.proc medkit_upload_effects
 ; A new-area pickup must not erase the old world's still-displayed item.
 ; Drop this overlay request; epoch/live-state checks suppress the collected
 ; new item when its matching world is eventually published. Start resets
 ; the pending flag first, so reset still hides every stale item immediately.
 lda encounter_visual_pending
 bne done
 lda visible_medkit_swap
 beq normal
 .repeat 4,I
 lda #(64+I*4)
 sta $2003
 lda #$FF
 sta $2004
 .endrepeat
 jmp done
normal:
 .repeat 4,I
 lda #(192+I*4)
 sta $2003
 lda #$FF
 sta $2004
 .endrepeat
done:
 lda #0
 sta $2003
 sta medkit_dirty
 rts
.endproc

.proc medkit_hide_zombie_live
 ; These 28 zombie slots never move.
 .repeat 28,I
 lda #(80+I*4)
 sta $2003
 lda #$FF
 sta $2004
 .endrepeat
 lda visible_medkit_swap
 beq normal
 .repeat 4,I
 lda #(192+I*4)
 sta $2003
 lda #$FF
 sta $2004
 .endrepeat
 rts
normal:
 .repeat 4,I
 lda #(64+I*4)
 sta $2003
 lda #$FF
 sta $2004
 .endrepeat
 rts
.endproc

.proc medkit_hide_zombie_staged
 lda #$FF
 .repeat 28,I
 ldy #(80+I*4)
 sta (zombie_oam_ptr),y
 .endrepeat
 ldx upload_buffer
 lda buffer_medkit_swap,x
 beq normal
 lda #$FF
 .repeat 4,I
 ldy #(192+I*4)
 sta (zombie_oam_ptr),y
 .endrepeat
 rts
normal:
 lda #$FF
 .repeat 4,I
 ldy #(64+I*4)
 sta (zombie_oam_ptr),y
 .endrepeat
 rts
.endproc
