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

; --- Divisor-zero guard (#80) ---
;
; C's x_prim_div ends in x_intval(a) / x_intval(b) with no zero test, no
; SIGFPE handler exists anywhere, and guard cannot catch a hardware trap --
; so (/ 1 0) killed the whole session, with no message.  The guard belongs
; here per the standing rule: the C core is the unchecked processor.
;
; The gate is %int-number?, the SAVED C number?, deliberately: it is #f for
; every boxed tower instance, so float/rational/bignum divisors fall through
; to the tower's own type-op dispatch untouched ((/ 1.0 0.0) stays IEEE inf,
; rational zero keeps its own error).  Only a C-level integer zero -- the
; one value that reaches raw C division -- is stopped.  eq? alone would NOT
; be a safe gate: it is a raw slot compare, and a boxed zero could collide.
(def %div-zero-guard
  (fn (_ name prim)
    (fn (_ a b)
      (if (if (%int-number? b) (eq? b 0) #f)
        (error (%str-append name ": division by zero"))
        (prim a b)))))
(def %int/0 (%div-zero-guard "/" %int/))
(def %int%0 (%div-zero-guard "%" %int%))

; The BINARY case bypasses fold entirely: (op a b) is the overwhelming
; shape (every counter, every digit loop), and the fold entry costs
; ~1,100 objects per call (per-step churn -- the measured 2026-07-16
; allocation disease).  0/1/2-arg tiers touch no list machinery.
; Nil operands raise INSIDE the C prims (the x_prim_eq nil-safety
; convention, #52 ruled): an x-level test here measured +9% on every method
; dispatch -- the wrapper tiers stay lean on purpose.
(set! +
  (fn (_ . args)
    (if (eq? args ()) 0
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int+ (first args) (first (rest args)))
          (%fold %int+ (first args) (rest args)))))))
(set! *
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int* (first args) (first (rest args)))
          (%fold %int* (first args) (rest args)))))))
(set! /
  (fn (_ . args)
    (if (eq? args ()) 1
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int/0 (first args) (first (rest args)))
          (%fold %int/0 (first args) (rest args)))))))
(set! -
  (fn (_ . args)
    (if (eq? args ())
      0
      (if (eq? (rest args) ())
        (%int- 0 (first args))
        (if (eq? (rest (rest args)) ())
          (%int- (first args) (first (rest args)))
          (%fold %int- (first args) (rest args)))))))
(set! %
  (fn (_ . args)
    ; The zero-arg tier is an ERROR, not an identity (#72, ruled): unlike
    ; + - * /, % has no meaningful identity element, and spec.md's old
    ; "(%) -> 0" claim was arbitrary. Without this tier (%) fell through to
    ; (first ()) -- the documented-unchecked prim -- and segfaulted.
    (if (eq? args ()) (error "%: needs at least one argument")
      (if (eq? (rest args) ()) (first args)
        (if (eq? (rest (rest args)) ())
          (%int%0 (first args) (first (rest args)))
          (%fold %int%0 (first args) (rest args)))))))

; --- Arity guards for the binary/unary C primitives (#72) ---
;
; These prims take their operands positionally and use them unchecked, so a
; missing operand arrives as NULL and the process dies -- (& 6) and (< 1) both
; segfaulted, and a REPL user typing either lost the session. The guard belongs
; here rather than in C: the core stays the unchecked processor, and this is
; the same layer that already gives + - * / their 0/1/2-arg tiers.
;
; ONE new global, not one per operator. The raw prim rides in the wrapper's
; CLOSURE -- (%arith-guard 2 "&" &) is handed the current value of & before
; set! rebinds it -- so no %int& / %int^ / %int<< family lands in the global
; namespace. (The %int+ .. %int= saves above predate this and stay: the tower
; and bignum fetch them by name.)
;
; The arity test runs ONCE, at wrap time, picking the unary or binary closure;
; the returned wrapper only does the checks the operator actually needs.
;
; COUNTING ARGUMENTS IS NOT ENOUGH. A nil operand reaches the prim and is
; dereferenced exactly like a missing one: x_prim_lt reads x_intval(NULL)
; (src/x-prim/pred.c) where x_prim_eq is explicitly nil-safe. The arity tier
; alone therefore left (< 1 ()) live, and with it every derived comparison in
; core/logic.x -- (> 1) binds b to nil and calls (< nil 1), which passes an
; arity test with two arguments and then dies. Reject nil here, once, rather
; than at each caller.
;
; The operator NAME is passed rather than a finished message: two faults now
; need wording, and %str-append (boot/string.x, loaded well before this file)
; builds both without duplicating a literal per operator.
(def %arith-guard
  (fn (_ n name prim)
    (if (eq? n 1)
      (fn (_ . args)
        (match
          ((eq? args ()) (error (%str-append name ": needs one argument")))
          ((null? (first args)) (error (%str-append name ": operand is nil")))
          (#t (prim (first args)))))
      (fn (_ . args)
        (match
          ((eq? args ()) (error (%str-append name ": needs two arguments")))
          ((eq? (rest args) ()) (error (%str-append name ": needs two arguments")))
          ((or (null? (first args)) (null? (first (rest args))))
            (error (%str-append name ": operands must not be nil")))
          (#t (prim (first args) (first (rest args)))))))))

; Strict-INT variant for the BITWISE family (#52 ruled): these have no tower
; semantics -- there is no float `&` and never will be -- so unlike `<`
; (where a strict test would break float comparisons dispatched through the
; C op registry), rejecting every non-INT operand is simply correct. The
; type test is an inline type-of + eq? pair per operand, not a closure call
; (the #51 cost model), and it subsumes the nil test: (%arith-type-of ())
; is nil, which is not the INT handle.
(def %arith-type-of (prim-ref (lit type) (lit of)))
(def %arith-int-t (%arith-type-of 0))
; CHARs pass: they ARE their code points (str-byte-ref returns CHAR and
; utf8 decode masks those bytes with & directly) -- the char/int pun is
; contract here, matching op-guard's exemption.
(def %arith-char-t (%arith-type-of #\A))
(def %arith-int-ok?
  (fn (_ t) (match ((eq? t %arith-int-t) #t) (#t (eq? t %arith-char-t)))))
(def %arith-int-guard
  (fn (_ n name prim)
    (if (eq? n 1)
      (fn (_ . args)
        (match
          ((eq? args ()) (error (%str-append name ": needs one argument")))
          ((not (%arith-int-ok? (%arith-type-of (first args))))
            (error (%str-append name ": operand must be an integer")))
          (#t (prim (first args)))))
      (fn (_ . args)
        (match
          ((eq? args ()) (error (%str-append name ": needs two arguments")))
          ((eq? (rest args) ()) (error (%str-append name ": needs two arguments")))
          ((not (%arith-int-ok? (%arith-type-of (first args))))
            (error (%str-append name ": operands must be integers")))
          ((not (%arith-int-ok? (%arith-type-of (first (rest args)))))
            (error (%str-append name ": operands must be integers")))
          (#t (prim (first args) (first (rest args)))))))))

(set! &  (%arith-int-guard 2 "&"  &))
(set! |  (%arith-int-guard 2 "|"  |))
(set! ^  (%arith-int-guard 2 "^"  ^))
(set! << (%arith-int-guard 2 "<<" <<))
(set! >> (%arith-int-guard 2 ">>" >>))
(set! <  (%arith-guard 2 "<"  <))
(set! ~  (%arith-int-guard 1 "~"  ~))

(doc (provide x/core/arithmetic)
  "Variadic +, -, *, /, % folded over the binary C primitives.")
