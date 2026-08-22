; tools/contract/features.x -- the closed vocabulary of the engine contract.
;
; x-lang is implementation-agnostic: x-engine-c is one engine, x-engine-rust may be
; another.  An engine DECLARES what it offers (its x-engine.xon); x-lang DECLARES
; what it needs (tools/contract/requires.x); a resolver pairs them.  This file is
; the vocabulary both sides quote from -- the language owns it, because an engine
; that defined the terms would be grading its own exam.
;
; THREE ROW KINDS, THREE COMPARE OPERATORS.  Collapsing them is the mistake this
; file exists to prevent:
;
;   CAPABILITY  a group of instructions is reachable.  Set membership; compared by
;               SUPERSET, so a richer engine is never refused.
;   GUARANTEE   a behaviour the engine promises, usually BY NOT DOING SOMETHING.
;               Compared by MUST-HOLD.  Invisible in isa.x -- no primitive names
;               them -- and the library's correctness rests on them anyway.
;   PARAMETER   a value the engine REPORTS (word size, byte order, os, arch).
;               Never a requirement: `word-size = 8` in a requires list would lock
;               out the 32-bit Pi, a supported target.  Per-module needs are
;               recorded as constraint rows in tools/contract/constraints.x.
;
; WHAT A CAPABILITY ROW MEANS, PRECISELY: the catalog COORDINATES in that group
; RESOLVE -- (prim-ref 'ns 'method) finds something callable, or the bare name is
; bound.  It does NOT mean "implemented in C".  lib/x/boot/reflect.x already
; replaces C prims with x-level ones filed under the same catalog names, and
; isa.x's surface is the REDUCED set that survives that.  An engine may satisfy a
; coordinate natively or in x; the contract is the coordinate, not the language it
; is written in.  That is why `isa/hot` is a capability like any other while being,
; by its own definition, derivable.
;
; GROUPS PARTITION THE ISA -- and a TAG IS NOT ALWAYS A GROUP.  Most groups are
; exactly one isa.x tag.  The `ffi` tag is NOT: it carries eleven rows that split
; into three unrelated capabilities, and treating it as one group would have made
; dlopen mandatory for every engine including a sandboxed one.  The evidence is
; direct -- lib/x/boot reaches int/->ptr, obj/->ptr, ptr/->int, ptr/->obj,
; str/->ptr, ptr/ref-word and ptr/set-word!, and reaches dlopen/dlsym/ffi-call
; ZERO times.  Boot needs the CASTS, not the DOOR.  So the split below is by
; explicit row membership, and tools/check/engine-contract.sh asserts the
; partition is TOTAL and DISJOINT over isa.x: every row lands in exactly one
; group, so a new C row cannot appear without landing somewhere on purpose.
;
; (isa.x's header legend also lists `registry`, which tags zero rows -- stale
; legend text in the engine's manifest, not a capability; no row here.)
;
; FORMAT (rigid, one entry per line -- the awk parses the same bytes):
;   (atom source)         source = the isa.x TAG that proves it, a BUILD FLAG,
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
  ; Assumed by x.sh everywhere and written down nowhere until now.
  ; What the ENGINE actually owes, checked against src/x-cli.c rather than
  ; assumed.  The first draft listed two more rows that turned out not to be the
  ; engine's at all -- see the note below.
  (invoke/pipe-stdin   -)   ; the program arrives on stdin and is read-eval'd
  (invoke/argv         -)   ; every argv element is bound as the `args` list.
                            ;   The engine parses NOTHING: it does not know what
                            ;   --batch or --quiet mean.
  (err/stderr-prefix   -)   ; diagnostics go to STDERR, prefixed `*** ERROR: `.
                            ;   Verified by running one, not by reading: the C
                            ;   binds args and hands straight to the read-eval
                            ;   loop, and the prefix comes from x_error.
)))

; Explicit membership for the split tag.  Every ffi-tagged isa.x row appears
; exactly once below; the gate checks that against isa.x directly, so a new ffi
; row must be classified in the same commit that adds it.
(def %feature-group-rows (lit (
  (reflect/ptr-casts int/->ptr obj/->ptr ptr/->int ptr/->obj ptr/->str str/->ptr)
  (isa/ffi-call      ffi/call ffi/dlopen ffi/dlsym ptr/call)
  (isa/syscall       syscall)
)))

