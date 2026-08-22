; tools/contract/requires.x -- what x-lang needs from an engine.
;
; The counterpart of an engine's x-engine.xon: the engine declares what it
; offers, this file declares what the library needs, and the resolver pairs them
; by SUPERSET (tools/contract/features.x holds the vocabulary both quote).
;
; DERIVED, NOT DECIDED.  Every row below is computed by
; tools/check/engine-contract.sh, which joins the engine's isa.x against every
; (prim-ref ns method) site and every bare `syscall` call in lib/ and apps/, maps
; each coordinate to its capability group, and diffs the result against this
; file.  A row cannot be added by opinion and cannot go stale: the gate fails
; both ways.
;
; A CAPABILITY THAT IS NOT prim-ref-ABLE CANNOT BE DERIVED, and two are not:
; instr/cov and instr/profile are build flags that change how existing primitives
; behave, so no call site names them and no row below can find them.  The coverage
; and profiling tools do need a suitably built engine; that dependency is real and
; is invisible to this derivation.  Recording it needs a hand-written row of the
; constraints.x kind, which is the honest shape for a need that leaves no trace in
; the source.  Until then this file under-reports by exactly those two.
;
; ONLY ABOVE-CORE CAPABILITIES GET ROWS.  Every file needs the `core` group; the
; useful question is which files need MORE, because those are the ones a minimal
; engine cannot load.  The answer is smaller than anyone expected: of ~150 files
; in lib/ and apps/, the ones below are the entire above-core surface.  Everything
; else runs with no foreign door, no syscalls and no collector -- which is the
; sandbox dialect's shape and the first target worth aiming a second engine at.
;
; THE ROWS OVER-APPROXIMATE, DELIBERATELY.  A row says the FILE references the
; capability, not that BOOT needs it.  lib/x/boot/module.x is the honest example:
; its syscall use is inside `module list-dir`, a cold method that imports
; x/platform/syscall in its own body, so booting never reaches it -- yet the file
; is charged for it here.  Narrowing this needs load-time-vs-call-time analysis
; (tools/check/boot-order.x does something adjacent), and until that exists the
; over-approximation is the safe direction: it can only make an engine look LESS
; capable of loading a file than it is.
;
; FORMAT (rigid, one entry per line -- the awk parses the same bytes):
;   (profile NAME)         the profile the COMPLETE library needs
;   (needs "PATH" cap...)  a file and the above-core capabilities it references

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
  (needs "apps/logo/dispatch.x" isa/ffi-call)
  (needs "apps/logo/main.x" isa/ffi-call)
  (needs "apps/logo/serve.x" isa/ffi-call)
  (needs "lib/x/boot/module.x" isa/syscall)
  (needs "lib/x/codec/zlib.x" isa/ffi-call)
  (needs "lib/x/net/tls.x" isa/ffi-call)
  (needs "lib/x/num/float.x" isa/ffi-call)
  (needs "lib/x/repl/loop.x" isa/gc)
  (needs "lib/x/rn.x" isa/syscall)
  (needs "lib/x/sys/file.x" isa/syscall)
  (needs "lib/x/sys/gc.x" isa/gc)
  (needs "lib/x/sys/posix.x" isa/ffi-call isa/sys)
  (needs "lib/x/sys/socket.x" isa/ffi-call)
  (needs "lib/x/tool/asm-compile.x" isa/ffi-call)
  (needs "lib/x/tool/asm.x" isa/ffi-call)
  (needs "lib/x/tool/compile.x" isa/ffi-call)
  (needs "lib/x/tool/profile.x" isa/gc)
  (needs "lib/x/type/ptr.x" isa/ffi-call)
)))
