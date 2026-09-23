; tool/compile/pipeline.x -- C generation stages (#38: split from compile.x).
;
; write-to-str C generation, top-level and multi-stage generation, and
; fvar table patching. Loaded by x/tool/compile after emit.x, whose state
; accessors and writer brackets it imports.
(module x/tool/compile/pipeline)

(import x/tool/compile/emit c-param-decls compile-fvars compile-params-set! compile-fns compile-fns-set! compile-push-writers compile-pop-writers)
; Fetched from the catalog into this module's frame.
(def %cvt (prim-ref 'convert 'to))
(def %write-to-str (prim-ref 'io 'write-to-str))
(def %dlsym (prim-ref 'ffi 'dlsym))
(def %ptr-set-word! (prim-ref 'ptr 'set-word!))

; --- Generate C via write-to-str ---

; Generate a C function body by pushing write handlers and serializing
(def generate-fn-body
  (fn (_ params body)
    (compile-params-set! params)
    (%write-to-str body)))

; Generate a complete C function
(def %generate-fn
  (fn (_ name params body)
    (Str append "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args) {\n"
         (c-param-decls params)
         "    return " (generate-fn-body params body) ";\n"
         "}\n\n")))

; --- Top-level C generation ---

; Generate forward declaration for a nested fn
(def %generate-fwd-decl
  (fn (_ name)
    (Str append "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args);\n"
         "extern x_obj_t " name "_prim[];\n")))

; Generate static prim object for a nested fn
(def %generate-static-prim
  (fn (_ name)
    (Str append "x_obj_t " name "_prim[] = {\n"
         "    { .v = NULL }, { .v = NULL }, { .fn = " name " }, { .v = NULL }\n"
         "};\n\n")))

; --- Multi-stage C generation ---

; Generate nested function bodies iteratively until stable.
; The nested-function holder is populated by the fn emitter during generation.
(def %generate-nested-fns
  (fn (_ )
    (def %nested-c "")
    (def %gen-loop
      (fn (self processed)
        (def %current (first (compile-fns)))
        (def %len (%length %current))
        (if (= %len processed) %nested-c
          (let ()  ; scoped: def in tail position would leak to global
            (def %gen-new
              (fn (self lst n)
                (unless (= n 0)
                  (let ()
                    (def %entry (first lst))
                    (def %name (first %entry))
                    (set! %nested-c
                      (Str append %nested-c
                        (%generate-fn %name
                          (first (rest %entry))
                          (first (rest (rest %entry))))))
                    (self (rest lst) (- n 1))))))
            (%gen-new %current (- %len processed))
            (self %len)))))
    (%gen-loop 0)))

; Generate forward declarations and static prim objects for nested fns.
(def %generate-declarations
  (fn (_ )
    (def %all-fwd "")
    (def %all-prims "")
    (def %gen-decls
      (fn (self lst)
        (unless (null? lst)
          (let ()
            (def %name (first (first lst)))
            (set! %all-fwd (Str append %all-fwd (%generate-fwd-decl %name)))
            (set! %all-prims (Str append %all-prims (%generate-static-prim %name)))
            (self (rest lst))))))
    (%gen-decls (first (compile-fns)))
    (pair %all-fwd %all-prims)))

; Generate complete C source with nested fn support.
; Write handlers must be pushed before calling this.
(def generate-c-with-fns
  (fn (_ expr fns-holder)
    (let ((params (first (rest expr)))
          (body (first (rest (rest expr)))))
      (compile-fns-set! fns-holder)
      (def %main-c (%generate-fn "fn_0" params body))
      (def %nested-c (%generate-nested-fns))
      (def %decls (%generate-declarations))
      (Str append "#include \"x-obj.h\"\n"
           "#include \"x-type/buffer.h\"\n\n"
           (if (null? (compile-fvars)) ""
             "x_obj_t *x_fvar_table[64];\n\n")
           (first %decls) "\n"
           %nested-c
           (rest %decls)
           %main-c))))

; --- The writer brackets around a custom generation ---

(doc (def compile-with-writers
  (fn (_ (param thunk CALLABLE "Zero-arg function to call with C emitters active"))
    (compile-push-writers)
    (def result (thunk))
    (compile-pop-writers)
    result))
  (returns ANY "Result of calling thunk")
  "Push C code-generation write handlers, call thunk, pop handlers. Use for custom C generation.")

; --- Fvar table patching: write runtime pointers into loaded .so ---
; After dlopen, resolve x_fvar_table symbol and fill with current fvar values.
(def compile-patch-fvars
  (fn (_ lib fvars)
    (unless (null? fvars)
      (let ((tbl (%dlsym lib "x_fvar_table")))
        (unless (null? tbl)
          (let ()
            (def %patch-go
              (fn (self fvs i)
                (unless (null? fvs)
                  (do
                    (%ptr-set-word! tbl (* i %word-size)
                      (if (null? (rest (first fvs))) 0
                        (%cvt (%cvt (rest (first fvs)) %ptr) %int)))
                    (self (rest fvs) (+ i 1))))))
            (%patch-go fvars 0)))))))

(provide x/tool/compile/pipeline
  generate-fn-body generate-c-with-fns compile-with-writers compile-patch-fvars)
