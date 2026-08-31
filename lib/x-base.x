; # Computational Expressions in C
;
; ## x-base.x -- x Standard Library (non-interactive)
;
; @description x-base: non-interactive full-stack library with a COMPILED
;   numeric tower (see docs/dialects.md and docs/type-system.md).  The
;   analyser-compilation lives in lib/x/boot/tower-compiled.x, shared with
;   the xenon/radon bodies; this entry is x-core plus that block, without the
;   interactive banner/REPL.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")

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
; HERE, NOT IN boot/tower-compiled.x, though that is where the burst is made:
; that file is importable and gets imported (doctest walks every module), and a
; collect inside an importer's process frees what the importer was holding.
; See the note at the end of that file.  Boot is the safe moment; a dialect
; body is never imported.  Cost ~0.2s of a ~5s boot.
((prim-ref (lit heap) (lit collect)))
