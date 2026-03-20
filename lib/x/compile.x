; compile.x -- Runtime compiler: x-lang to native code
;
; (compile '(fn (params...) body))  =>  <prim>
;
; Generates C code, compiles with cc, loads via dlopen/dlsym.
; The result is a native primitive with the same calling convention
; as hand-written C primitives.

; --- libc write/unlink/access (not in posix.x) ---

(def %c-write (%resolve "write"))
(def %c-unlink (%resolve "unlink"))
(def %c-system (%resolve "system"))
(def %c-access (%resolve "access"))

(def %fd-write
  (fn (fd s)
    (ptr-call %c-write fd s (string-length s))))

; --- Compile counter for unique temp file names ---

(def %compile-id 0)

; --- Compile cache ---

(def %compile-cache-dir "/tmp/x-cache-")

; Check if a file exists (access with F_OK=0)
(def %file-exists?
  (fn (path) (= (ptr-call %c-access path 0) 0)))

; --- Platform-specific cc flags ---

(def %compile-cc-flags
  (if (string-contains? x-machine "darwin")
    (list "-bundle" "-undefined" "dynamic_lookup")
    (list "-shared" "-fPIC")))

(def %compile-ext
  (if (string-contains? x-machine "darwin") ".bundle" ".so"))

; --- Multi-arg string concatenation ---

(def str
  (fn args
    (fold string-append "" args)))

; --- C code generator ---

; Generate the x_restobj chain to access parameter at index n
(def %c-args-ref
  (fn (n)
    (if (= n 0) "p_args"
      (str "x_restobj(" (%c-args-ref (- n 1)) ")"))))

; Generate parameter declarations at function entry
(def %c-param-decls
  (fn (params)
    (def %go
      (fn (ps i)
        (if (null? ps) ""
          (str "    x_obj_t *p_" (symbol->string (first ps))
               " = x_firstobj(" (%c-args-ref i) ");\n"
               (%go (rest ps) (+ i 1))))))
    (%go params 0)))

; Check if symbol is in a list (member not available in x-core.x)
(def %compile-member?
  (fn (sym lst)
    (if (null? lst) ()
      (if (eq? sym (first lst)) lst
        (%compile-member? sym (rest lst))))))

; Free variable bindings for compile: ((sym . val) ...)
; Set by compile before code generation, read by %emit-expr.
(def %compile-fvars ())

(def %compile-fvar-lookup
  (fn (sym)
    (def %fv-go
      (fn (fvs)
        (if (null? fvs) ()
          (if (eq? sym (first (first fvs)))
            (first fvs)
            (%fv-go (rest fvs))))))
    (%fv-go %compile-fvars)))

; Forward declarations for mutual recursion
(def %emit-expr ())
(def %emit-form ())

; --- Emit helpers (all reference %emit-expr via forward decl) ---

; (if cond then else) => ternary
(def %emit-if
  (fn (args params fns)
    (let ((cond-c (%emit-expr (first args) params fns))
          (then-c (%emit-expr (first (rest args)) params fns))
          (else-c (if (null? (rest (rest args)))
                    "NULL"
                    (%emit-expr (first (rest (rest args))) params fns))))
      (str "((x_obj_t *)" cond-c " ? "
           then-c " : " else-c ")"))))

; (= a b) => integer comparison, returns truthy or NULL
(def %emit-eq
  (fn (args params fns)
    (let ((a (first args))
          (b (first (rest args))))
      (str "(("
        (if (number? a)
          (number->string a)
          (str "x_atomint(" (%emit-expr a params fns) ")"))
        " == "
        (if (number? b)
          (number->string b)
          (str "x_atomint(" (%emit-expr b params fns) ")"))
        ") ? (x_obj_t *)1 : NULL)"))))

; (score-set score sign buffer) => inline
(def %emit-score-set
  (fn (args params fns)
    (let ((score (%emit-expr (first args) params fns))
          (sign (first (rest args)))
          (buffer (%emit-expr (first (rest (rest args))) params fns)))
      (str "(x_firstint(" score ") = "
        (number->string sign) " * x_bufferlen(" buffer
        "), " score ")"))))

; (%seq a b) => comma operator
(def %emit-seq
  (fn (args params fns)
    (str "(" (%emit-expr (first args) params fns)
         ", " (%emit-expr (first (rest args)) params fns) ")")))

; (buffer-unread buffer) => decrement read pointer
(def %emit-buffer-unread
  (fn (args params fns)
    (let ((buffer (%emit-expr (first args) params fns)))
      (str "(x_bufferread(" buffer ")--, " buffer ")"))))

; Nested fn: generates a separate C function + static prim object
(def %emit-nested-fn
  (fn (args fns)
    (let ((inner-params (first args))
          (inner-body (first (rest args)))
          (fn-name (str "fn_" (number->string (+ 1 (length (first fns)))))))
      ; Add this fn to the list
      (set-first fns
        (pair (list fn-name inner-params inner-body)
              (first fns)))
      ; Return pointer to the static prim object
      (str "(x_obj_t *)" fn-name "_prim"))))

; (or a b ...) => short-circuit logical OR, returns truthy or NULL
(def %emit-or
  (fn (args params fns)
    (def %or-parts
      (fn (as)
        (if (null? (rest as))
          (%emit-expr (first as) params fns)
          (str (%emit-expr (first as) params fns)
               " || " (%or-parts (rest as))))))
    (str "((x_obj_t *)(long)(" (%or-parts args) "))")))

; (first x) => x_firstobj(x) — read first element of pair/cell
(def %emit-first
  (fn (args params fns)
    (str "x_firstobj(" (%emit-expr (first args) params fns) ")")))

; (set-first cell val) => (x_firstobj(cell) = (x_obj_t *)val, (x_obj_t *)val)
(def %emit-set-first
  (fn (args params fns)
    (let ((cell (%emit-expr (first args) params fns))
          (val (%emit-expr (first (rest args)) params fns)))
      (str "(x_firstobj(" cell ") = (x_obj_t *)" val
           ", (x_obj_t *)" val ")"))))

; (atom-add! atom-expr n) => in-place integer add, returns atom
(def %emit-atom-add
  (fn (args params fns)
    (let ((atom (%emit-expr (first args) params fns))
          (n (first (rest args))))
      (str "(x_atomint(" atom ") += " (number->string n) ", " atom ")"))))

; (atom-set! atom-expr n) => in-place integer set, returns atom
(def %emit-atom-set
  (fn (args params fns)
    (let ((atom (%emit-expr (first args) params fns))
          (n (first (rest args))))
      (str "(x_atomint(" atom ") = " (number->string n) ", " atom ")"))))

; (atom-val atom-expr) => read integer as truthy/falsy pointer (0→NULL, nonzero→truthy)
(def %emit-atom-val
  (fn (args params fns)
    (str "(x_obj_t *)(long)x_atomint(" (%emit-expr (first args) params fns) ")")))

; --- Set the mutually recursive functions ---

(set %emit-expr
  (fn (expr params fns)
    (if (null? expr) "NULL"
      (if (number? expr)
        (number->string expr)
        (if (symbol? expr)
          (if (%compile-member? expr params)
            (str "p_" (symbol->string expr))
            ; Free variable: look up in compile-time fvars alist
            (let ((%fv-entry (%compile-fvar-lookup expr)))
              (if (null? %fv-entry)
                (error (str "compile: free variable: " (symbol->string expr)))
                (let ((%fv-val (rest %fv-entry)))
                  (if (null? %fv-val)
                    "NULL"
                    (str "(x_obj_t *)"
                      (number->string (ptr->int (obj->ptr %fv-val)))))))))
          (if (pair? expr)
            (%emit-form (first expr) (rest expr) params fns)
            (error "compile: unknown expression type")))))))

(set %emit-form
  (fn (op args params fns)
    (if (eq? op (lit if))
      (%emit-if args params fns)
      (if (eq? op (lit =))
        (%emit-eq args params fns)
        (if (eq? op (lit score-set))
          (%emit-score-set args params fns)
          (if (eq? op (lit %seq))
            (%emit-seq args params fns)
            (if (eq? op (lit buffer-unread))
              (%emit-buffer-unread args params fns)
              (if (eq? op (lit fn))
                (%emit-nested-fn args fns)
                (if (eq? op (lit or))
                  (%emit-or args params fns)
                  (if (eq? op (lit first))
                    (%emit-first args params fns)
                    (if (eq? op (lit set-first))
                      (%emit-set-first args params fns)
                      (if (eq? op (lit atom-add!))
                        (%emit-atom-add args params fns)
                        (if (eq? op (lit atom-set!))
                          (%emit-atom-set args params fns)
                          (if (eq? op (lit atom-val))
                            (%emit-atom-val args params fns)
                            (error (str "compile: unsupported form: "
                                        (symbol->string op)))))))))))))))))))

