; engine.x -- THE ONE PLACE x-lang NAMES ITS ENGINE.
;
; x-lang is implementation-agnostic by design: x-engine-c is one engine, and a
; second implementation should require no edit to the library.  That claim was
; false in three places -- the boot's two contract includes, the JIT's header
; search paths, and the pin tool's fingerprint lookup -- each of which spelled
; `ext/x-engine-c` in its own file.  They are gathered here so the claim has a
; single seam instead of a scatter, and tools/check/engine-seam.sh holds the line.
;
; WHY A LITERAL AND NOT A COMPUTED PATH.  This file loads FIRST, before
; registry.x, so `prim-ref` does not exist yet and neither does any string
; operation: there is nothing available to build a path with.  The includes must
; also stay textually resolvable, because tools/release/amalgamate.sh inlines them
; by matching `(include "<root>/...")` at the start of a line -- a computed form
; would travel into the amalgam UNRESOLVED, and an installed tree has no ext/ to
; find it in later.  That exact bug shipped once during the engine split.
;
; So the indirection is deliberately shallow, and it is now in the FILESYSTEM
; rather than in this file: `engine` is a symlink at the repo root, pointed by
; the Makefile at whatever engine this tree builds against -- the submodule, a
; local checkout named by X_ENGINE_DIR, or (phase 4) an unpacked release.  A
; path can be one thing and mean another, which is the one indirection available
; to a file that must stay textually resolvable.
;
; Choosing an engine is therefore no longer an edit to this file at all.  It was
; four lines here; now it is where the link points.
;
; ORDER: base-paths.x must precede registry.x (the catalog walk reads it), and
; obj-layout.x must precede data.x (its header offsets).  Both are pure `def`
; forms over integers and lists -- no dependencies of their own -- so loading them
; together here, ahead of both consumers, is safe and keeps the seam in one place.

; The engine's root, as DATA, for the consumers that need a path at RUNTIME
; rather than at include time: lib/x/tool/compile.x builds the JIT's -I flags
; from it, and lib/x/tool/pin.x reads the engine's ISA manifest through it.
; Those run long after the library is up, so a value is enough for them; only
; the includes below need a literal.
(def %engine-root "engine")
(def %engine-contract-root "engine/tools/contract")

(include "engine/tools/contract/base-paths.x")
(include "engine/tools/contract/obj-layout.x")
