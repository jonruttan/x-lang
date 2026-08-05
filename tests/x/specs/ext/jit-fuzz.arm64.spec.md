# @lib ../tests/x/lib/compile.x

Differential fuzzing of the JIT: generate expressions from its supported
grammar, run each BOTH compiled and interpreted, and require the two to
agree. The interpreter is the oracle — there are no hand-written
expectations to rot.

Arch-tagged: the assembler backend is ARM64 (x86_64 parity is in
progress), so the runner skips this file on other hosts.

**Deterministic on purpose.** A gate that fails differently every run is
unactionable, so the generator is a seeded LCG: a failure prints the
case that broke and the seed that produced it, and rerunning that seed
reproduces it exactly. Widen coverage by raising the case count or
changing the seed — never by making it time-dependent.

**Scope, stated honestly.** The generated expressions are
INTEGER-VALUED: comparisons and the boolean forms appear only inside
`if` tests. That is deliberate, not laziness — the JIT answers `1`/`0`
where the interpreter answers `#t`/`#f`, and the JIT's nil is a raw `0`,
so comparing those directly would test a known, documented boundary
rather than a bug. Division and modulo take non-zero literal divisors
(a zero divisor is a trap in both, not a difference). This runs under
helium: with the numeric tower loaded, interpreted arithmetic would
promote to bignum where the JIT wraps, so the oracle would disagree for
reasons that are not defects.

## differential fuzz

### compiled and interpreted agree across generated expressions

```scheme
(do
  ; --- seeded LCG (Numerical Recipes constants); pure INT ops ---
  (def %seed-cell (pair 20260805 ()))
  (def %rand
    (fn (_ n)
      (%set-first! %seed-cell (& (+ (* (first %seed-cell) 1664525) 1013904223) 4294967295))
      (% (>> (first %seed-cell) 8) n)))

  ; --- generators: integer-valued expr, boolean-valued test ---
  (def %gen-expr ())
  (def %gen-test ())
  (def %leaf
    (fn (_)
      (def %k (%rand 5))
      (if (= %k 0) 'a
        (if (= %k 1) 'b
          (if (= %k 2) (%rand 100)
            ; wide literals: the MOVZ/MOVK boundary (the #189 class)
            (if (= %k 3) (+ 65500 (%rand 200)) (+ 100000 (%rand 900000))))))))
  (set! %gen-expr
    (fn (_ d)
      (if (<= d 0) (%leaf)
        (let ((k (%rand 8)))
          (if (= k 0) (list '+ (%gen-expr (- d 1)) (%gen-expr (- d 1)))
            (if (= k 1) (list '- (%gen-expr (- d 1)) (%gen-expr (- d 1)))
              (if (= k 2) (list '* (%gen-expr (- d 1)) (%leaf))
                (if (= k 3) (list '/ (%gen-expr (- d 1)) (+ 1 (%rand 50)))
                  (if (= k 4) (list '% (%gen-expr (- d 1)) (+ 1 (%rand 50)))
                    (if (= k 5) (list 'do (%gen-expr (- d 1)) (%gen-expr (- d 1)))
                      (if (= k 6) (list 'if (%gen-test (- d 1))
                                        (%gen-expr (- d 1)) (%gen-expr (- d 1)))
                        (%leaf))))))))))))
  (set! %gen-test
    (fn (_ d)
      (if (<= d 0) (list '< (%leaf) (%leaf))
        (let ((k (%rand 8)))
          (if (= k 0) (list '< (%gen-expr (- d 1)) (%gen-expr (- d 1)))
            (if (= k 1) (list '> (%gen-expr (- d 1)) (%gen-expr (- d 1)))
              (if (= k 2) (list '= (%gen-expr (- d 1)) (%gen-expr (- d 1)))
                (if (= k 3) (list '<= (%gen-expr (- d 1)) (%gen-expr (- d 1)))
                  (if (= k 4) (list '>= (%gen-expr (- d 1)) (%gen-expr (- d 1)))
                    (if (= k 5) (list 'not (%gen-test (- d 1)))
                      (if (= k 6) (list 'and (%gen-test (- d 1)) (%gen-test (- d 1)))
                        (list 'or (%gen-test (- d 1)) (%gen-test (- d 1))))))))))))))

  ; Evaluate a CONSTRUCTED form in the caller's environment: the op gets
  ; its argument unevaluated, so the first eval runs the (list ...) call
  ; that BUILDS the fn form and the second turns that form into a
  ; closure.  Wrapping the argument in a `lit` skips the build step and
  ; hands back the fn form as DATA -- which, a list being callable, then
  ; silently index-calls and answers nil instead of computing.
  (def %evalit (op (form) e (eval (eval form e) e)))

  ; --- the loop: compile, interpret, compare on several argument pairs ---
  (def %args (list (pair 0 0) (pair 1 2) (pair 7 3) (pair 100 250) (pair 65535 65536)))
  ; compile and interpret ONCE per expression, then vary the arguments:
  ; every compile-asm mmaps a fresh code buffer, so rebuilding per
  ; argument pair burns memory for nothing.
  (def %check-args
    (fn (self expr c i pairs)
      (if (null? pairs) 'ok
        (let ((cv (c (first (first pairs)) (rest (first pairs))))
              (iv (i (first (first pairs)) (rest (first pairs)))))
          (if (= cv iv) (self expr c i (rest pairs))
            (list 'MISMATCH expr (first pairs) 'compiled cv 'interpreted iv))))))
  (def %check
    (fn (_ expr)
      (%check-args expr
        (compile-asm (list 'fn '(_ a b) expr))
        (%evalit (list 'fn '(_ a b) expr))
        %args)))

  (def %run
    (fn (self n)
      (if (= n 0) 'ok
        (let ((e (%gen-expr 3)))
          (let ((r (%check e)))
            (if (eq? r 'ok) (self (- n 1)) r))))))

  (display (%run 60)))
```
---
    ok