; Generate a complete C function
(def %generate-fn
  (fn (name params body fns)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args) {\n"
         (%c-param-decls params)
         "    return " (%emit-expr body params fns) ";\n"
         "}\n\n")))

; --- Top-level C generation ---

; Generate forward declaration for a nested fn (function + extern prim array)
(def %generate-fwd-decl
  (fn (name)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args);\n"
         "extern x_obj_t " name "_prim[];\n")))

; Generate static prim object for a nested fn
; Layout: [heap=NULL][type=NULL][flags=0][data=fn_ptr]
; Type slot is patched after dlopen by the x-lang compile function.
(def %generate-static-prim
  (fn (name)
    (str "x_obj_t " name "_prim[] = {\n"
         "    { .v = NULL }, { .v = NULL }, { .i = 0 }, { .fn = " name " }\n"
         "};\n\n")))

; %generate-c-with-fns: generate C source, fns-holder captures nested fn info
; Iteratively generates nested fn bodies until no new fns are discovered,
; then emits forward declarations and static prims for ALL nested fns.
(def %generate-c-with-fns
  (fn (expr fns-holder)
    (let ((params (first (rest expr)))
          (body (first (rest (rest expr))))
          (fns fns-holder))
      ; Generate the main function (may populate fns with nested fns)
      (def %main-c (%generate-fn "fn_0" params body fns))
      ; Iteratively generate nested fn bodies until stable
      ; New nested fns may be discovered while generating existing ones
      (def %nested-c "")
      (def %gen-loop
        (fn (processed)
          (def %current (first fns))
          (def %len (length %current))
          (if (= %len processed) ()
            (do
              ; Process new fns (prepended at front of list)
              (def %gen-new
                (fn (lst n)
                  (if (= n 0) ()
                    (do
                      (def %entry (first lst))
                      (def %name (first %entry))
                      (set %nested-c
                        (str %nested-c
                          (%generate-fn %name
                            (first (rest %entry))
                            (first (rest (rest %entry)))
                            fns)))
                      (%gen-new (rest lst) (- n 1))))))
              (%gen-new %current (- %len processed))
              (%gen-loop %len)))))
      (%gen-loop 0)
      ; Generate forward decls and static prims for ALL discovered nested fns
      (def %all-fwd "")
      (def %all-prims "")
      (def %gen-decls
        (fn (lst)
          (if (null? lst) ()
            (do
              (def %name (first (first lst)))
              (set %all-fwd (str %all-fwd (%generate-fwd-decl %name)))
              (set %all-prims (str %all-prims (%generate-static-prim %name)))
              (%gen-decls (rest lst))))))
      (%gen-decls (first fns))
      ; Combine: preamble + forward decls + nested fns + static prims + main fn
      (str "#include \"x-obj.h\"\n"
           "#include \"x-type/buffer.h\"\n\n"
           %all-fwd "\n"
           %nested-c
           %all-prims
           %main-c))))

