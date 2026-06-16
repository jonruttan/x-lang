; type/ptr.x -- Ptr + Ffi: the raw-pointer and foreign-function surface.
;
; The C primitives live in src/x-prim/ffi.c (catalog ns `ptr` and `ffi`);
; the methods fetch inline per the cold rule. Both namespaces are
; DE-REGISTERED (R5): the classes -- or catalog fetches -- are the only
; surface. Low-level/hot consumers (boot/data.x's int mutators, the JIT
; assembler, the FFI float ops) fetch-and-cache into module %-vars:
;   (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
;
; Pointer CONSTRUCTION from an int is int->ptr (catalog ns `int`, method
; ->ptr); (Ptr from-int n) fetches it. obj->ptr / str->ptr live on the Obj
; and (via Convert) string surfaces.

(import x/type/object)

; Type helpers for ptr? (ns `type` de-registered; fetch from the catalog).
; The PTR handle is obtained by type-of'ing a null pointer -- not dereferenced.
(def %type-of (prim-ref (lit type) (lit of)))
(def %type? (prim-ref (lit type) (lit ?)))
(def %ptr (%type-of ((prim-ref (lit int) (lit ->ptr)) 0)))

(def-class Ptr ()
  (static
    (method from-int (self (param n INT "Integer address"))
      (doc "Construct a pointer from an integer address (the int->ptr cast)."
        (returns PTR "A pointer to that address"))
      ((prim-ref (lit int) (lit ->ptr)) n))
    (method ptr? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a raw pointer."
        (returns BOOL "True if x is a pointer"))
      (%type? x %ptr))
    (method ->int (self (param p PTR "A pointer"))
      (doc "The integer (address) representation of a pointer."
        (returns INT "Integer address"))
      ((prim-ref (lit ptr) (lit ->int)) p))
    (method ->str (self (param p PTR "A C string pointer"))
      (doc "Copy the NUL-terminated C string at P into a fresh x-lang string."
        (returns STRING "A new string (survives the C buffer)"))
      ((prim-ref (lit ptr) (lit ->str)) p))
    (method ref (self (param p PTR "Base pointer") (param off INT "Byte offset")
                      (param width INT "Read width in bytes (1,2,4,8)"))
      (doc "Read a WIDTH-byte little-endian value at P+OFF."
        (returns INT "The value read"))
      ((prim-ref (lit ptr) (lit ref)) p off width))
    (method set! (self (param p PTR "Base pointer") (param off INT "Byte offset")
                       (param v INT "Value to store") (param width INT "Write width in bytes"))
      (doc "Write a WIDTH-byte little-endian value V at P+OFF."
        (returns ANY "nil"))
      ((prim-ref (lit ptr) (lit set!)) p off v width))
    (method ref-word (self (param p PTR "Base pointer") (param off INT "Byte offset"))
      (doc "Read one machine word (sizeof(long)) at P+OFF."
        (returns INT "The word value"))
      ((prim-ref (lit ptr) (lit ref-word)) p off))
    (method set-word! (self (param p PTR "Base pointer") (param off INT "Byte offset")
                            (param v INT "Word value to store"))
      (doc "Write one machine word V at P+OFF."
        (returns ANY "nil"))
      ((prim-ref (lit ptr) (lit set-word!)) p off v))
    (method call (self (param p PTR "C function pointer")
                       . (param args STRING "String arguments (variadic)"))
      (doc "Call a C function pointer with string arguments."
        (returns INT "The C return value"))
      (apply (prim-ref (lit ptr) (lit call)) (pair p args)))))

(def-class Ffi ()
  (static
    (method dlopen (self (param path STRING "Library file path (() for the main program)")
                         (param mode INT "dlopen mode flags (e.g. 1 = RTLD_LAZY)"))
      (doc "Load a shared library."
        (returns PTR "Library handle, or () on failure"))
      ((prim-ref (lit ffi) (lit dlopen)) path mode))
    (method dlsym (self (param lib PTR "Library handle from dlopen") (param name STRING "Symbol name"))
      (doc "Look up a symbol in a loaded library."
        (returns PTR "Function or data pointer"))
      ((prim-ref (lit ffi) (lit dlsym)) lib name))
    (method call (self (param sig STRING "Calling signature (e.g. \"d+d\", \"s0->d\")")
                       (param lib ANY "Library handle, or () for a built-in signature")
                       . (param args ANY "Call arguments (variadic)"))
      (doc "Invoke a C function through the typed-signature FFI bridge."
        (returns ANY "The converted C return value"))
      (apply (prim-ref (lit ffi) (lit call)) (pair sig (pair lib args))))))

(doc (provide x/type/ptr Ptr Ffi)
  (note "ns `ptr`/`ffi` are de-registered; low-level/hot callers fetch-and-cache the prims. int->ptr is ns `int` (Ptr from-int).")
  "Raw pointers (Ptr) and the foreign-function interface (Ffi): the FFI surface for C interop.")
