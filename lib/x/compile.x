; compile.x -- Runtime compiler: x-lang to native code
(import x/list)
(import x/posix)
(import x/hash)
;
; (compile '(fn (params...) body))  =>  <prim>
;
; Generates C code by pushing C-emitting write handlers onto the type
; system's write stacks.  write-to-string then walks the expression tree
; via normal type dispatch, each type emitting its own C representation.
; The result is compiled with cc, loaded via dlopen/dlsym.

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

(note "Utilities")

(doc (def str
  (fn args
    (fold string-append "" args)))
  (returns STRING "Concatenated result")
  "Concatenate all arguments into a single string.")

; --- C code generator utilities ---

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
          (str "    x_obj_t *p_" (convert (first ps) %string)
               " = x_firstobj(" (%c-args-ref i) ");\n"
               (%go (rest ps) (+ i 1))))))
    (%go params 0)))

; Check if symbol is in a list
(def %compile-member?
  (fn (sym lst)
    (if (null? lst) ()
      (if (eq? sym (first lst)) lst
        (%compile-member? sym (rest lst))))))

; --- Compile state (globals read by write handlers) ---

(def %compile-fvars ())
(def %compile-params ())
(def %compile-fns ())

(def %compile-fvar-lookup
  (fn (sym)
    (def %fv-go
      (fn (fvs)
        (if (null? fvs) ()
          (if (eq? sym (first (first fvs)))
            (first fvs)
            (%fv-go (rest fvs))))))
    (%fv-go %compile-fvars)))

; --- Type system access ---

; Navigate type struct to io group and write-stack
; Type layout: (name (data (heap (proc (cvt (io (iter)))))))
; IO layout: (analyse (delimit (read (write (display (error))))))
(def %type-io
  (fn (t) (first (rest (rest (rest (rest (rest t))))))))

; Cell containing the write-stack (so we can push/pop)
; write-stack = first(write-cell), where write-cell = rest^3(io)
(def %type-write-cell
  (fn (t) (rest (rest (rest (%type-io t))))))

; Push a handler onto a type's write stack
(def %type-push-write
  (fn (type-struct handler)
    (let ((cell (%type-write-cell type-struct)))
      (set-first! cell (pair handler (first cell))))))

; Pop a handler from a type's write stack
(def %type-pop-write
  (fn (type-struct)
    (let ((cell (%type-write-cell type-struct)))
      (set-first! cell (rest (first cell))))))

; Type alist path: first(first(first(first(rest(first(%base))))))
(def %type-alist
  (fn ()
    (first (first (first (first (rest (first (%base)))))))))

; Find a type struct by name atom (from type-of) in the type alist
(def %type-by-atom
  (fn (name-atom)
    (def %go
      (fn (alist)
        (if (null? alist) (error "compile: type not found")
          (if (eq? (first (first alist)) name-atom)
            (rest (first alist))
            (%go (rest alist))))))
    (%go (%type-alist))))

; Cache type structs at load time using representative objects
(def %list-type (%type-by-atom (type-of (list 1))))
(def %symbol-type (%type-by-atom (type-of (lit a))))
(def %int-type (%type-by-atom (type-of 0)))

; --- C-emitting write handlers ---
;
; These are pushed onto the write stack so that write-to-string on a
; quoted expression emits C code.  display is used for literal C text
; (display dispatches to the display-stack, not write-stack, so no
; recursion).  write on sub-expressions dispatches back to these handlers.

; SYMBOL: emit C variable reference
(def %compile-symbol-write
  (fn (sym)
    (if (%compile-member? sym %compile-params)
      (display (str "p_" (convert sym %string)))
      (let ((fv-entry (%compile-fvar-lookup sym)))
        (if (null? fv-entry)
          (error (str "compile: free variable: " (convert sym %string)))
          (let ((fv-val (rest fv-entry)))
            (if (null? fv-val)
              (display "NULL")
              (display (str "(x_obj_t *)"
                (convert (convert (convert fv-val %ptr) %int) %string))))))))))
; INT: emit integer literal
(def %compile-int-write
  (fn (n)
    (display (convert n %string))))

; LIST: inspect operator, dispatch to form-specific C emission
; Sub-expressions are emitted by calling write on them (recurses through
; the pushed write handlers).

; Emit a sub-expression: nil => NULL, otherwise write dispatches to handler
(def %cw-emit
  (fn (expr)
    (if (null? expr) (display "NULL") (write expr))))

; --- Form emitters (called by the list write handler) ---

