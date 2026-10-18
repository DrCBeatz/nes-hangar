; NMI-owned completion statistics in the unused tail of the bank1 dirty list.
; The two upload lists have64-byte strides and at most48 entries. Offsets
; 112..126 are never read or written by the uploader; slime_timer owns127.
; These are aliases into existing BSS storage, not new RAM allocations.
.ifndef RESULTS_MEMORY_INCLUDED
RESULTS_MEMORY_INCLUDED = 1
.import nt_dirty_list
results_frames = nt_dirty_list+112
results_seconds = nt_dirty_list+113
results_minutes = nt_dirty_list+114
results_kills = nt_dirty_list+115
results_items = nt_dirty_list+116
results_screen_state = nt_dirty_list+117
; Screen handoff:0gameplay,1completionpending,2requestblank,3NMIblanked,
; 4screenready,5displayed,6restartrequest. Only NMI and the main gateway own it.
; Pause owns118..123; title owns124; offsets125..126 remain unused.
.assert results_screen_state < nt_dirty_list+127, error, "Completion state overlaps slime timer"
.endif