; Convenience wrapper (no fns output needed)
(def %generate-c
  (fn (expr)
    (%generate-c-with-fns expr (list (list)))))

; --- Type casting ---
; Copy the type slot from src object to dst object.
; Object layout: [heap][type][flags][data...] — type at word offset 1.
; sizeof(x_obj_t) = sizeof(void*) = %word-size (bound by C FFI layer).
; We use ptr-ref-word/ptr-set-word! which operate in bytes.

(def %type-offset %word-size)

(def type-cast!
  (fn (obj type-src)
    (def %dst-ptr (obj->ptr obj))
    (def %src-ptr (obj->ptr type-src))
    (def %type-val (ptr-ref-word %src-ptr %type-offset))
    (ptr-set-word! %dst-ptr %type-offset %type-val)
    obj))

; --- Compilation pipeline ---

; %compile-cc: invoke cc on a source file, return nothing
(def %compile-cc
  (fn (src-path lib-path)
    (def %cc-cmd
      (fold (fn (acc s) (str acc " " s))
        "cc"
        (append %compile-cc-flags
          (list "-O2" "-DX_HEAP" "-DX_TYPE" "-Wno-unused-value"
                "-Iext/x-expr/include" "-I./include"
                "-o" lib-path src-path))))
    (def %cc-status (ptr-call %c-system %cc-cmd))
    (if (not (= %cc-status 0))
      (error (str "compile: cc failed with status " (number->string %cc-status))))))

; %patch-nested-prims: patch type slot of static prim objects in the .so
; prim-type-val: the integer type pointer value from a real prim
(def %patch-nested-prims
  (fn (lib fns prim-type-val)
    (if (null? fns) ()
      (do
        (def %prim-sym (str (first (first fns)) "_prim"))
        (def %prim-ptr (dlsym lib %prim-sym))
        (if (not (null? %prim-ptr))
          (ptr-set-word! %prim-ptr %type-offset prim-type-val))
        (%patch-nested-prims lib (rest fns) prim-type-val)))))

; Load a cached library, returning the prim (or () if not found)
(def %compile-cache-load
  (fn (cache-path fns-holder)
    (if (not (%file-exists? cache-path)) ()
      (let ((lib (dlopen cache-path 1)))
        (if (null? lib) ()
          (let ((fn-ptr (dlsym lib "fn_0")))
            (if (null? fn-ptr) ()
              (do
                (type-cast! fn-ptr first)
                (def %prim-type-val (ptr-ref-word (obj->ptr first) %type-offset))
                (%patch-nested-prims lib (first fns-holder) %prim-type-val)
                fn-ptr))))))))

