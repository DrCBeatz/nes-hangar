; Producer records are private to their bank until its publication. The
; zombie's consumed 32-byte column mask becomes eight prepared OAM entries.
CORPSE_PROJECT0 = $6EB9
CORPSE_PROJECT1 = $7EB9
CORPSE_PREPARED_OAM0 = $6EC0
CORPSE_PREPARED_OAM1 = $7EC0
CORPSE_PREPARED_PATTERNS0 = $6B80
CORPSE_PREPARED_PATTERNS1 = $7B80
C_LEFT = 0
C_FOOT = 2
C_SIZE = 4
C_COUNT = 5
C_CULL = 6

; Published cache is NMI-owned. Copy only after timing-critical PPU writes.
corpse_quick_patterns0 = $6C00 ; first96 pattern bytes
corpse_quick_patterns1 = $7C00 ; last32 pattern bytes
corpse_quick_oam = $7C20      ; eight entries, hidden entries have Y=$FF
corpse_quick_ready = $7C40
corpse_quick_pending = $7C41
corpse_quick_published = $7C42
corpse_preparing = $7C43      ; producer-only compositor mode flag
corpse_prepare_scratch = $7C44 ; producer-only, exactly9 bytes; $7C4D..5F is wide-coordinate state
corpse_quick_cull = $7EB8

CORPSE_QUICK_FIRST_TILE = 248
CORPSE_NORMAL_PATTERN_CAPACITY = 184
