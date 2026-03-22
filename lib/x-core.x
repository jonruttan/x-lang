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

(def null? (fn (_ x) (eq? x ())))

(def if
  (op (test then . else)
    e
    (match
      ((eval test e) (tail-eval then e))
      ((null? else) ())
      (#t (tail-eval (first else) e)))))

(def %let-params
  (fn (_ bindings)
    (match
      ((null? bindings) ())
      (#t
        (pair
          (first (first bindings))
          (%let-params (rest bindings)))))))

(def %let-vals
  (fn (_ bindings e)
    (match
      ((null? bindings) ())
      (#t
        (pair
          (eval (first (rest (first bindings))) e)
          (%let-vals (rest bindings) e))))))

(def let
  (op (bindings . body)
    e
    (apply
      (eval (pair (lit fn) (pair (pair (lit _) (%let-params bindings)) body)) e)
      (%let-vals bindings e))))

(def %type-pair (type-of (pair 1 2)))

(def %type-int (type-of 0))

(def %type-str (type-of ""))

(def %type-sym (type-of (lit a)))

(def %type-char (type-of (integer->char 0)))

(def %type-proc (type-of (fn (_ ) ())))

(def %type-prim (type-of eq?))

(def pair? (fn (_ x) (type? x %type-pair)))

(def number? (fn (_ x) (type? x %type-int)))

(def string? (fn (_ x) (type? x %type-str)))

(def symbol? (fn (_ x) (type? x %type-sym)))

(def char? (fn (_ x) (type? x %type-char)))

(def procedure?
  (fn (_ x)
    (match
      ((type? x %type-proc) #t)
      ((type? x %type-prim) #t)
      (#t #f))))

(def %do-nest
  (fn (_ %dn-f)
    (match
      ((null? (rest %dn-f)) (first %dn-f))
      (#t
        (pair
          (lit %seq)
          (pair (first %dn-f) (pair (%do-nest (rest %dn-f)) ())))))))

(def %do-seq
  (op %do-f
    %do-e
    (match
      ((null? %do-f) ())
      (#t (eval (%do-nest %do-f))))))

(def do %do-seq)

(def begin do)
; --- End boot ---

(do
  (def x-lib-version "0.2.0")
  ; --- Derived from C primitives ---

  (def not (fn (_ x) (if x #f #t)))
  (def atom? (fn (_ x) (not (pair? x))))
  (def list (fn (_ . args) args))
  ; number->string: (number->string n [radix]) -> string representation
  ; Captures / and % at definition time so later overrides don't break it
  (def %n2s/ /)
  (def %n2s% %)
  (def number->string
    (fn (_ n . rest)
      (def radix (if (null? rest) 10 (first rest)))
      (def %d "0123456789abcdefghijklmnopqrstuvwxyz")
      (if (= n 0) "0"
        (if (< n 0)
          (string-append "-" (number->string (- 0 n) radix))
          (let ((rem (%n2s% n radix)))
            (if (< n radix)
              (list->string (list (%d rem)))
              (string-append
                (number->string (%n2s/ n radix) radix)
                (list->string (list (%d rem))))))))))
  ; string->number: (string->number str [radix]) -> integer or ()
  (def string->number
    (fn (_ s . rest)
      (def radix (if (null? rest) 10 (first rest)))
      (def len (s))
      (if (= len 0) ()
        (do
          (def %0 (char->integer ("0" 0)))
          (def %digit
            (fn (_ ch)
              (def c (char->integer ch))
              (if (if (not (< c %0)) (not (< (+ %0 9) c)) #f)
                (- c %0)
                (if (if (not (< c (char->integer ("a" 0))))
                        (not (< (+ (char->integer ("a" 0)) 25) c)) #f)
                  (+ 10 (- c (char->integer ("a" 0))))
                  (if (if (not (< c (char->integer ("A" 0))))
                          (not (< (+ (char->integer ("A" 0)) 25) c)) #f)
                    (+ 10 (- c (char->integer ("A" 0))))
                    ())))))
          (def c0 (char->integer (s 0)))
          (def neg (= c0 (char->integer ("-" 0))))
          (def start
            (if neg 1
              (if (= c0 (char->integer ("+" 0))) 1 0)))
          (if (= start len) ()
            (do
              (def %parse
                (fn (_ i acc)
                  (if (= i len) acc
                    (do
                      (def d (%digit (s i)))
                      (if (null? d) ()
                        (if (< d radix)
                          (%parse (+ i 1) (+ (* acc radix) d))
                          ()))))))
              (def result (%parse start 0))
              (if (null? result) ()
                (if neg (- 0 result) result))))))))
  (include "lib/x/type.x")
  (include "lib/x/convert.x")
  (def newline (fn (_ ) (display "\n")))
  (def string-ref (fn (_ s i) (s i)))
  (def string-length (fn (_ s) (s)))
  (def substring (fn (_ s start end) (s start (- end start))))
  (def heap-collect (fn (_ ) (applicative heap-mark heap-sweep) ()))
  ; GC hooks: navigate base tree to gc-hooks cells
  (def %gc-hooks
    (rest (rest (rest (rest (rest (rest (rest (first (%base))))))))))
  (def %gc-hooks-rest (rest %gc-hooks))
  (def heap-mark-root!
    (fn (_ obj)
      (def %cell (rest %gc-hooks-rest))
      (set-first! %cell (pair obj (first %cell)))))
  (def heap-mark-hook!
    (fn (_ hook)
      (def %cell (first %gc-hooks))
      (set-first! %cell (pair hook (first %cell)))))
  (def heap-free-hook!
    (fn (_ hook)
      (def %cell (first %gc-hooks-rest))
      (set-first! %cell (pair hook (first %cell)))))
  ; Extend base tree: add include-list cell under io-state (after false-stack)
  (def %io-state (rest (first (rest (first (%base))))))
  (def %false-stack (rest (rest %io-state)))
  (set-rest! %false-stack (pair () ()))
  (def %include-list-cell (rest %false-stack))
  (def %rewrite
    (fn (_ p a b) (set-first! p a) (set-rest! p b) p))
  (def %expanded (pair () ()))
  (def %string-eq-loop
    (fn (_ a b i len)
      (if (= i len)
        #t
        (if (= (char->integer (a i)) (char->integer (b i)))
          (%string-eq-loop a b (+ i 1) len)
          #f))))
  (def string=?
    (fn (_ a b) (if (= (a) (b)) (%string-eq-loop a b 0 (a)) #f)))
  ; --- Include-once / require-once ---
  (def %include-list-has?
    (fn (_ path)
      (def %go
        (fn (_ lst)
          (if (null? lst) #f
            (if (string=? (first lst) path) #t
              (%go (rest lst))))))
      (%go (first %include-list-cell))))
  (def include-once
    (op (path) e
      (def %io-path (eval path e))
      (if (%include-list-has? %io-path) ()
        (do (set-first! %include-list-cell
              (pair %io-path (first %include-list-cell)))
            (include %io-path)))))
  (def require-once include-once)
  ; --- Module system: provide / import ---
  (set-rest! %include-list-cell (pair () ()))
  (def %module-registry-cell (rest %include-list-cell))
  ; --- Documentation system ---
  (set-rest! %module-registry-cell (pair () ()))
  (def %doc-registry-cell (rest %module-registry-cell))
  (def %module-register!
    (fn (_ name exports)
      (set-first! %module-registry-cell
        (pair (pair name exports)
              (first %module-registry-cell)))))
  (def %module-resolve
    (fn (_ name)
      (string-append "lib/"
        (string-append (symbol->string name) ".x"))))
  (def provide
    (op (name . syms) e
      (%module-register! name syms)))
  (def import
    (op (name . syms) e
      (include-once (%module-resolve name))
      ()))
  ; Pre-register all library paths so import calls in library files are no-ops
  (set-first! %include-list-cell
    (pair "lib/x/doc.x"
    (pair "lib/x/doc-prims.x"
    (pair "lib/x/type.x"
    (pair "lib/x/convert.x"
    (pair "lib/x/fn.x"
    (pair "lib/x/logic.x"
    (pair "lib/x/list.x"
    (pair "lib/x/math.x"
    (pair "lib/x/derived.x"
    (pair "lib/x/numeric.x"
    (pair "lib/x/alist.x"
    (pair "lib/x/char.x"
    (pair "lib/x/string.x"
    (pair "lib/x/vector.x"
    (pair "lib/x/promise.x"
    (pair "lib/x/token.x"
      (first %include-list-cell))))))))))))))))))
  ; --- Documentation system ---
  (include "lib/x/doc.x")
  (include "lib/x/doc-prims.x")

  ; --- Core forms as operatives ---

  ; Compile-on-first-use: expand to if-tree, cache in source form via %rewrite.

  ; First call: expand + rewrite + eval. Subsequent calls: eq? + eval.

  (def and
    (op args
      e
      (if (null? args)
        #t
        (if (null? (rest args))
          (eval (first args) e)
          (if (eval (first args) e)
            (eval (pair (lit and) (rest args)) e)
            #f)))))
  (def or
    (op args
      e
      (if (null? args)
        ()
        (if (null? (rest args))
          (eval (first args) e)
          (let ((%or-v (eval (first args) e)))
            (if %or-v %or-v
              (eval (pair (lit or) (rest args)) e)))))))
  ; match, %seq are C primitives; do/%do-seq are x-lang boot (x-core.x)

  ; --- Profiling ---

  (def time
    (op args
      e
      (let ((t0 (clock)))
        (let ((result (eval (first args) e)))
          (display (- (clock) t0))
          (display " us\n")
          result))))
  ; Write to stderr (swap fileout fd, display, restore)

  (def %stderr
    (fn (_ msg)
      (def %files (rest (first (first (rest (first (%base)))))))
      (def %fo (first (rest %files)))
      (def %s (first-int %fo))
      (set-first-int! %fo (first-int (first (rest (rest %files)))))
      (display msg)
      (set-first-int! %fo %s)))
  ; Dump alloc-count and heap-count to stderr

  (def %profile-dump
    (fn (_ )
      (%stderr
        (first-int
          (first (first (first (first (rest (rest (first (%base))))))))))
      (%stderr " ")
      (%stderr (heap-count))
      (%stderr "\n")
      ()))
  (include "lib/x/fn.x")
  (include "lib/x/logic.x")
  (include "lib/x/list.x")
  (include "lib/x/math.x")
  (include "lib/x/derived.x")
  (include "lib/x/numeric.x")
  ; --- Save integer primitives and make arithmetic variadic ---

  ; fold (from list.x) enables variadic wrappers. float.x later overrides

  ; these with float-aware versions, reusing the saved %int* primitives.

  (def %int+ +)
  (def %int- -)
  (def %int* *)
  (def %int/ /)
  (def modulo-int %)
  (def %int< <)
  (def %int= =)
  (def %int-number? number?)
  (set! +
    (fn (_ . args)
      (if (null? args) 0 (fold %int+ (first args) (rest args)))))
  (set! *
    (fn (_ . args)
      (if (null? args) 1 (fold %int* (first args) (rest args)))))
  (set! /
    (fn (_ . args)
      (if (null? args) 1 (fold %int/ (first args) (rest args)))))
  (set! -
    (fn (_ . args)
      (if (null? args)
        0
        (if (null? (rest args))
          (%int- 0 (first args))
          (fold %int- (first args) (rest args))))))
  (set! % (fn (_ . args) (fold modulo-int (first args) (rest args))))
  ; --- Intrinsic scoring helpers for custom type analysers ---

  (def buffer-len
    (fn (_ buffer)
      (- (first-int (rest buffer)) (first-int buffer))))
  (def buffer-unread
    (fn (_ buffer)
      (set-first-int!
        (rest buffer)
        (- (first-int (rest buffer)) 1))))
  (def score-set
    (fn (_ score sign buffer)
      (set-first-int! score (* sign (buffer-len buffer)))))
  (def peek-char
    (fn (_ )
      (def %ch (read-char))
      (if (null? %ch)
        ()
        (do
          (buffer-unread
            (first
              (first (rest (rest (rest (rest (first (%base)))))))))
          %ch))))
  (def current-line
    (fn (_ )
      (first-int
        (first (first (rest (first (rest (first (%base))))))))))
  (include "lib/x/alist.x")
  (include "lib/x/char.x")
  (include "lib/x/string.x")
  (include "lib/x/vector.x")
  (include "lib/x/promise.x")
  (include "lib/x/token.x")
  ; --- quasi (needs append from list.x) ---

  ; Compile template to a pair/lit/append tree that, when eval'd,

  ; constructs the result with current bindings.

  (def %quasi-compile
    (fn (_ t)
      (if (or (null? t) (atom? t))
        (list (lit lit) t)
        (if (eq? (first t) (lit unquote))
          (first (rest t))
          (if (and
                (pair? (first t))
                (eq? (first (first t)) (lit unquote-splicing)))
            (list
              (lit append)
              (first (rest (first t)))
              (%quasi-compile (rest t)))
            (list
              (lit pair)
              (%quasi-compile (first t))
              (%quasi-compile (rest t))))))))
  (def quasi
    (op args
      e
      (if (eq? (first args) %expanded)
        (eval (first (rest args)))
        (%seq
          (def %t (%quasi-compile (first args)))
          (%seq (%rewrite args %expanded (pair %t ())) (eval %t))))))
  ; --- REPL ---

  (def %repl-read read)
  (def %repl-prompt "> ")
  (def %repl-print
    (fn (_ result)
      (if (null? result) () (write result))
      (newline)))
  (def repl
    (op ()
      ()
      (display %repl-prompt)
      (def %r (%repl-read))
      (if (null? %r)
        ()
        (%seq
          (guard (err (display "Error: ") (display err) (newline))
            (%repl-print (eval! %r)))
          (repl)))))
  ; --- Banner ---

  (def %lang-name ())
  (def %lang-version ())
  (def %banner
    (fn (_ )
      (def %quiet
        (fold
          (fn (_ acc a)
            (or acc (string=? a "--quiet") (string=? a "-q")))
          ()
          args))
      (if %quiet
        ()
        (if (null? %lang-name)
          ()
          (do
            (display %lang-name)
            (if (null? %lang-version)
              ()
              (do (display " v") (display %lang-version)))
            (display " on x-lang")
            (newline))))))
  (doc (provide x/type
    type-alist type-by-atom type-io type-cvt
    type-write-cell type-analyse-cell type-from-cell type-to-cell
    type-push-write type-pop-write type-push-analyse type-cast!)
    "Type system reflection and manipulation.")
  (doc (provide x/core
    null? if let do begin not atom? list convert number->string string->number
    string=? string-ref string-length substring
    newline heap-collect heap-mark-root! heap-mark-hook!
    heap-free-hook! include-once require-once provide import
    peek-char current-line quasi repl doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
