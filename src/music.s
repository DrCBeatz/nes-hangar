; FamiStudio experimental integration. Playback and song data are always visible.
; Reset-only engine initialization lives in BOOTDATA with NMI disabled.
; Only reset with NMI off or the NMI tail may borrow movement's scratch ZP.
.setcpu "6502"
.include "audio-memory.inc"
.import audio_music_regs, audio_music_active, audio_reset, audio_mix
.import prg_boot, prg_map
.import pause_active, title_state, results_screen_state, pistol_health
.export music_init, music_tick, music_disabled
.importzp movement_scratch_begin

FAMISTUDIO_CFG_EXTERNAL = 1
FAMISTUDIO_CFG_NTSC_SUPPORT = 1
FAMISTUDIO_CFG_PAL_SUPPORT = 0
FAMISTUDIO_CFG_SFX_SUPPORT = 0
FAMISTUDIO_CFG_DPCM_SUPPORT = 0
FAMISTUDIO_CFG_SMOOTH_VIBRATO = 0
; Required by Dr. C Beatz's new E1M1 export (2026-10-24). Native FamiStudio tempo; no DPCM.
FAMISTUDIO_USE_FAMITRACKER_TEMPO = 0
FAMISTUDIO_USE_VOLUME_TRACK = 1
FAMISTUDIO_USE_VIBRATO = 1
FAMISTUDIO_USE_DUTYCYCLE_EFFECT = 0
FAMISTUDIO_APU_BASE = audio_music_regs
.define FAMISTUDIO_CA65_ZP_SEGMENT AUDIO_ZP
.define FAMISTUDIO_CA65_RAM_SEGMENT AUDIO_ENGINE
.define FAMISTUDIO_CA65_CODE_SEGMENT AUDIO_CODE
FAMISTUDIO_CFG_BANKED_INIT = 1
.define FAMISTUDIO_CA65_INIT_SEGMENT BOOTDATA
.include "../vendor/famistudio/famistudio_ca65.s"
.assert famistudio_r0 = movement_scratch_begin, lderror, "Audio scratch alias moved"

; The guide owns this one-byte preference. Reset preserves it across the
; gameplay RAM clear; audio_reset clears only mixer state, not this setting.
.segment "AUDIO_SETTINGS"
music_disabled: .res 1       ; 0 music enabled, 1 sound effects only
.assert music_disabled >= AUDIO_WORKSPACE_BASE, lderror, "Music preference precedes audio workspace"
.assert music_disabled < AUDIO_WORKSPACE_LIMIT, lderror, "Music preference exceeds audio reserve"

.segment "AUDIO_CODE"
.proc music_init
 jsr prg_boot              ; fixed trampoline: reset-only setup, NMI disabled
 jmp music_init_banked
.endproc

.segment "BOOTDATA"
.proc music_init_banked
 jsr audio_reset
 lda #1                   ; NTSC (only NTSC compiled here)
 ldx #<music_data_untitled   ; project label supplied by the FamiStudio export
 ldy #>music_data_untitled
 jsr famistudio_init
 lda #0
 jsr famistudio_music_play
 jmp prg_map               ; fixed mapper routine restores map before returning
.endproc

.segment "AUDIO_CODE"
.proc music_tick
 lda #0
 sta audio_music_active
.if ::MUSIC_ENABLED
 lda music_disabled
 bne mix                   ; skip sequencer CPU work as well as music output
 lda title_state
 ora pause_active
 ora results_screen_state
 bne mix
 lda pistol_health
 beq mix
 lda #1
 sta audio_music_active
 jsr famistudio_update
.endif
mix:
 jsr audio_mix
music_tick_end:
 rts
.endproc
.export music_tick_end := music_tick::music_tick_end
.include "../music/e1m1/e1m1-drcbeatz.s"
