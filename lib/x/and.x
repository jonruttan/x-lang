; and.x -- x/and: Stable/Hardened dialect
;
; Built on x-lang. Imports the full stable toolbox: compiler, POSIX,
; numeric tower, regex. Does NOT include experimental extensions
; (syscall, file, socket).

; --- Convenience aliases ---
(def second (fn (_ x) (first (rest x))))
(def third (fn (_ x) (first (rest (rest x)))))
(def else #t)

; --- Compatibility aliases ---
(def list-ref (fn (_ lst n) (nth n lst)))
(def list-tail (fn (_ lst n) (drop n lst)))
(def str-copy (fn (_ s) (substring s 0 (str-length s))))

(doc (provide x/and
  second third else list-ref list-tail str-copy)
  (note "Stable/hardened dialect with compiler, POSIX, and full numeric tower.")
  (note "No experimental extensions (syscall, file, socket).")
  "x/and: Stable full-stack dialect built on x-lang.")
