# @lib ../tests/x/lib/compile.x
# @requires native/jit

# @weight 9
Differential fuzzing of the JIT: generate expressions from its supported
grammar, run each BOTH compiled and interpreted, and require the two to
agree. The interpreter is the oracle — there are no hand-written
expectations to rot.

Untagged on purpose: both backends (ARM64 and x86-64) compile the
same vocabulary, so this file runs on every host and IS the parity
contract.

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
(a zero divisor is a trap in both, not a difference), and shift amounts
stay under 32 (ARM64 shifts by the low six bits of the register, C's
shift by at least the word width is undefined — comparing those would
pit a defined answer against an undefined one). Signed overflow in `*`
and `<<` is assumed to wrap identically on both sides, which it does:
the interpreter's arithmetic is C on a 64-bit word and the JIT's is the
register file. This runs under
helium: with the numeric tower loaded, interpreted arithmetic would
promote to bigint where the JIT wraps, so the oracle would disagree for
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

  ; Local list walkers.  This file's harness is x-core + posix + hash +
  ; compile -- the `List` CLASS is not loaded, and the runner discards
  ; stderr, so reaching for `List ref` here does not fail loudly: the
  ; unbound-symbol error disappears and the block reports a garbage
  ; value with no hint of the cause.  Count with %len rather than
  ; writing the row totals as constants; a hand-written count silently
  ; stops generating whichever form gets appended past it.
  (def %nth (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))
  (def %len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs))))))
  (def %pick (fn (_ xs) (%nth (%rand (%len xs)) xs)))

  ; --- generators: integer-valued expr, boolean-valued test ---
  ;
  ; The grammar is a TABLE of (operator . operand-shape) rows, not a
  ; cascade of ifs.  It was a cascade at eight forms and was already
  ; hard to read; the bitwise family took it to fifteen, and every
  ; future JIT form would deepen it further.  Adding a form is now a
  ; row, and the shapes are named:
  ;
  ;   ee   both operands recurse       el   operand then a bare leaf
  ;   ed   operand then a NON-ZERO divisor literal
  ;   es   operand then a 0..31 shift amount
  ;   e    unary                       tee  test then two operands
  (def %gen-expr ())
  (def %gen-test ())
  (def %leaf
    (fn (_)
      (let ((k (%rand 6)))
        (match
          ((= k 0) 'a)
          ((= k 1) 'b)
          ((= k 2) (%rand 100))
          ; wide literals: the MOVZ/MOVK boundary (the #189 class)
          ((= k 3) (+ 65500 (%rand 200)))
          ((= k 4) (+ 100000 (%rand 900000)))
          ; NEGATIVE literals.  Two's complement needs all four MOVK
          ; halfwords, and a negative operand is the only way a
          ; sign-extending shift differs from a logical one -- with the
          ; grammar's leaves all non-negative, the LSRV-for-ASRV bug was
          ; invisible to this whole file.
          (#t (- 0 (+ 1 (%rand 70000))))))))
  (def %expr-forms
    (list (pair '+ 'ee)  (pair '- 'ee)  (pair '& 'ee)
          (pair '| 'ee)  (pair '^ 'ee)  (pair 'do 'ee)
          (pair '* 'el)
          (pair '/ 'ed)  (pair '% 'ed)
          (pair '<< 'es) (pair '>> 'es)
          (pair '~ 'e)
          (pair 'if 'tee)))
  (set! %gen-expr
    (fn (_ d)
      (if (<= d 0) (%leaf)
        (let ((row (%pick %expr-forms)))
          (let ((op (first row)))
            (match
              ((eq? (rest row) 'ee)
                (list op (%gen-expr (- d 1)) (%gen-expr (- d 1))))
              ((eq? (rest row) 'el) (list op (%gen-expr (- d 1)) (%leaf)))
              ((eq? (rest row) 'ed)
                (list op (%gen-expr (- d 1)) (+ 1 (%rand 50))))
              ; a shift amount is bounded to 0..31: ARM64 shifts by the
              ; low six bits of the register while C's shift by >= the
              ; word width is undefined, so a wider amount would compare
              ; a defined result against an undefined one.
              ((eq? (rest row) 'es) (list op (%gen-expr (- d 1)) (%rand 32)))
              ((eq? (rest row) 'e) (list op (%gen-expr (- d 1))))
              (#t (list op (%gen-test (- d 1))
                        (%gen-expr (- d 1)) (%gen-expr (- d 1))))))))))
  ; Tests: the comparisons take two expressions, `not` one test, the
  ; connectives two tests.
  (def %test-forms
    (list (pair '< 'ee)  (pair '> 'ee)  (pair '= 'ee)
          (pair '<= 'ee) (pair '>= 'ee)
          (pair 'not 't) (pair 'and 'tt) (pair 'or 'tt)))
  (set! %gen-test
    (fn (_ d)
      (if (<= d 0) (list '< (%leaf) (%leaf))
        (let ((row (%pick %test-forms)))
          (let ((op (first row)))
            (match
              ((eq? (rest row) 'ee)
                (list op (%gen-expr (- d 1)) (%gen-expr (- d 1))))
              ((eq? (rest row) 't) (list op (%gen-test (- d 1))))
              (#t (list op (%gen-test (- d 1)) (%gen-test (- d 1))))))))))

  ; Evaluate a CONSTRUCTED form in the caller's environment: the op gets
  ; its argument unevaluated, so the first eval runs the (list ...) call
  ; that BUILDS the fn form and the second turns that form into a
  ; closure.  Wrapping the argument in a `lit` skips the build step and
  ; hands back the fn form as DATA -- which, a list being callable, then
  ; silently index-calls and answers nil instead of computing.
  (def %evalit (op (form) e (eval (eval form e) e)))

  ; --- the loop: compile, interpret, compare on several argument pairs ---
  ; Negative arguments earn their place: every pair here used to be
  ; non-negative, which is exactly why a sign-extension bug in `>>`
  ; survived a differential fuzzer aimed straight at it.
  (def %args (list (pair 0 0) (pair 1 2) (pair 7 3) (pair 100 250)
                   (pair 65535 65536) (pair -1 -7) (pair -65536 5)))
  ; compile and interpret ONCE per expression, then vary the arguments:
  ; every compile-asm mmaps a fresh code buffer, so rebuilding per
  ; argument pair burns memory for nothing.
  ; The verdict is DISPLAYED and must be the block's last output.  The
  ; runner compares the LAST non-empty line, and the batch printer
  ; renders the block's own value after whatever was displayed -- so a
  ; trailing `(newline)`, or a stray paren that ends the `do` early and
  ; leaves later forms at top level, puts something else on that line.
  ; Both mistakes surface identically, as an opaque `#<ATOM:0x...>` where
  ; the verdict should be, which says nothing about which one it was.
  ;
  ; The report is a STRING naming the case.  `Str append` is binary, so
  ; the parts are joined by a fold rather than passed as one wide call.
  (def %w (prim-ref (lit io) (lit write-to-str)))
  (def %cat
    (fn (self parts)
      (if (null? (rest parts)) (first parts)
        (Str append (first parts) (self (rest parts))))))
  (def %report
    (fn (_ expr pr cv iv)
      (%cat (list "MISMATCH " (%w expr)
                  " on a=" (%w (first pr))
                  " b=" (%w (rest pr))
                  " compiled=" (%w cv)
                  " interpreted=" (%w iv)))))
  (def %check-args
    (fn (self expr c i pairs)
      (if (null? pairs) 'ok
        (let ((cv (c (first (first pairs)) (rest (first pairs))))
              (iv (i (first (first pairs)) (rest (first pairs)))))
          (if (= cv iv) (self expr c i (rest pairs))
            (%report expr (first pairs) cv iv))))))
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
  ; The same operator/shape table the straight-line grammar uses, minus
  ; the growers.  `&`, `|`, `^`, `~` and `>>` are bounded by their
  ; operands and survive six iterations; `<<` is not, and an overflow
  ; compounded once per level puts the oracle past the point where its
  ; answer means anything.
  (def %nth (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))
  (def %len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs))))))
  (def %pick (fn (_ xs) (%nth (%rand (%len xs)) xs)))
  (def %forms
    (list (pair '+ 'ee) (pair '- 'ee) (pair '& 'ee)
          (pair '| 'ee) (pair '^ 'ee)
          (pair '* 'el) (pair '/ 'ed) (pair '% 'ed)
          (pair '>> 'es) (pair '~ 'e) (pair 'if 'tee)))
  (def %gen
    (fn (self d)
      (if (<= d 0) (%leaf)
        (let ((row (%pick %forms)))
          (let ((op (first row)))
            (match
              ((eq? (rest row) 'ee) (list op (self (- d 1)) (self (- d 1))))
              ((eq? (rest row) 'el) (list op (self (- d 1)) (%leaf)))
              ((eq? (rest row) 'ed) (list op (self (- d 1)) (+ 1 (%rand 20))))
              ((eq? (rest row) 'es) (list op (self (- d 1)) (%rand 32)))
              ((eq? (rest row) 'e) (list op (self (- d 1))))
              (#t (list op (list '< (self (- d 1)) (self (- d 1)))
                        (self (- d 1)) (self (- d 1))))))))))

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

## scratch-memory fuzz

### a computed store lands where a constant read finds it, and touches nothing else

The memory forms have no interpreted counterpart, so the interpreter
cannot be the oracle here the way it is above. Two independent oracles
stand in for it:

- **a model of the buffer.** Every slot is pre-filled with a distinct
  sentinel, so a single generated store must leave the other
  sixty-three sentinels exactly as they were. That is what catches a
  wrong scale or a stray offset — bugs that a read-back of the slot
  just written would happily confirm.
- **`ptr ref-word`.** The JIT writes; plain x-lang reads. A scale bug
  shared by the compiler's store and load paths would agree with
  itself; an x-lang reader has no such sympathy.

Case count is bounded by the batch, not by taste: all three blocks in
this file share one interpreter process, and each `compile-asm` mmaps
its own code buffer. At twenty-four cases the process died mid-batch.
Raise the count only alongside a measurement, and never by raising the
runner's allocation ceiling — a tripped ceiling is the measurement.

The index is a generated expression masked with `(& i 31)`, which pins
it to a valid slot for any operand, negative included — the buffer is
128 slots, so the masked quarter stays comfortably inside it. The
interpreter *is* still the oracle for that index arithmetic, which is
ordinary integer work; it is only the load and store that need the
model.

Cases alternate between the WORD family and the BYTE family
(`%mem-byte-*`), which shares the shape but not the scale: byte indices
mask with `(& i 255)` over the same 256-byte region the word slots
occupy, the byte model is sentinel-filled and verified per BYTE, and a
byte store lands `(& v 255)` while the form yields the full value.
Sharing one region is deliberate — a scale confusion between the
families (a byte store scaled by 8, a word store unscaled) corrupts the
other family's sentinels and is caught by whichever phase runs next.

```scheme
(do
  (def %seed-cell (pair 20260806 ()))
  (def %rand
    (fn (_ n)
      (%set-first! %seed-cell (& (+ (* (first %seed-cell) 1664525) 1013904223) 4294967295))
      (% (>> (first %seed-cell) 8) n)))
  (def %nth (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))
  (def %len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs))))))
  (def %pick (fn (_ xs) (%nth (%rand (%len xs)) xs)))
  (def %w (prim-ref (lit io) (lit write-to-str)))
  (def %cat
    (fn (self parts)
      (if (null? (rest parts)) (first parts)
        (Str append (first parts) (self (rest parts))))))
  (def %evalit (op (form) e (eval (eval form e) e)))

  ; --- the buffer, and the x-lang-side reader that checks it ---
  (def %buf ((prim-ref (lit str) (lit make)) 1024))
  (def %ptr ((prim-ref (lit str) (lit ->ptr)) %buf))
  (def %addr ((prim-ref (lit ptr) (lit ->int)) %ptr))
  (def %refw (prim-ref (lit ptr) (lit ref-word)))
  (def %setw (prim-ref (lit ptr) (lit set-word!)))
  (def %slots 32)
  ; A per-slot sentinel, not zero: zeroed memory cannot tell "left alone"
  ; apart from "written with the wrong value at the wrong index".
  (def %sentinel (fn (_ j) (+ (* j 7) 1)))
  (def %fill
    (fn (self j)
      (unless (>= j %slots)
        (do (%setw %ptr (* j 8) (%sentinel j)) (self (+ j 1))))))

  ; --- index expressions: integer arithmetic over the two arguments ---
  (def %gen ())
  (def %leaf
    (fn (_)
      (let ((k (%rand 5)))
        (match
          ((= k 0) 'a)
          ((= k 1) 'b)
          ((= k 2) (%rand 100))
          ((= k 3) (+ 100000 (%rand 900000)))
          (#t (- 0 (+ 1 (%rand 70000))))))))
  (def %forms
    (list (pair '+ 'ee) (pair '- 'ee) (pair '& 'ee) (pair '| 'ee)
          (pair '^ 'ee) (pair '* 'el) (pair '<< 'es) (pair '>> 'es)
          (pair '~ 'e)))
  (set! %gen
    (fn (_ d)
      (if (<= d 0) (%leaf)
        (let ((row (%pick %forms)))
          (let ((op (first row)))
            (match
              ((eq? (rest row) 'ee) (list op (%gen (- d 1)) (%gen (- d 1))))
              ((eq? (rest row) 'el) (list op (%gen (- d 1)) (%leaf)))
              ((eq? (rest row) 'es) (list op (%gen (- d 1)) (%rand 32)))
              (#t (list op (%gen (- d 1))))))))))

  ; --- one compiled runtime loader per family, shared by every case ---
  (def %ld (compile-asm '(fn (_ m i) (%mem-ref-at m i))))
  (def %ldb (compile-asm '(fn (_ m i) (%mem-byte-ref-at m i))))

  ; Every slot must hold its sentinel, except the one slot the case
  ; wrote, which must hold the value.
  (def %verify
    (fn (self j slot v)
      (if (>= j %slots) 'ok
        (let ((got (%refw %ptr (* j 8)))
              (want (if (= j slot) v (%sentinel j))))
          (if (= got want) (self (+ j 1) slot v)
            (%cat (list "SLOT " (%w j) " got=" (%w got) " want=" (%w want))))))))

  (def %check
    (fn (_ idx-expr a b v)
      (do
        (%fill 0)
        (let ((slot ((%evalit (list 'fn '(_ a b) (list '& idx-expr 31))) a b)))
          (do
            ((compile-asm (list 'fn '(_ m a b)
                            (list '%mem-set-at! 'm (list '& idx-expr 31) v)))
              %addr a b)
            (let ((buf-verdict (%verify 0 slot v)))
              (if (not (eq? buf-verdict 'ok))
                (%cat (list "MISMATCH " (%w idx-expr) " a=" (%w a) " b=" (%w b)
                            " " buf-verdict))
                ; the compiled loader and a constant-index loader must
                ; both find what the computed store left behind
                (let ((rt (%ld %addr slot))
                      (konst ((compile-asm (list 'fn '(_ m)
                                             (list '%mem-ref 'm slot))) %addr)))
                  (if (and (= rt v) (= konst v)) 'ok
                    (%cat (list "READBACK " (%w idx-expr) " slot=" (%w slot)
                                " runtime=" (%w rt) " const=" (%w konst)
                                " stored=" (%w v))))))))))))

  ; --- the byte phase: same design, byte granularity ---
  (def %refb (prim-ref (lit ptr) (lit ref)))
  (def %setb (prim-ref (lit ptr) (lit set!)))
  (def %bbytes 256)
  (def %bsentinel (fn (_ j) (& (+ (* j 7) 1) 255)))
  (def %bfill
    (fn (self j)
      (unless (>= j %bbytes)
        (do (%setb %ptr j (%bsentinel j) 1) (self (+ j 1))))))
  (def %bverify
    (fn (self j at v)
      (if (>= j %bbytes) 'ok
        (let ((got (%refb %ptr j 1))
              (want (if (= j at) (& v 255) (%bsentinel j))))
          (if (= got want) (self (+ j 1) at v)
            (%cat (list "BYTE " (%w j) " got=" (%w got) " want=" (%w want))))))))
  (def %bcheck
    (fn (_ idx-expr a b v)
      (do
        (%bfill 0)
        (let ((at ((%evalit (list 'fn '(_ a b) (list '& idx-expr 255))) a b)))
          (do
            ((compile-asm (list 'fn '(_ m a b)
                            (list '%mem-byte-set-at! 'm (list '& idx-expr 255) v)))
              %addr a b)
            (let ((buf-verdict (%bverify 0 at v)))
              (if (not (eq? buf-verdict 'ok))
                (%cat (list "BYTE-MISMATCH " (%w idx-expr) " a=" (%w a) " b=" (%w b)
                            " " buf-verdict))
                (let ((rt (%ldb %addr at))
                      (konst ((compile-asm (list 'fn '(_ m)
                                             (list '%mem-byte-ref 'm at))) %addr)))
                  (if (and (= rt (& v 255)) (= konst (& v 255))) 'ok
                    (%cat (list "BYTE-READBACK " (%w idx-expr) " at=" (%w at)
                                " runtime=" (%w rt) " const=" (%w konst)
                                " stored=" (%w v))))))))))))

  (def %run
    (fn (self n)
      (if (= n 0) 'ok
        (let ((e (%gen 3))
              (a (- (%rand 2000) 1000))
              (b (- (%rand 2000) 1000))
              (v (+ 1000000 (%rand 1000000))))
          (let ((r (if (= 0 (% n 2)) (%check e a b v) (%bcheck e a b v))))
            (if (eq? r 'ok) (self (- n 1)) r))))))

  (display (%run 12)))
```
---
    ok
