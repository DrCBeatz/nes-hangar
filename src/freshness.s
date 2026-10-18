; Main-thread presentation scheduling for the optional NTSC latency experiment.
; This never changes buffer ownership or cancels a render/upload. Before taking
; a camera snapshot, wait until the older view's remaining transfer is about as
; long as the preceding render, plus an optional physical-frame margin.
; The default zero margin favors fresher poses; a longer render may briefly
; leave the uploader waiting. A two-frame margin remains a build comparison.
; All state here belongs to the producer. NMI may increment scene_version when
; simulation changes the world; include it in render_begin's coherent snapshot.
.setcpu "6502"
.macpack longbranch
.include "coordinate-memory.inc"
.ifndef FRESHNESS_MARGIN
FRESHNESS_MARGIN = 0
.endif
.export FRESHNESS_MARGIN
.importzp nmi_count, nmi_count_hi, player_x, player_z, pending_angle, requested_mode
.importzp render_x, render_z, render_angle, render_mode, render_buffer
.importzp upload_phase, upload_blocks, nt_upload_index
.importzp zombie_x, zombie_z, render_zombie_x, render_zombie_z
.import buffer_state, buffer_tile_count, nt_dirty_count
.export freshness_gate, freshness_begin, freshness_complete
.exportzp scene_version, render_scene_version
.exportzp freshness_gate_reason, freshness_remaining, freshness_last_span
.exportzp freshness_valid, freshness_last_x, freshness_last_z
.exportzp freshness_last_angle, freshness_last_mode, freshness_last_scene
.exportzp freshness_last_zombie_x, freshness_last_zombie_z
.exportzp freshness_render_start

.segment "ZEROPAGE"
; Non-motion world mutations increment this even when the camera is stationary.
; Actor coordinates are compared separately, so continuous motion cannot wrap it.
; Zero initialization and increment wrap are safe provided fewer than 256 world
; changes occur between successfully completed views. A future faster simulation
; should widen this version instead of silently relying on that bound.
scene_version: .res 1
render_scene_version: .res 1
freshness_valid: .res 1
freshness_last_x: .res 2
freshness_last_z: .res 2
freshness_last_angle: .res 1
freshness_last_mode: .res 1
freshness_last_scene: .res 1
freshness_last_zombie_x: .res 2
freshness_last_zombie_z: .res 2
freshness_render_start: .res 2
freshness_last_span: .res 1
; Observable diagnostics: reason 0=allow, 1=identical, 2=upload still too early.
freshness_gate_reason: .res 1
freshness_remaining: .res 1
; Private scratch, never touched by NMI.
freshness_snapshot: .res 1
freshness_snapshot_hi: .res 1
freshness_patterns: .res 1
freshness_names: .res 1
freshness_threshold: .res 1
freshness_decision: .res 1

.segment "CODE"
; Call only while render_buffer's state is free, immediately before render_begin.
; Returns carry set to render or clear to try again. A/X are scratch, Y preserved.
.proc freshness_gate
@retry:
 lda nmi_count
 sta freshness_snapshot
 lda #0
 sta freshness_remaining
 sta freshness_gate_reason
 lda freshness_valid
 jeq @changed
 lda player_x
 cmp freshness_last_x
 jne @changed
 lda player_x+1
 cmp freshness_last_x+1
 jne @changed
 lda player_x_hi
 cmp freshness_last_x_hi
 jne @changed
 lda player_z
 cmp freshness_last_z
 jne @changed
 lda player_z+1
 cmp freshness_last_z+1
 jne @changed
 lda player_z_hi
 cmp freshness_last_z_hi
 jne @changed
 lda pending_angle
 cmp freshness_last_angle
 jne @changed
 lda requested_mode
 cmp freshness_last_mode
 jne @changed
 lda scene_version
 cmp freshness_last_scene
 jne @changed
 ; Actor movement is a separate freshness key. Do not wrap an eight-bit
 ; scene counter on every simulation tick or cancel in-flight pictures.
 lda zombie_x
 cmp freshness_last_zombie_x
 jne @changed
 lda zombie_x+1
 cmp freshness_last_zombie_x+1
 jne @changed
 lda zombie_x_hi
 cmp freshness_last_zombie_x_hi
 jne @changed
 lda zombie_z
 cmp freshness_last_zombie_z
 jne @changed
 lda zombie_z+1
 cmp freshness_last_zombie_z+1
 jne @changed
 lda zombie_z_hi
 cmp freshness_last_zombie_z_hi
 jne @changed
 lda #1
 sta freshness_gate_reason
 lda #0
 jmp @consistent
