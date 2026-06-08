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
    (pair "lib/x/type/str-utf8.x"
    (pair "lib/x/type/vector.x"
    (pair "lib/x/type/promise.x"
    (pair "lib/x/type/object.x"
    (pair "lib/x/protocol/seq.x"
    (pair "lib/x/protocol/str/str8.x"
    (pair "lib/x/protocol/str/utf8.x"
    (pair "lib/x/type/str.x"
    (pair "lib/x/sys/token.x"
    (pair "lib/x/core/quasi.x"
    (pair "lib/x/type/quasi-reader.x"
    (pair "lib/x/type/lit-reader.x"
    (pair "lib/x/core/repl.x"
    (pair "lib/x/core/banner.x"
      (first %include-list-cell)))))))))))))))))))))))))))))))))))

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
  ; include-once (not include): registers the path so str-utf8.x's and the Utf8
  ; protocol class's (import x/codec/utf8) become no-ops instead of reloading it.
  (include-once "lib/x/codec/utf8.x")
  ; Low-level UTF-8 code-point layer for the STRING type: the list<->str
  ; transforms (needed by char-io / number->str / convert) plus the bare (s i)
  ; -> code-point handler. Safe here -- str-ref/str-length/substring stay pinned
  ; to the byte primitives, and every reader/tokenizer/loader that needs bytes
  ; uses them (not the ambient (s i) call).
  (include "lib/x/type/str-utf8.x")
  ; UTF-8-aware CHARACTER write/display handlers (shadow the C byte fallback)
  (include "lib/x/type/char-io.x")
  (include "lib/x/type/vector.x")
  (include "lib/x/type/promise.x")
  (include "lib/x/type/object.x")
  ; Fn: function combinators (the Fn class). Moved here from the early core block
  ; -- it needs def-class, and nothing loaded before object.x references it.
  (include "lib/x/core/fn.x")
  ; String library: the protocol classes (Str8/StrUTF8) + the Str entry point.
  ; Loaded AFTER the object system they are built on. (The low-level code-point
  ; layer in type/str-utf8.x already loaded earlier, before objects, for boot
  ; code that needs the list<->string conversions.)
  (include "lib/x/protocol/seq.x")
  (include "lib/x/protocol/str/str8.x")
  (include "lib/x/protocol/str/utf8.x")
  (include "lib/x/type/str.x")
  ; Iterator protocol: defines the Iter class + wires the iter slot on the
  ; sequence types (registered above) + consumers.
  (include "lib/x/type/iter.x")
  ; Base: execution-context objects via the Base class.
  (include "lib/x/type/base.x")
  ; List: list/sequence operations as the List class (core/list.x holds the
  ; low-level impl + %-helpers; functions migrate onto this class over time).
  (include "lib/x/type/list.x")
  ; Catalog -> object-system bridge: a class per catalog namespace (transitional,
  ; as the object system supersedes the flat catalog + bare-name registration).
  ; After the real classes above, so it folds onto them rather than projecting.
  (include "lib/x/type/catalog.x")
  (include "lib/x/sys/token.x")

  ; Quasi-quoting
  (include "lib/x/core/quasi.x")

  ; Quasi-quote reader syntax (backtick, comma, comma-at)
  (include "lib/x/type/quasi-reader.x")

  ; Quote reader syntax (apostrophe expr to lit expr)
  (include "lib/x/type/lit-reader.x")

  ; REPL
  (include "lib/x/core/repl.x")

  ; ANSI colour: syntax-highlighted REPL output + colourised help.  Loaded
  ; after repl.x (it wraps %repl-print) and doc.x (it sets the %c-* help
  ; colours).  All colours are empty no-ops unless stdout is a TTY and
  ; NO_COLOR/TERM=dumb/--no-color do not disable them.
  (include "lib/x/sys/ansi.x")

  ; Banner
  (include "lib/x/core/banner.x")

  ; Install the SIGINT handler so ctrl-c breaks loops.  On builds without
  ; signal support these primitives are absent; fall back to inert no-ops so
  ; the REPL still loads (%sigint-flag becomes an unused settable cell).
  (guard (_
      (def sigint-install (fn () ()))
      (def sigint-restore (fn () ()))
      (def %sigint-flag (list 0)))
    (sigint-install))

  ; --- Provide ---
  (doc (provide x/sys/type
    type-alist type-by-atom type-io type-cvt
    type-write-cell type-analyse-cell type-from-cell type-to-cell
    type-push-write type-pop-write type-push-analyse type-iter-cell
    type-push-iter type-cast!)
    "Type system reflection and manipulation.")
  (doc (provide x/core
    null? if let do begin not atom? list convert number->str str->number
    str=? str-ref str-length substring
    newline heap-collect heap-mark-root! heap-mark-hook!
    heap-free-hook! include-once require-once provide import
    peek-char current-line quasi repl doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
