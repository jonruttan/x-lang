; callback.x -- Callback: a C function pointer that calls an x function
;
; A C library that takes a function pointer -- qsort's comparator, bsearch's,
; atexit's handler -- calls native code.  (Callback make f nargs) writes a
; small native function, a stub, that a C caller calls like any other: it
; takes NARGS integer or pointer arguments in the C calling convention,
; makes each an x integer, evaluates (F a ...) in the base the callback was
; made in, and answers the result as a C long.  (cb address) is the stub's
; address, the integer to hand the library.
;
; The stub reaches the interpreter through the engine's JIT doors --
; jit_mkint, jit_mkpair, jit_call_value, jit_eval_arg, jit_atomint -- whose
; addresses, the base's, the function's and the pair prim's are written into
; it as immediates.  So the function must stay alive while the address is in
; use: the Callback holds it, and the caller holds the Callback.  It is
; written with x/tool/asm's
; portable registers, the same on arm64 and x86-64 but for where the C
; convention puts the third and fourth arguments.
;
; F answers an integer, which is the C result; #t is 1, and anything else
; -- nil from a function called for its effect -- is 0.  An error raised in
; F unwinds through the C caller's frames, which a caller in the middle of
; its own work may not survive: a callback that can fail should catch its
; own errors.
;
; The stub is process state, as compiled code is: make registers a
; transient that frees it before a state image is written, and a recache
; hook that writes it again after a load, at a new address.

(module x/sys/callback)
(import x/type/class)
(import x/tool/asm)

