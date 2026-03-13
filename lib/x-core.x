; # Computational Expressions in C
;
; ## x-core.x -- x Core Standard Library (without regex/float)
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

; --- Boot: primitives implemented in x-lang (saves ROM) ---

(def null? (fn (x) (eq? x ())))

(def if (op (test then . else) e
  (match
    ((eval test e) (tail-eval then e))
    ((null? else) ())
    ((lit t) (tail-eval (first else) e)))))

(def %let-params (fn (bindings)
  (match
    ((null? bindings) ())
    (t (pair (first (first bindings))
             (%let-params (rest bindings)))))))

(def %let-vals (fn (bindings e)
  (match
    ((null? bindings) ())
    (t (pair (eval (first (rest (first bindings))) e)
             (%let-vals (rest bindings) e))))))

(def let (op (bindings . body) e
  (apply (eval (pair (lit fn)
           (pair (%let-params bindings)
             body))
         e)
    (%let-vals bindings e))))

(def %type-pair (type-of (pair 1 2)))
(def %type-int  (type-of 0))
(def %type-str  (type-of ""))
(def %type-sym  (type-of (lit a)))
(def %type-char (type-of (integer->char 0)))
(def %type-proc (type-of (fn () ())))
(def %type-prim (type-of eq?))

(def pair?      (fn (x) (type? x %type-pair)))
(def number?    (fn (x) (type? x %type-int)))
(def string?    (fn (x) (type? x %type-str)))
(def symbol?    (fn (x) (type? x %type-sym)))
(def char?      (fn (x) (type? x %type-char)))
(def procedure? (fn (x)
  (match ((type? x %type-proc) t) ((type? x %type-prim) t) (t ()))))

(def %do-nest (fn (%dn-f)
  (match
    ((null? (rest %dn-f)) (first %dn-f))
    (t (pair (lit %seq) (pair (first %dn-f)
         (pair (%do-nest (rest %dn-f)) ())))))))
(def %do-seq (op %do-f %do-e
  (match
    ((null? %do-f) ())
    ((lit t) (eval (%do-nest %do-f))))))
(def do %do-seq)
(def begin do)

; --- End boot ---

