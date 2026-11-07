; Test harness: x-core.x + the ISA manifest as data (%isa-catalogue,
; %isa-bare, %isa-values from engine/tools/contract/isa.x -- the committed C-surface
; contract the isa spec ratchets against).
(include "lib/x-core.x")
(include "engine/tools/contract/isa.x")
; x-core compiles (obj ref), null?, and, or and the rest of Compiled's list in
; place, so each of them is a primitive here, and native code the JIT made in
; this process is not the engine's C surface.  The walks see the interpreted
; versions, as the image writer's walk does: here, and again after a state
; image loads, since the loader's recache hook compiles the list anew and this
; hook is added after it.
(import x/tool/compiled)
(def %isa-interpret-all! (fn (_) (Compiled interpret-all!)))
(%isa-interpret-all!)
((prim-ref (lit image) (lit recache-hook!)) %isa-interpret-all!)
; The library's own value aliases of bare primitives, beside the manifest's.
; x/core/fn binds apply over the engine's and keeps the primitive as %apply,
; and boot/operatives.x binds do and begin to %seq, which the isa spec's walk
; of the globals must recognise.  The manifest's %isa-aliases arrives with the
; pinned engine release and no tool in the engine reads it, so an alias the
; library makes is declared here, with the library, and tools/dev/image-write.x
; names the primitive for an image.
(def %isa-aliases
  (pair (lit (%apply apply))
    (pair (lit (do %seq)) (pair (lit (begin %seq)) %isa-aliases))))
