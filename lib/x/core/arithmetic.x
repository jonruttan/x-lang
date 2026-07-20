; arithmetic.x -- Variadic arithmetic wrappers
;
; Wraps binary C arithmetic primitives into variadic functions using fold.
; Requires: core/list.x (fold)

; Save integer primitives before overriding
(def %int+ +)
(def %int- -)
(def %int* *)
(def %int/ /)
(def %int% %)
(def %int< <)
(def %int= =)
(def %int-number? number?)
(def %int& &)
(def %int-or |)
(def %int^ ^)
(def %int<< <<)
(def %int>> >>)
(def %int~ ~)

; The BINARY case bypasses fold entirely: (op a b) is the overwhelming
; shape (every counter, every digit loop), and the fold entry costs
; ~1,100 objects per call (per-step churn -- the measured 2026-07-16
; allocation disease).  0/1/2-arg tiers touch no list machinery.
(set! +
  (fn (_ . args)
    (if (eq? args ()) 0
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int+ (first args) (first (rest args)))
          (fold %int+ (first args) (rest args)))))))
(set! *
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int* (first args) (first (rest args)))
          (fold %int* (first args) (rest args)))))))
(set! /
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int/ (first args) (first (rest args)))
          (fold %int/ (first args) (rest args)))))))
(set! -
  (fn (_ . args)
    (if (eq? args ())
      0
      (if (eq? (rest args) ())
        (%int- 0 (first args))
        (if (eq? (rest (rest args)) ())
          (%int- (first args) (first (rest args)))
          (fold %int- (first args) (rest args)))))))
(set! %
  (fn (_ . args)
    ; The zero-arg tier is an ERROR, not an identity (#72, ruled): unlike
    ; + - * /, % has no meaningful identity element, and spec.md's old
    ; "(%) -> 0" claim was arbitrary. Without this tier (%) fell through to
    ; (first ()) -- the documented-unchecked prim -- and segfaulted.
    (if (eq? args ()) (%arith-arity "%: needs at least one argument")
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int% (first args) (first (rest args)))
          (fold %int% (first args) (rest args)))))))

; --- Arity guards for the binary/unary C primitives (#72) ---
;
; These prims take their operands positionally and use them unchecked, so a
; missing operand arrives as NULL and the process dies -- (& 6) and (< 1) both
; segfaulted, and a REPL user typing either lost the session. The guard belongs
; here rather than in C: the core stays the unchecked processor, and this is
; the same layer that already gives + - * / their 0/1/2-arg tiers.
;
; Shape matters for cost. The checks are INLINE and the shared helper is only
; reached on the failing path, so the good path pays two eq? tests and no extra
; call -- the same shape as the binary tier above. The saved %int-* prims are
; untouched, so hot internal callers (bignum, dict) that fetch them directly
; are unaffected.
(def %arith-arity (fn (_ msg) (error msg)))

(set! &
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "&: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity "&: needs two arguments")
        (%int& (first args) (first (rest args)))))))
(set! |
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "|: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity "|: needs two arguments")
        (%int-or (first args) (first (rest args)))))))
(set! ^
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "^: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity "^: needs two arguments")
        (%int^ (first args) (first (rest args)))))))
(set! <<
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "<<: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity "<<: needs two arguments")
        (%int<< (first args) (first (rest args)))))))
(set! >>
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity ">>: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity ">>: needs two arguments")
        (%int>> (first args) (first (rest args)))))))
(set! ~
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "~: needs one argument")
      (%int~ (first args)))))
(set! <
  (fn (_ . args)
    (if (eq? args ()) (%arith-arity "<: needs two arguments")
      (if (eq? (rest args) ()) (%arith-arity "<: needs two arguments")
        (%int< (first args) (first (rest args)))))))

(doc (provide x/core/arithmetic)
  "Variadic +, -, *, /, % folded over the binary C primitives.")
