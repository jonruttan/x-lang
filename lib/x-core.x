; # Computational Expressions in C
;
; ## x-core.x -- x Core Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

; --- Bootstrap (minimum to get provide/import working) ---
(include "lib/x/boot/operatives.x")
(include "lib/x/boot/data.x")
(include "lib/x/boot/string.x")
(include "lib/x/boot/module.x")

(do
  (def x-lib-version "0.2.0")

  ; Pre-register all library paths so import calls are no-ops
  (set-first! %include-list-cell
    (pair "lib/x/core/predicates.x"
    (pair "lib/x/core/control.x"
    (pair "lib/x/sys/gc.x"
    (pair "lib/x/doc/doc.x"
    (pair "lib/x/doc/doc-prims.x"
    (pair "lib/x/sys/type.x"
    (pair "lib/x/sys/convert.x"
    (pair "lib/x/core/boolean.x"
    (pair "lib/x/core/fn.x"
    (pair "lib/x/core/logic.x"
    (pair "lib/x/core/list.x"
    (pair "lib/x/core/math.x"
    (pair "lib/x/core/syntax.x"
    (pair "lib/x/num/tower.x"
    (pair "lib/x/core/alist.x"
    (pair "lib/x/core/arithmetic.x"
    (pair "lib/x/sys/intrinsics.x"
    (pair "lib/x/sys/posix.x"
    (pair "lib/x/type/char.x"
    (pair "lib/x/type/string.x"
    (pair "lib/x/type/vector.x"
    (pair "lib/x/type/promise.x"
    (pair "lib/x/type/object.x"
    (pair "lib/x/sys/token.x"
    (pair "lib/x/core/quasi.x"
    (pair "lib/x/type/quasi-reader.x"
    (pair "lib/x/type/lit-reader.x"
    (pair "lib/x/core/repl.x"
    (pair "lib/x/core/banner.x"
      (first %include-list-cell)))))))))))))))))))))))))))))))

  ; --- Standard modules ---
  (include "lib/x/core/predicates.x")
  (include "lib/x/core/control.x")
  (include "lib/x/sys/gc.x")

  ; Type system internals (before doc, cannot use provide)
  (include "lib/x/sys/type.x")
  (include "lib/x/sys/convert.x")

  ; Documentation system
  (include "lib/x/doc/doc.x")
  (include "lib/x/doc/doc-prims.x")

  ; Boolean operatives
  (include "lib/x/core/boolean.x")

  ; Core library
  (include "lib/x/core/fn.x")
  (include "lib/x/core/logic.x")
  (include "lib/x/core/list.x")
  (include "lib/x/core/math.x")
  (include "lib/x/core/syntax.x")
  (include "lib/x/num/tower.x")

  ; Variadic arithmetic
  (include "lib/x/core/arithmetic.x")

  ; Tokenizer helpers
  (include "lib/x/sys/intrinsics.x")

  ; POSIX wrappers (needed by REPL for fd swap on ctrl-c recovery)
  (include "lib/x/sys/posix.x")

  ; Type extensions
  (include "lib/x/core/alist.x")
  (include "lib/x/type/char.x")
  ; include-once (not include): registers the path so string.x's and the Utf8
  ; protocol class's (import x/codec/utf8) become no-ops instead of reloading it.
  (include-once "lib/x/codec/utf8.x")
  (include "lib/x/type/string.x")
  ; UTF-8-aware CHARACTER write/display handlers (shadow the C byte fallback)
  (include "lib/x/type/char-io.x")
  (include "lib/x/type/vector.x")
  (include "lib/x/type/promise.x")
  (include "lib/x/type/object.x")
  (include "lib/x/sys/token.x")

  ; Quasi-quoting
  (include "lib/x/core/quasi.x")

  ; Quasi-quote reader syntax (backtick, comma, comma-at)
  (include "lib/x/type/quasi-reader.x")

  ; Quote reader syntax (apostrophe expr to lit expr)
  (include "lib/x/type/lit-reader.x")

  ; REPL
  (include "lib/x/core/repl.x")

  ; Banner
  (include "lib/x/core/banner.x")

  ; Install the SIGINT handler so ctrl-c breaks loops.  On builds without
  ; signal support these primitives are absent; fall back to inert no-ops so
  ; the REPL still loads (%sigint-flag becomes an unused settable cell).
  (guard (%e
      (def sigint-install (fn () ()))
      (def sigint-restore (fn () ()))
      (def %sigint-flag (list 0)))
    (sigint-install))

  ; --- Provide ---
  (doc (provide x/sys/type
    type-alist type-by-atom type-io type-cvt
    type-write-cell type-analyse-cell type-from-cell type-to-cell
    type-push-write type-pop-write type-push-analyse type-cast!)
    "Type system reflection and manipulation.")
  (doc (provide x/core
    null? if let do begin not atom? list convert number->str str->number
    str=? str-ref str-length substring
    newline heap-collect heap-mark-root! heap-mark-hook!
    heap-free-hook! include-once require-once provide import
    peek-char current-line quasi repl doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
