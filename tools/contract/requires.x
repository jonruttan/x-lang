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
; hand-written row like those constraints.x holds; until then this file
; under-reports by exactly those two.
;
; Only above-core capabilities get rows.  Every file needs the `core` group, so
; the useful question is which files need more, those being the ones a minimal
; engine cannot load.  Of ~150 files in lib/ and apps/, the ones below are the
; entire above-core surface; everything else runs with no foreign door, no
; syscalls and no collector, which is the sandbox dialect.
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
  (needs "lib/x/boot/module.x" isa/gc isa/sys isa/syscall)
  (needs "lib/x/boot/tower-compiled.x" isa/ffi-call)
  ; The doors module fetches the foreign door (dlopen, dlsym, ptr call) and
  ; the collector once, for every file that imports them: codec/bytes.x,
  ; codec/zlib.x, num/float.x, sys/socket.x, the asm and compile tools, and
  ; repl/loop.x and repl/line.x for the collector, name the primitive nowhere
  ; and have no row of their own.
  (needs "lib/x/core/doors.x" isa/ffi-call isa/gc)
  (needs "lib/x/net/http.x" isa/ffi-call)  ; memcpy for its runs
  ; syscall-door makes the call for whoever holds the door; sys/file.x reaches
  ; the kernel through it and names the primitive nowhere.
  (needs "lib/x/platform/syscall.x" isa/syscall)
  ; The line editor's terminal layer: termios through the ffi door
  ; (tcgetattr/tcsetattr/cfmakeraw), and TIOCGWINSZ through the syscall door
  ; -- ioctl is variadic, and a variadic argument does not travel in the
  ; register a fixed one does on Apple arm64, so the ffi door silently
  ; measured every terminal at 80x24.  repl/edit.x, repl/paint.x and
  ; repl/line.x need neither: they are string and list work over what this
  ; file hands them.
  (needs "lib/x/repl/term.x" isa/ffi-call isa/syscall)
  (needs "lib/x/sys/cont.x" isa/gc)
  (needs "lib/x/sys/gc.x" isa/gc)
  (needs "lib/x/sys/host.x" isa/ffi-call)
  (needs "lib/x/sys/posix.x" isa/sys isa/syscall)
  ; posix_openpt and the rest through the ffi door; TIOCSWINSZ and TIOCSCTTY
  ; through the syscall door, for term.x's reason: ioctl is variadic.
  (needs "lib/x/sys/pty.x" isa/ffi-call isa/syscall)
  (needs "lib/x/tool/asm-cache.x" isa/ffi-call)
  ; The image walk collects as it goes, and hands the collector, the mark and
  ; the clear to the image tools.
  (needs "lib/x/tool/image/walk.x" isa/gc)
  ; The linter sweeps between top-level forms and between a class's methods
  ; once the allocated count passes its threshold.
  (needs "lib/x/tool/lint.x" isa/gc)
  (needs "lib/x/tool/profile.x" isa/gc)
  (needs "lib/x/type/err.x" isa/ffi-call)
  (needs "lib/x/type/ptr.x" isa/ffi-call)
  (needs "lib/xe.x" isa/gc)
)))
