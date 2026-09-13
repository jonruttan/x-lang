; tools/contract/features.x -- the closed vocabulary of the engine contract.
;
; x-lang is implementation-agnostic: x-engine-c is one engine, x-engine-rust may
; be another.  An engine declares what it offers (its x-engine.xon); x-lang
; declares what it needs (tools/contract/requires.x); a resolver pairs them.
; This file is the vocabulary both sides quote from, and the language owns it:
; an engine that defined the terms would be grading its own exam.
;
; Three row kinds, three compare operators, which must not be collapsed:
;
;   capability  a group of instructions is reachable.  Set membership; compared
;               by superset, so a richer engine is never refused.
;   guarantee   a behaviour the engine promises, usually by not doing
;               something.  Compared by must-hold.  Invisible in isa.x, since
;               no primitive names them, and the library's correctness rests on
;               them.
;   parameter   a value the engine reports (word size, byte order, os, arch).
;               Never a requirement: `word-size = 8` in a requires list would
;               lock out the 32-bit Pi, a supported target.  Per-module needs
;               are recorded as constraint rows in
;               tools/contract/constraints.x.
;
; A capability row means the catalog coordinates in that group resolve:
; (prim-ref 'ns 'method) finds something callable, or the bare name is bound.
; It does not mean "implemented in C".  lib/x/boot/reflect.x replaces C prims
; with x-level ones filed under the same catalog names, and isa.x's surface is
; the reduced set that survives that.  An engine may satisfy a coordinate
; natively or in x; the contract is the coordinate, not the language it is
; written in.  That is why `isa/hot` is a capability like any other while
; being, by its own definition, derivable.
;
; Groups partition the ISA, and a tag is not always a group.  Most groups are
; exactly one isa.x tag; the `ffi` tag is not.  It carries eleven rows that
; split into three unrelated capabilities, and treating it as one group makes
; dlopen mandatory for every engine, a sandboxed one included.  lib/x/boot
; reaches int/->ptr, obj/->ptr, ptr/->int, ptr/->obj, str/->ptr, ptr/ref-word
; and ptr/set-word!, and reaches dlopen/dlsym/ffi-call zero times: boot needs
; the casts, not the door.  So the split below is by explicit row membership,
; and tools/check/engine-contract.sh asserts the partition is total and
; disjoint over isa.x -- every row lands in exactly one group, so a new C row
; cannot appear without landing somewhere on purpose.
;
; (isa.x's header legend also lists `registry`, which tags zero rows -- stale
; legend text in the engine's manifest, not a capability; no row here.)
;
; Format (rigid, one entry per line -- the awk parses the same bytes):
;   (atom source)         source = the isa.x tag that proves it, a build flag,
;                         `rows` when membership is listed explicitly below, or
;                         `-` when proven some other way (named in the comment)
;   (group-rows atom ns/method ...)   explicit membership, for split tags

; --- CAPABILITIES ------------------------------------------------------------
; Every group below is genuinely reached by lib/ or apps/ -- verified by joining
; the catalog against every (prim-ref ...) site in the tree.  None is speculative.
(def %feature-capabilities (lit (
  (isa/spine    spine)    ; the evaluator and binder: eval, apply, fn/op, def, call/cc
  (isa/alloc    alloc)    ; heap construction: pair, atoms, instances
  (isa/raw-op   raw-op)   ; machine ALU/compare/cast: int arithmetic, eq?, char->int
  (isa/raw-mem  raw-mem)  ; unchecked memory/byte access: ptr ref/set!/ref-word/
                          ;   set-word!, str byte-sub -- the LOAD/STORE half of
                          ;   reflection (the cast half is reflect/ptr-casts)
  (isa/types    types)    ; the C type-object registry protocol: type-of, iter
  (isa/tok      tok)      ; the tokenizer inner loop -- reader macros, dialects
  (isa/io       io)       ; the process I/O boundary: read, write, display
  (isa/gc       gc)       ; heap management: collect, hooks, limits    [X_HEAP]
  (isa/sys      sys)      ; OS facilities: clock, signals   [X_SYS_CLOCK, X_SIGNAL]
  (isa/hot      hot)      ; DERIVABLE in x, kept native on a measured exception.
                          ;   A capability like any other (the coordinate must
                          ;   resolve) but the ONE group an engine may always
                          ;   implement in x -- requires.x must never demand it
                          ;   be a primitive.
  ; --- the three-way split of tag `ffi` (see the header) ---
  (reflect/ptr-casts rows) ; object<->pointer<->int materialization.  MANDATORY
                           ;   under decision L1: reflect.x reads header words
                           ;   through these, and boot cannot start without them.
  (isa/ffi-call      rows) ; the FOREIGN DOOR -- dlopen/dlsym and calling through
                           ;   a pointer.  Genuinely optional; a sandboxed or
                           ;   wasm engine drops it and still boots x-core.
  (isa/syscall       rows) ; the raw kernel door                     [X_SYSCALL]
  ; --- capabilities that are BUILD FLAGS, not tags ---
  ; Absent from isa.x because the manifest describes the default build's surface,
  ; not the switches behind it.
  (io/include    X_INCLUDE) ; the `include` primitive.  Repo-mode boot CANNOT
                            ;   start without it: x.sh cats an entry whose first
                            ;   act is to include the boot closure.
  (instr/cov     X_COV)     ; coverage marking -- tools/dev/cov.x, x-bin-cov
  (instr/profile X_PROFILE) ; eval counters -- lib/x/tool/profile.x
  ; --- the native-extension lanes -----------------------------------------
  ; Neither is a tag: both are things an engine SHIPS or EXPORTS, proven the
  ; way reflect/layout-data is.  They were undeclared assumptions until a
  ; second engine met them: x-base.x died on `cc failed with status 160`
  ; because nothing said an engine can host a compiled prim, and the jit/asm
  ; spec files reported failures against an engine that never claimed the
  ; lane.  A capability turns those from failures into NOT APPLICABLE.
  (native/cc     -)         ; ships its C headers beside the binary
                            ;   (include/ and ext/x-expr/include/), so
                            ;   x/tool/compile.x can build an object against
                            ;   the ENGINE'S OWN layout and dlopen it.  The
                            ;   compiled numeric tower rides this; an engine
                            ;   without it keeps the interpreted analysers
                            ;   (boot/tower-compiled.x falls back on
                            ;   %compile-hosted?, which probes exactly these
                            ;   two directories).
  (native/jit    -)         ; hosts the in-process assembler lane: EXPORTS the
                            ;   jit_* runtime helpers from its running binary
                            ;   (dlopen self resolves jit_buffer_len et al.)
                            ;   and permits executing assembled pages.
                            ;   Consumer: x/tool/asm-compile.x; spec files
                            ;   carrying `# @requires native/jit`.
  (tok/variant      -)         ; the tokenizer's VARIANT CHANNEL: an analyser state
                            ;   declares what it accepted (x-token.c hangs a
                            ;   variant cell off the score; jit_score_variant is the
                            ;   compiled states' door) and the type's reader
                            ;   receives it as its second argument, nil when
                            ;   no state declared one.  Consumer:
                            ;   x/reader/intrinsics.x %score-variant! and
                            ;   %read-variant, x/tool/asm-compile.x; spec files
                            ;   carrying `# @requires tok/variant`.
  ; --- reflection support that is not a row at all ---
  (reflect/layout-data -)   ; ships obj-layout.x + base-paths.x, the two files
                            ;   lib/x/boot/engine.x includes before data.x runs.
                            ;   NOT base-layout.x: that is the C engine's own
                            ;   generator input (gen-base-layout.awk turns it into
                            ;   C accessors) and nothing in lib/ reads it.  This
                            ;   row named three files and the wrong includer until
                            ;   a second engine was asked to satisfy it and would
                            ;   have had to emit C for a compiler it does not use.
  (reflect/word-probe  -)   ; int<->ptr round-trip faithful enough to size a word
                            ;   (lib/x/boot/data.x probes it at boot)
  ; --- the invocation protocol (contract layer E) ---
  ; What the engine owes x.sh, checked against src/x-cli.c.
  (invoke/pipe-stdin   -)   ; the program arrives on stdin and is read-eval'd
  (invoke/argv         -)   ; every argv element is bound as the `args` list.
                            ;   The engine parses NOTHING: it does not know what
                            ;   --batch or --quiet mean.
  (err/stderr-prefix   -)   ; diagnostics go to STDERR, prefixed `*** ERROR: `.
                            ;   Verified by running one, not by reading: the C
                            ;   binds args and hands straight to the read-eval
                            ;   loop, and the prefix comes from x_error.

  (meta/identity rows)      ; THE ENGINE SAYS WHICH ENGINE IT IS, at runtime:
                            ;   x-release (the build's release) and x-version
                            ;   (the implementation's own version).  Required by
                            ;   `core`, because with two implementations in the
                            ;   world "which engine is this?" stops being
                            ;   rhetorical: x.sh prints both in -V, and the pin
                            ;   records the engine's release so a project can be
                            ;   paired with the engine it was verified against.
                            ;   A declaration file answers the same question, but
                            ;   only about the tree it sits in -- these answer for
                            ;   the PROCESS, which is what a bug report needs.
  (meta/platform rows)      ; x-machine: the build triple as a bound value.  NOT
                            ;   required and not in any profile -- the declared
                            ;   (param os/arch/machine) rows are the door now,
                            ;   and this is the fallback for an engine that ships
                            ;   no build params.  lib/x/platform/syscall.x reads
                            ;   the params first and parses this only if absent.
)))

; Explicit membership for the split tag.  Every ffi-tagged isa.x row appears
; exactly once below; the gate checks that against isa.x directly, so a new ffi
; row must be classified in the same commit that adds it.
(def %feature-group-rows (lit (
  (reflect/ptr-casts int/->ptr obj/->ptr ptr/->int ptr/->obj ptr/->str str/->ptr)
  (isa/ffi-call      ffi/call ffi/dlopen ffi/dlsym ptr/call)
  (isa/syscall       syscall)
  ; The value rows.  isa.x's %isa-values carries no tag column, so each one is
  ; classified here or the partition fails.  Unclassified, they are nameable by
  ; no atom, and x.sh can depend on a value no engine is obliged to have.
  (meta/identity     x-release x-version)
  (meta/platform     x-machine)
  (invoke/argv       args)          ; the argv list this group is already about
  (isa/sys           %sigint-flag)  ; the flag the signal door sets
  (isa/tok           %token-eof)    ; the reader's end sentinel
  (isa/spine         #t #f)         ; the booleans the evaluator itself binds
)))

; Not capabilities.  `--batch` is interpreted by lib/x/repl/banner.x and
; lib/x/tool/contract.x, and the fd-3 stdin reclaim is lib/x/repl/loop.x
; calling (Sys dup2 3 0).  Both are conventions between the wrapper and the
; library; an engine that binds argv and offers the syscall door supports them
; without knowing they exist.  Listed as engine capabilities, they would make a
; second engine implement a protocol it has no part in.

; --- GUARANTEES --------------------------------------------------------------
; Behavioural promises.  These CANNOT be derived from isa.x -- they are what the
; engine does not do -- so each row cites the code that depends on it.  An engine
; that satisfies every capability and reports compatible parameters can still
; break every one of these, silently.  That is what the compliance test is for.
(def %feature-guarantees (lit (
  ; Six sites hold raw pointers as integers across allocating expressions on
  ; exactly this grounds: reflect.x:11-12 and :246, boot/string.x:38 and :53,
  ; protocol/str/str8.x:174, reader/lit-reader.x:76.  An engine with automatic,
  ; incremental or moving collection corrupts all six without a word.
  (gc/explicit-only -)      ; allocation NEVER collects; only an explicit call does
  (gc/non-moving -)         ; a live object's address is stable for its lifetime
  ; SEMANTIC, not a performance note: the project's own rule is that a tail `def`
  ; binds globally BECAUSE of TCO, and 10+ library files are written to it.  A
  ; non-TCO engine does not run slower, it overflows the stack in ordinary code.
  (eval/tco -)              ; proper tail calls, unbounded depth
  ; x-lib's ruled string semantics: a str value IS a C string, and bytes past the
  ; NUL are unobservable.  Ruled three times; the codecs read to it.
  (str/nul-terminated -)
  ; ext/x-expr/include/x.h asserts sizeof(x_int_t) == sizeof(void *) at COMPILE
  ; time.  Fixnum width and pointer width therefore cannot diverge, which is what
  ; lets one parameter (word-size) cover both and what makes data.x's probe --
  ; round-tripping 2^32 through a pointer cast -- a legitimate way to size a word.
  (int/ptr-same-width -)
  ; The language words errors; the engine does not.  An engine that flattens
  ; its message and the thing it is complaining about into one English string
  ; leaves nothing to reword -- the structure is gone before x-lang sees it,
  ; and a type-less value has no dispatch stacks to push a handler onto.  So a
  ; raise delivers the two facts apart, on a registered type, and the base's
  ; `err` row holds a value of that same type (which is how x/type/err-io.x
  ; finds it).  Identity is not required: the reference engine reuses one
  ; instance so a raise allocates nothing, but allocating per raise conforms
  ; equally.
  (err/typed-raise -)
)))

; There is no tok/callback-no-alloc row.  The live constraint is that ops are
; banned inside x_token_read (docs/syntax.md), and that is an obligation the
; engine imposes on callback authors rather than a promise it makes to callers,
; so it is not a guarantee.  It is documented in docs/engine-contract.md, where
; an implementer meets it.  A guarantee that does not describe the engine
; cannot be falsified, and compliance would report it as a claim awaiting an
; experiment indefinitely.

; --- parameters ---------------------------------------------------------------
; Values an engine reports.  Listed here so the vocabulary is closed (a requires
; row naming any of these is refused by the gate); the per-module needs live in
; tools/contract/constraints.x, which is where a value can legitimately bind.
;
; The values themselves are part of the vocabulary.  Held only in one engine's
; build script, they would be an engine choosing the terms it is judged by, and
; a second implementation would have to reverse-engineer them: Rust's own names
; for the same machines are `macos` and `aarch64`, and an engine stamping those
; reports true facts in a vocabulary nothing else can read, so every comparison
; against a literal fails silently.
;
; Format: (name value ...).  A row with values is closed and the gate checks
; against it; a row with none accepts anything.  `unknown` is always legal and
; means the build could not say -- consumers skip it rather than guessing.
;
; A closed value set is NOT a requirement.  Naming 4 and 8 says which widths this
; vocabulary can spell, not that an engine must have one of them: a requires row
; naming a parameter is still refused, and only constraints.x may bind a value.
; Adding an OS or an architecture is a deliberate edit here, which is the point --
; the alternative is each engine inventing its own spelling in silence.
(def %feature-parameters (lit (
  (word-size 4 8)          ; bytes per machine word AND per fixnum (int/ptr-same-width)
  (int-width)              ; DERIVED: word-size * 8; declared for readers, never required
  (endian little big)      ; byte order of a widening (ptr ref) read
  (os darwin linux bsd)
  (arch arm64 x86-64 i386)
  (machine)                ; the full build triple, as DATA -- replaces x-machine sniffing
  (release)                ; the release THIS BINARY was built as.  Free-form, like
                           ;   machine: a project spells its releases however it
                           ;   likes and nothing may parse the string -- the pin
                           ;   compares releases for EQUALITY and never reads them.
                           ;   Declared beside the binary rather than asked of it,
                           ;   because the wrapper needs it BEFORE deciding whether
                           ;   this engine may boot a pinned amalgam at all.
)))

; --- PROFILES ----------------------------------------------------------------
; Bundles, so a partial engine has a TARGET instead of an all-or-nothing wall.
; A profile INCLUDES the one before it (the gate checks the chain is closed).
;
; Four tiers rather than six.  `reader` and `io` do not separate from core:
; lib/x/boot reaches the `io` tag (the printer is x-level but must emit bytes)
; and lib/x/type reaches `tok`.  `posix` does not separate from the foreign
; door either -- lib/x/sys/posix.x, the foundation of that tier, fetches
; dlopen, dlsym and ptr/call alongside syscall.  The chain below is what the
; library is, rather than what a tidier diagram would show.
;
; The interesting boundary is therefore core|gc: an engine with NO foreign door,
; NO syscalls and NO collector still boots x-core.  That is the sandbox dialect's
; shape (docs/sandboxing-tutorial.md), and it is the first target worth aiming a
; second engine at.
(def %feature-profiles (lit (
  (core  isa/spine isa/alloc isa/raw-op isa/raw-mem isa/types isa/tok isa/io
         isa/hot reflect/ptr-casts reflect/layout-data reflect/word-probe
         io/include invoke/pipe-stdin invoke/argv err/stderr-prefix
         meta/identity)
  (gc    core isa/gc)
  (posix gc isa/sys isa/syscall isa/ffi-call)
  (full  posix instr/cov instr/profile)
)))
