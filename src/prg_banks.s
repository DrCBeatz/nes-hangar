; MMC1 mode3: $C000-$FFFF stays fixed; $8000-$BFFF selects a16KiB bank.
; Each switchable bank has identical code/data at $A000-$BFFF. The NMI
; uses only that common region and the fixed bank, and never writes MMC1.
; It can interrupt any serial write without disturbing this transaction.
; No mapper state byte or new RAM is needed: the producer's phases choose
; their bank explicitly, and restore map bank0 before any retry/publication.
.setcpu "6502"
.export prg_map, prg_art, prg_boot, prg_render, prg_select
.export prg_select_first_write, prg_select_commit, prg_select_end
.export PRG_MAP_BANK, PRG_ART_BANK, PRG_BOOT_BANK, PRG_RENDER_BANK
.export mmc1_bootstrap
.import cold_reset

PRG_MAP_BANK = 0
PRG_ART_BANK = 1
PRG_BOOT_BANK = 2
PRG_RENDER_BANK = 3

.segment "CODE"
.proc prg_map
 lda #PRG_MAP_BANK
 jmp prg_select
.endproc

.proc prg_art
 lda #PRG_ART_BANK
 jmp prg_select
.endproc

.proc prg_boot
 lda #PRG_BOOT_BANK
 jmp prg_select
.endproc

.proc prg_render
 lda #PRG_RENDER_BANK
 ; Fall through to the same fixed-bank serial writer.
.endproc

; A = PRG bank number (bit4 clear keeps WRAM enabled); clobbers A/flags,
; preserves X/Y. Stores are separated by LSR so none is a consecutive-cycle
; MMC1 write. Reset configured mode3 before any of these entry points run.
.proc prg_select
first_write:
 sta $E000
 lsr a
 sta $E000
 lsr a
 sta $E000
 lsr a
 sta $E000
 lsr a
commit:
 sta $E000
end:
 rts
.endproc
prg_select_first_write = prg_select::first_write
prg_select_commit = prg_select::commit
prg_select_end = prg_select::end

; The packer mirrors this last16-byte tail into every physical PRG bank.
; Even an unknown power-on MMC1 mode therefore finds the same reset vector
; and instructions. The write fixes the last bank at $C000 before jumping
; into reset; the next opcode has the same address/content in every bank.
.segment "STARTUP"
.proc mmc1_bootstrap
 sei
 lda #$80
 sta $FFF0
 jmp cold_reset
.endproc
.assert mmc1_bootstrap = $FFF0, lderror, "MMC1 bootstrap moved"
