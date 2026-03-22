; compile.x -- Runtime compiler: x-lang to native code
(import x/list)
(import x/string)
(import x/posix)
(import x/hash)
;
; (compile '(fn (_ params...) body))  =>  <prim>
;
; Generates C code by pushing C-emitting write handlers onto the type
; system's write stacks.  write-to-string then walks the expression tree
; via normal type dispatch, each type emitting its own C representation.
; The result is compiled with cc, loaded via dlopen/dlsym.

; --- libc resolves (fd-write and file-exists? now in posix.x) ---

(def %c-unlink (%resolve "unlink"))
(def %c-system (%resolve "system"))

; --- Compile counter for unique temp file names ---

(def %compile-id 0)

; --- Compile cache ---

(def %compile-cache-dir "/tmp/x-cache-")

; --- Platform-specific cc flags ---

(def %compile-cc-flags
  (if (string-contains? x-machine "darwin")
    (list "-bundle" "-undefined" "dynamic_lookup")
    (list "-shared" "-fPIC")))

(def %compile-ext
  (if (string-contains? x-machine "darwin") ".bundle" ".so"))

; --- Multi-arg string concatenation ---

; str moved to string.x

; --- C code generator utilities ---

; Generate the x_restobj chain to access parameter at index n
(def %c-args-ref
  (fn (_ n)
    (if (= n 0) "p_args"
      (str "x_restobj(" (%c-args-ref (- n 1)) ")"))))

; Generate parameter declarations at function entry
(def %c-param-decls
  (fn (_ params)
    (def %go
      (fn (_ ps i)
        (if (null? ps) ""
          (str "    x_obj_t *p_" (convert (first ps) %string)
               " = x_firstobj(" (%c-args-ref i) ");\n"
               (%go (rest ps) (+ i 1))))))
    (%go params 0)))

; memq replaced by memq from list.x

; --- Compile state (globals read by write handlers) ---

(def %compile-fvars ())
(def %compile-params ())
(def %compile-fns ())

(def %compile-fvar-lookup
  (fn (_ sym)
    (def %fv-go
      (fn (_ fvs)
        (if (null? fvs) ()
          (if (eq? sym (first (first fvs)))
            (first fvs)
            (%fv-go (rest fvs))))))
    (%fv-go %compile-fvars)))

; Return the index of a fvar symbol in %compile-fvars (for table emission)
(def %compile-fvar-index
  (fn (_ sym)
    (def %go
      (fn (_ fvs i)
        (if (null? fvs) ()
          (if (eq? sym (first (first fvs))) i
            (%go (rest fvs) (+ i 1))))))
    (%go %compile-fvars 0)))

; --- Type system access (via type.x) ---

; Cache type structs at load time using representative objects
(def %list-type (type-by-atom (type-of (list 1))))
(def %symbol-type (type-by-atom (type-of (lit a))))
(def %int-type (type-by-atom (type-of 0)))

; --- C-emitting write handlers ---
;
; These are pushed onto the write stack so that write-to-string on a
; quoted expression emits C code.  display is used for literal C text
; (display dispatches to the display-stack, not write-stack, so no
; recursion).  write on sub-expressions dispatches back to these handlers.

; SYMBOL: emit C variable reference
(def %compile-symbol-write
  (fn (_ sym)
    (if (memq sym %compile-params)
      (display (str "p_" (convert sym %string)))
      (let ((fv-entry (%compile-fvar-lookup sym)))
        (if (null? fv-entry)
          (error (str "compile: free variable: " (convert sym %string)))
          (let ((fv-val (rest fv-entry)))
            (if (null? fv-val)
              (display "NULL")
              ; Emit table lookup: x_fvar_table[N] (cacheable, patched at load)
              (display (str "x_fvar_table["
                (convert (%compile-fvar-index sym) %string) "]")))))))))
; INT: emit integer literal
(def %compile-int-write
  (fn (_ n)
    (display (convert n %string))))

; LIST: inspect operator, dispatch to form-specific C emission
; Sub-expressions are emitted by calling write on them (recurses through
; the pushed write handlers).

; Emit a sub-expression: nil => NULL, otherwise write dispatches to handler
(def %cw-emit
  (fn (_ expr)
    (if (null? expr) (display "NULL") (write expr))))

; --- Form emitters (called by the list write handler) ---

; (if cond then else) => ternary
(def %cw-if
  (fn (_ args)
    (display "((x_obj_t *)")
    (%cw-emit (first args))
    (display " ? ")
    (%cw-emit (first (rest args)))
    (display " : ")
    (if (null? (rest (rest args)))
      (display "NULL")
      (%cw-emit (first (rest (rest args)))))
    (display ")")))

; (= a b) => integer comparison
(def %cw-eq
  (fn (_ args)
    (display "((")
    (if (number? (first args))
      (display (convert (first args) %string))
      (do (display "x_atomint(") (%cw-emit (first args)) (display ")")))
    (display " == ")
    (if (number? (first (rest args)))
      (display (convert (first (rest args)) %string))
      (do (display "x_atomint(") (%cw-emit (first (rest args))) (display ")")))
    (display ") ? (x_obj_t *)1 : NULL)")))

; (score-set score sign buffer) => inline
(def %cw-score-set
  (fn (_ args)
    (display "(x_firstint(")
    (%cw-emit (first args))
    (display ") = ")
    (display (convert (first (rest args)) %string))
    (display " * x_bufferlen(")
    (%cw-emit (first (rest (rest args))))
    (display "), ")
    (%cw-emit (first args))
    (display ")")))

; (%seq a b) => comma operator
(def %cw-seq
  (fn (_ args)
    (display "(")
    (%cw-emit (first args))
    (display ", ")
    (%cw-emit (first (rest args)))
    (display ")")))

; (buffer-unread buffer) => decrement read pointer
(def %cw-buffer-unread
  (fn (_ args)
    (display "(x_bufferread(")
    (%cw-emit (first args))
    (display ")--, ")
    (%cw-emit (first args))
    (display ")")))

; (fn (_ params) body) => nested function
(def %cw-fn
  (fn (_ args)
    (let ((inner-params (first args))
          (inner-body (first (rest args)))
          (fn-name (str "fn_" (convert (+ 1 (length (first %compile-fns))) %string))))
      ; Add this fn to the list
      (set-first! %compile-fns
        (pair (list fn-name inner-params inner-body)
              (first %compile-fns)))
      ; Return pointer to the static prim object
      (display (str "(x_obj_t *)" fn-name "_prim")))))

; (or a b ...) => short-circuit logical OR
(def %cw-or
  (fn (_ args)
    (display "((x_obj_t *)(long)(")
    (def %or-go
      (fn (_ as)
        (%cw-emit (first as))
        (if (not (null? (rest as)))
          (do (display " || ") (%or-go (rest as))))))
    (%or-go args)
    (display "))")))

; (< a b) => integer comparison, returns truthy or NULL
(def %cw-lt
  (fn (_ args)
    (display "((")
    (if (number? (first args))
      (display (convert (first args) %string))
      (do (display "x_atomint(") (%cw-emit (first args)) (display ")")))
    (display " < ")
    (if (number? (first (rest args)))
      (display (convert (first (rest args)) %string))
      (do (display "x_atomint(") (%cw-emit (first (rest args))) (display ")")))
    (display ") ? (x_obj_t *)1 : NULL)")))

; (first x) => x_firstobj(x)
(def %cw-first
  (fn (_ args)
    (display "x_firstobj(")
    (%cw-emit (first args))
    (display ")")))

; (set-first! cell val) => assign + return val
(def %cw-set-first
  (fn (_ args)
    (display "(x_firstobj(")
    (%cw-emit (first args))
    (display ") = (x_obj_t *)")
    (%cw-emit (first (rest args)))
    (display ", (x_obj_t *)")
    (%cw-emit (first (rest args)))
    (display ")")))

; (atom-add! atom n) => in-place add
(def %cw-atom-add
  (fn (_ args)
    (display "(x_atomint(")
    (%cw-emit (first args))
    (display ") += ")
    (display (convert (first (rest args)) %string))
    (display ", ")
    (%cw-emit (first args))
    (display ")")))

; (atom-set! atom n) => in-place set
(def %cw-atom-set
  (fn (_ args)
    (display "(x_atomint(")
    (%cw-emit (first args))
    (display ") = ")
    (display (convert (first (rest args)) %string))
    (display ", ")
    (%cw-emit (first args))
    (display ")")))

; (atom-val atom) => read as truthy/falsy pointer
(def %cw-atom-val
  (fn (_ args)
    (display "(x_obj_t *)(long)x_atomint(")
    (%cw-emit (first args))
    (display ")")))

; Emitter dispatch table: (operator . handler) alist
(def compile-emitters
  (list
    (pair (lit if)            %cw-if)
    (pair (lit =)             %cw-eq)
    (pair (lit <)             %cw-lt)
    (pair (lit score-set)     %cw-score-set)
    (pair (lit %seq)          %cw-seq)
    (pair (lit buffer-unread) %cw-buffer-unread)
    (pair (lit fn)            %cw-fn)
    (pair (lit or)            %cw-or)
    (pair (lit first)         %cw-first)
    (pair (lit set-first!)    %cw-set-first)
    (pair (lit atom-add!)     %cw-atom-add)
    (pair (lit atom-set!)     %cw-atom-set)
    (pair (lit atom-val)      %cw-atom-val)))

(doc (def compile-add-emitter!
  (fn (_ (param op SYMBOL "Operator symbol to handle")
       (param handler CALLABLE "Emitter function: (fn (_ args) ...)"))
    (set! compile-emitters (pair (pair op handler) compile-emitters))))
  (returns LIST "Updated emitter alist")
  "Register a new C code emitter for a form. The handler receives the argument list.")

; LIST write handler: dispatch via alist
(def %compile-list-write
  (fn (_ lst)
    (if (null? lst)
      (display "NULL")
      (let ((entry (assq (first lst) compile-emitters)))
        (if entry
          ((rest entry) (rest lst))
          (error (str "compile: unsupported form: "
            (convert (first lst) %string))))))))

; --- Generate C via write-to-string ---

; Generate a C function body by pushing write handlers and serializing
(def %generate-fn-body
  (fn (_ params body)
    (set! %compile-params params)
    (write-to-string body)))

; Generate a complete C function
(def %generate-fn
  (fn (_ name params body)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args) {\n"
         (%c-param-decls params)
         "    return " (%generate-fn-body params body) ";\n"
         "}\n\n")))

