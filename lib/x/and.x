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
