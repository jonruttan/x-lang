; int-form-jit.x -- integer (fn ...) forms compiled, and adopted only when
; they agree with their pure-x twins.
;
; Loaded lazily by the libraries whose loops are int forms (x/gfx/canvas,
; x/audio/mixer), never on their import: this module pulls the JIT
; toolchain, and each library stays usable and correct on a host with no
; JIT.  It compiles the forms a library hands it, the same forms its pure-x
; loops are made from (x/tool/int-form), and answers them only after the
; library's own check finds every one writes what its pure twin writes.
(module x/tool/int-form-jit)

(import x/tool/compile compile-asm)

; FORMS: the kernels as (fn ...) forms.  CHECK: (fn (_ engine) -> #t) when
; ENGINE, a list of kernels in FORMS' order, agrees with the pure ones.
; Answers ENGINE, or raises: on a host with no assembler backend, a
; toolchain error, or any disagreement.  The caller guards; a raise means
; "stay pure-x".
(def int-form-jit-make
  (fn (_ forms check)
    (def engine (List map (fn (_ f) (compile-asm f)) forms))
    (Heap collect)
    (unless (check engine)
      (Err raise (lit state) "int-form-jit: the compiled loops disagree with the pure-x loops" ()))
    engine))

; A library reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, where an import is one the
; linter cannot see.
(prim-reg! (lit int-form) (lit jit-make) int-form-jit-make)

(doc (provide x/tool/int-form-jit int-form-jit-make)
  "Integer loops compiled by the JIT (ARM64 and x86-64 backends) from their int forms, adopted only after a library's check finds they agree with the pure-x loops: what (Canvas jit!) and (Mixer jit!) build."
  (sample "(do (import x/gfx/canvas) (Canvas jit!))" "#t where a JIT backend is, #f elsewhere"))