; --- Top-level C generation ---

; Generate forward declaration for a nested fn
(def %generate-fwd-decl
  (fn (_ name)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args);\n"
         "extern x_obj_t " name "_prim[];\n")))

; Generate static prim object for a nested fn
(def %generate-static-prim
  (fn (_ name)
    (str "x_obj_t " name "_prim[] = {\n"
         "    { .v = NULL }, { .v = NULL }, { .i = 0 }, { .fn = " name " }\n"
         "};\n\n")))

; --- Multi-stage C generation ---

; Generate nested function bodies iteratively until stable.
; %compile-fns is populated by %cw-fn during generation.
(def %generate-nested-fns
  (fn (_ )
    (def %nested-c "")
    (def %gen-loop
      (fn (_ processed)
        (def %current (first %compile-fns))
        (def %len (length %current))
        (if (= %len processed) %nested-c
          (do
            (def %gen-new
              (fn (_ lst n)
                (if (= n 0) ()
                  (do
                    (def %entry (first lst))
                    (def %name (first %entry))
                    (set! %nested-c
                      (str %nested-c
                        (%generate-fn %name
                          (first (rest %entry))
                          (first (rest (rest %entry))))))
                    (%gen-new (rest lst) (- n 1))))))
            (%gen-new %current (- %len processed))
            (%gen-loop %len)))))
    (%gen-loop 0)))

