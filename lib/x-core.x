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
; engine.x is the ONE place the library names its engine: it carries both
; contract includes (base-paths for the catalog walk, obj-layout for the header
; offsets) and the engine root the JIT and the pin tool read at runtime.
; tools/check/engine-seam.sh holds it to being the only such place.
(include "lib/x/boot/engine.x")
(include "lib/x/boot/registry.x")
(include "lib/x/boot/operatives.x")
(include "lib/x/boot/data.x")
(include "lib/x/boot/reflect.x")
; printer BEFORE string.x: string.x's callers resolve display/write from it,
; and its own number->str dependency is call-time only.
(include "lib/x/boot/printer.x")
(include "lib/x/boot/string.x")
(include "lib/x/boot/module.x")

; --- ONE-SHOT FROM HERE, and that is what makes x-core re-includable --------
; Everything below is include-ONCE, not include.  During a normal boot nothing
; changes: each file is reached exactly once either way.  What it buys is that
; a SECOND (include "lib/x-core.x") -- on an already-booted tower -- skips them
; all instead of re-running them.
;
; That second include is the first two lines of anyone's personality
; extraction, and it used to SIGSEGV with nothing on stdout or stderr.  Making
; every module idempotent would be 39 separate fixes (measured: re-including
; lib/x/core/arithmetic.x alone kills the process); making the ENTRY skip work
; it has already done is one.
;
; The forms above this line stay plain `include`: include-once is defined in
; boot/module.x, so it does not exist yet -- and those eight re-load safely on
; their own, which is why they can.


(def x-lib-version "0.12.0")

