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
; The base-paths contract + the catalog protocol load FIRST: everything
; after them (operatives.x included) fetches its C instruments through
; prim-ref, which is pure X -- a first/rest walk over the prims cell.
(include "tools/base-paths.x")
(include "lib/x/boot/registry.x")
(include "lib/x/boot/operatives.x")
; The object-layout contract: header offsets data.x and reflect.x build on.
(include "tools/obj-layout.x")
(include "lib/x/boot/data.x")
(include "lib/x/boot/reflect.x")
; printer BEFORE string.x: string.x's callers resolve display/write from it,
; and its own number->str dependency is call-time only.
(include "lib/x/boot/printer.x")
(include "lib/x/boot/string.x")
(include "lib/x/boot/module.x")

(do
  (def x-lib-version "0.3.0")

  ; Pre-register all library paths so import calls are no-ops.
  ; INVARIANT (machine-checked by make check-boot-order): every lib path this
  ; file loads with raw `include` -- which does NOT register -- must appear
  ; here, or a later import of it silently reloads the file mid-boot.  The
  ; boot files above (loaded before the module system existed) are listed too,
  ; so the invariant holds uniformly.
  (%set-first! %include-list-cell
    (pair "lib/x-core.x"
    (pair "lib/x/boot/registry.x"
    (pair "lib/x/boot/operatives.x"
    (pair "lib/x/boot/data.x"
    (pair "lib/x/boot/reflect.x"
    (pair "lib/x/boot/printer.x"
    (pair "lib/x/boot/string.x"
    (pair "lib/x/boot/module.x"
    (pair "lib/x/core/predicates.x"
    (pair "lib/x/core/control.x"
    (pair "lib/x/sys/gc.x"
    (pair "lib/x/doc/doc.x"
    (pair "lib/x/doc/doc-prims.x"
    (pair "lib/x/type/struct.x"
    (pair "lib/x/type/type.x"
    (pair "lib/x/type/obj.x"
    (pair "lib/x/type/buf.x"
    (pair "lib/x/type/ptr.x"
    (pair "lib/x/type/io.x"
    (pair "lib/x/type/convert.x"
    (pair "lib/x/core/boolean.x"
    (pair "lib/x/core/fn.x"
    (pair "lib/x/core/logic.x"
    (pair "lib/x/core/list.x"
    (pair "lib/x/core/math.x"
    (pair "lib/x/core/syntax.x"
    (pair "lib/x/core/alist.x"
    (pair "lib/x/type/assoc.x"
    (pair "lib/x/core/arithmetic.x"
    (pair "lib/x/reader/intrinsics.x"
    (pair "lib/x/sys/posix.x"
    (pair "lib/x/type/char.x"
    (pair "lib/x/type/str-utf8.x"
    (pair "lib/x/type/char-io.x"
    (pair "lib/x/type/vector.x"
    (pair "lib/x/type/promise.x"
    (pair "lib/x/type/class.x"
    (pair "lib/x/protocol/seq.x"
    (pair "lib/x/protocol/str/str8.x"
    (pair "lib/x/protocol/str/utf8.x"
    (pair "lib/x/type/str.x"
    (pair "lib/x/type/iter.x"
    (pair "lib/x/type/base.x"
    (pair "lib/x/type/list.x"
    (pair "lib/x/type/gen.x"
    (pair "lib/x/reader/token.x"
    (pair "lib/x/core/quasi.x"
    (pair "lib/x/reader/quasi-reader.x"
    (pair "lib/x/reader/lit-reader.x"
    (pair "lib/x/repl/loop.x"
    (pair "lib/x/type/bool.x"
    (pair "lib/x/core/op-guard.x"
    (pair "lib/x/type/err.x"
    (pair "lib/x/repl/ansi.x"
    (pair "lib/x/repl/banner.x"
      (first %include-list-cell)))))))))))))))))))))))))))))))))))))))))))))))))))))))))

  ; --- Standard modules ---
  (include "lib/x/core/predicates.x")
  (include "lib/x/core/control.x")

  ; Type system internals (before doc, cannot use provide)
  (include "lib/x/type/struct.x")

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
  (include "lib/x/reader/intrinsics.x")

  ; Type extensions
  (include "lib/x/core/alist.x")
  ; include-once (not include): registers the path so str-utf8.x's and the StrUTF8
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
  (include "lib/x/type/class.x")
  ; Convert: the conversion dispatcher (registered in the catalog as
  ; (convert . to)) + the Convert class with the no-match policy member.
  ; Relocated past object.x from the early type-internals block -- it needs
  ; def-class + doc, and every caller (tower, regex, posix, hash, tools)
  ; loads later still.
  (include "lib/x/type/convert.x")
  ; Type: the type-system reflection API (the Type class). The mechanism stays
  ; in sys/type.x (pre-object, %-private, filed under catalog ns `type`);
  ; this class presents it and carries the docs.
  (include "lib/x/type/type.x")
  ; Obj: the raw object layer (slots, metadata, FFI handles) as the Obj class.
  ; ns `obj` is de-registered; boot/data.x's pair mutators fetch the prims.
  (include "lib/x/type/obj.x")
  ; Buf + Tok: the tokenizer buffer / token-stream API. ns buf/tok are
  ; de-registered; reader-hot modules fetch-and-cache the prims.
  (include "lib/x/type/buf.x")
  ; Ptr + Ffi: the raw-pointer / foreign-function surface. ns ptr/ffi are
  ; de-registered; low-level/hot callers fetch-and-cache the prims.
  (include "lib/x/type/ptr.x")
  ; Io: input/output surface (the Io class). ns io is de-registered except
  ; write/display (kept bare via the keep-list); the rest fetch-and-cache.
  (include "lib/x/type/io.x")
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
  ; Gen: lazy generators (unfold-based). Needs object/list/vector, all above.
  (include "lib/x/type/gen.x")
  (include "lib/x/reader/token.x")

  ; Quasi-quoting
  (include "lib/x/core/quasi.x")

  ; Quasi-quote reader syntax (backtick, comma, comma-at)
  (include "lib/x/reader/quasi-reader.x")

  ; Quote reader syntax (apostrophe expr to lit expr)
  (include "lib/x/reader/lit-reader.x")

  ; REPL
  (include "lib/x/repl/loop.x")

  ; Structured errors (#20): the Err class + errno translation.  Loaded
  ; after lit-reader (the file speaks 'x) and after platform/syscall's
  ; transitive boot load (the errno table picks its OS column via
  ; os-darwin? at load).  Raise sites throughout lib bind Err at CALL
  ; time, so every post-boot error can be structured regardless of the
  ; raising module's own boot position.
  (include "lib/x/type/err.x")

  ; Non-numeric types refuse arithmetic (#52): error-raising op handlers
  ; registered on string/symbol/char/list/pair/vector, so op_try routes
  ; (+ 1 "abc") to err:type instead of the int fallthrough's pointer math.
  ; After err.x (Err raise) and vector.x (the #() handle).
  (include "lib/x/core/op-guard.x")

  ; BOOL claims the #t/#f singletons (#101): an x-defined type over the
  ; C statics via (obj retag!), closing the #52 boolean residual -- and
  ; (Type of #t) finally answers. After op-guard (reuses its refusal
  ; machinery).
  (include "lib/x/type/bool.x")

  ; ANSI colour: syntax-highlighted REPL output + colourised help.  Loaded
  ; after repl.x (it wraps %repl-print) and doc.x (it sets the %c-* help
  ; colours).  All colours are empty no-ops unless stdout is a TTY and
  ; NO_COLOR/TERM=dumb/--no-color do not disable them.
  (include "lib/x/repl/ansi.x")

  ; Banner
  (include "lib/x/repl/banner.x")

  ; Install the SIGINT handler so ctrl-c breaks loops.  On builds without
  ; signal support these primitives are absent; fall back to inert no-ops so
  ; the REPL still loads (%sigint-flag becomes an unused settable cell).
  (guard (_
      (def sigint-install (fn () ()))
      (def sigint-restore (fn () ()))
      (def %sigint-flag (list 0)))
    (sigint-install))

  ; --- Provide ---
  ; Retroactive provides for the boot layer: those files load BEFORE the
  ; module system exists, so they cannot call provide themselves; registering
  ; them here makes them visible to (modules) and module-level (help).
  (doc (provide x/boot/registry)
    "Boot: the catalog protocol -- prim-ref and the instrument registry (loads first).")
  (doc (provide x/boot/operatives)
    "Boot: the core operative layer over the C primitives.")
  (doc (provide x/boot/data)
    "Boot: data constructors and the pair mutators (set-first!/set-rest!).")
  (doc (provide x/boot/reflect)
    "Boot: base-struct reflection walkers over the base-paths contract.")
  (doc (provide x/boot/printer)
    "Boot: display/write and the printer seams (loads before string.x).")
  (doc (provide x/boot/string)
    "Boot: substring/str->number/number->str/bytes->str over the byte prims.")
  (doc (provide x/boot/module)
    "Boot: include-once/import/provide and the include-list registry.")
  (doc (provide x/type/struct)
    (note "The reflection helpers are %-private here and filed under catalog ns `type`; the API is the Type class (x/type/type).")
    "Type system mechanism: struct navigation and handler-stack wiring, registered in the catalog.")
  (doc (provide x/core
    null? if let do begin not atom? list number->str str->number
    str=? str-ref str-length substring
    newline include-once require-once provide import import-path!
    peek-char current-line quasi repl quit doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
