; canvas-jit.x -- the compiled pixel loops behind (Canvas jit!).
;
; Loaded lazily by x/gfx/canvas, never on its import: this module pulls the
; JIT toolchain, and the canvas stays usable and correct on a host with no
; JIT.  It compiles the kernel forms x/gfx/canvas hands it, the same forms
; the pure-x loops are made from, and answers them only after the canvas's
; own check finds every one writes what its pure twin writes.
(module x/gfx/canvas-jit)

(import x/tool/compile compile-asm)

; FORMS: the kernels as (fn ...) forms.  CHECK: (fn (_ engine) -> #t) when
; ENGINE, a list of kernels in FORMS' order, agrees with the pure ones.
; Answers ENGINE, or raises: on a host with no assembler backend, a
; toolchain error, or any disagreement.  The caller guards; a raise means
; "stay pure-x".
(def canvas-jit-make
  (fn (_ forms check)
    (def engine (List map (fn (_ f) (compile-asm f)) forms))
    (Heap collect)
    (unless (check engine)
      (Err raise (lit state) "canvas-jit: the compiled loops disagree with the pure-x loops" ()))
    engine))

; The canvas reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit canvas) (lit jit-make) canvas-jit-make)

(doc (provide x/gfx/canvas-jit canvas-jit-make)
  "The compiled pixel loops (JIT, ARM64 and x86-64 backends) behind (Canvas jit!): copy, fill, blend, stamp, stretch, lerp and light, adopted only after they agree with the pure-x loops."
  (sample "(do (import x/gfx/canvas) (Canvas jit!))" "#t where a JIT backend is, #f elsewhere"))
