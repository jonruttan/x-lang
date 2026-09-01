; diff-gen.x -- generate a deterministic batch of forms for cross-engine
; differential testing.
;
; Two independent engines pass the same suite; this tool probes the space
; the suite does not reach.  It prints COUNT wrapped forms, one per line:
;
;   (write (guard (%dg-e (lit E)) FORM)) (newline)
;
; so a batch fed to two engines yields line-aligned output, and any line
; that differs is an engine divergence or a behaviour the suite never
; pinned.  A raise compares as the bare symbol E -- error MESSAGES are
; engine prose and comparing them would report wording, not semantics.
;
; Deterministic on purpose, as ext/jit-fuzz.spec.md rules: a seeded LCG,
; so a mismatch names the seed and line that reproduce it exactly.
;
; Usage (via either engine):
;   { cat lib/x-base.x; cat tools/fuzz/diff-gen.x; } | ENGINE -- SEED COUNT DEPTH
; or through the driver, tests/x/diff-engines.sh.

; --- arguments: the numeric tail of argv is (seed count depth); anything
; unparseable (the engine path, a -- separator) is skipped.  Defaults
; 20260901, 300, 5. ---
(def %dg-numeric-args
  ((fn (self xs)
     (match ((null? xs) ())
            (#t (let ((n (%str->number (first xs))) (r (self (rest xs))))
                  (match ((null? n) r) (#t (pair n r)))))))
   (rest args)))
(def %dg-argn
  (fn (_ n dflt)
    ((fn (self i xs)
       (match ((null? xs) dflt)
              ((= i 0) (first xs))
              (#t (self (- i 1) (rest xs)))))
     n %dg-numeric-args)))
(def %dg-seed  (%dg-argn 0 20260901))
(def %dg-count (%dg-argn 1 300))
(def %dg-depth (%dg-argn 2 5))

; --- seeded LCG (Numerical Recipes constants), as jit-fuzz's ---
(def %dg-seed-cell (pair %dg-seed ()))
(def %dg-rand
  (fn (_ n)
    (%set-first! %dg-seed-cell
      (& (+ (* (first %dg-seed-cell) 1664525) 1013904223) 4294967295))
    (% (>> (first %dg-seed-cell) 8) n)))

(def %dg-nth (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))
(def %dg-len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs))))))
(def %dg-pick (fn (_ xs) (%dg-nth (%dg-rand (%dg-len xs)) xs)))

; --- leaves: named vars are BOUND by the wrapper's let, so closures and
; shadowing get exercised without unbound raises ---
(def %dg-leaf
  (fn (_)
    (let ((k (%dg-rand 7)))
      (match
        ((= k 0) '%dg-a)
        ((= k 1) '%dg-b)
        ((= k 2) (%dg-rand 100))
        ((= k 3) (+ 65500 (%dg-rand 200)))
        ((= k 4) (+ 100000 (%dg-rand 900000)))
        ((= k 5) (- 0 (+ 1 (%dg-rand 70000))))
        (#t (%dg-rand 10))))))

; --- the grammar: a TABLE of (operator . shape) rows, jit-fuzz style.
; Integer core plus the territory the JIT grammar cannot reach: pairs and
; lists, predicates as values, closures applied in place, and let frames.
;   ee both recurse       el operand + leaf       ed operand + divisor
;   es operand + shift    e  unary                tee test + two operands
;   pp pair build+probe   ll list build+index     fn closure applied
;   lt let-bound body
(def %dg-expr ())
(def %dg-test ())
(def %dg-expr-forms
  (list (pair '+ 'ee) (pair '- 'ee) (pair '& 'ee)
        (pair '| 'ee) (pair '^ 'ee) (pair 'do 'ee)
        (pair '* 'el)
        (pair '/ 'ed) (pair '% 'ed)
        (pair '<< 'es) (pair '>> 'es)
        (pair '~ 'e)
        (pair 'if 'tee)
        (pair 'pp 'pp) (pair 'll 'll)
        (pair 'fn 'fn) (pair 'lt 'lt)))
(set! %dg-expr
  (fn (_ d)
    (if (<= d 0) (%dg-leaf)
      (let ((row (%dg-pick %dg-expr-forms)))
        (let ((op (first row)) (sh (rest row)))
          (match
            ((eq? sh 'ee) (list op (%dg-expr (- d 1)) (%dg-expr (- d 1))))
            ((eq? sh 'el) (list op (%dg-expr (- d 1)) (%dg-leaf)))
            ((eq? sh 'ed) (list op (%dg-expr (- d 1)) (+ 1 (%dg-rand 50))))
            ((eq? sh 'es) (list op (%dg-expr (- d 1)) (%dg-rand 32)))
            ((eq? sh 'e) (list op (%dg-expr (- d 1))))
            ((eq? sh 'tee)
              (list 'if (%dg-test (- d 1)) (%dg-expr (- d 1)) (%dg-expr (- d 1))))
            ; (first/rest (pair E E)) -- spine probes over built pairs
            ((eq? sh 'pp)
              (list (%dg-pick (list 'first 'rest))
                    (list 'pair (%dg-expr (- d 1)) (%dg-expr (- d 1)))))
            ; list build + head index
            ((eq? sh 'll)
              (list 'first
                    (list 'list (%dg-expr (- d 1)) (%dg-expr (- d 1)))))
            ; a closure applied in place: ((fn (_ x) BODY-over-x) E)
            ((eq? sh 'fn)
              (list (list 'fn (list '_ 'x)
                          (list (%dg-pick (list '+ '- '* '&)) 'x (%dg-leaf)))
                    (%dg-expr (- d 1))))
            ; a let frame shadowing %dg-a
            (#t
              (list 'let (list (list '%dg-a (%dg-expr (- d 1))))
                    (list (%dg-pick (list '+ '^ '|)) '%dg-a (%dg-leaf))))))))))
(def %dg-test-forms
  (list (pair '< 'ee) (pair '> 'ee) (pair '= 'ee)
        (pair '<= 'ee) (pair '>= 'ee)
        (pair 'not 't) (pair 'and 'tt) (pair 'or 'tt)
        (pair 'null? 'p) (pair 'pair? 'p)))
(set! %dg-test
  (fn (_ d)
    (if (<= d 0) (list '< (%dg-leaf) (%dg-leaf))
      (let ((row (%dg-pick %dg-test-forms)))
        (let ((op (first row)) (sh (rest row)))
          (match
            ((eq? sh 'ee) (list op (%dg-expr (- d 1)) (%dg-expr (- d 1))))
            ((eq? sh 't) (list op (%dg-test (- d 1))))
            ((eq? sh 'tt) (list op (%dg-test (- d 1)) (%dg-test (- d 1))))
            ; predicates over a built or empty spine
            (#t (list op (if (= 0 (%dg-rand 2))
                           (list 'pair (%dg-leaf) (%dg-leaf))
                           ())))))))))

; --- emission: each case is one line, wrapped so a raise prints as E and
; the free vars are bound.  A bespoke printer, because `write` decorates
; symbols with quote marks -- readable as DATA, not as the code it was ---
(def %dg-print ())
(def %dg-print-spine
  (fn (self xs sep)
    (unless (null? xs)
      (do (display sep)
          (%dg-print (first xs))
          (self (rest xs) " ")))))
(set! %dg-print
  (fn (_ f)
    (match
      ((null? f) (display "()"))
      ((pair? f) (do (display "(") (%dg-print-spine f "") (display ")")))
      (#t (display f)))))
(def %dg-emit
  (fn (_ form)
    (%dg-print
      (list 'write
        (list 'guard (list '%dg-e (list 'lit 'E))
          (list 'let (list (list '%dg-a 7) (list '%dg-b -3)) form))))
    (display "(newline)")
    (newline)))

; A collect every 64 cases, on BOTH sides of the pipe: generation churns
; each case's tree into garbage the moment it is printed, and the
; EXECUTING engine churns the same evaluating it -- the alloc-limit!
; guard counts allocations, not survivors.  The interleaved
; (Heap collect) form prints nothing, so the output stays line-aligned
; with the cases.
((fn (self i)
   (unless (= i %dg-count)
     (do (when (= 0 (& i 63))
           (do (Heap collect)
               (display "(Heap collect)")
               (newline)))
         (%dg-emit (%dg-expr %dg-depth))
         (self (+ i 1))))) 0)
