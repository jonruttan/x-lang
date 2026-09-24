; Test harness: x-core.x + the ISA manifest as data (%isa-catalog,
; %isa-bare, %isa-values from engine/tools/contract/isa.x -- the committed C-surface
; contract the isa spec ratchets against).
(include "lib/x-core.x")
(include "engine/tools/contract/isa.x")
; The library's own value aliases of bare primitives, beside the manifest's.
; x/core/fn binds apply over the engine's and keeps the primitive as %apply,
; which the isa spec's walk of the globals must recognise.  The manifest's
; %isa-aliases arrives with the pinned engine release and no tool in the
; engine reads it, so an alias the library makes is declared here, with the
; library, and tools/dev/image-write.x names the primitive for an image.
(def %isa-aliases (pair (lit (%apply apply)) %isa-aliases))
