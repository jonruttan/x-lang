; compile.x -- Runtime compiler: x-lang to native code
(import x/core/list)
; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-push-write (prim-ref 'type 'push-write))
(def %type-pop-write (prim-ref 'type 'pop-write))
(def %type-cast! (prim-ref 'type 'cast!))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))

(import x/type/str)
(import x/sys/posix)
(import x/type/hash)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref 'type 'of))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr-ref-word (prim-ref 'ptr 'ref-word))
(def %ptr-set-word! (prim-ref 'ptr 'set-word!))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))



;
; (compile '(fn (_ params...) body))  =>  <prim>
;
; Generates C code by pushing C-emitting write handlers onto the type
; system's write stacks.  write-to-str then walks the expression tree
; via normal type dispatch, each type emitting its own C representation.
; The result is compiled with cc, loaded via dlopen/dlsym.

; --- libc resolves (fd-write / file-exists? live on the Sys class) ---

(def %c-unlink (%resolve "unlink"))
(def %c-system (%resolve "system"))

; --- Compile counter for unique temp file names ---

(def %compile-id 0)

; --- Compile cache ---

(def %compile-cache-dir "/tmp/x-cache-")

; --- Platform-specific cc flags ---

(def %compile-cc-flags
  (if (Str contains? "darwin" x-machine)
    (list "-bundle" "-undefined" "dynamic_lookup")
    (list "-shared" "-fPIC")))

(def %compile-ext
  (if (Str contains? "darwin" x-machine) ".bundle" ".so"))

; --- Multi-arg string concatenation ---

; str moved to string.x

; --- The emitters and generation stages (#38 split; load order matters:
; emit defines the state cells and write handlers pipeline brackets) ---
(import x/tool/compile/emit)
(import x/tool/compile/pipeline)

; --- Exposed pipeline stages ---

; --- Compilation internals (must be before public API for closure capture) ---

(def %compile-cc
  (fn (_ src-path lib-path)
    (def %cc-cmd
      (fold (fn (_ acc s) (Str append acc " " s))
        "cc"
        (append %compile-cc-flags
          (list "-O2" "-DX_HEAP" "-DX_TYPE" "-Wno-unused-value"
                "-Iext/x-expr/include" "-I./include"
                "-o" lib-path src-path))))
    ; %sys-fold (x/sys/posix): keeps a failed status readable, not u32-huge
    (def %cc-status (%sys-fold (%ptr-call %c-system %cc-cmd)))
    (if (not (= %cc-status 0))
      (Err raise 'io (Str append "compile: cc failed with status " (%cvt %cc-status %string)) ()))))

(def %patch-nested-prims
  (fn (self lib fns prim-type-val)
    (unless (null? fns)
      (let ()
        (def %prim-sym (Str append (first (first fns)) "_prim"))
        (def %prim-ptr (%dlsym lib %prim-sym))
        (if (not (null? %prim-ptr))
          (%ptr-set-word! %prim-ptr %type-offset prim-type-val))
        (self lib (rest fns) prim-type-val)))))

(def %compile-cache-load
  (fn (_ cache-path fns-holder)
    (unless (not (Sys file-exists? cache-path))
      (let ((lib (%dlopen cache-path 1)))
        (unless (null? lib)
          (let ((fn-ptr (%dlsym lib "fn_0")))
            (unless (null? fn-ptr)
              (let ()
                (%type-cast! fn-ptr first)
                (def %prim-type-val (%ptr-ref-word (%cvt first %ptr) %type-offset))
                (%patch-nested-prims lib (first fns-holder) %prim-type-val)
                fn-ptr))))))))

(note "Pipeline stages")

; Pipeline stage docs use bare-symbol form to avoid tail-eval closure issues
(def compile-to-c
  (fn (_ expr . rest)
    (set! %compile-fvars (unless (null? rest) (first rest)))
    (if (not (eq? (first expr) 'fn))
      (Err raise 'type "compile-to-c: expression must be (fn (_ params...) body)" ()))
    (def %fns-holder (list (list)))
    (compile-with-writers
      (fn (_ ) (%generate-c-with-fns expr %fns-holder)))))
(doc compile-to-c "Generate C source code from an (fn ...) expression."
  (param expr LIST "A (fn (_ params...) body) expression")
  (returns STRING "Generated C source code"))

(def compile-write
  (fn (_ path source)
    (def fd (Sys open-write path))
    (Sys fd-write fd source)
    (Sys close fd)
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
    (def %lib (%dlopen lib-path 1))
    (if (null? %lib) (Err raise 'io "compile-load: dlopen failed" ()))
    (def %fn (%dlsym %lib "fn_0"))
    (if (null? %fn) (Err raise 'io "compile-load: dlsym failed for fn_0" ()))
    (%type-cast! %fn first)
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

(def compile-c
  (fn (_ expr . rest)
    (def fvars (unless (null? rest) (first rest)))
    (set! %compile-fvars fvars)

    ; Cache lookup: hash the expression to get a stable filename
    (def %expr-key (%write-to-str expr))
    (def %cache-hash (Hash ->hex (Hash fnv-1a %expr-key)))
    (def %cache-path (Str append %compile-cache-dir %cache-hash compile-ext))

    ; Try loading from cache (fvar table is patched after load)
    (def %cached (%compile-cache-load %cache-path (list (list))))
    (if (not (null? %cached))
      (do
        ; Patch fvar table with current runtime pointers
        (if (not (null? fvars))
          (let ((lib (%dlopen %cache-path 1)))
            (%compile-patch-fvars lib fvars)))
        %cached)

      ; Cache miss: generate, write, compile, load
      (let ()
        (set! %compile-id (+ %compile-id 1))
        (def %id (%cvt %compile-id %string))
        (def %src-path (Str append "/tmp/x-compile-" %id ".c"))

        (compile-write %src-path (compile-to-c expr fvars))
        (compile-cc %src-path %cache-path)
        (%ptr-call %c-unlink %src-path)

        (def %lib (%dlopen %cache-path 1))
        (if (null? %lib) (Err raise 'io "compile: dlopen failed" ()))
        (def %fn (%dlsym %lib "fn_0"))
        (if (null? %fn) (Err raise 'io "compile: dlsym failed for fn_0" ()))
        (%type-cast! %fn first)
        (def %prim-type-val (%ptr-ref-word (%cvt first %ptr) %type-offset))
        (%patch-nested-prims %lib (first (list (list))) %prim-type-val)
        ; Patch fvar table
        (if (not (null? fvars))
          (%compile-patch-fvars %lib fvars))
        %fn))))
(doc compile-c "Compile an (fn ...) expression to a native primitive via C compiler. Caches by expression hash."
  (param expr LIST "A (fn (_ params...) body) expression")
  (returns PRIM "Compiled native function"))

; --- Full C compilation (called by compile-cache.x on cache miss) ---

(def %compile-c-full
  (fn (_ expr fvars)
    (set! %compile-fvars fvars)
    (set! %compile-id (+ %compile-id 1))
    (def %id (%cvt %compile-id %string))
    (def %src-path (Str append "/tmp/x-compile-" %id ".c"))

    (def %expr-key (%write-to-str expr))
    (def %cache-hash (Hash ->hex (Hash fnv-1a %expr-key)))
    (def %cache-path (Str append %compile-cache-dir %cache-hash compile-ext))

    (compile-write %src-path (compile-to-c expr fvars))
    (compile-cc %src-path %cache-path)
    (%ptr-call %c-unlink %src-path)

    (def %lib (%dlopen %cache-path 1))
    (if (null? %lib) (Err raise 'io "compile: dlopen failed" ()))
    (def %fn (%dlsym %lib "fn_0"))
    (if (null? %fn) (Err raise 'io "compile: dlsym failed for fn_0" ()))
    (%type-cast! %fn first)
    (def %prim-type-val (%ptr-ref-word (%cvt first %ptr) %type-offset))
    (%patch-nested-prims %lib (first (list (list))) %prim-type-val)
    (if (not (null? fvars))
      (%compile-patch-fvars %lib fvars))
    %fn))

; --- JIT assembler: lazy-loaded on first pure-JIT use ---
; The assembler toolchain (asm-compile.x -> asm.x -> host platform) is ~900 lines,
; about half of compile.x's parse cost, and only the pure-JIT path needs it --
; compile-to-c and the C-compiler path never do. So ship a stub that loads the
; toolchain on first call via include-once (an op, so its top-level defs bind
; globally and REPLACE this stub with the real compile-asm), then dispatches.
(def compile-asm
  (fn (_ expr)
    (include-once "lib/x/tool/asm-compile.x")
    (compile-asm expr)))

; --- Default compile: JIT assembler with C compiler fallback ---

(def compile
  (fn (_ expr . %c-rest)
    (if (null? %c-rest)
      (compile-asm expr)
      (compile-c expr (first %c-rest)))))
(doc compile "Compile an (fn ...) expression to native code. Pure expressions use JIT assembler; fvar expressions use C compiler with persistent caching."
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
      (fn (self lib i n)
        (unless (= i n)
          (let ((name (Str append "batch_" (%cvt i %string))))
            (def %fn (%dlsym lib name))
            (if (null? %fn)
              (Err raise 'io (Str append "compile-batch: dlsym failed for " name) ()))
            (%type-cast! %fn first)
            (pair %fn (self lib (+ i 1) n))))))

    ; Cache lookup
    (def %batch-key (%write-to-str exprs))
    (def %batch-hash (Hash ->hex (Hash fnv-1a %batch-key)))
    (def %cache-path (Str append %compile-cache-dir %batch-hash compile-ext))

    (if (Sys file-exists? %cache-path)
      ; Cache hit: load and patch fvar table
      (let ((lib (%dlopen %cache-path 1)))
        (when (not (null? lib))
          (do
            (if (not (null? %compile-fvars))
              (%compile-patch-fvars lib %compile-fvars))
            (%resolve-all lib 0 %n))))

      ; Cache miss: generate, compile, cache, load
      (let ()
        (set! %compile-id (+ %compile-id 1))
        (def %id (%cvt %compile-id %string))
        (def %src-path (Str append "/tmp/x-compile-" %id ".c"))

        (%compile-push-writers)

        (def %c-all
          (fn (self es i acc)
            (if (null? es) acc
              (let ((expr (first es)))
                (if (not (eq? (first expr) 'fn))
                  (Err raise 'type "compile-batch: each expression must be (fn ...)" ()))
                (let ((params (first (rest expr)))
                      (body (first (rest (rest expr))))
                      (name (Str append "batch_" (%cvt i %string))))
                  (set! %compile-fns (list (list)))
                  (def %fn-c
                    (Str append "x_obj_t *" name
                         "(x_obj_t *p_base, x_obj_t *p_args) {\n"
                         (%c-param-decls params)
                         "    return " (%generate-fn-body params body) ";\n"
                         "}\n\n"))
                  (self (rest es) (+ i 1) (Str append acc %fn-c)))))))

        (def %c-source
          (Str append "#include \"x-obj.h\"\n"
               "#include \"x-type/buffer.h\"\n\n"
               (if (null? %compile-fvars) ""
                 "x_obj_t *x_fvar_table[64];\n\n")
               (%c-all exprs 0 "")))

        (%compile-pop-writers)

        (compile-write %src-path %c-source)
        (compile-cc %src-path %cache-path)
        (%ptr-call %c-unlink %src-path)

        (def %lib (%dlopen %cache-path 1))
        (if (null? %lib) (Err raise 'io "compile-batch: dlopen failed" ()))

        ; Patch fvar table with current runtime pointers
        (if (not (null? %compile-fvars))
          (%compile-patch-fvars %lib %compile-fvars))

        (%resolve-all %lib 0 %n)))))
(doc compile-batch "Compile multiple (fn ...) expressions in a single cc invocation."
  (returns LIST "List of compiled native primitives"))

(doc (provide x/tool/compile
  compile-to-c compile-write compile-cc compile-load
  compile-cc-flags compile-ext compile-with-writers
  compile-emitters compile-add-emitter!
  compile compile-c compile-asm compile-batch)
  (note "Default compile uses JIT assembler. compile-c falls back to C compiler. compile-asm is the pure JIT path.")
  "Native code compiler: JIT assembler (default) with C compiler fallback.")