; NOT CAPABILITIES, though the first draft of this file listed them as such.
; `--batch` is interpreted by lib/x/repl/banner.x and lib/x/tool/contract.x, and
; the fd-3 stdin reclaim is lib/x/repl/loop.x calling (Sys dup2 3 0).  Both are
; conventions between the WRAPPER and the LIBRARY; an engine that binds argv and
; offers the syscall door supports them without knowing they exist.  Listing them
; as engine capabilities would have made a second engine implement a protocol it
; has no part in.

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
)))

; REMOVED, and worth saying why rather than leaving a hole: tok/callback-no-alloc.
; It was declared as "tokenizer callbacks run without allocating", and it was wrong
; twice over.  Wrong in CONTENT -- lib/x/reader/lit-reader.x records that the
; no-allocation rationale is OBSOLETE ("GC is explicit-only, so re-entering the
; tokenizer from a reader handler is safe"), and docs/syntax.md states the live
; constraint as something else entirely: OPS ARE BANNED INSIDE x_token_read.  And
; wrong in CATEGORY -- that ban is an obligation the engine imposes on callback
; AUTHORS, not a promise the engine makes to callers, so it is not a guarantee at
; all.  It is documented in docs/engine-contract.md where an implementer meets it.
;
; A guarantee that cannot be falsified because it does not describe the engine is
; worse than an untested one: compliance would have reported it as a claim awaiting
; an experiment forever.

; --- PARAMETERS --------------------------------------------------------------
; Values an engine reports.  Listed here so the vocabulary is closed (a requires
; row naming any of these is refused by the gate); the per-module needs live in
; tools/contract/constraints.x, which is where a value can legitimately bind.
;
; THE VALUES ARE PART OF THE VOCABULARY TOO, and they were not written down.
; They existed -- ext/x-engine-c/tools/contract/gen-build-params.sh normalises a
; build triple to darwin/linux/bsd and arm64/x86-64/i386, and
; tests/x/conformance/posix/foreign.spec.md compares %param-os against those very
; spellings -- but they lived inside ONE ENGINE'S build script, which is an
; engine choosing the terms it is judged by.  A second implementation had to
; reverse-engineer them from that script and a spec file: Rust's own names for
; the same machines are `macos` and `aarch64`, and an engine stamping those
; reports true facts in a vocabulary nothing can read, so every comparison
; against a literal fails silently.
;
; FORMAT: (name value ...).  A row with values is CLOSED and the gate checks
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
)))

; --- PROFILES ----------------------------------------------------------------
; Bundles, so a partial engine has a TARGET instead of an all-or-nothing wall.
; A profile INCLUDES the one before it (the gate checks the chain is closed).
;
; FOUR TIERS, NOT SIX.  The first draft had `reader` and `io` as tiers above a
; smaller core; the evidence refused it.  lib/x/boot reaches the `io` tag (the
; printer is x-level but must emit bytes) and lib/x/type reaches `tok`, so
; neither separates from core.  And `posix` cannot separate from the foreign
; door: lib/x/sys/posix.x, the foundation of that tier, fetches dlopen, dlsym
; AND ptr/call alongside syscall.  The chain below is what the library actually
; is, not what a tidy diagram would prefer.
;
; The interesting boundary is therefore core|gc: an engine with NO foreign door,
; NO syscalls and NO collector still boots x-core.  That is the sandbox dialect's
; shape (docs/sandboxing-tutorial.md), and it is the first target worth aiming a
; second engine at.
(def %feature-profiles (lit (
  (core  isa/spine isa/alloc isa/raw-op isa/raw-mem isa/types isa/tok isa/io
         isa/hot reflect/ptr-casts reflect/layout-data reflect/word-probe
         io/include invoke/pipe-stdin invoke/argv err/stderr-prefix)
  (gc    core isa/gc)
  (posix gc isa/sys isa/syscall isa/ffi-call)
  (full  posix instr/cov instr/profile)
)))
