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