; (if cond then else) => ternary
(def %cw-if
  (fn (args)
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
  (fn (args)
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
  (fn (args)
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
  (fn (args)
    (display "(")
    (%cw-emit (first args))
    (display ", ")
    (%cw-emit (first (rest args)))
    (display ")")))

; (buffer-unread buffer) => decrement read pointer
(def %cw-buffer-unread
  (fn (args)
    (display "(x_bufferread(")
    (%cw-emit (first args))
    (display ")--, ")
    (%cw-emit (first args))
    (display ")")))

; (fn (params) body) => nested function
(def %cw-fn
  (fn (args)
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
  (fn (args)
    (display "((x_obj_t *)(long)(")
    (def %or-go
      (fn (as)
        (%cw-emit (first as))
        (if (not (null? (rest as)))
          (do (display " || ") (%or-go (rest as))))))
    (%or-go args)
    (display "))")))

; (first x) => x_firstobj(x)
(def %cw-first
  (fn (args)
    (display "x_firstobj(")
    (%cw-emit (first args))
    (display ")")))

; (set-first! cell val) => assign + return val
(def %cw-set-first
  (fn (args)
    (display "(x_firstobj(")
    (%cw-emit (first args))
    (display ") = (x_obj_t *)")
    (%cw-emit (first (rest args)))
    (display ", (x_obj_t *)")
    (%cw-emit (first (rest args)))
    (display ")")))

; (atom-add! atom n) => in-place add
(def %cw-atom-add
  (fn (args)
    (display "(x_atomint(")
    (%cw-emit (first args))
    (display ") += ")
    (display (convert (first (rest args)) %string))
    (display ", ")
    (%cw-emit (first args))
    (display ")")))

; (atom-set! atom n) => in-place set
(def %cw-atom-set
  (fn (args)
    (display "(x_atomint(")
    (%cw-emit (first args))
    (display ") = ")
    (display (convert (first (rest args)) %string))
    (display ", ")
    (%cw-emit (first args))
    (display ")")))

; (atom-val atom) => read as truthy/falsy pointer
(def %cw-atom-val
  (fn (args)
    (display "(x_obj_t *)(long)x_atomint(")
    (%cw-emit (first args))
    (display ")")))

; LIST write handler: dispatch on operator symbol
(def %compile-list-write
  (fn (lst)
    (if (null? lst)
      (display "NULL")
      (let ((op (first lst))
            (args (rest lst)))
        (if (eq? op (lit if))       (%cw-if args)
        (if (eq? op (lit =))        (%cw-eq args)
        (if (eq? op (lit score-set)) (%cw-score-set args)
        (if (eq? op (lit %seq))     (%cw-seq args)
        (if (eq? op (lit buffer-unread)) (%cw-buffer-unread args)
        (if (eq? op (lit fn))       (%cw-fn args)
        (if (eq? op (lit or))       (%cw-or args)
        (if (eq? op (lit first))    (%cw-first args)
        (if (eq? op (lit set-first!)) (%cw-set-first args)
        (if (eq? op (lit atom-add!)) (%cw-atom-add args)
        (if (eq? op (lit atom-set!)) (%cw-atom-set args)
        (if (eq? op (lit atom-val)) (%cw-atom-val args)
          (error (str "compile: unsupported form: "
            (convert op %string)))))))))))))))))))

; --- Generate C via write-to-string ---

; Generate a C function body by pushing write handlers and serializing
(def %generate-fn-body
  (fn (params body)
    (set! %compile-params params)
    (write-to-string body)))

; Generate a complete C function
(def %generate-fn
  (fn (name params body)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args) {\n"
         (%c-param-decls params)
         "    return " (%generate-fn-body params body) ";\n"
         "}\n\n")))

; --- Top-level C generation ---

; Generate forward declaration for a nested fn
(def %generate-fwd-decl
  (fn (name)
    (str "x_obj_t *" name "(x_obj_t *p_base, x_obj_t *p_args);\n"
         "extern x_obj_t " name "_prim[];\n")))

; Generate static prim object for a nested fn
(def %generate-static-prim
  (fn (name)
    (str "x_obj_t " name "_prim[] = {\n"
         "    { .v = NULL }, { .v = NULL }, { .i = 0 }, { .fn = " name " }\n"
         "};\n\n")))

; Generate complete C source with nested fn support.
; Write handlers must be pushed before calling this.
(def %generate-c-with-fns
  (fn (expr fns-holder)
    (let ((params (first (rest expr)))
          (body (first (rest (rest expr)))))
      (set! %compile-fns fns-holder)
      ; Generate the main function (may populate fns via %cw-fn)
      (def %main-c (%generate-fn "fn_0" params body))
      ; Iteratively generate nested fn bodies until stable
      (def %nested-c "")
      (def %gen-loop
        (fn (processed)
          (def %current (first %compile-fns))
          (def %len (length %current))
          (if (= %len processed) ()
            (do
              (def %gen-new
                (fn (lst n)
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
      (%gen-loop 0)
      ; Generate forward decls and static prims
      (def %all-fwd "")
      (def %all-prims "")
      (def %gen-decls
        (fn (lst)
          (if (null? lst) ()
            (do
              (def %name (first (first lst)))
              (set! %all-fwd (str %all-fwd (%generate-fwd-decl %name)))
              (set! %all-prims (str %all-prims (%generate-static-prim %name)))
              (%gen-decls (rest lst))))))
      (%gen-decls (first %compile-fns))
      ; Combine
      (str "#include \"x-obj.h\"\n"
           "#include \"x-type/buffer.h\"\n\n"
           %all-fwd "\n"
           %nested-c
           %all-prims
           %main-c))))

; --- Push/pop write handlers around code generation ---

(def %compile-push-writers
  (fn ()
    (%type-push-write %list-type %compile-list-write)
    (%type-push-write %symbol-type %compile-symbol-write)
    (%type-push-write %int-type %compile-int-write)))

(def %compile-pop-writers
  (fn ()
    (%type-pop-write %list-type)
    (%type-pop-write %symbol-type)
    (%type-pop-write %int-type)))

; --- Type casting ---

(def %type-offset %word-size)

(doc (def type-cast!
  (fn ((param obj ANY "Object to cast") (param type-src ANY "Object whose type to copy"))
    (def %dst-ptr (convert obj %ptr))
    (def %src-ptr (convert type-src %ptr))
    (def %type-val (ptr-ref-word %src-ptr %type-offset))
    (ptr-set-word! %dst-ptr %type-offset %type-val)
    obj))
  (returns ANY "The original object with its type tag replaced")
  "Overwrite an object's type tag with the type of another object.")

; --- Compilation pipeline ---

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
      (error (str "compile: cc failed with status " (convert %cc-status %string))))))

(def %patch-nested-prims
  (fn (lib fns prim-type-val)
    (if (null? fns) ()
      (do
        (def %prim-sym (str (first (first fns)) "_prim"))
        (def %prim-ptr (dlsym lib %prim-sym))
        (if (not (null? %prim-ptr))
          (ptr-set-word! %prim-ptr %type-offset prim-type-val))
        (%patch-nested-prims lib (rest fns) prim-type-val)))))

(def %compile-cache-load
  (fn (cache-path fns-holder)
    (if (not (%file-exists? cache-path)) ()
      (let ((lib (dlopen cache-path 1)))
        (if (null? lib) ()
          (let ((fn-ptr (dlsym lib "fn_0")))
            (if (null? fn-ptr) ()
              (do
                (type-cast! fn-ptr first)
                (def %prim-type-val (ptr-ref-word (convert first %ptr) %type-offset))
                (%patch-nested-prims lib (first fns-holder) %prim-type-val)
                fn-ptr))))))))

; compile: compile a single (fn ...) expression to a native prim
; Optional second arg: free variable alist ((sym . val) ...)
; Caches compiled libraries keyed by FNV-1a hash of the expression.
(note "Compilation")

(doc (def compile
  (fn ((param expr LIST "A (fn (params...) body) expression") . rest)
    (set! %compile-fvars (if (null? rest) () (first rest)))
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
        (set! %compile-id (+ %compile-id 1))
        (def %id (convert %compile-id %string))
        (def %src-path (str "/tmp/x-compile-" %id ".c"))

        ; Push C-emitting write handlers, generate C, pop
        (%compile-push-writers)
        (def %c-source (%generate-c-with-fns expr %fns-holder))
        (%compile-pop-writers)

        (def %fd (sh-open-write %src-path))
        (%fd-write %fd %c-source)
        (sh-close %fd)

        ; Compile to cache or temp path
        (def %lib-path (if (null? %compile-fvars) %cache-path
          (str "/tmp/x-compile-" %id %compile-ext)))
        (%compile-cc %src-path %lib-path)

        ; Clean up source
        (ptr-call %c-unlink %src-path)

        (def %lib (dlopen %lib-path 1))
        (if (null? %lib) (error "compile: dlopen failed"))

        (def %fn (dlsym %lib "fn_0"))
        (if (null? %fn) (error "compile: dlsym failed for fn_0"))
        (type-cast! %fn first)

        ; Patch nested fn static prims
        (def %prim-type-val (ptr-ref-word (convert first %ptr) %type-offset))
        (%patch-nested-prims %lib (first %fns-holder) %prim-type-val)

        ; Clean up temp lib for fvar compilations
        (if (not (null? %compile-fvars))
          (ptr-call %c-unlink %lib-path))

        %fn))))
  (returns PRIM "Compiled native function")
  "Compile an (fn ...) expression to a native primitive via C. Caches results by expression hash.")

; compile-batch: compile multiple (fn ...) expressions in one cc call.
; Returns a list of prims, one per expression.
(doc (def compile-batch
  (fn exprs
    (set! %compile-id (+ %compile-id 1))
    (def %id (convert %compile-id %string))
    (def %src-path (str "/tmp/x-compile-" %id ".c"))
    (def %lib-path (str "/tmp/x-compile-" %id %compile-ext))

    (%compile-push-writers)

    ; Generate all functions with unique top-level names
    (def %c-all
      (fn (es i acc)
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
           (%c-all exprs 0 "")))

    (%compile-pop-writers)

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
          (let ((name (str "batch_" (convert i %string))))
            (def %fn (dlsym %lib name))
            (if (null? %fn)
              (error (str "compile-batch: dlsym failed for " name)))
            (type-cast! %fn first)
            (pair %fn (%resolve-all (+ i 1) n))))))

    (%resolve-all 0 (length exprs))))
  (returns LIST "List of compiled native primitives")
  "Compile multiple (fn ...) expressions in a single cc invocation.")

(provide x/compile str type-cast! compile compile-batch)
