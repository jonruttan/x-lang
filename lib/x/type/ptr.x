; type/ptr.x -- Ptr + Ffi: the raw-pointer and foreign-function surface.
;
; The C primitives live in src/x-prim/ffi.c (catalogue ns `ptr` and `ffi`);
; the methods fetch inline per the cold rule. Both namespaces are
; DE-REGISTERED (R5): the classes -- or catalogue fetches -- are the only
; surface. Low-level/hot consumers (boot/data.x's int mutators, the JIT
; assembler, x/num/float's stubs) fetch-and-cache into module %-vars:
;   (def ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
;
; Pointer CONSTRUCTION from an int is int->ptr (catalogue ns `int`, method
; ->ptr); (Ptr from-int n) fetches it. obj->ptr / str->ptr live on the Obj
; and (via Convert) string surfaces.
(module x/type/ptr)

(import x/type/class)

; Type helpers for ptr? (ns `type` de-registered; fetch from the catalogue).
; The PTR handle is obtained by type-of'ing a null pointer -- not dereferenced.
(import x/core/doors int->ptr obj->ptr str->ptr type-of type?)
(def %ptr (type-of ((prim-ref (lit int) (lit ->ptr)) 0)))

(def-class Ptr ()
  (static
    (method from-int (self (param n INTEGER "Integer address"))
      (doc "Construct a pointer from an integer address (the int->ptr cast)."
        (returns POINTER "A pointer to that address")
        (example "(Ptr ->int (Ptr from-int 4096))" "4096"))
      ((prim-ref (lit int) (lit ->ptr)) n))
    (method ptr? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a raw pointer."
        (returns BOOL "True if x is a pointer")
        (example "(Ptr ptr? (Ptr from-int 0))" "#t")
        (example "(Ptr ptr? 5)" "#f"))
      (type? x %ptr))
    (method ->int (self (param p POINTER "A pointer"))
      (doc "The integer (address) representation of a pointer."
        (returns INTEGER "Integer address")
        (example "(Ptr ->int (Ptr from-int 64))" "64"))
      ((prim-ref (lit ptr) (lit ->int)) p))
    (method ->str (self (param p POINTER "A C string pointer"))
      (doc "Copy the NUL-terminated C string at P into a fresh x-lang string."
        (returns STRING "A new string (survives the C buffer)")
        (example "(Ptr ->str ((prim-ref 'str '->ptr) \"hello\"))" "\"hello\""))
      ((prim-ref (lit ptr) (lit ->str)) p))
    ; The engine reads this as a memcpy of `width` bytes into the low end of a
    ; zeroed machine int (x_prim_ptr_ref, src/x-prim/ffi.c).  On a big-endian
    ; host those bytes land in the HIGH end and any width below the full word
    ; reads wrong -- which is what "little-endian" in the doc below means.
    ; ref-word is exempt: a full-width copy has no byte-order question.
    ; constraint: endian = little -- widening (ptr ref) is a low-end memcpy
    (method ref (self (param p POINTER "Base pointer") (param off INTEGER "Byte offset")
                      (param width INTEGER "Read width in bytes (1,2,4,8)"))
      (doc "Read a WIDTH-byte little-endian value at P+OFF."
        (returns INTEGER "The value read")
        (example "(let ((p ((prim-ref 'str '->ptr) \"AB\"))) (Ptr ref p 1 1))" "66"))
      ((prim-ref (lit ptr) (lit ref)) p off width))
    (method set! (self (param p POINTER "Base pointer") (param off INTEGER "Byte offset")
                       (param v INTEGER "Value to store") (param width INTEGER "Write width in bytes"))
      (doc "Write a WIDTH-byte little-endian value V at P+OFF."
        (returns ANY "nil")
        (example "(let ((p ((prim-ref 'str '->ptr) ((prim-ref 'str 'make) 8)))) (Ptr set! p 0 200 1) (Ptr ref p 0 1))" "200"))
      ((prim-ref (lit ptr) (lit set!)) p off v width))
    (method ref-word (self (param p POINTER "Base pointer") (param off INTEGER "Byte offset"))
      (doc "Read one machine word (sizeof(long)) at P+OFF."
        (returns INTEGER "The word value")
        (example "(let ((p ((prim-ref 'str '->ptr) ((prim-ref 'str 'make) (* 2 %word-size))))) (Ptr set-word! p %word-size -7) (Ptr ref-word p %word-size))" "-7"))
      ((prim-ref (lit ptr) (lit ref-word)) p off))
    (method set-word! (self (param p POINTER "Base pointer") (param off INTEGER "Byte offset")
                            (param v INTEGER "Word value to store"))
      (doc "Write one machine word V at P+OFF."
        (returns ANY "nil")
        (example "(let ((p ((prim-ref 'str '->ptr) ((prim-ref 'str 'make) %word-size)))) (Ptr set-word! p 0 12345) (Ptr ref-word p 0))" "12345"))
      ((prim-ref (lit ptr) (lit set-word!)) p off v))
    (method call (self (param p POINTER "C function pointer")
                       . (param args STRING "String arguments (variadic)"))
      (doc "Call a C function pointer with string arguments."
        (returns INTEGER "The C return value")
        (sample "(Ptr call (Ffi dlsym (Ffi dlopen () 1) \"strlen\") \"hello\")" "5, where the C library dlopen reaches exports strlen"))
      (apply (prim-ref (lit ptr) (lit call)) (pair p args)))))

(def-class Ffi ()
  (static
    (method dlopen (self (param path STRING "Library file path (() for the main program)")
                         (param mode INTEGER "dlopen mode flags (e.g. 1 = RTLD_LAZY)"))
      (doc "Load a shared library."
        (returns POINTER "Library handle, or () on failure")
        (example "(null? (Ffi dlopen \"/no/such/lib.so\" 1))" "#t")
        (sample "(Ffi dlopen () 1)" "a handle on the main program and the libraries it loaded"))
      ((prim-ref (lit ffi) (lit dlopen)) path mode))
    (method dlsym (self (param lib POINTER "Library handle from dlopen") (param name STRING "Symbol name"))
      (doc "Look up a symbol in a loaded library."
        (returns POINTER "Function or data pointer")
        (sample "(Ffi dlsym (Ffi dlopen () 1) \"strlen\")" "a pointer to strlen, for (Ptr call ...); () when the symbol is missing"))
      ((prim-ref (lit ffi) (lit dlsym)) lib name))))
; There is no typed call here.  (Ptr call) calls through a pointer with
; long arguments and a long result; a C function that takes or returns a
; double is reached through x/num/float's libm-fn, whose stubs move the
; bits into the FP registers.

(doc (provide x/type/ptr Ptr Ffi)
  (note "ns `ptr`/`ffi` are de-registered; low-level/hot callers fetch-and-cache the prims. int->ptr is ns `int` (Ptr from-int).")
  (example "(Ptr ->int (Ptr from-int 4096))" "4096")
  "Raw pointers (Ptr) and the foreign-function interface (Ffi): the FFI surface for C interop.")
