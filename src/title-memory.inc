; One previously unused dirty-list byte. No additional RAM allocation.
.ifndef TITLE_MEMORY_INCLUDED
TITLE_MEMORY_INCLUDED = 1
.import nt_dirty_list
title_state = nt_dirty_list+124
; 0 gameplay,1 boot-only title (NMI disabled),2 first-world preparation.
.assert title_state < nt_dirty_list+127, error, "Title overlaps slime timer"
.endif