; Generate forward declarations and static prim objects for nested fns.
(def %generate-declarations
  (fn (_ )
    (def %all-fwd "")
    (def %all-prims "")
    (def %gen-decls
      (fn (_ lst)
        (if (null? lst) ()
          (do
            (def %name (first (first lst)))
            (set! %all-fwd (str %all-fwd (%generate-fwd-decl %name)))
            (set! %all-prims (str %all-prims (%generate-static-prim %name)))
            (%gen-decls (rest lst))))))
    (%gen-decls (first %compile-fns))
    (pair %all-fwd %all-prims)))

; Generate complete C source with nested fn support.
; Write handlers must be pushed before calling this.
(def %generate-c-with-fns
  (fn (_ expr fns-holder)
    (let ((params (first (rest expr)))
          (body (first (rest (rest expr)))))
      (set! %compile-fns fns-holder)
      (def %main-c (%generate-fn "fn_0" params body))
      (def %nested-c (%generate-nested-fns))
      (def %decls (%generate-declarations))
      (str "#include \"x-obj.h\"\n"
           "#include \"x-type/buffer.h\"\n\n"
           (if (null? %compile-fvars) ""
             "x_obj_t *x_fvar_table[64];\n\n")
           (first %decls) "\n"
           %nested-c
           (rest %decls)
           %main-c))))

