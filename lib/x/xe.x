; xe.x -- x/xe: xenon, the stable/hardened dialect
;
; Built on x-lang. Imports the full stable toolbox: compiler, POSIX,
; numeric tower, regex, Dict. Does NOT include experimental extensions
; (syscall, file, socket).
;

; --- Common containers ---
; Dict rides the dialect, not x-core: helium stays light (x-core only),
; and Dict pulls x/type/hash, which the light boot does not carry.  The
; tower dialects already load hash (tower-compiled.x), so this import is
; the bucket layer only.  Pinned by dialects/smoke.spec.md.
(import x/type/dict)

(doc (provide x/xe)
  (note "xenon: stable/hardened dialect with compiler, POSIX, and full numeric tower.")
  (note "Common containers loaded by default: Dict (content-hashed mutable table).")
  (note "No experimental extensions (syscall, file, socket).")
  "x/xe: Stable full-stack dialect built on x-lang.")
