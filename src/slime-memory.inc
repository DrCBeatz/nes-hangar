; Immutable world-palette choice associated with each CPU render bank.
; Medkit projection uses $xEA0..$xEB6; these previously unused bytes precede
; the corpse metadata. They are CPU-only and never uploaded as nametable data.
; Zero keeps the accepted brown shade; one gives material2 the slime green.
BUFFER_SLIME0 = $6EB7
BUFFER_SLIME1 = $7EB7