; --- Push/pop write handlers around code generation ---

(def %compile-push-writers
  (fn (_ )
    (type-push-write %list-type %compile-list-write)
    (type-push-write %symbol-type %compile-symbol-write)
    (type-push-write %int-type %compile-int-write)))

(def %compile-pop-writers
  (fn (_ )
    (type-pop-write %list-type)
    (type-pop-write %symbol-type)
    (type-pop-write %int-type)))

(doc (def compile-with-writers
  (fn (_ (param thunk CALLABLE "Zero-arg function to call with C emitters active"))
    (%compile-push-writers)
    (def result (thunk))
    (%compile-pop-writers)
    result))
  (returns ANY "Result of calling thunk")
  "Push C code-generation write handlers, call thunk, pop handlers. Use for custom C generation.")

; --- Fvar table patching: write runtime pointers into loaded .so ---
; After dlopen, resolve x_fvar_table symbol and fill with current fvar values.
(def %compile-patch-fvars
  (fn (_ lib fvars)
    (if (null? fvars) ()
      (let ((tbl (dlsym lib "x_fvar_table")))
        (if (null? tbl) ()
          (do
            (def %patch-go
              (fn (_ fvs i)
                (if (null? fvs) ()
                  (do
                    (ptr-set-word! tbl (* i %word-size)
                      (if (null? (rest (first fvs))) 0
                        (convert (convert (rest (first fvs)) %ptr) %int)))
                    (%patch-go (rest fvs) (+ i 1))))))
            (%patch-go fvars 0)))))))

; type-cast! moved to type.x

; --- Exposed pipeline stages ---

; --- Compilation internals (must be before public API for closure capture) ---

(def %compile-cc
  (fn (_ src-path lib-path)
    (def %cc-cmd
      (fold (fn (_ acc s) (str acc " " s))
        "cc"
        (append %compile-cc-flags
          (list "-O2" "-DX_HEAP" "-DX_TYPE" "-Wno-unused-value"
                "-Iext/x-expr/include" "-I./include"
                "-o" lib-path src-path))))
    (def %cc-status (ptr-call %c-system %cc-cmd))
    (if (not (= %cc-status 0))
      (error (str "compile: cc failed with status " (convert %cc-status %string))))))

(def %patch-nested-prims
  (fn (_ lib fns prim-type-val)
    (if (null? fns) ()
      (do
        (def %prim-sym (str (first (first fns)) "_prim"))
        (def %prim-ptr (dlsym lib %prim-sym))
        (if (not (null? %prim-ptr))
          (ptr-set-word! %prim-ptr %type-offset prim-type-val))
        (%patch-nested-prims lib (rest fns) prim-type-val)))))

