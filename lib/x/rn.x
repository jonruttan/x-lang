; rn.x -- x/rn: radon, the experimental/hacking dialect
;
; Built on x-lang.  Pulls in the heavy toolbox eagerly (compiler comes in
; transitively via the radon body, lib/x/boot/radon.x; POSIX FFI, numeric
; tower, regex).
; The system-level extensions (syscall table, file I/O, sockets) are
; deferred -- nothing in this dialect uses them by default, so leave
; them as opt-in `(include …)` calls for code that does.

; --- Heavy imports ---
(import x/sys/posix)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

(import x/type/hash)
(import x/num/bignum)
(import x/type/regex)
; Common containers: Dict and Set ride the dialects (helium stays light) --
; same rationale as x/xe.x; pinned by dialects/smoke.spec.md.
(import x/type/dict)
(import x/type/set)
; x/tool/compile is already loaded by the radon body; no need to re-import.

; --- Opt-in system extensions ---
; (include "lib/x/platform/syscall.x")  ; needed by (system …) below
; (include "lib/x/sys/file.x")
; (include "lib/x/platform/socket.x")

; --- Character constants ---
(def #newline "\n")
(def #nl #newline)
(def #cr "\r")
(def #esc "\x1b")
(def #0 "")
(def #crnl (%str-append #cr #nl))

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

; Scheme-compat list accessors: subject-FIRST R7RS names, at home in this
; dialect with the cxr ladder; the core List class stays data-last.
(def list-ref (fn (_ lst n) (List ref n lst)))
(def list-tail (fn (_ lst n) (List drop n lst)))

; --- System functions ---
(def system
  (fn (_ cmd)
    (if (= (syscall (syscall-id 'fork)) 0)
      (syscall
        (syscall-id 'execve)
        "/bin/sh"
        (list "/bin/sh" "-c" cmd)))))

; --- do-loop: Scheme iteration form ---
; (do-loop ((var init step) ...) (test result ...) body ...)
(def do-loop
  (op (bindings test-and-result . body)
    e
    (def variables (%map first bindings))
    (def inits (%map cadr bindings))
    (def steps
      (%map
        (fn (_ clause)
          (if (null? (cddr clause)) (first clause) (caddr clause)))
        bindings))
    (def test-expr (first test-and-result))
    (def result-exprs (rest test-and-result))
    (eval
      (list
        'letrec
        (list
          (list
            '%loop
            (pair
              'fn
              (pair
                (pair '_ variables)
                (list
                  'if
                  test-expr
                  (pair 'do result-exprs)
                  (%append
                    (pair 'do body)
                    (list (pair '%loop steps))))))))
        (pair '%loop inits))
      e)))

(doc (provide x/rn
  stdin stdout stderr current-input-handle current-output-handle current-error-handle
  #newline #nl #cr #esc #0 #crnl
  caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
  caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
  cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
  system do-loop)
  (note "Experimental/unstable dialect with full toolbox.")
  (note "Includes compiler and POSIX FFI.")
  (note "Common containers loaded by default: Dict (content-hashed mutable table).")
  (note "Extends arithmetic with bignum, float, rational, complex, regex.")
  (note "Syscall table, file I/O, and sockets are opt-in -- include them yourself if you call (system …) or use these subsystems.")
  "x/rn: Experimental hacking dialect built on x-lang.")
