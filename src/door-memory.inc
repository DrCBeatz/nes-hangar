; Persistent and immutable door records occupy unused dirty-list entries48..54.
; The uploader owns at most48 entries in either64-byte stride. No extra RAM.
.ifndef DOOR_MEMORY_INCLUDED
DOOR_MEMORY_INCLUDED = 1
DOOR_CLOSED = 0
DOOR_REQUESTED = 1
DOOR_OPEN = 2
.import door_state, door_near, door_sound_timer
.import render_door, buffer_door, visible_door
.endif
