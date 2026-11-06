; obj-compiled.x -- (obj ref) and (obj set!) compiled where they stand
;
; Every vector, record and object field access in the library reads or
; writes one data word through (obj ref) or (obj set!), and both are
; interpreted closures (boot/reflect.x, boot/data.x).  The library binds
; each once, as the doors of x/core/doors and the prim-ref forms beside
; them, so a compiled version bound to a new name would reach no caller.
; Here each is compiled through compile-asm in object mode and installed
; into the closure object itself (Compiled in-place): every holder calls
; the compiled version, and the interpreted one stays on Compiled's list
; for an image write, an engine without a JIT, or a compile that raises.
;
; Data word I of an object is word (%obj-meta-len + I) from its address,
; and I arrives as an integer object whose value is its own first data
; word.  The bodies read and write that word as the interpreted versions
; do, with no check of either operand.

(module x/tool/obj-compiled)
(import x/tool/compile compile-asm)
(import x/tool/compiled)

(def %obj-compiled-ref
  (prim-ref (lit obj) (lit ref)))
(def %obj-compiled-set!
  (prim-ref (lit obj) (lit set!)))

; (o i) -> the word of O that I names, as an address offset in words.
(def %obj-compiled-word
  (list (lit +) (list (lit %mem-ref) (lit i) %obj-meta-len) %obj-meta-len))

(Compiled in-place (lit obj-ref) %obj-compiled-ref
  (fn (_)
    (compile-asm
      (list (lit fn) (lit (_ o i)) (list (lit %mem-ref-at) (lit o) %obj-compiled-word))
      () (lit object))))

(Compiled in-place (lit obj-set!) %obj-compiled-set!
  (fn (_)
    (compile-asm
      (list (lit fn) (lit (_ o i v)) (list (lit %mem-set-at!) (lit o) %obj-compiled-word (lit v)))
      () (lit object))))

(doc (provide x/tool/obj-compiled)
  "Compiles (obj ref) and (obj set!) and installs each into its own closure object, so every holder of either calls the compiled version.")