(def-class Callback ()
  (doc "A C function pointer that calls an x function: (Callback make f nargs), then hand (cb address) to a C library that takes a function pointer."
    (note "The C caller passes up to four integer or pointer arguments; F gets each as an integer and answers the C result, #t as 1 and anything else that is not an integer as 0.")
    (note "Keep the Callback while the library may call the address: it holds F, and the stub reaches F through its address.")
    (note "An error raised in F unwinds through the C caller's frames; a callback that can fail should catch its own errors.")
    (sample "(Callback make (fn (_ a b) (- a b)) 2)" "a comparator a C library can call"))
  (doc (target ()) "The function the stub calls: the one made with, answering its result as an integer")
  (doc (nargs 0) "How many arguments the C caller passes, 0 to 4")
  (doc (asm ()) "The assembler buffer the stub was written into, or nil between an image write and its load")
  (doc (address 0) "The stub's address, the integer to hand a C library; 0 between an image write and its load")

  (method remake! (self)
    (doc "Write the stub again -- what the recache hook does after an image load; a consumer never needs to call it."
      (returns INTEGER "The stub's new address"))
    (self free!)
    (self asm (Callback %write (self target) (self nargs)))
    (self address ((Callback %ptr->int) (asm-finalize! (self asm))))
    (self address))

  (method free! (self)
    (doc "Release the stub.  The address is not callable afterwards."
      (returns ANY "nil"))
    (if (null? (self asm)) () (asm-free! (self asm)))
    (self asm ())
    (self address 0)
    ())

  (static
    ; --- the catalogue doors, fetched once at load ------------------------------
    (%dlopen (prim-ref (lit ffi) (lit dlopen)))
    (%dlsym (prim-ref (lit ffi) (lit dlsym)))
    (%ptr->int (prim-ref (lit ptr) (lit ->int)))
    (%obj->ptr (prim-ref (lit obj) (lit ->ptr)))
    (%transient! (prim-ref (lit image) (lit transient!)))
    (%recache-hook! (prim-ref (lit image) (lit recache-hook!)))

    (method make (self (param f CALLABLE "The x function to call, taking NARGS integers")
                       (param nargs INTEGER "How many arguments the C caller passes, 0 to 4"))
      (doc "A C function pointer that calls f: the stub is written and its address is (cb address)."
        (returns Callback "The callback")
        (sample "(let ((cb (Callback make (fn (_ a b) (- a b)) 2))) (cb address))" "an integer address"))
      (if (if (< nargs 0) #t (> nargs 4))
        (Err raise (lit value) "Callback make: a C caller passes 0 to 4 arguments" ()))
      ; the result as a C long: an integer, #t as 1, anything else as 0
      (def wrapped
        (fn (_ . args)
          (let ((r (apply f args)))
            (if (number? r) r (if (eq? r #t) 1 0)))))
      (let ((target wrapped) (asm ()) (address 0))
        (def cb (new Callback target target nargs nargs asm asm address address))
        (cb remake!)
        ((Callback %transient!) (fn (_) (cb free!)))
        ((Callback %recache-hook!) (fn (_) (cb remake!)))
        cb))

    ; the address of the engine's JIT door NAME
    (method %door (self name)
      (def p ((Callback %dlsym) ((Callback %dlopen) () 1) name))
      (if (null? p) (Err raise (lit state) "Callback: this engine has no JIT door for a stub" ()))
      ((Callback %ptr->int) p))

    ; Write a stub calling F with NARGS arguments into a new buffer, not yet
    ; finalized.  The C arguments are kept in x19-x22, which the prologue
    ; saves and the C convention has a callee keep; the argument list is
    ; built from the last argument back, its tail on the stack across each
    ; call; then the call is made and its value unboxed into x0.
    (method %write (self f nargs)
      (def base ((Callback %ptr->int) ((Callback %obj->ptr) (%base))))
      (def at ((Callback %ptr->int) ((Callback %obj->ptr) f)))
      (def mkint (Callback %door "jit_mkint"))
      (def mkpair (Callback %door "jit_mkpair"))
      (def call-value (Callback %door "jit_call_value"))
      (def eval-arg (Callback %door "jit_eval_arg"))
      (def pair-at ((Callback %ptr->int) ((Callback %obj->ptr) pair)))
      (def atomint (Callback %door "jit_atomint"))
      ; where the C convention puts the arguments, past the prologue: arm64's
      ; x0-x3; x86-64's rdi (the prologue's x0), rsi (x1), rdx and rcx
      (def args-in (if arch-arm64? (list x0 x1 (reg 2) (reg 3)) (list x0 x1 (reg 2) (reg 1))))
      (def keep (list x19 x20 x21 x22))
      (def a (asm-new 1024))
      (def call (fn (_ addr) (do (asm-load-imm64! a x8 addr) (asm-emit! a (lit blr) x8))))
      (def nth (fn (self l i) (if (= i 0) (first l) (self (rest l) (- i 1)))))
      (def save
        (fn (self i)
          (if (< i nargs)
            (do (asm-emit! a (lit mov) (nth keep i) (nth args-in i)) (self (+ i 1)))
            ())))
      ; the tail on the stack: the argument I boxed, paired onto it
      (def build
        (fn (self i)
          (if (< i 0) ()
            (do (asm-emit! a (lit mov) x1 (nth keep i))
                (asm-load-imm64! a x0 base)
                (call mkint)
                (asm-emit! a (lit mov) x1 x0)
                (asm-pop! a x2)
                (asm-load-imm64! a x0 base)
                (call mkpair)
                (asm-push! a x0)
                (self (- i 1))))))
      (asm-prologue! a)
      (save 0)
      (asm-emit! a (lit mov) x0 (imm 0))
      (asm-push! a x0)
      (build (- nargs 1))
      ; The call (F . ARGS), evaluated, its value unboxed.  The pairs
      ; jit_mkpair makes carry no type, and such an object evaluates to
      ; itself, so the call's own pair comes from the pair prim, called
      ; through jit_call_value as (pair F ARGS): the prim evaluates its
      ; arguments, and F, an object, and ARGS, typeless, are themselves.
      ; jit_eval_arg then runs the call to its end, a tail call included.
      (asm-pop! a x1)
      (asm-emit! a (lit mov) x2 (imm 0))
      (asm-load-imm64! a x0 base)
      (call mkpair)
      (asm-emit! a (lit mov) x2 x0)
      (asm-load-imm64! a x1 at)
      (asm-load-imm64! a x0 base)
      (call mkpair)
      (asm-emit! a (lit mov) x2 x0)
      (asm-load-imm64! a x1 pair-at)
      (asm-load-imm64! a x0 base)
      (call mkpair)
      (asm-emit! a (lit mov) x1 x0)
      (asm-load-imm64! a x0 base)
      (call call-value)
      (asm-emit! a (lit mov) x1 x0)
      (asm-load-imm64! a x0 base)
      (call eval-arg)
      (call atomint)
      (asm-epilogue! a)
      a)))

(doc (provide x/sys/callback Callback)
  "C function pointers that call x functions: a stub per callback, for a C library that takes a function pointer.")
