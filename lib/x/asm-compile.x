; asm-compile.x -- JIT compiler: x-lang expressions to native machine code
; Produces proper x-lang prims that work with map, fold, closures, etc.
(import x/list)
(import x/asm)

; --- Resolve JIT runtime functions ---
(def %jit-lib (dlopen () 1))
(def %jit-mkint    (ptr->int (dlsym %jit-lib "jit_mkint")))
(def %jit-mkpair   (ptr->int (dlsym %jit-lib "jit_mkpair")))
(def %jit-firstobj (ptr->int (dlsym %jit-lib "jit_firstobj")))
(def %jit-restobj  (ptr->int (dlsym %jit-lib "jit_restobj")))
(def %jit-atomint  (ptr->int (dlsym %jit-lib "jit_atomint")))
(def %jit-eval-arg (ptr->int (dlsym %jit-lib "jit_eval_arg")))

; --- Emit helpers: call a JIT runtime function ---
; Loads address into x8, calls via BLR. Preserves x19 (p_base), x20 (p_args).
(def %emit-call-jit!
  (fn (_ asm addr)
    (asm-load-imm64! asm x8 addr)
    (asm-emit! asm (lit blr) x8)))

; Stack push/pop constants
(def %PUSH 4162785248)   ; STR x0, [sp, #-16]!
(def %POP  4165011424)   ; LDR x0, [sp], #16

; --- Forward declarations ---
(def %asm-compile-expr ())
(def %asm-compile-param ())
(def %asm-compile-call ())
(def %asm-compile-binop ())
(def %asm-compile-mod ())
(def %asm-compile-if ())
(def %asm-compile-funcall ())
(def %asm-self-cell ())
(def %asm-label-counter 0)

; Generate unique label names (for nested if/else)
(def %asm-genlabel
  (fn (_ prefix)
    (set! %asm-label-counter (+ %asm-label-counter 1))
    (string->symbol (str prefix (number->string %asm-label-counter)))))

; --- Code generation ---
; Convention: result always in x0 as a RAW INTEGER.
; x19 = p_base (callee-saved), x20 = p_args (callee-saved).
; All intermediate values are raw integers; boxing happens at the end.

; Emit code for an expression
(set! %asm-compile-expr
  (fn (_ asm expr params)
    (if (number? expr)
      (asm-emit! asm (lit mov) x0 (imm expr))
      (if (symbol? expr)
        (%asm-compile-param asm expr params)
        (if (pair? expr)
          (%asm-compile-call asm expr params)
          (error (str "asm-compile: unsupported: " (write-to-string expr))))))))

; Compile parameter access from x-lang args list
; p_args = (self arg0 arg1 ...) — walk rest N+1 times, first, eval, atomint
(set! %asm-compile-param
  (fn (_ asm name params)
    (def %find
      (fn (_ ps idx)
        (if (null? ps)
          (error (str "asm-compile: unbound: " (symbol->string name)))
          (if (eq? name (first ps)) idx (%find (rest ps) (+ idx 1))))))
    (def idx (%find params 0))
    ; Start from p_args (x20)
    (asm-emit! asm (lit mov) x0 x20)
    ; Skip self + idx args: (idx + 1) rest calls
    (def %skip
      (fn (_ n)
        (if (< n 0) ()
          (do (%emit-call-jit! asm %jit-restobj) (%skip (- n 1))))))
    (%skip idx)
    ; first -> get the expression
    (%emit-call-jit! asm %jit-firstobj)
    ; eval_arg(p_base, expr) -> evaluate it
    (asm-emit! asm (lit mov) x1 x0)
    (asm-emit! asm (lit mov) x0 x19)
    (%emit-call-jit! asm %jit-eval-arg)
    ; atomint -> raw integer
    (%emit-call-jit! asm %jit-atomint)))

; Compile a call expression
(set! %asm-compile-call
  (fn (_ asm expr params)
    (def op (first expr))
    (def args (rest expr))
    (if (eq? op (lit +))
      (%asm-compile-binop asm (lit add) args params)
      (if (eq? op (lit -))
        (if (null? (rest args))
          (do (%asm-compile-expr asm (first args) params)
              (asm-emit! asm (lit sub) x0 xzr x0))
          (%asm-compile-binop asm (lit sub) args params))
        (if (eq? op (lit *))
          (%asm-compile-binop asm (lit mul) args params)
          (if (eq? op (lit /))
            (%asm-compile-binop asm (lit sdiv) args params)
            (if (eq? op (lit %))
              (%asm-compile-mod asm args params)
              (if (eq? op (lit if))
                (%asm-compile-if asm args params)
                (%asm-compile-funcall asm op args params)))))))))

; Binary operation: push left, eval right, pop left, combine
(set! %asm-compile-binop
  (fn (_ asm insn args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm (lit mov) x1 x0)
    (%emit-u32-le! asm %POP)
    (asm-emit! asm insn x0 x0 x1)))

; Modulo: SDIV + MSUB
(set! %asm-compile-mod
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm (lit mov) x1 x0)
    (%emit-u32-le! asm %POP)
    (asm-emit! asm (lit sdiv) x2 x0 x1)
    (asm-emit! asm (lit msub) x0 x2 x1 x0)))

