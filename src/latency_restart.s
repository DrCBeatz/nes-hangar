; Bounded producer-only restart policy for stale directional-input snapshots.
; No physics, uploader, queued-buffer or visible-PPU state is changed here.
.setcpu "6502"
.ifndef CAMERA_RETRY
CAMERA_RETRY = 0
.endif
.include "coordinate-memory.inc"
.include "door-memory.inc"
.importzp player_x, player_z, pending_angle, requested_mode
.importzp render_x, render_z, render_angle, render_mode
.importzp scene_version, render_scene_version, medkit_state
.importzp zombie_x, zombie_z, zombie_epoch, zombie_walk_counter
.importzp render_zombie_x, render_zombie_z, render_zombie_epoch, render_zombie_pose
.import zombie_hp, corpse_state, render_zombie_hp, active_encounter, render_medkit_state
.export latency_snapshot_current, latency_current_check, latency_camera_safe
.importzp input_buttons, button_edges, nmi_count
.ifdef LATENCY_HEIGHT_PRIORITY
.importzp render_floor, render_eye, player_floor, player_eye, visible_floor, visible_eye
.export latency_hard_epoch, latency_render_hard_epoch, latency_height_decision
.export latency_height_check, latency_height_protected
.endif
.export latency_job_begin, latency_checkpoint, latency_record_abort, latency_observe_input
.export latency_epoch, latency_render_epoch, latency_budget, latency_abort_count
.export latency_intent, latency_new_intent, latency_check_version, latency_check_epoch

.segment "BSS"
; NMI-owned: main only reads these through its existing NMI snapshot guard.
latency_epoch: .res 2
latency_intent: .res 1
latency_new_intent: .res 1
.ifdef LATENCY_HEIGHT_PRIORITY
latency_hard_epoch: .res 2   ; Select/Start bypass floor-transition presentation priority
.endif
; Main-owned. NMI must never borrow this scratch or alter the job budget.
latency_render_epoch: .res 2
latency_budget: .res 1
latency_abort_count: .res 2
latency_check_version: .res 1
latency_check_epoch: .res 2
.ifdef LATENCY_HEIGHT_PRIORITY
latency_render_hard_epoch: .res 2
latency_height_decision: .res 1  ; coherent decision: 0 preserve, 1 reject
.endif

.segment "CODE"
.proc latency_job_begin
 ; Cap wasted work at ONE abandoned attempt per acquired free bank, even
 ; if controls reverse on every NMI. The second attempt always completes.
 lda #1
 sta latency_budget
 rts
.endproc

.proc latency_observe_input
.ifdef LATENCY_HEIGHT_PRIORITY
 ; Observe hard controls independently: a simultaneous release must not
 ; bypass this epoch via the ordinary direction-change early branch below.
 lda button_edges
 and #$30
 beq :+
 inc latency_hard_epoch
 bne :+
 inc latency_hard_epoch+1
:
.endif
 ; Normalize simultaneous opposites exactly as the movement intent does.
 ; Only A with an active left/right direction distinguishes turn/strafe.
 lda input_buttons
 and #$0F
 sta latency_new_intent
 and #$0C
 cmp #$0C
 bne :+
 lda latency_new_intent
 and #$F3
 sta latency_new_intent
:
 lda latency_new_intent
 and #$03
 cmp #$03
 bne :+
 lda latency_new_intent
 and #$FC
 sta latency_new_intent
:
 lda latency_new_intent
 and #$03
 beq :+
 lda input_buttons
 and #$80
 ora latency_new_intent
 sta latency_new_intent
:
 ; A start, stop, reversal or added direction can all obsolete a camera.
 ; Include starts while an actor update already has the producer occupied;
 ; otherwise that old stationary view may delay the first movement feedback.
 ; The same one-retry budget and current-pose/height protection still apply.
 lda latency_new_intent
 eor latency_intent
 and #$0F
 bne changed
 ; Switching an existing left/right action between turning and strafing
 ; rejects it. A alone without a left/right direction does not request a retry.
 lda latency_intent
 and #$03
 beq controls
 lda latency_new_intent
 eor latency_intent
 and #$80
 bne changed
controls:
 ; Select switches visual mode; Start is a hard UI edge. B firing must not
 ; restart the world renderer. Both hard controls are actual edges.
 lda button_edges
 and #$30
 beq done
changed:
 inc latency_epoch
 bne done
 inc latency_epoch+1
done:
 lda latency_new_intent
 sta latency_intent
 rts
.endproc

.proc latency_checkpoint
 ; C=1 asks the producer to restart. Preserve X/Y. The count guard makes
 ; the two-byte epoch coherent even across low-byte wrap in an NMI.
 lda latency_budget
 beq allowed
snapshot:
 lda nmi_count
 sta latency_check_version
 lda latency_epoch
 sta latency_check_epoch
 lda latency_epoch+1
 sta latency_check_epoch+1
 lda nmi_count
 cmp latency_check_version
 bne snapshot
 lda latency_check_epoch
 cmp latency_render_epoch
.ifdef LATENCY_HEIGHT_PRIORITY
 bne height_snapshot
.else
 bne rejected
.endif
 lda latency_check_epoch+1
 cmp latency_render_epoch+1
