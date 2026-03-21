; or-base.x -- x/or Standard Library (non-interactive)
;
; x/or: Maximal Lisp dialect built on x-lang.
; Loads the full x-lang standard library plus system-level extensions.
(include "lib/x-core.x")
(do
  ; Pre-register paths so import calls within these files are no-ops
  (set-first! %include-list-cell
    (pair "lib/x/posix.x"
    (pair "lib/x/hash.x"
    (pair "lib/x/compile.x"
    (pair "lib/x/float.x"
    (pair "lib/x/rational.x"
    (pair "lib/x/complex.x"
    (pair "lib/x/regex.x"
      (first %include-list-cell)))))))))
  ; Extended standard library
  (include "lib/x/posix.x")
  (include "lib/x/hash.x")
  (include "lib/x/compile.x")
  (include "lib/x/float.x")
  (include "lib/x/rational.x")
  (include "lib/x/complex.x")
  (include "lib/x/regex.x")

  ; x/or specific: syscall tables, file I/O, sockets
  (include "lang/x-or/lib/x/syscall.x")
  (include "lang/x-or/lib/x/file.x")
  (include "lang/x-or/lib/x/socket.x")

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

  (def time (fn () (syscall (syscall-id (lit time)))))

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
        e))))