### compiled and interpreted agree across generated RECURSIVE functions

Recursion needs one guard the straight-line grammar does not:
**termination**. Free-form recursive calls would generate functions that
never return, so these use a fixed decreasing-counter shape —
`(fn (self n acc) (if (<= n 0) BASE (self (- n 1) STEP)))` — with `BASE`
and `STEP` generated. The counter always decreases and the base case is
`<=`, so every generated function terminates by construction.

Leaves are bounded here too: six iterations of unbounded multiplication
would overflow 64 bits, where the JIT wraps and the interpreter's answer
stops being a useful oracle. That is a limit of the comparison, not a
defect either side.

This is the coverage that would have caught the unknown-operator bug —
anything the JIT does not implement used to compile *as* a self-call.

```scheme
(do
  (def %seed-cell (pair 777001 ()))
  (def %rand
    (fn (_ n)
      (%set-first! %seed-cell (& (+ (* (first %seed-cell) 1664525) 1013904223) 4294967295))
      (% (>> (first %seed-cell) 8) n)))

  ; bounded leaves: the two params and small literals only
  (def %leaf
    (fn (_)
      (def %k (%rand 4))
      (if (= %k 0) 'n (if (= %k 1) 'acc (%rand 50)))))
  (def %gen
    (fn (self d)
      (if (<= d 0) (%leaf)
        (let ((k (%rand 6)))
          (if (= k 0) (list '+ (self (- d 1)) (self (- d 1)))
            (if (= k 1) (list '- (self (- d 1)) (self (- d 1)))
              (if (= k 2) (list '* (self (- d 1)) (%leaf))
                (if (= k 3) (list '/ (self (- d 1)) (+ 1 (%rand 20)))
                  (if (= k 4) (list '% (self (- d 1)) (+ 1 (%rand 20)))
                    (list 'if (list '< (self (- d 1)) (self (- d 1)))
                          (self (- d 1)) (self (- d 1))))))))))))

  (def %evalit (op (form) e (eval (eval form e) e)))

  ; (fn (self n acc) (if (<= n 0) BASE (self (- n 1) STEP)))
  (def %gen-rec
    (fn (_)
      (list 'fn '(self n acc)
        (list 'if (list '<= 'n 0)
          (%gen 2)
          (list 'self (list '- 'n 1) (%gen 2))))))

  (def %counts (list 0 1 2 5))
  (def %check-args
    (fn (self form c i ns)
      (if (null? ns) 'ok
        (let ((cv (c (first ns) 3)) (iv (i (first ns) 3)))
          (if (= cv iv) (self form c i (rest ns))
            (list 'MISMATCH form 'n (first ns) 'compiled cv 'interpreted iv))))))
  (def %run
    (fn (self k)
      (if (= k 0) 'ok
        (let ((form (%gen-rec)))
          (let ((r (%check-args form (compile-asm form) (%evalit form) %counts)))
            (if (eq? r 'ok) (self (- k 1)) r))))))

  (display (%run 30)))
```
---
    ok
