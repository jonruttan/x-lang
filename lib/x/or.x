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
; Single compile-batch call = one cc invocation for all 5 entry points.
; Set %compile-fvars to embed runtime pointers to state machines.

(set! %compile-fvars
  (list
    (pair (lit %float-int-digits) %float-int-digits)
    (pair (lit %rat-numer) %rat-numer)
    (pair (lit %rat-sign)
      (fn (_ buffer score chr)
        (if (< chr 48) () (if (< chr 58) %rat-numer ()))))
    (pair (lit %big-sign-state) %big-sign-state)
    (pair (lit %big-digits) %big-digits)
    (pair (lit %cx-real-int) %cx-real-int)
    (pair (lit %int-capped-digits) %int-capped-digits)))

(def %compiled-analysers
  (compile-batch
    ; 0: float entry
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    ; 1: rational entry
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
        (if (< chr 58) %rat-numer ()))))
    ; 2: bignum entry
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    ; 3: complex entry
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    ; 4: int-capped entry
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %int-capped-digits ()))))))

(set! %compile-fvars ())

; Patch compiled analysers onto type stacks
(def %nth (fn (_ n lst) (if (= n 0) (first lst) (%nth (- n 1) (rest lst)))))
(type-push-analyse (type-by-atom (type-of 1.0)) (%nth 0 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 1/2)) (%nth 1 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of (expt 2 64))) (%nth 2 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 1+1i)) (%nth 3 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 0)) (%nth 4 %compiled-analysers))

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
(def caar (fn (_ x) (first (first x))))
(def cadr (fn (_ x) (first (rest x))))
(def cdar (fn (_ x) (rest (first x))))
(def cddr (fn (_ x) (rest (rest x))))
(def caaar (fn (_ x) (first (caar x))))
(def caadr (fn (_ x) (first (cadr x))))
(def cadar (fn (_ x) (first (cdar x))))
(def caddr (fn (_ x) (first (cddr x))))
(def cdaar (fn (_ x) (rest (caar x))))
(def cdadr (fn (_ x) (rest (cadr x))))
(def cddar (fn (_ x) (rest (cdar x))))
(def cdddr (fn (_ x) (rest (cddr x))))
(def caaaar (fn (_ x) (first (caaar x))))
(def caaadr (fn (_ x) (first (caadr x))))
(def caadar (fn (_ x) (first (cadar x))))
(def caaddr (fn (_ x) (first (caddr x))))
(def cadaar (fn (_ x) (first (cdaar x))))
(def cadadr (fn (_ x) (first (cdadr x))))
(def caddar (fn (_ x) (first (cddar x))))
(def cadddr (fn (_ x) (first (cdddr x))))
(def cdaaar (fn (_ x) (rest (caaar x))))
(def cdaadr (fn (_ x) (rest (caadr x))))
(def cdadar (fn (_ x) (rest (cadar x))))
(def cdaddr (fn (_ x) (rest (caddr x))))
(def cddaar (fn (_ x) (rest (cdaar x))))
(def cddadr (fn (_ x) (rest (cdadr x))))
(def cdddar (fn (_ x) (rest (cddar x))))
(def cddddr (fn (_ x) (rest (cdddr x))))

; --- Convenience aliases ---
(def second cadr)
(def third caddr)
(def else #t)

; --- Compatibility aliases ---
(def list-ref (fn (_ lst n) (nth n lst)))
(def list-tail (fn (_ lst n) (drop n lst)))
(def string-copy (fn (_ s) (substring s 0 (string-length s))))

; --- System functions ---
(def system
  (fn (_ cmd)
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
        (fn (_ clause)
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
                (pair (lit _) variables)
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
