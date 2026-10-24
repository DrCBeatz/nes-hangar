; Persistent audio state replaces duplicate odd-column raster storage.
; All four unique samples per tile and all 18 viewport rows remain intact.
; This block is independent of both staged WRAM buffers and NMI ZP scratch.
.ifndef AUDIO_MEMORY_INCLUDED
AUDIO_MEMORY_INCLUDED = 1
AUDIO_WORKSPACE_BASE = $0543
AUDIO_WORKSPACE_BYTES = 216
AUDIO_WORKSPACE_LIMIT = AUDIO_WORKSPACE_BASE+AUDIO_WORKSPACE_BYTES
; Audio may borrow movement_scratch_begin..+7 only at the NMI tail, after
; movement/collision/AI calls finish, or during init with NMI disabled.
; Its first eight bytes are transient; floor/eye at offsets13/14 are not.
AUDIO_ZP_BYTES = 8
.endif