(do (def x-lib-version "0.2.0")

  ; --- Derived from C primitives ---
  (def not null?)
  (def atom? (fn (x) (not (pair? x))))
  (def list (fn args args))
  (def %expanded (pair () ()))

  ; --- Core forms as operatives ---
  ; Compile-on-first-use: expand to if-tree, cache in source form via %rewrite.
  ; First call: expand + rewrite + eval. Subsequent calls: eq? + eval.

  (def %and-expand (fn (args)
    (if (null? args) (lit t)
      (if (null? (rest args))
        (first args)
        (list (lit if) (first args)
          (%and-expand (rest args))
          ())))))
  (def and (op args e
    (if (null? args) (lit t)
      (if (eq? (first args) %expanded)
        (eval (first (rest args)))
        (%seq (def %t (%and-expand args))
              (%seq (%rewrite args %expanded (pair %t ()))
                    (eval %t)))))))

  (def %or-expand (fn (args)
    (if (null? args) ()
      (if (null? (rest args))
        (first args)
        (list (lit %seq)
          (list (lit def) (lit %or-v) (first args))
          (list (lit if) (lit %or-v) (lit %or-v)
            (%or-expand (rest args))))))))
  (def or (op args e
    (if (null? args) ()
      (if (eq? (first args) %expanded)
        (eval (first (rest args)))
        (%seq (def %t (%or-expand args))
              (%seq (%rewrite args %expanded (pair %t ()))
                    (eval %t)))))))

  ; match, %seq are C primitives; do/%do-seq are x-lang boot (x-core.x)

  ; --- Derived comparisons ---
  (def > (fn (a b) (< b a)))
  (def <= (fn (a b) (or (< a b) (= a b))))
  (def >= (fn (a b) (or (< b a) (= a b))))

  ; --- Profiling ---
  (def time (op args e
    (let ((t0 (clock)))
      (let ((result (eval (first args) e)))
        (display (- (clock) t0))
        (display " us\n")
        result))))

  ; Write to stderr (swap fileout fd, display, restore)
  (def %stderr (fn (msg)
    (def %fo (rest (first (rest (first (%base))))))
    (def %s (first-int %fo))
    (set-first-int %fo (first-int (rest (rest (first (rest (first (%base))))))))
    (display msg)
    (set-first-int %fo %s)))

  ; Dump alloc-count and heap-count to stderr
  (def %profile-dump (fn ()
    (%stderr (first-int (first (first (rest (rest (rest (rest (rest (first (%base)))))))))))
    (%stderr " ")
    (%stderr (heap-count))
    (%stderr "\n")
    ()))

  (include "lib/x/fn.x")
  (include "lib/x/math.x")
  (include "lib/x/logic.x")
  (include "lib/x/list.x")

  ; --- Save integer primitives and make arithmetic variadic ---
  ; fold (from list.x) enables variadic wrappers. float.x later overrides
  ; these with float-aware versions, reusing the saved %int* primitives.
  (def %int+ +)
  (def %int- -)
  (def %int* *)
  (def %int/ /)
  (def %int< <)
  (def %int= =)
  (def %int-number? number?)

  (set + (fn args
    (if (null? args) 0
      (fold %int+ (first args) (rest args)))))

  (set * (fn args
    (if (null? args) 1
      (fold %int* (first args) (rest args)))))

  (set / (fn args
    (if (null? args) 1
      (fold %int/ (first args) (rest args)))))

  (set - (fn args
    (if (null? args) 0
      (if (null? (rest args))
        (%int- 0 (first args))
        (fold %int- (first args) (rest args))))))

  ; --- Intrinsic scoring helpers for custom type analysers ---
  (def buffer-len (fn (buffer)
    (- (first-int (rest buffer)) (first-int buffer))))
  (def buffer-unread (fn (buffer)
    (set-first-int (rest buffer) (- (first-int (rest buffer)) 1))))
  (def score-set (fn (score sign buffer reader)
    (%seq (set-first-int score (* sign (buffer-len buffer)))
          (set-rest score reader))))

  (include "lib/x/alist.x")
  (include "lib/x/string.x")
  (include "lib/x/vector.x")

  ; --- quasi (needs append from list.x) ---
  ; Compile template to a pair/lit/append tree that, when eval'd,
  ; constructs the result with current bindings.
  (def %quasi-compile (fn (t)
    (if (or (null? t) (atom? t))
      (list (lit lit) t)
      (if (eq? (first t) (lit unquote))
        (first (rest t))
        (if (and (pair? (first t))
                 (eq? (first (first t)) (lit unquote-splicing)))
          (list (lit append)
                (first (rest (first t)))
                (%quasi-compile (rest t)))
          (list (lit pair)
                (%quasi-compile (first t))
                (%quasi-compile (rest t))))))))
  (def quasi (op args e
    (if (eq? (first args) %expanded)
      (eval (first (rest args)))
      (%seq (def %t (%quasi-compile (first args)))
            (%seq (%rewrite args %expanded (pair %t ()))
                  (eval %t))))))

  ; --- REPL ---
  (def %repl-prompt "> ")
  (def %repl-print (fn (result) (if (null? result) () (write result)) (newline)))

  (def repl (op () ()
    (display %repl-prompt)
    (def %r (read))
    (if (null? %r) ()
      (%seq (guard (err
              (display "Error: ")
              (display err)
              (newline))
              (%repl-print (eval! %r)))
            (repl)))))

  ; --- Banner ---
  (def %lang-name ())
  (def %lang-version ())
  (def %banner (fn ()
    (def %quiet (fold (fn (acc a)
      (or acc (string=? a "--quiet") (string=? a "-q"))) () args))
    (if %quiet ()
      (if (null? %lang-name) ()
        (do (display %lang-name)
            (if (null? %lang-version) ()
              (do (display " v") (display %lang-version)))
            (display " on x-lang")
            (newline))))))
)
