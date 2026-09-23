; tools/contract/requires.x -- what x-lang needs from an engine.
;
; The counterpart of an engine's x-engine.xon: the engine declares what it
; offers, this file declares what the library needs, and the resolver pairs them
; by SUPERSET (tools/contract/features.x holds the vocabulary both quote).
;
; Derived rather than decided.  Every row below is computed by
; tools/check/engine-contract.x, which tools/check/engine-contract.sh runs: it
; reads lib/ and apps/ as forms, finds every (prim-ref ns method) site and every
; `syscall` call, maps each coordinate to its capability group through the
; reference engine's isa.x, and diffs the result against this file.  A site
; nested inside another call counts; words in a comment or a string do not.  A
; row cannot be added by opinion and cannot go stale: the gate fails both ways.
;
; A capability that is not prim-ref-able cannot be derived, and two are not:
; instr/cov and instr/profile are build flags that change how existing
; primitives behave, so no call site names them and no row below can find them.
; The coverage and profiling tools do need a suitably built engine, and that
; dependency is invisible to this derivation.  Recording it needs a
; hand-written row of the constraints.x kind; until then this file
; under-reports by exactly those two.
;
; Only above-core capabilities get rows.  Every file needs the `core` group, so
; the useful question is which files need more, those being the ones a minimal
; engine cannot load.  Of ~150 files in lib/ and apps/, the ones below are the
; entire above-core surface; everything else runs with no foreign door, no
; syscalls and no collector, which is the sandbox dialect's shape.
;
; The rows over-approximate, deliberately: a row says the file references the
; capability, not that boot needs it.  lib/x/boot/module.x is the example:
; its syscall use is inside `module list-dir`, a cold method that imports
; x/platform/syscall in its own body, so booting never reaches it -- yet the file
; is charged for it here.  Narrowing this needs load-time-vs-call-time analysis
; (tools/check/boot-order.x does something adjacent), and until that exists the
; over-approximation is the safe direction: it can only make an engine look LESS
; capable of loading a file than it is.
;
; Format:
;   (profile NAME)         the profile the complete library needs
;   (needs "PATH" cap...)  a file and the above-core capabilities it references,
;                          in byte order, since the gate compares each row as
;                          written

(def %requires (lit (
  ; The profile the whole library needs.  DERIVED, and it is `posix`, not `full`:
  ; the union of every above-core capability any file reaches is
  ; {isa/ffi-call, isa/gc, isa/sys, isa/syscall}, and `posix` is the smallest
  ; profile containing all four.  `full` adds instr/cov and instr/profile, which
  ; NOTHING in lib/ or apps/ reaches -- they are not prim-ref-able at all, being
  ; build flags that change how existing primitives behave.  Naming `full` here
  ; would have made the default engine fail `provides >= requires`, because
  ; coverage and profiling are VARIANT builds (x-bin-cov, x-bin-profile) and the
  ; default x-bin honestly does not have them.
  (profile posix)
  (needs "lib/rn.x" isa/gc)
  (needs "lib/x-base.x" isa/gc)
  (needs "lib/x-core.x" isa/gc)      ; collects between its own includes (the boot rule)
  (needs "lib/x/boot/module.x" isa/syscall)
  (needs "lib/x/boot/tower-compiled.x" isa/ffi-call)
  (needs "lib/x/codec/zlib.x" isa/ffi-call)
  (needs "lib/x/net/tls.x" isa/ffi-call)
  (needs "lib/x/num/float.x" isa/ffi-call)
  (needs "lib/x/repl/loop.x" isa/gc)
  ; The line editor runs the turn loop itself when it is installed, and
  ; sweeps at the top of each turn as loop.x does, through its own fetch.
  (needs "lib/x/repl/line.x" isa/gc)
  ; The line editor's terminal layer: termios through the ffi door
  ; (tcgetattr/tcsetattr/cfmakeraw), and TIOCGWINSZ through the syscall door
  ; -- ioctl is variadic, and a variadic argument does not travel in the
  ; register a fixed one does on Apple arm64, so the ffi door silently
  ; measured every terminal at 80x24.  repl/edit.x, repl/paint.x and
  ; repl/line.x need neither: they are string and list work over what this
  ; file hands them.
  (needs "lib/x/repl/term.x" isa/ffi-call isa/syscall)
  (needs "lib/x/sys/file.x" isa/syscall)
  (needs "lib/x/sys/gc.x" isa/gc)
  (needs "lib/x/sys/posix.x" isa/ffi-call isa/sys)
  (needs "lib/x/sys/socket.x" isa/ffi-call)
  (needs "lib/x/tool/asm-cache.x" isa/ffi-call)
  (needs "lib/x/tool/asm-compile.x" isa/ffi-call)
  (needs "lib/x/tool/asm.x" isa/ffi-call)
  (needs "lib/x/tool/compile.x" isa/ffi-call)
  ; The pipeline resolves x_fvar_table in the loaded object with its own
  ; dlsym fetch, to patch it after a load.
  (needs "lib/x/tool/compile/pipeline.x" isa/ffi-call)
  (needs "lib/x/tool/profile.x" isa/gc)
  (needs "lib/x/type/err.x" isa/ffi-call)
  (needs "lib/x/type/ptr.x" isa/ffi-call)
  (needs "lib/xe.x" isa/gc)
)))
