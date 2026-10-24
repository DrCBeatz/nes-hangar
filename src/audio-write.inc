; Original effects request APU register values in RAM. The common NMI-tail
; mixer is the sole hardware writer and gives these requests priority over
; music. Stores preserve the caller's registers and processor flags.
.ifndef AUDIO_WRITE_INCLUDED
AUDIO_WRITE_INCLUDED = 1
.import audio_sfx_regs, audio_sfx_trigger

.macro AUDIO_SFX_WRITE reg
 .assert reg >= $4000 .and reg <= $4017, error, "SFX register outside audio shadow"
 sta audio_sfx_regs + (reg - $4000)
 ; A high-register write is an explicit length/envelope restart even when its
 ; value has not changed. Counters preserve that event without resetting the
 ; pulse phase on every ordinary mixer update. Fewer than256 triggers can
 ; occur between mixer calls; wraparound therefore remains unambiguous.
 .if reg = $4003 .or reg = $4007 .or reg = $400B .or reg = $400F
  php
  inc audio_sfx_trigger + ((reg - $4003) / 4)
  plp
 .endif
.endmacro
.endif
