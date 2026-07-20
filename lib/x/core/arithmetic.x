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
    (if (eq? args ()) (error "%: needs at least one argument")
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
; ONE new global, not one per operator. The raw prim rides in the wrapper's
; CLOSURE -- (%arith-guard 2 msg &) is handed the current value of & before
; set! rebinds it -- so no %int& / %int^ / %int<< family lands in the global
; namespace. (The %int+ .. %int= saves above predate this and stay: the tower
; and bignum fetch them by name.)
;
; The arity test runs ONCE, at wrap time, picking the unary or binary closure;
; the returned wrapper only does the eq? checks the operator actually needs,
; so the good path costs what the binary tier above costs.
(def %arith-guard
  (fn (_ n msg prim)
    (if (eq? n 1)
      (fn (_ . args)
        (if (eq? args ()) (error msg) (prim (first args))))
      (fn (_ . args)
        (if (eq? args ()) (error msg)
          (if (eq? (rest args) ()) (error msg)
            (prim (first args) (first (rest args)))))))))

(set! &  (%arith-guard 2 "&: needs two arguments"  &))
(set! |  (%arith-guard 2 "|: needs two arguments"  |))
(set! ^  (%arith-guard 2 "^: needs two arguments"  ^))
(set! << (%arith-guard 2 "<<: needs two arguments" <<))
(set! >> (%arith-guard 2 ">>: needs two arguments" >>))
(set! <  (%arith-guard 2 "<: needs two arguments"  <))
(set! ~  (%arith-guard 1 "~: needs one argument"   ~))

(doc (provide x/core/arithmetic)
  "Variadic +, -, *, /, % folded over the binary C primitives.")
