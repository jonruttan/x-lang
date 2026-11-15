; word-form-jit.x -- (fn ...) forms over machine words compiled, and
; adopted only when they agree with their pure-x twins.
;
; Loaded lazily by the libraries whose loops are word forms (x/gfx/canvas,
; x/audio/mixer), never on their import: this module pulls the JIT
; toolchain, and each library stays usable and correct on a host with no
; JIT.  It compiles the forms a library hands it, the same forms its pure-x
; loops are made from (x/tool/word-form), and answers them only after the
; library's own check finds every one writes what its pure twin writes.
(module x/tool/word-form-jit)

(import x/tool/compile compile-asm)
(import x/tool/word-form word-form-wide)

; FORMS: the kernels as (fn ...) forms.  CHECK: (fn (_ engine) -> #t) when
; ENGINE, a list of kernels in FORMS' order, agrees with the pure ones.
; Answers ENGINE, or raises: on a host with no assembler backend, a
; toolchain error, or any disagreement.  The caller guards; a raise means
; "stay pure-x".
(def word-form-jit-make
  (fn (_ forms check)
    (def engine (List map (fn (_ f) (compile-asm (word-form-wide f))) forms))
    (Heap collect)
    (unless (check engine)
      (Err raise (lit state) "word-form-jit: the compiled loops disagree with the pure-x loops" ()))
    engine))

; A library reaches the maker through the catalogue: it loads this module
; inside the function that builds its engine, where an import is one the
; linter cannot see.
(prim-reg! (lit word-form) (lit jit-make) word-form-jit-make)

(doc (provide x/tool/word-form-jit word-form-jit-make)
  "Loops compiled by the JIT (ARM64 and x86-64 backends) from their word forms, adopted only after a library's check finds they agree with the pure-x loops: what (Canvas jit!) and (Mixer jit!) build."
  (sample "(do (import x/gfx/canvas) (Canvas jit!))" "#t where a JIT backend is, #f elsewhere"))
