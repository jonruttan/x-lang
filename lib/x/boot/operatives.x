; operatives.x -- do and begin, the sequencing forms (bootstrap)
;
; do is the engine's %seq: each form but the last is evaluated in the caller's
; environment, so a def in the body binds there, and the last is handed to the
; trampoline in tail position.  No forms answers nil; a dotted body raises
; where the walk reaches the dot, the forms before it evaluated.
(def do %seq)

(def begin do)