; Pre-register all boot module NAMES so import calls are no-ops.
; INVARIANT (machine-checked by make check-boot-order): every lib module
; this file loads with raw `include` -- which does NOT register -- must
; appear here, or a later import of it silently reloads the file mid-boot.
; The boot files above (loaded before the module system existed) are listed
; too, so the invariant holds uniformly.  Names, not paths: identity must
; be root-independent.  (lit ...) because the '
; reader sugar is not loaded yet at this point in boot.
(%set-first! %module-loaded-cell
  (pair (lit x-core)
  (pair (lit x/boot/engine)
  (pair (lit x/boot/registry)
  (pair (lit x/boot/operatives)
  (pair (lit x/boot/data)
  (pair (lit x/boot/reflect)
  (pair (lit x/boot/printer)
  (pair (lit x/boot/string)
  (pair (lit x/boot/module)
  (pair (lit x/core/predicates)
  (pair (lit x/core/control)
  (pair (lit x/sys/gc)
  (pair (lit x/doc/doc)
  (pair (lit x/doc/doc-prims)
  (pair (lit x/type/struct)
  (pair (lit x/type/type)
  (pair (lit x/type/obj)
  (pair (lit x/type/buf)
  (pair (lit x/type/ptr)
  (pair (lit x/type/io)
  (pair (lit x/type/convert)
  (pair (lit x/type/block)
  (pair (lit x/core/boolean)
  (pair (lit x/core/fn)
  (pair (lit x/core/logic)
  (pair (lit x/core/list)
  (pair (lit x/core/math)
  (pair (lit x/core/syntax)
  (pair (lit x/core/alist)
  (pair (lit x/type/assoc)
  (pair (lit x/core/arithmetic)
  (pair (lit x/reader/intrinsics)
  (pair (lit x/sys/posix)
  (pair (lit x/type/char)
  (pair (lit x/type/str-utf8)
  (pair (lit x/type/char-io)
  (pair (lit x/type/vector)
  (pair (lit x/type/promise)
  (pair (lit x/type/class)
  (pair (lit x/type/record)
  (pair (lit x/protocol/seq)
  (pair (lit x/protocol/str/str8)
  (pair (lit x/protocol/str/utf8)
  (pair (lit x/type/str)
  (pair (lit x/type/iter)
  (pair (lit x/type/base)
  (pair (lit x/type/list)
  (pair (lit x/type/gen)
  (pair (lit x/reader/analyser)
  (pair (lit x/core/quasi)
  (pair (lit x/reader/quasi-reader)
  (pair (lit x/reader/lit-reader)
  (pair (lit x/repl/loop)
  (pair (lit x/type/bool)
  (pair (lit x/core/op-guard)
  (pair (lit x/type/err)
  (pair (lit x/repl/ansi)
  (pair (lit x/repl/banner)
    (first %module-loaded-cell))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))

; --- Standard modules ---
(include-once "lib/x/core/predicates.x")
(include-once "lib/x/core/control.x")

; Type system internals (before doc, cannot use provide)
(include-once "lib/x/type/struct.x")

; Documentation system
(include-once "lib/x/doc/doc.x")
(include-once "lib/x/doc/doc-prims.x")

; Boolean operatives
(include-once "lib/x/core/boolean.x")

; Core library
(include-once "lib/x/core/logic.x")
(include-once "lib/x/core/list.x")
(include-once "lib/x/core/syntax.x")

; Variadic arithmetic
(include-once "lib/x/core/arithmetic.x")

; Tokenizer helpers
(include-once "lib/x/reader/intrinsics.x")

; Type extensions
(include-once "lib/x/core/alist.x")
; import (not include): registers the NAME so str-utf8.x's and the StrUtf8
; protocol class's (import x/codec/utf8) become no-ops instead of reloading it.
(import x/codec/utf8)
; Low-level UTF-8 code-point layer for the STRING type: the list<->str
; transforms (needed by char-io / number->str / convert) plus the bare (s i)
; -> code-point handler. Safe here -- str-ref/str-length/substring stay pinned
; to the byte primitives, and every reader/tokenizer/loader that needs bytes
; uses them (not the ambient (s i) call).
(include-once "lib/x/type/str-utf8.x")
; UTF-8-aware CHARACTER write/display handlers (shadow the C byte fallback)
(include-once "lib/x/type/char-io.x")
; ERR write/display: the wording of an engine-raised error, which the
; engine deliberately leaves unspelled.  Beside char-io for the same
; reason -- both fill IO stacks the C layer boots empty -- and EARLY,
; since until it loads an engine error renders as #<obj:ERR>.
(include-once "lib/x/type/err-io.x")
(include-once "lib/x/type/class.x")
; Records: def-record, lightweight named-field data types over def-class.
(include-once "lib/x/type/record.x")
; Convert: the conversion dispatcher (registered in the catalog as
; (convert . to)) + the Convert class with the no-match policy member.
; Relocated past object.x from the early type-internals block -- it needs
; def-class + doc, and every caller (tower, regex, posix, hash, tools)
; loads later still.
(include-once "lib/x/type/convert.x")
; Block-form methods: the (names ...) body ... call shape. Machinery only --
; each class wires its own selectors -- so it loads before the collections do.
(include-once "lib/x/type/block.x")
; Type: the type-system reflection API (the Type class). The mechanism stays
; in sys/type.x (pre-object, %-private, filed under catalog ns `type`);
; this class presents it and carries the docs.
(include-once "lib/x/type/type.x")
; Obj: the raw object layer (slots, metadata, FFI handles) as the Obj class.
; ns `obj` is de-registered; boot/data.x's pair mutators fetch the prims.
(include-once "lib/x/type/obj.x")
; Buf + Tok: the tokenizer buffer / token-stream API. ns buf/tok are
; de-registered; reader-hot modules fetch-and-cache the prims.
(include-once "lib/x/type/buf.x")
; Ptr + Ffi: the raw-pointer / foreign-function surface. ns ptr/ffi are
; de-registered; low-level/hot callers fetch-and-cache the prims.
(include-once "lib/x/type/ptr.x")
; Io: input/output surface (the Io class). ns io is de-registered except
; write/display (kept bare via the keep-list); the rest fetch-and-cache.
(include-once "lib/x/type/io.x")
; Fn: function combinators (the Fn class). Moved here from the early core block
; -- it needs def-class, and nothing loaded before object.x references it.
(include-once "lib/x/core/fn.x")
; Num: integer math utilities + number predicates (the Num class). Relocated
; past object.x -- nothing loaded before the object system calls these.
(include-once "lib/x/core/math.x")
; Promise: the delay form + the Promise class. Relocated past object.x --
; nothing loaded before the object system uses promises.
(include-once "lib/x/type/promise.x")
; Assoc: the association-list API (the Assoc class). core/alist.x keeps the
; bootstrap five the object system runs on; this class delegates to them.
(include-once "lib/x/type/assoc.x")
; Heap: GC control (the Heap class; methods fetch the C prims from the
; catalog). Relocated from the early block -- the heap-* bare C names are
; bound by registration regardless of where this module loads.
(include-once "lib/x/sys/gc.x")
; Sys: POSIX wrappers (the Sys class). Relocated -- every caller (the REPL's
; ctrl-c fd recovery, ansi, logo, tools) loads after the object system.
(include-once "lib/x/sys/posix.x")
; Vector: #() type machinery + the Vector class. Needs def-class; relocated past
; object.x from the early block -- nothing before it uses vectors or #() literals.
(include-once "lib/x/type/vector.x")
; Char: classification / case / comparison (the Char class). Needs def-class; the
; pre-object string layer uses char->integer, not these, so it relocated here.
(include-once "lib/x/type/char.x")
; String library: the protocol classes (Str8/StrUtf8) + the Str entry point.
; Loaded AFTER the object system they are built on. (The low-level code-point
; layer in type/str-utf8.x already loaded earlier, before objects, for boot
; code that needs the list<->string conversions.)
(include-once "lib/x/protocol/seq.x")
(include-once "lib/x/protocol/str/str8.x")
(include-once "lib/x/protocol/str/utf8.x")
(include-once "lib/x/type/str.x")
; Iterator protocol: defines the Iter class + wires the iter slot on the
; sequence types (registered above) + consumers.
(include-once "lib/x/type/iter.x")
; Base: execution-context objects via the Base class.
(include-once "lib/x/type/base.x")
; List: list/sequence operations as the List class (core/list.x holds the
; low-level impl + %-helpers; functions migrate onto this class over time).
(include-once "lib/x/type/list.x")
; Gen: lazy generators (unfold-based). Needs object/list/vector, all above.
(include-once "lib/x/type/gen.x")
(include-once "lib/x/reader/analyser.x")

; Quasi-quoting
(include-once "lib/x/core/quasi.x")

; Quasi-quote reader syntax (backtick, comma, comma-at)
(include-once "lib/x/reader/quasi-reader.x")

; Quote reader syntax (apostrophe expr to lit expr)
(include-once "lib/x/reader/lit-reader.x")

; REPL
(include-once "lib/x/repl/loop.x")

; Structured errors (#20): the Err class + errno translation.  Loaded
; after lit-reader (the file speaks 'x) and after platform/syscall's
; transitive boot load (the errno table picks its OS column via
; os-darwin? at load).  Raise sites throughout lib bind Err at CALL
; time, so every post-boot error can be structured regardless of the
; raising module's own boot position.
(include-once "lib/x/type/err.x")

; Non-numeric types refuse arithmetic (#52): error-raising op handlers
; registered on string/symbol/char/list/pair/vector, so op_try routes
; (+ 1 "abc") to err:type instead of the int fallthrough's pointer math.
; After err.x (Err raise) and vector.x (the #() handle).
(include-once "lib/x/core/op-guard.x")

; BOOL claims the #t/#f singletons (#101): an x-defined type over the
; C statics via (obj retag!), closing the #52 boolean residual -- and
; (Type of #t) finally answers. After op-guard (reuses its refusal
; machinery).
(include-once "lib/x/type/bool.x")

; ANSI colour: syntax-highlighted REPL output + colourised help.  Loaded
; after repl.x (it wraps %repl-print) and doc.x (it sets the %c-* help
; colours).  All colours are empty no-ops unless stdout is a TTY and
; NO_COLOR/TERM=dumb/--no-color do not disable them.
(include-once "lib/x/repl/ansi.x")

; Banner
(include-once "lib/x/repl/banner.x")

; Install the SIGINT handler so ctrl-c breaks loops.  On builds without
; signal support these primitives are absent; fall back to inert no-ops so
; the REPL still loads (%sigint-flag becomes an unused settable cell).
(guard (_
    (def sigint-install (fn () ()))
    (def sigint-restore (fn () ()))
    (def %sigint-flag (list 0)))
  (sigint-install))
; THE HANDLER IS THIS PROCESS'S, so it is installed again after a state image
; loads.  What the image carries is the heap the install left behind -- the
; flag cell the evaluator's poll reads -- and not the OS disposition, which
; belongs to the process that called sigaction and to no other.  Without this
; every boot from an image ran with SIGINT at its default: ctrl-c killed the
; session outright instead of raising STOP, in every lang and every dialect.
; A build without signal support installed the no-op above and re-installs it.
(set! %image-recache-hooks (pair (fn (_) (sigint-install)) %image-recache-hooks))

; --- Provide ---
; Retroactive provides for the boot layer: those files load BEFORE the
; module system exists, so they cannot call provide themselves; registering
; them here makes them visible to (modules) and module-level (help).
(doc (provide x/boot/engine)
  "Boot: the engine seam -- the one place the library names its engine, carrying both contract includes and the engine root.")
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
  "Core language: operatives, string primitives, GC, modules.")
