; Pause state and sound control shadows in unused dirty-list tail bytes.
; Offsets112..117 belong to completion;127 is the slime timer.
.ifndef PAUSE_MEMORY_INCLUDED
PAUSE_MEMORY_INCLUDED = 1
.import nt_dirty_list
pause_active = nt_dirty_list+118
pause_sound_pulse1 = nt_dirty_list+119
pause_sound_pulse2 = nt_dirty_list+120
pause_sound_noise = nt_dirty_list+121
pause_cue_timer = nt_dirty_list+122
pause_cue_direction = nt_dirty_list+123
.assert pause_cue_direction < nt_dirty_list+127, error, "Pause overlaps slime timer"
.endif
