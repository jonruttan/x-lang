; xe.x -- x/xe: xenon, the stable/hardened dialect
;
; Built on x-lang. Imports the full stable toolbox: compiler, POSIX,
; numeric tower, regex. Does NOT include experimental extensions
; (syscall, file, socket).
;
; Convenience aliases (second, third, else, list-ref, list-tail, str-copy)
; are now provided by x/core/list.

(doc (provide x/xe)
  (note "xenon: stable/hardened dialect with compiler, POSIX, and full numeric tower.")
  (note "No experimental extensions (syscall, file, socket).")
  "x/xe: Stable full-stack dialect built on x-lang.")