(def %compile-cache-load
  (fn (_ cache-path fns-holder)
    (if (not (file-exists? cache-path)) ()
      (let ((lib (dlopen cache-path 1)))
        (if (null? lib) ()
          (let ((fn-ptr (dlsym lib "fn_0")))
            (if (null? fn-ptr) ()
              (do
                (type-cast! fn-ptr first)
                (def %prim-type-val (ptr-ref-word (convert first %ptr) %type-offset))
                (%patch-nested-prims lib (first fns-holder) %prim-type-val)
                fn-ptr))))))))

(note "Pipeline stages")

; Pipeline stage docs use bare-symbol form to avoid tail-eval closure issues
(def compile-to-c
  (fn (_ expr . rest)
    (set! %compile-fvars (if (null? rest) () (first rest)))
    (if (not (eq? (first expr) (lit fn)))
      (error "compile-to-c: expression must be (fn (_ params...) body)"))
    (def %fns-holder (list (list)))
    (compile-with-writers
      (fn (_ ) (%generate-c-with-fns expr %fns-holder)))))
(doc compile-to-c "Generate C source code from an (fn ...) expression."
  (param expr LIST "A (fn (_ params...) body) expression")
  (returns STRING "Generated C source code"))

(def compile-write
  (fn (_ path source)
    (def fd (sh-open-write path))
    (fd-write fd source)
    (sh-close fd)
    path))
(doc compile-write "Write a string to a file. Returns the path."
  (param path STRING "Output file path")
  (param source STRING "Content to write")
  (returns STRING "The path written to"))

(def compile-cc
  (fn (_ src-path lib-path)
    (%compile-cc src-path lib-path)))
(doc compile-cc "Invoke the C compiler on a source file to produce a shared library."
  (param src-path STRING "C source file")
  (param lib-path STRING "Output shared library path"))

(def compile-load
  (fn (_ lib-path)
    (def %lib (dlopen lib-path 1))
    (if (null? %lib) (error "compile-load: dlopen failed"))
    (def %fn (dlsym %lib "fn_0"))
    (if (null? %fn) (error "compile-load: dlsym failed for fn_0"))
    (type-cast! %fn first)
    %fn))
(doc compile-load "Load a compiled shared library and return fn_0 as a callable primitive."
  (param lib-path STRING "Path to shared library")
  (returns PRIM "Native function"))

(def compile-cc-flags %compile-cc-flags)
(doc compile-cc-flags "Compiler flags for the current platform."
  (returns LIST "Platform-specific cc flags"))

(def compile-ext %compile-ext)
(doc compile-ext "Shared library file extension for the current platform."
  (returns STRING ".bundle or .so"))

; compile: compile a single (fn ...) expression to a native prim
; Optional second arg: free variable alist ((sym . val) ...)
; Caches compiled libraries keyed by FNV-1a hash of the expression.
(note "Compilation")

(def compile
  (fn (_ expr . rest)
    (def fvars (if (null? rest) () (first rest)))
    (set! %compile-fvars fvars)

    ; Cache lookup: hash the expression to get a stable filename
    (def %expr-key (write-to-string expr))
    (def %cache-hash (hash->hex (fnv-1a %expr-key)))
    (def %cache-path (str %compile-cache-dir %cache-hash compile-ext))

    ; Try loading from cache (fvar table is patched after load)
    (def %cached (%compile-cache-load %cache-path (list (list))))
    (if (not (null? %cached))
      (do
        ; Patch fvar table with current runtime pointers
        (if (not (null? fvars))
          (let ((lib (dlopen %cache-path 1)))
            (%compile-patch-fvars lib fvars)))
        %cached)

      ; Cache miss: generate, write, compile, load
      (do
        (set! %compile-id (+ %compile-id 1))
        (def %id (convert %compile-id %string))
        (def %src-path (str "/tmp/x-compile-" %id ".c"))

        (compile-write %src-path (compile-to-c expr fvars))
        (compile-cc %src-path %cache-path)
        (ptr-call %c-unlink %src-path)

        (def %lib (dlopen %cache-path 1))
        (if (null? %lib) (error "compile: dlopen failed"))
        (def %fn (dlsym %lib "fn_0"))
        (if (null? %fn) (error "compile: dlsym failed for fn_0"))
        (type-cast! %fn first)
        (def %prim-type-val (ptr-ref-word (convert first %ptr) %type-offset))
        (%patch-nested-prims %lib (first (list (list))) %prim-type-val)
        ; Patch fvar table
        (if (not (null? fvars))
          (%compile-patch-fvars %lib fvars))
        %fn))))