; If: with comparison operators or nil test
(set! %asm-compile-if
  (fn (_ asm args params)
    (def test-expr (first args))
    (def then-expr (first (rest args)))
    (def else-expr (if (null? (rest (rest args))) 0 (first (rest (rest args)))))
    (def lbl-else (%asm-genlabel "%else"))
    (def lbl-end  (%asm-genlabel "%end"))

    (def %cmp-branch
      (fn (_ op)
        (if (eq? op (lit =))  (lit b/ne)
          (if (eq? op (lit <))  (lit b/ge)
            (if (eq? op (lit >))  (lit b/le)
              (if (eq? op (lit <=)) (lit b/gt)
                (if (eq? op (lit >=)) (lit b/lt)
                  ())))))))

    (if (and (pair? test-expr) (not (null? (%cmp-branch (first test-expr)))))
      (do
        (def cmp-op (first test-expr))
        (def cmp-args (rest test-expr))
        (%asm-compile-expr asm (first cmp-args) params)
        (%emit-u32-le! asm %PUSH)
        (%asm-compile-expr asm (first (rest cmp-args)) params)
        (asm-emit! asm (lit mov) x1 x0)
        (%emit-u32-le! asm %POP)
        (asm-emit! asm (lit cmp) x0 x1)
        (asm-emit! asm (%cmp-branch cmp-op) (label lbl-else))
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm (lit b) (label lbl-end))
        (asm-label! asm lbl-else)
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm lbl-end))
      (do
        (%asm-compile-expr asm test-expr params)
        (asm-emit! asm (lit cbz) x0 (label lbl-else))
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm (lit b) (label lbl-end))
        (asm-label! asm lbl-else)
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm lbl-end)))))

