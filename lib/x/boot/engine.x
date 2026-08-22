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
; So the indirection is deliberately shallow: one file to edit, not one variable
; to thread.  Pointing x-lang at another engine means changing these four lines.
; Making it a RUNTIME choice needs the engine to arrive as a pinned artifact at a
; known location, which is the arc's phase 4; this file is what that phase will
; rewrite, and gathering it here first is what makes that a one-file change.
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
(def %engine-root "ext/x-engine-c")
(def %engine-contract-root "ext/x-engine-c/tools/contract")

(include "ext/x-engine-c/tools/contract/base-paths.x")
(include "ext/x-engine-c/tools/contract/obj-layout.x")
