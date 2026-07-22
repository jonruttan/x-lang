; and-or.x -- Boolean operatives
;
; Requires: operatives.x (if, let), predicates.x (null?)

; eq?-nil instead of null?: null? is an interpreted predicate (~20
; objects/call) while eq? is the free C op, and these loops run per
; and/or ARM across the whole library (the 2026-07-16 disease probes).
(def %and-loop
  (fn (self args e)
    (if (eq? (rest args) ())
      (eval (first args) e)
      (if (eval (first args) e)
        (self (rest args) e)
        #f))))
(doc (def and
  (op args e
    (if (eq? args ()) #t (%and-loop args e))))
  (param args ANY "Zero or more expressions")
  (returns ANY "Last truthy value, or #f if any expression is falsy")
  (example "(and 1 2 3)" "3")
  (example "(and 1 #f 3)" "#f")
  "Short-circuit logical AND. Evaluates left to right, returns #f on first falsy value.")

; The evaluated arm rides a PARAMETER, not a let: the old
; (let ((%v ...)) ...) allocated a fresh closure per or-ARM evaluation
; (~170 objects) -- params are per-activation and near-free.
(def %or-val
  (fn (_ v args e)
    (if v v (%or-loop args e))))
(def %or-loop
  (fn (self args e)
    (if (eq? (rest args) ())
      (eval (first args) e)
      (%or-val (eval (first args) e) (rest args) e))))
(doc (def or
  (op args e
    (if (eq? args ()) () (%or-loop args e))))
  (param args ANY "Zero or more expressions")
  (returns ANY "First truthy value; if none is truthy, the last operand unchanged")
  (example "(or #f 2 3)" "2")
  (example "(null? (or #f ()))" "#t")
  ; or does NOT normalize its failure the way `and` does (#73, ruled): the
  ; last operand passes through, so the falsy answer is whichever of () or #f
  ; the caller supplied last. Both directions ride ONE example inside a list --
  ; a bare (or #f ()) doctest cannot work, since nil renders as an empty line
  ; and the expected string would have to be "".
  (example "(list (or () #f) (or #f ()))" "(#f ())")
  "Short-circuit logical OR. Evaluates left to right, returns the first truthy value; when nothing is truthy the last operand passes through unchanged.")

(doc (provide x/core/boolean and or)
  "Short-circuit logical AND and OR operatives.")
