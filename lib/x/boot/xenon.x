; boot/xenon.x -- the xenon dialect body: everything but the launcher
;
; Included by the lib/xe.x entry (#95).  The (repl) launcher cannot ride
; a nested (include ...): the REPL reads the CURRENT input source, so
; inside an include frame it meets the file's EOF and exits instead of
; reading the session's stdin.  The entry therefore keeps the launcher at
; stream top level and includes this body.  (Same extraction idiom as
; boot/tower-compiled.x.)

; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")

; Load the x/xe module (parsed through all compiled analysers).  Pre-registered
; so a later (import x/xe) is a no-op.  This body registers itself too: the
; entry and shim load it via raw `include`, which does not register
; (pre-seed invariant, check-boot-order).
(%set-first! %module-loaded-cell
  (pair (lit x/boot/xenon)
  (pair (lit x/xe) (first %module-loaded-cell))))
(include "lib/x/xe.x")

; ANSI colour already loaded by x-core.x -- a second include here re-captured
; the wrapped %repl-print as %saved-repl-print, making (Ansi disable-repl)
; "restore" the highlighted printer.

(set! %lang-name "xenon")
(set! %lang-version x-lib-version)

; --- Reclaim the tower's load burst -----------------------------------------
;
; ONE COLLECT, WORTH 99.7% OF THE HEAP.  Measured: a xenon boot leaves
; 46,630,058 live objects and one collect takes it to 123,597.  The tower does
; not RETAIN that -- decimal, the largest stage, keeps ~18.9K objects and
; spends ~32M reaching them.  The rest is load garbage: forms read, closures
; built and dropped, the compiler's ASTs, every intermediate of eight analyser
; compilations.  There is no auto-GC, so without this it stays live for the
; life of the process.
;
; IT IS NOT TIDINESS.  The engine's ceiling -- alloc-limit!, what
; tests/spec-runner.sh arms -- counts LIVE objects, not cumulative allocations
; (verified: ~26M of allocation survives a 20M ceiling when collects run
; between the bursts).  So every process booting the tower used to start 46M
; into its budget and carry it for life, which is how a bundle spec batch came
; to sit at 83-97% of a 300M ceiling.
;
; NOT HERE EITHER.  This body is reached through `include`, and the include
; wrapper (boot/module.x) is a procedure mid-call while it loads: its formals
; and its restore compound are the importer's state, and the engine parks
; them where the collector cannot see them for the length of the load
; (x_eval_load, x-engine-c fix/load-roots).  A collect on this line swept
; them, and the wrapper resumed into freed memory -- a SIGSEGV in symbol
; lookup wherever the allocator reuses a freed cell at once (glibc; x86-64
; Linux CI), luck everywhere else.  The safe moment is one line later than
; this file can reach: the ENTRY's top level, after `include` returns, where
; nothing is in flight.  The collect lives in lib/xe.x; the measurements
; above are why it exists at all.
