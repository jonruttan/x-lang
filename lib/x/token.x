; token.x -- Composable tokenizer state machines
;
; State objects are prim-like objects with extra slots for configurable
; next-state transitions. C analyzer functions read these slots to
; determine where to go instead of using hardcoded transitions.
;
; Slot layout:
;   0: C function pointer (same offset as prim fn)
;   1: next-on-done (returned when the state finishes matching)
;   2: next-on-loop (returned for self-loops, default: self)
;
; When slots are nil, the C function falls back to its original
; hardcoded behavior (backward compatible with plain prims).

; --- State constructor ---

; Create a state object from a C analyzer prim with configurable transitions.
; prim-fn: a C analyzer primitive (e.g. int-analyse-digits)
; next-done: state to transition to on completion (nil = default: score)
; next-loop: state to return for self-loops (nil = default: self)
(def make-state
  (fn (prim-fn next-done next-loop)
    (def s (make-obj (type-of prim-fn) 3))
    ; Copy the function pointer from the prim
    (set-first! s (first prim-fn))
    ; Set configurable transitions
    (obj-set! s 1 next-done)
    (obj-set! s 2 next-loop)
    ; Set X_OBJ_FLAG_STATE (FLAG_3 = 0x4) so C code knows slots exist
    (def %flags-ptr (obj->ptr s))
    (ptr-set-word! %flags-ptr %word-size
      (| (ptr-ref-word %flags-ptr %word-size) 4))
    s))

; --- Tokenizer helpers ---

; Accept: unread last char and set positive score
(def token-accept
  (fn (buffer score chr)
    (buffer-unread buffer)
    (score-set score 1 buffer)))

; Accept inclusive: set positive score without unreading
(def token-accept-inclusive
  (fn (buffer score chr)
    (score-set score 1 buffer)))

(provide x/token
  make-state token-accept token-accept-inclusive)