@changed:
 lda render_buffer
 eor #1
 tax
 lda buffer_state,x
 cmp #2
 beq @queued
 cmp #3
 beq @uploading
 ; No older completed view owns the other bank, so do not delay startup.
 lda #1
 jmp @consistent
@queued:
 lda buffer_tile_count,x
 sta freshness_patterns
 lda nt_dirty_count,x
 sta freshness_names
 jmp @remaining
@uploading:
.ifdef COMBAT
 lda upload_phase
 cmp #2
 bne :+
 lda #1                 ; completed transfer awaits its dedicated DMA/commit NMI
 sta freshness_remaining
 jmp @compare
:
.endif
 lda #0
 sta freshness_patterns
 lda upload_phase
 bne :+
 lda upload_blocks
 sta freshness_patterns
:
 lda nt_dirty_count,x
 sec
 sbc nt_upload_index
 sta freshness_names
@remaining:
 ; Exact transfer opportunities including final publication for the seven-CHR /
 ; six-sparse-NT uploader: P/7 + (D + P%7)/6 + 1, both divisions floor.
.ifdef COMBAT
 lda #2                 ; plus the separate sprite-DMA publication interrupt
.else
 lda #1
.endif
 sta freshness_remaining
 lda freshness_patterns
@patterns:
 cmp #7
 bcc @names_begin
 sec
 sbc #7
 inc freshness_remaining
 bne @patterns           ; count cannot wrap: at most 192 patterns + 64 NT blocks
@names_begin:
 clc
 adc freshness_names
@names:
 cmp #6
 bcc @compare
 sec
 sbc #6
 inc freshness_remaining
 bne @names
@compare:
 lda freshness_last_span
 clc
 adc #FRESHNESS_MARGIN   ; physical frames tolerating variation in render cost
 bcc :+
 lda #$FF
:
 sta freshness_threshold
 lda freshness_remaining
 cmp freshness_threshold
 bcc @allow
 beq @allow
 lda #2
 sta freshness_gate_reason
 lda #0
 jmp @consistent
@allow:
 lda #1
@consistent:
 sta freshness_decision
 lda nmi_count
 cmp freshness_snapshot
 beq @return
 jmp @retry              ; all camera / uploader reads belong to one NMI epoch
@return:
 lda freshness_decision
 lsr a                   ; return allow/wait in carry
 rts
.endproc

; Call after the coherent render pose+scene snapshot, before geometry_frame.
; Preserve X/Y, which render_begin still uses for its destination-buffer metadata.
.proc freshness_begin
@retry:
 lda nmi_count
 sta freshness_render_start
 lda nmi_count_hi
 sta freshness_render_start+1
 lda nmi_count
 cmp freshness_render_start
 bne @retry
 rts
.endproc

; Call only after successful complete rendering, BEFORE publishing buffer state 2.
; Save the completed snapshot, not current input: the camera may have moved while
; rendering. The next gate can skip an identical view even if it is still queued.
; Preserve X/Y so render_done can publish its already-selected buffer safely.
.proc freshness_complete
@retry:
 lda nmi_count
 sta freshness_snapshot
 lda nmi_count_hi
 sta freshness_snapshot_hi
 lda nmi_count
 cmp freshness_snapshot
 bne @retry
 sec
 sbc freshness_render_start
 sta freshness_last_span
 lda freshness_snapshot_hi
 sbc freshness_render_start+1
 bne @saturate
 lda freshness_last_span
 cmp #254
 bcc @snapshot
@saturate:
 lda #253
 sta freshness_last_span
@snapshot:
 lda render_x
 sta freshness_last_x
 lda render_x+1
 sta freshness_last_x+1
 lda render_x_hi
 sta freshness_last_x_hi
 lda render_z
 sta freshness_last_z
 lda render_z+1
 sta freshness_last_z+1
 lda render_z_hi
 sta freshness_last_z_hi
 lda render_angle
 sta freshness_last_angle
 lda render_mode
 sta freshness_last_mode
 lda render_scene_version
 sta freshness_last_scene
 lda render_zombie_x
 sta freshness_last_zombie_x
 lda render_zombie_x+1
 sta freshness_last_zombie_x+1
 lda render_zombie_x_hi
 sta freshness_last_zombie_x_hi
 lda render_zombie_z
 sta freshness_last_zombie_z
 lda render_zombie_z+1
 sta freshness_last_zombie_z+1
 lda render_zombie_z_hi
 sta freshness_last_zombie_z_hi
 lda #1
 sta freshness_valid
 rts
.endproc
