; or.x -- x/or: Experimental/Hacking dialect
;
; Built on x-lang. Imports the full toolbox: compiler, POSIX, numeric
; tower, regex, plus system-level extensions (syscall, file, socket).

; --- Heavy imports ---
(import x/posix)
(import x/hash)
(import x/compile)
(import x/bignum)
(import x/regex)

; --- Compile tokenizer analysers for all numeric types ---
; State machine functions use (if (>= chr 48) (<= chr 57) #f) pattern
; (nested if instead of and, which the compiler doesn't support).
; compile-batch compiles all in one cc invocation for speed.

; --- Compile tokenizer analysers for numeric types ---
; Entry-point functions are hot (called for every char of every token).
; Uses fvars to embed references to the state-machine next functions.
; Digit check: (if (< chr 48) () (if (< chr 58) MATCH ()))

(type-push-analyse (type-by-atom (type-of 1.0))
  (compile (lit (fn (buffer score chr)
    (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    (list (pair (lit %float-int-digits) %float-int-digits))))

(type-push-analyse (type-by-atom (type-of 1/2))
  (compile (lit (fn (buffer score chr)
    (if (< chr 48)
      (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
      (if (< chr 58) %rat-numer ()))))
    (list (pair (lit %rat-numer) %rat-numer)
          (pair (lit %rat-sign)
            (fn (buffer score chr)
              (if (< chr 48) () (if (< chr 58) %rat-numer ())))))))

(type-push-analyse (type-by-atom (type-of (expt 2 64)))
  (compile (lit (fn (buffer score chr)
    (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) %big-sign-state ())
      (if (< chr 58) %big-digits ()))))
    (list (pair (lit %big-sign-state) %big-sign-state)
          (pair (lit %big-digits) %big-digits))))

(type-push-analyse (type-by-atom (type-of 1+1i))
  (compile (lit (fn (buffer score chr)
    (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    (list (pair (lit %cx-real-int) %cx-real-int))))

(type-push-analyse (type-by-atom (type-of 0))
  (compile (lit (fn (buffer score chr)
    (if (< chr 48) () (if (< chr 58) %int-capped-digits ()))))
    (list (pair (lit %int-capped-digits) %int-capped-digits))))

; --- System extensions ---
(include "lib/x/or/syscall.x")
(include "lib/x/or/file.x")
(include "lib/x/or/socket.x")

; --- Character constants ---
(def #newline (substring "\n" 0 1))
(def #nl #newline)
(def #cr (substring "\r" 0 1))
(def #esc (substring "\x1b" 0 1))
(def #0 (substring "" 0 1))
(def #crnl (string-append #cr #nl))

; --- I/O constants ---
(def stdin 0)
(def stdout 1)
(def stderr 2)
(def current-input-handle stdin)
(def current-output-handle stdout)
(def current-error-handle stderr)

; --- Car/cdr composition chains ---
(def caar (fn (x) (first (first x))))
(def cadr (fn (x) (first (rest x))))
(def cdar (fn (x) (rest (first x))))
(def cddr (fn (x) (rest (rest x))))
(def caaar (fn (x) (first (caar x))))
(def caadr (fn (x) (first (cadr x))))
(def cadar (fn (x) (first (cdar x))))
(def caddr (fn (x) (first (cddr x))))
(def cdaar (fn (x) (rest (caar x))))
(def cdadr (fn (x) (rest (cadr x))))
(def cddar (fn (x) (rest (cdar x))))
(def cdddr (fn (x) (rest (cddr x))))
(def caaaar (fn (x) (first (caaar x))))
(def caaadr (fn (x) (first (caadr x))))
(def caadar (fn (x) (first (cadar x))))
(def caaddr (fn (x) (first (caddr x))))
(def cadaar (fn (x) (first (cdaar x))))
(def cadadr (fn (x) (first (cdadr x))))
(def caddar (fn (x) (first (cddar x))))
(def cadddr (fn (x) (first (cdddr x))))
(def cdaaar (fn (x) (rest (caaar x))))
(def cdaadr (fn (x) (rest (caadr x))))
(def cdadar (fn (x) (rest (cadar x))))
(def cdaddr (fn (x) (rest (caddr x))))
(def cddaar (fn (x) (rest (cdaar x))))
(def cddadr (fn (x) (rest (cdadr x))))
(def cdddar (fn (x) (rest (cddar x))))
(def cddddr (fn (x) (rest (cdddr x))))

; --- Convenience aliases ---
(def second cadr)
(def third caddr)
(def else #t)

; --- Compatibility aliases ---
(def list-ref (fn (lst n) (nth n lst)))
(def list-tail (fn (lst n) (drop n lst)))
(def string-copy (fn (s) (substring s 0 (string-length s))))

; --- System functions ---
(def system
  (fn (cmd)
    (if (= (syscall (syscall-id (lit fork))) 0)
      (syscall
        (syscall-id (lit execve))
        "/bin/sh"
        (list "/bin/sh" "-c" cmd)))))

; --- do-loop: Scheme iteration form ---
; (do-loop ((var init step) ...) (test result ...) body ...)
(def do-loop
  (op (bindings test-and-result . body)
    e
    (def variables (map first bindings))
    (def inits (map cadr bindings))
    (def steps
      (map
        (fn (clause)
          (if (null? (cddr clause)) (first clause) (caddr clause)))
        bindings))
    (def test-expr (first test-and-result))
    (def result-exprs (rest test-and-result))
    (eval
      (list
        (lit letrec)
        (list
          (list
            (lit %loop)
            (pair
              (lit fn)
              (pair
                variables
                (list
                  (lit if)
                  test-expr
                  (pair (lit do) result-exprs)
                  (append
                    (pair (lit do) body)
                    (list (pair (lit %loop) steps))))))))
        (pair (lit %loop) inits))
      e)))

(doc (provide x/or
  stdin stdout stderr current-input-handle current-output-handle current-error-handle
  #newline #nl #cr #esc #0 #crnl
  caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
  caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
  cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
  second third else list-ref list-tail string-copy system do-loop)
  (note "Experimental/unstable dialect with full toolbox.")
  (note "Includes compiler, POSIX, syscall, file I/O, sockets.")
  (note "Extends arithmetic with bignum, float, rational, complex, regex.")
  "x/or: Experimental hacking dialect built on x-lang.")