; compile: compile a single (fn ...) expression to a native prim
; Optional second arg: free variable alist ((sym . val) ...)
; Caches compiled libraries keyed by FNV-1a hash of the expression.
(def compile
  (fn (expr . rest)
    (set %compile-fvars (if (null? rest) () (first rest)))
    (if (not (eq? (first expr) (lit fn)))
      (error "compile: expression must be (fn (params...) body)"))

    ; Cache lookup: hash the expression to get a stable filename
    (def %fns-holder (list (list)))
    (def %expr-key (write-to-string expr))
    (def %cache-hash (hash->hex (fnv-1a %expr-key)))
    (def %cache-path (str %compile-cache-dir %cache-hash %compile-ext))

    ; Try loading from cache (skip if fvars — they embed heap pointers)
    (def %cached (if (null? %compile-fvars)
      (%compile-cache-load %cache-path %fns-holder) ()))
    (if (not (null? %cached)) %cached

      ; Cache miss: compile and save to cache path
      (do
        (set %compile-id (+ %compile-id 1))
        (def %id (number->string %compile-id))
        (def %src-path (str "/tmp/x-compile-" %id ".c"))

        ; Generate C (fns list captures nested fn info)
        (def %c-source (%generate-c-with-fns expr %fns-holder))
        (def %fd (sh-open-write %src-path))
        (%fd-write %fd %c-source)
        (sh-close %fd)

        ; Compile to cache or temp path
        (def %lib-path (if (null? %compile-fvars) %cache-path
          (str "/tmp/x-compile-" %id %compile-ext)))
        (%compile-cc %src-path %lib-path)

        ; Clean up source (and temp lib if fvars, else cache persists)
        (ptr-call %c-unlink %src-path)

        (def %lib (dlopen %lib-path 1))
        (if (null? %lib) (error "compile: dlopen failed"))

        (def %fn (dlsym %lib "fn_0"))
        (if (null? %fn) (error "compile: dlsym failed for fn_0"))
        (type-cast! %fn first)

        ; Patch nested fn static prims
        (def %prim-type-val (ptr-ref-word (obj->ptr first) %type-offset))
        (%patch-nested-prims %lib (first %fns-holder) %prim-type-val)

        ; Clean up temp lib for fvar compilations (stays mapped by dlopen)
        (if (not (null? %compile-fvars))
          (ptr-call %c-unlink %lib-path))

        %fn))))

; compile-batch: compile multiple (fn ...) expressions in one cc call.
; Returns a list of prims, one per expression.
(def compile-batch
  (fn exprs
    (set %compile-id (+ %compile-id 1))
    (def %id (number->string %compile-id))
    (def %src-path (str "/tmp/x-compile-" %id ".c"))
    (def %lib-path (str "/tmp/x-compile-" %id %compile-ext))

    ; Generate all functions with unique top-level names
    (def %c-all
      (fn (es i acc)
        (if (null? es) acc
          (let ((expr (first es)))
            (if (not (eq? (first expr) (lit fn)))
              (error "compile-batch: each expression must be (fn ...)"))
            (let ((params (first (rest expr)))
                  (body (first (rest (rest expr))))
                  (fns (list (list)))
                  (name (str "batch_" (number->string i))))
              (def %fn-c
                (str "x_obj_t *" name
                     "(x_obj_t *p_base, x_obj_t *p_args) {\n"
                     (%c-param-decls params)
                     "    return " (%emit-expr body params fns) ";\n"
                     "}\n\n"))
              (%c-all (rest es) (+ i 1) (str acc %fn-c)))))))

    (def %c-source
      (str "#include \"x-obj.h\"\n"
           "#include \"x-type/buffer.h\"\n\n"
           (%c-all exprs 0 "")))

    (def %fd (sh-open-write %src-path))
    (%fd-write %fd %c-source)
    (sh-close %fd)

    (%compile-cc %src-path %lib-path)

    (def %lib (dlopen %lib-path 1))
    (if (null? %lib) (error "compile-batch: dlopen failed"))

    ; Clean up temp files
    (ptr-call %c-unlink %src-path)
    (ptr-call %c-unlink %lib-path)

    ; Resolve each function symbol
    (def %resolve-all
      (fn (i n)
        (if (= i n) ()
          (let ((name (str "batch_" (number->string i))))
            (def %fn (dlsym %lib name))
            (if (null? %fn)
              (error (str "compile-batch: dlsym failed for " name)))
            (type-cast! %fn first)
            (pair %fn (%resolve-all (+ i 1) n))))))

    (%resolve-all 0 (length exprs))))
