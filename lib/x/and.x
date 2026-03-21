; and.x -- x/and: Stable/Hardened dialect
;
; Built on x-lang. Imports the full stable toolbox: compiler, POSIX,
; numeric tower, regex. Does NOT include experimental extensions
; (syscall, file, socket).

; --- Heavy imports ---
(import x/posix)
(import x/hash)
(import x/compile)
(import x/bignum)
(import x/regex)

; --- Compile tokenizer analysers for numeric types ---
; Single compile-batch call = one cc invocation for all 5 entry points.

(set! %compile-fvars
  (list
    (pair (lit %float-int-digits) %float-int-digits)
    (pair (lit %rat-numer) %rat-numer)
    (pair (lit %rat-sign)
      (fn (buffer score chr)
        (if (< chr 48) () (if (< chr 58) %rat-numer ()))))
    (pair (lit %big-sign-state) %big-sign-state)
    (pair (lit %big-digits) %big-digits)
    (pair (lit %cx-real-int) %cx-real-int)
    (pair (lit %int-capped-digits) %int-capped-digits)))

(def %compiled-analysers
  (compile-batch
    (lit (fn (buffer score chr)
      (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    (lit (fn (buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
        (if (< chr 58) %rat-numer ()))))
    (lit (fn (buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    (lit (fn (buffer score chr)
      (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    (lit (fn (buffer score chr)
      (if (< chr 48) () (if (< chr 58) %int-capped-digits ()))))))

(set! %compile-fvars ())

(def %nth (fn (n lst) (if (= n 0) (first lst) (%nth (- n 1) (rest lst)))))
(type-push-analyse (type-by-atom (type-of 1.0)) (%nth 0 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 1/2)) (%nth 1 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of (expt 2 64))) (%nth 2 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 1+1i)) (%nth 3 %compiled-analysers))
(type-push-analyse (type-by-atom (type-of 0)) (%nth 4 %compiled-analysers))

; --- Convenience aliases ---
(def second (fn (x) (first (rest x))))
(def third (fn (x) (first (rest (rest x)))))
(def else #t)

; --- Compatibility aliases ---
(def list-ref (fn (lst n) (nth n lst)))
(def list-tail (fn (lst n) (drop n lst)))
(def string-copy (fn (s) (substring s 0 (string-length s))))

(doc (provide x/and
  second third else list-ref list-tail string-copy)
  (note "Stable/hardened dialect with compiler, POSIX, and full numeric tower.")
  (note "No experimental extensions (syscall, file, socket).")
  "x/and: Stable full-stack dialect built on x-lang.")
