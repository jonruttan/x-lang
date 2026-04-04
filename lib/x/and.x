; and.x -- x/and: Stable/Hardened dialect
;
; Built on x-lang. Imports the full stable toolbox: compiler, POSIX,
; numeric tower, regex. Does NOT include experimental extensions
; (syscall, file, socket).
;
; Convenience aliases (second, third, else, list-ref, list-tail, str-copy)
; are now provided by x/core/list.

(doc (provide x/and)
  (note "Stable/hardened dialect with compiler, POSIX, and full numeric tower.")
  (note "No experimental extensions (syscall, file, socket).")
  "x/and: Stable full-stack dialect built on x-lang.")
