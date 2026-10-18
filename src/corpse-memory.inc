; NMI-owned corpse lifecycle in CPU-only nametable space.
; The medkit projection occupies $6EA0..$6EB6; masks begin at $6EC0.
; $80 waits for the first visible publication, 121..1 counts refreshes, 0 absent.
corpse_state = $6EB8
CORPSE_PENDING = $80
CORPSE_DISPLAY_FRAMES = 120