(doc compile "Compile an (fn ...) expression to a native primitive via C. Caches by expression hash."
  (param expr LIST "A (fn (_ params...) body) expression")
  (returns PRIM "Compiled native function"))

; compile-batch: compile multiple (fn ...) expressions in one cc call.
; Returns a list of prims, one per expression.
; Caches the shared library by expression hash. Fvar table patched after load.
(def compile-batch
  (fn (_ . exprs)
    (def %n (length exprs))

    ; Resolve functions from a loaded library
    (def %resolve-all
      (fn (_ lib i n)
        (if (= i n) ()
          (let ((name (str "batch_" (convert i %string))))
            (def %fn (dlsym lib name))
            (if (null? %fn)
              (error (str "compile-batch: dlsym failed for " name)))
            (type-cast! %fn first)
            (pair %fn (%resolve-all lib (+ i 1) n))))))

    ; Cache lookup
    (def %batch-key (write-to-string exprs))
    (def %batch-hash (hash->hex (fnv-1a %batch-key)))
    (def %cache-path (str %compile-cache-dir %batch-hash compile-ext))

    (if (file-exists? %cache-path)
      ; Cache hit: load and patch fvar table
      (let ((lib (dlopen %cache-path 1)))
        (if (not (null? lib))
          (do
            (if (not (null? %compile-fvars))
              (%compile-patch-fvars lib %compile-fvars))
            (%resolve-all lib 0 %n))
          ()))

      ; Cache miss: generate, compile, cache, load
      (do
        (set! %compile-id (+ %compile-id 1))
        (def %id (convert %compile-id %string))
        (def %src-path (str "/tmp/x-compile-" %id ".c"))

        (%compile-push-writers)

        (def %c-all
          (fn (_ es i acc)
            (if (null? es) acc
              (let ((expr (first es)))
                (if (not (eq? (first expr) (lit fn)))
                  (error "compile-batch: each expression must be (fn ...)"))
                (let ((params (first (rest expr)))
                      (body (first (rest (rest expr))))
                      (name (str "batch_" (convert i %string))))
                  (set! %compile-fns (list (list)))
                  (def %fn-c
                    (str "x_obj_t *" name
                         "(x_obj_t *p_base, x_obj_t *p_args) {\n"
                         (%c-param-decls params)
                         "    return " (%generate-fn-body params body) ";\n"
                         "}\n\n"))
                  (%c-all (rest es) (+ i 1) (str acc %fn-c)))))))

        (def %c-source
          (str "#include \"x-obj.h\"\n"
               "#include \"x-type/buffer.h\"\n\n"
               (if (null? %compile-fvars) ""
                 "x_obj_t *x_fvar_table[64];\n\n")
               (%c-all exprs 0 "")))

        (%compile-pop-writers)

        (compile-write %src-path %c-source)
        (compile-cc %src-path %cache-path)
        (ptr-call %c-unlink %src-path)

        (def %lib (dlopen %cache-path 1))
        (if (null? %lib) (error "compile-batch: dlopen failed"))

        ; Patch fvar table with current runtime pointers
        (if (not (null? %compile-fvars))
          (%compile-patch-fvars %lib %compile-fvars))

        (%resolve-all %lib 0 %n)))))
(doc compile-batch "Compile multiple (fn ...) expressions in a single cc invocation."
  (returns LIST "List of compiled native primitives"))

(doc (provide x/compile
  compile-to-c compile-write compile-cc compile-load
  compile-cc-flags compile-ext compile-with-writers
  compile-emitters compile-add-emitter!
  compile compile-batch)
  (note "Pipeline: compile-to-c -> compile-write -> compile-cc -> compile-load. Each stage usable independently.")
  "Native code compiler via dlopen/dlsym.")
