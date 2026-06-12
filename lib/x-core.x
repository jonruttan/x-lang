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
    (pair "lib/x/type/type.x"
    (pair "lib/x/sys/convert.x"
    (pair "lib/x/core/boolean.x"
    (pair "lib/x/core/fn.x"
    (pair "lib/x/core/logic.x"
    (pair "lib/x/core/list.x"
    (pair "lib/x/core/math.x"
    (pair "lib/x/core/syntax.x"
    (pair "lib/x/core/alist.x"
    (pair "lib/x/type/assoc.x"
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
      (first %include-list-cell))))))))))))))))))))))))))))))))))))

  ; --- Standard modules ---
  (include "lib/x/core/predicates.x")
  (include "lib/x/core/control.x")

  ; Type system internals (before doc, cannot use provide)
  (include "lib/x/sys/type.x")

  ; Documentation system
  (include "lib/x/doc/doc.x")
  (include "lib/x/doc/doc-prims.x")

  ; Boolean operatives
  (include "lib/x/core/boolean.x")

  ; Core library
  (include "lib/x/core/logic.x")
  (include "lib/x/core/list.x")
  (include "lib/x/core/syntax.x")

  ; Variadic arithmetic
  (include "lib/x/core/arithmetic.x")

  ; Tokenizer helpers
  (include "lib/x/sys/intrinsics.x")

  ; Type extensions
  (include "lib/x/core/alist.x")
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
  (include "lib/x/type/object.x")
  ; Convert: the conversion dispatcher (registered in the catalog as
  ; (convert . to)) + the Convert class with the no-match policy member.
  ; Relocated past object.x from the early type-internals block -- it needs
  ; def-class + doc, and every caller (tower, regex, posix, hash, tools)
  ; loads later still.
  (include "lib/x/sys/convert.x")
  ; Type: the type-system reflection API (the Type class). The mechanism stays
  ; in sys/type.x (pre-object, %-private, filed under catalog ns `type`);
  ; this class presents it and carries the docs.
  (include "lib/x/type/type.x")
  ; Fn: function combinators (the Fn class). Moved here from the early core block
  ; -- it needs def-class, and nothing loaded before object.x references it.
  (include "lib/x/core/fn.x")
  ; Num: integer math utilities + number predicates (the Num class). Relocated
  ; past object.x -- nothing loaded before the object system calls these.
  (include "lib/x/core/math.x")
  ; Promise: the delay form + the Promise class. Relocated past object.x --
  ; nothing loaded before the object system uses promises.
  (include "lib/x/type/promise.x")
  ; Assoc: the association-list API (the Assoc class). core/alist.x keeps the
  ; bootstrap five the object system runs on; this class delegates to them.
  (include "lib/x/type/assoc.x")
  ; Heap: GC control (the Heap class; methods fetch the C prims from the
  ; catalog). Relocated from the early block -- the heap-* bare C names are
  ; bound by registration regardless of where this module loads.
  (include "lib/x/sys/gc.x")
  ; Sys: POSIX wrappers (the Sys class). Relocated -- every caller (the REPL's
  ; ctrl-c fd recovery, ansi, logo, tools) loads after the object system.
  (include "lib/x/sys/posix.x")
  ; Vector: #() type machinery + the Vector class. Needs def-class; relocated past
  ; object.x from the early block -- nothing before it uses vectors or #() literals.
  (include "lib/x/type/vector.x")
  ; Char: classification / case / comparison (the Char class). Needs def-class; the
  ; pre-object string layer uses char->integer, not these, so it relocated here.
  (include "lib/x/type/char.x")
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
  (doc (provide x/sys/type)
    (note "The reflection helpers are %-private here and filed under catalog ns `type`; the API is the Type class (x/type/type).")
    "Type system mechanism: struct navigation and handler-stack wiring, registered in the catalog.")
  (doc (provide x/core
    null? if let do begin not atom? list number->str str->number
    str=? str-ref str-length substring
    newline heap-collect heap-mark-root! heap-mark-hook!
    heap-free-hook! include-once require-once provide import
    peek-char current-line quasi repl doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
