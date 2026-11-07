; obj-compiled.x -- (obj ref), (obj set!), null?, and and or compiled where
; they stand
;
; Every vector, record and object field access in the library reads or
; writes one data word through (obj ref) or (obj set!), every list walk ends
; on null?, and and and or run per arm of every test written with them.
; All five are interpreted (boot/reflect.x, boot/data.x, core/predicates.x,
; core/boolean.x).  The library binds each once, as the doors of
; x/core/doors, the prim-ref forms beside them and the globals, so a
; compiled version bound to a new name would reach no caller.  Here each is
; compiled through the assembler lane's cache door (compile-asm's own
; function) and installed into the object itself (Compiled in-place): every
; holder calls the compiled version, and the interpreted one stays on
; Compiled's list for an image write, an engine without a JIT, or a compile
; that raises.  x-core imports this module last, beside x/core/first-rest,
; so every dialect runs the compiled versions; it needs only the lane x-core
; already carries, never the cc lane's x/tool/compile.
;
; Data word I of an object is word (%obj-meta-len + I) from its address,
; and I arrives as an integer object whose value is its own first data
; word.  The bodies read and write that word as the interpreted versions
; do, with no check of either operand.  Nil is the null pointer, so null?
; compares its operand with 0 and answers the #t or #f object.
;
; and and or are operatives: each compiles as one (compile-asm's operative
; world), whose parameter is the argument list as the call wrote it, and
; evaluates an argument with %eval only when it is reached.  They answer as
; core/boolean.x's do: and gives #t for no arguments, #f at the first false
; one, and the last value otherwise; or gives nil for no arguments, the
; first true value, or the last value when none is true.

(module x/tool/obj-compiled)
(import x/tool/asm-cache asm-compile-cached)
(import x/tool/compiled)

(def %obj-compiled-ref
  (prim-ref (lit obj) (lit ref)))
(def %obj-compiled-set!
  (prim-ref (lit obj) (lit set!)))

; (o i) -> the word of O that I names, as an address offset in words.
(def %obj-compiled-word
  (list (lit +) (list (lit %mem-ref) (lit i) %obj-meta-len) %obj-meta-len))

(Compiled in-place (lit obj-ref) %obj-compiled-ref
  (fn (_)
    (asm-compile-cached
      (list (lit fn) (lit (_ o i)) (list (lit %mem-ref-at) (lit o) %obj-compiled-word))
      () (lit object))))

(Compiled in-place (lit obj-set!) %obj-compiled-set!
  (fn (_)
    (asm-compile-cached
      (list (lit fn) (lit (_ o i v)) (list (lit %mem-set-at!) (lit o) %obj-compiled-word (lit v)))
      () (lit object))))

(Compiled in-place (lit null?) null?
  (fn (_)
    (asm-compile-cached (lit (fn (_ x) (if (= x ()) t f)))
      (list (pair (lit t) #t) (pair (lit f) #f)) (lit object))))

(Compiled in-place (lit and) and
  (fn (_)
    (asm-compile-cached
      (lit (fn (self l)
             (match
               ((= l ()) t)
               ((= (rest l) ()) (%eval (first l)))
               ((%eval (first l)) (self (rest l)))
               (#t f))))
      (list (pair (lit t) #t) (pair (lit f) #f)) (lit operative))))

(Compiled in-place (lit or) or
  (fn (_)
    (asm-compile-cached
      (lit (fn (self l)
             (match
               ((= l ()) ())
               ((= (rest l) ()) (%eval (first l)))
               (#t (or (%eval (first l)) (self (rest l)))))))
      () (lit operative))))

(doc (provide x/tool/obj-compiled)
  "Compiles (obj ref), (obj set!), null?, and and or, and installs each into its own object, so every holder of any of them calls the compiled version.")