.ifdef LATENCY_HEIGHT_PRIORITY
 bne height_snapshot
.else
 bne rejected
.endif
allowed:
 clc
 rts
rejected:
 sec
 rts
.ifdef LATENCY_HEIGHT_PRIORITY
height_snapshot:
 ; Pay for height presentation priority only after ordinary intent changed.
 ; The first view of a new floor height is a useful step cue even if its
 ; pose is slightly old. Protect it only while it still matches simulation;
 ; stepping back again must not force an obsolete height to be published.
 lda nmi_count
 sta latency_check_version
 lda #1
 sta latency_height_decision
 lda latency_hard_epoch
 cmp latency_render_hard_epoch
 bne height_consistent
 lda latency_hard_epoch+1
 cmp latency_render_hard_epoch+1
 bne height_consistent
 ; A soft edge can arrive before the next simulation tick moves the camera.
 ; With CAMERA_RETRY, actor position/walk aging alone must not spend the one
 ; retry on that same camera. Scene/lifecycle/door checks remain mandatory.
 ; Do not acknowledge the intent epoch: later checkpoints must reconsider
 ; the still-pending edge once the camera progresses.
current_check:
 jsr latency_snapshot_current
 bcs height_protected
 lda render_floor
 cmp player_floor
 bne height_consistent
 lda render_eye
 cmp player_eye
 bne height_consistent
 lda visible_eye
 beq height_consistent  ; boot has no published camera yet
 lda render_floor
 cmp visible_floor
 bne height_protected
 lda render_eye
 cmp visible_eye
 beq height_consistent
height_protected:
 lda #0
 sta latency_height_decision
height_consistent:
 lda nmi_count
 cmp latency_check_version
 bne height_snapshot
 lda latency_height_decision
 beq allowed
 jmp rejected
.endif
.endproc
.ifdef LATENCY_HEIGHT_PRIORITY
latency_current_check = latency_checkpoint::current_check
latency_height_check = latency_checkpoint::height_snapshot
latency_height_protected = latency_checkpoint::height_protected
.endif

.proc latency_record_abort
 lda #0
 sta latency_budget
 inc latency_abort_count
 bne :+
 inc latency_abort_count+1
:
 rts
.endproc


; C=1 when it is safe to retain this camera for a soft input edge. CAMERA_RETRY
; ignores only actor position/walk-pose aging; camera, scene, lifecycle, pickup
; and door inputs must still match. Disabled builds retain the original exact
; snapshot predicate. The legacy export remains for existing diagnostic tools.
; Caller guards the whole decision with nmi_count and rejects hard controls.
; A/C are scratch; X/Y and every live/producer/buffer field are untouched.
; Independently published weapon/HUD/palette timers are deliberately absent.
.macro CURRENT_EQUALS live, captured
 lda live
 cmp captured
 beq :+
 clc
 rts
:
.endmacro

.proc latency_snapshot_current
 CURRENT_EQUALS player_x, render_x
 CURRENT_EQUALS player_x+1, render_x+1
 CURRENT_EQUALS player_x_hi, render_x_hi
 CURRENT_EQUALS player_z, render_z
 CURRENT_EQUALS player_z+1, render_z+1
 CURRENT_EQUALS player_z_hi, render_z_hi
 CURRENT_EQUALS pending_angle, render_angle
 CURRENT_EQUALS player_floor, render_floor
 CURRENT_EQUALS player_eye, render_eye
 CURRENT_EQUALS requested_mode, render_mode
 CURRENT_EQUALS scene_version, render_scene_version
 CURRENT_EQUALS zombie_epoch, render_zombie_epoch
.if !::CAMERA_RETRY
 CURRENT_EQUALS zombie_x, render_zombie_x
 CURRENT_EQUALS zombie_x+1, render_zombie_x+1
 CURRENT_EQUALS zombie_x_hi, render_zombie_x_hi
 CURRENT_EQUALS zombie_z, render_zombie_z
 CURRENT_EQUALS zombie_z+1, render_zombie_z+1
 CURRENT_EQUALS zombie_z_hi, render_zombie_z_hi
 lda zombie_walk_counter
 and #$20
 cmp render_zombie_pose
 beq :+
 clc
 rts
:
.endif
 ; Exactly the live/corpse/absent type normalization used by render_begin.
 lda zombie_hp
 bne actor_type
 lda corpse_state
 beq actor_type
 lda #$80
actor_type:
 cmp render_zombie_hp
 beq :+
 clc
 rts
:
 ; Selected collection bit and item type, without borrowing X from the caller.
 lda active_encounter
 beq health_item
 cmp #2
 bcc ammo_item
 lda #$80                  ; third encounter has no pickup
 bne item_type
ammo_item:
 lda medkit_state
 asl a
 and #$80
 ora #$40
 bne item_type
health_item:
 lda medkit_state
 and #$80
item_type:
 cmp render_medkit_state
 beq :+
 clc
 rts
:
 ; Requested and published-open have the same geometry. Start/Select are
 ; handled separately by the caller's hard epoch and existing publication.
 lda door_state
 beq door_type
 lda #1
door_type:
 cmp render_door
 beq :+
 clc
 rts
:
 sec
 rts
.endproc
latency_camera_safe = latency_snapshot_current