; Self-recursive call via trampoline
; The trampoline cell holds the prim's address. Save/restore x19/x20
; across the call since the callee uses them too.
(set! %asm-compile-funcall
  (fn (_ asm fn-name args params)
    (if (null? %asm-self-cell)
      (error (str "asm-compile: unknown function: " (symbol->string fn-name))))
    (def nargs (length args))

    ; The recursive call goes through the SAME code, which uses the x-lang ABI.
    ; We need to build a proper arg list: (prim arg0-atom arg1-atom ...)
    ; Then call through the prim's fn-ptr with (p_base, arg-list).

    ; Evaluate each arg to raw integer, push to stack
    (for-each
      (fn (_ arg)
        (%asm-compile-expr asm arg params)
        (%emit-u32-le! asm %PUSH))
      args)

    ; Build the arg list by boxing each raw int and consing
    ; Start with nil, pop args in reverse order, mkint + mkpair
    (asm-emit! asm (lit mov) x0 (imm 0))  ; nil (accumulator)
    (def %build
      (fn (_ i)
        (if (< i 0) ()
          (do
            ; Save current list on stack
            (%emit-u32-le! asm %PUSH)
            ; Pop raw value
            (%emit-u32-le! asm (| %POP 1))  ; x1 = raw value
            ; Save x1 (raw val), restore list
            (%emit-u32-le! asm %PUSH)        ; push x0 (don't need, x1 has val)
            ; Oops, need to: pop raw -> x1, then mkint(p_base, x1) -> x0 = atom
            ; then mkpair(p_base, atom, list) -> x0 = new list
            ; But we need the list in x2. Let me use stack differently:

            ; At this point: stack has [raw_val] [... more raw vals ...]
            ; x0 = list-so-far
            ; Save list, pop raw, mkint, mkpair

            ; Actually let me redo the stack:
            ; After initial loop, stack has: [argN-1] ... [arg0] (arg0 on top)
            ; After starting with nil, we need to pop arg0, mkint, mkpair(atom, nil)
            ; then pop arg1, mkint, mkpair(atom, list), etc.
            ; But we pushed left-to-right, so arg0 is DEEPEST, argN-1 is on top.
            ; Pop gives us argN-1 first. We want to build list right-to-left:
            ; (pair argN-1 nil), (pair argN-2 prev), ... (pair arg0 prev)
            ; This builds (arg0 arg1 ... argN-1) — correct!

            ; x0 = list-so-far. Save on stack, pop raw value
            (%emit-u32-le! asm %PUSH)          ; push list
            ; Stack: [list] [raw_val] ...
            ; We need raw_val. It's at [sp, #16]. Swap:
            ; pop list -> x3, pop raw -> x1, push list back
            (%emit-u32-le! asm (| %POP 3))     ; x3 = list
            (%emit-u32-le! asm %POP)           ; x0 = raw val
            (asm-emit! asm (lit mov) x1 x0)    ; x1 = raw
            ; push list and raw_val atom pointers will be in x0 after mkint
            ; Save list on stack
            (asm-emit! asm (lit mov) x0 x3)
            (%emit-u32-le! asm %PUSH)          ; push list
            ; mkint(p_base, raw_val)
            (asm-emit! asm (lit mov) x0 x19)   ; x0 = p_base (x1 = raw already)
            (%emit-call-jit! asm %jit-mkint)   ; x0 = atom
            ; mkpair(p_base, atom, list)
            (asm-emit! asm (lit mov) x1 x0)    ; x1 = atom
            (%emit-u32-le! asm (| %POP 2))     ; x2 = list (pop from stack)
            (asm-emit! asm (lit mov) x0 x19)   ; x0 = p_base
            (%emit-call-jit! asm %jit-mkpair)  ; x0 = (atom . list)
            (%build (- i 1))))))
    (%build (- nargs 1))

    ; x0 = arg list (arg0 arg1 ... argN-1)
    ; Prepend self (nil placeholder): mkpair(p_base, nil, args)
    (asm-emit! asm (lit mov) x2 x0)           ; x2 = args
    (asm-emit! asm (lit mov) x1 (imm 0))      ; x1 = nil (self placeholder)
    (asm-emit! asm (lit mov) x0 x19)           ; x0 = p_base
    (%emit-call-jit! asm %jit-mkpair)          ; x0 = (nil . args) = p_args for call

    ; Save p_base/p_args, set up call
    (asm-emit! asm (lit mov) x1 x0)           ; x1 = new p_args
    (asm-emit! asm (lit mov) x0 x19)          ; x0 = p_base

    ; Load self address from trampoline
    (asm-load-imm64! asm x8 (ptr->int %asm-self-cell))
    (asm-emit! asm (lit ldr) x8 (mem 8 0))
    (asm-emit! asm (lit blr) x8)

    ; x0 = result (already a boxed x-lang object from mkint in the callee)
    ; Unbox it back to raw integer for our caller
    (%emit-call-jit! asm %jit-atomint)))

; --- Public API ---

(doc (def compile-asm
  (fn (_ expr)
    (if (not (eq? (first expr) (lit fn)))
      (error "compile-asm: expression must be (fn (_ params...) body)"))
    (def fn-params (first (rest expr)))
    (def fn-body (first (rest (rest expr))))
    (def params (rest fn-params))  ; skip self (_)
    (def nparams (length params))

    ; Allocate trampoline cell for self-recursion
    (def c-malloc (dlsym %jit-lib "malloc"))
    (def self-cell (ptr-call c-malloc 8))
    (ptr-set-word! self-cell 0 0)
    (set! %asm-self-cell self-cell)

    (def asm (asm-new))

    ; Prologue: save callee-saved registers
    (asm-prologue! asm)
    ; Save p_base and p_args
    (asm-emit! asm (lit mov) x19 x0)    ; p_base
    (asm-emit! asm (lit mov) x20 x1)    ; p_args

    ; Compile body — result is a raw integer in x0
    (%asm-compile-expr asm fn-body params)

    ; Box result: mkint(p_base, raw_result)
    (asm-emit! asm (lit mov) x1 x0)     ; x1 = raw result
    (asm-emit! asm (lit mov) x0 x19)    ; x0 = p_base
    (%emit-call-jit! asm %jit-mkint)

    ; Epilogue
    (asm-epilogue! asm)

    (def raw-fn (asm-finalize! asm))

    ; Patch trampoline with actual address
    (ptr-set-word! self-cell 0 (ptr->int raw-fn))
    (set! %asm-self-cell ())

    ; Create proper x-lang prim
    (jit-make-prim raw-fn)))
  (returns CALLABLE "X-lang callable prim")
  "JIT compile an x-lang (fn ...) expression to a native prim.
   The compiled function works with map, fold, closures, etc.")

(doc (provide x/asm-compile compile-asm)
  "JIT compiler: x-lang to native code via assembler.")
