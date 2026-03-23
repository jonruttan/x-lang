; asm-compile.x -- JIT compiler: x-lang expressions to native machine code
; Uses the assembler (lib/x/asm.x) instead of shelling out to cc.
(import x/list)
(import x/asm)

; Object layout constants
(def %data-offset (* %word-size 3))   ; offset to first data slot (meta=3 slots)
(def %rest-offset (* %word-size 4))   ; offset to second data slot (rest/cdr)

; --- Forward declarations for mutual recursion ---
(def %asm-compile-expr ())
(def %asm-compile-param ())
(def %asm-compile-call ())
(def %asm-compile-binop ())
(def %asm-compile-mod ())
(def %asm-compile-if ())

; --- Code generation ---
; Walk expression tree, emit instructions.
; Convention: result always in x0.
; p_base in x19 (callee-saved), p_args in x20 (callee-saved).

; Emit code for an expression. Returns nothing (emits into asm buffer).
(set! %asm-compile-expr
  (fn (_ asm expr params)
    (if (number? expr)
      ; Integer literal: mov x0, #N
      (asm-emit! asm (lit mov) x0 (imm expr))

      (if (symbol? expr)
        ; Parameter reference: load from args list
        (%asm-compile-param asm expr params)

        (if (pair? expr)
          ; Function call / special form
          (%asm-compile-call asm expr params)

          ; Unsupported
          (error (str "asm-compile: unsupported expression: "
            (write-to-string expr))))))))

; Compile parameter access: params are in registers x2..x7
; (passed as ptr-call args 2..7, after the base/args slots)
; Param 0 -> x2, Param 1 -> x3, etc. (shifted by 2 from the raw ptr-call args)
; But we saved raw args starting at known positions via the wrapper.
; Simpler: params are at x20+N*8 in a pre-built array.
; Actually simplest: param N is at stack offset from a saved array pointer.
;
; New approach: the wrapper calls ptr-call with up to 5 raw int args.
; ptr-call(fn, arg0, arg1, arg2, arg3, arg4, arg5, arg6)
; ARM64 calling convention: x0=fn-result, x0..x7 are arg registers
; ptr-call puts: x0=fn_ptr (consumed by dispatch), x1=arg0, x2=arg1, ...
; So inside the JIT function: x0=base(unused), x1=arg0, x2=arg1, ...
; Wait: ptr-call signature is (ptr-call fptr a1 a2 a3 a4 a5 a6 a7)
; The JIT function receives: x0=a1, x1=a2, x2=a3, ...
; No wait: C calling convention on ARM64:
; ptr-call calls fn(a1, a2, a3, a4, a5, a6, a7)
; so x0=a1, x1=a2, x2=a3, x3=a4, x4=a5, x5=a6, x6=a7

; We'll make the wrapper call: ptr-call(raw-fn, param0, param1, ...)
; Inside JIT: param0 in x0, param1 in x1, etc.
; This is the simplest approach — no object access needed in JIT code.

(set! %asm-compile-param
  (fn (_ asm name params)
    (def %find
      (fn (_ ps idx)
        (if (null? ps)
          (error (str "asm-compile: unbound parameter: " (symbol->string name)))
          (if (eq? name (first ps))
            idx
            (%find (rest ps) (+ idx 1))))))
    (def idx (%find params 0))
    ; Param idx maps directly to register: x0=param0, x1=param1, ...
    ; But x0/x1 are also used as scratch. Save params in x19+ at prologue.
    ; Actually, the prologue saves x0→x19, x1→x20. We need more for params.
    ; New approach: params are at fixed registers, just mov to x0.
    ; The wrapper ensures params go into x0, x1, x2, etc.
    ; After prologue: x19=original x0 (param0), x20=original x1 (param1)
    ; For more params, we'd need to save x2→x21, x3→x22, etc.
    (if (= idx 0) (asm-emit! asm (lit mov) x0 x19)
      (if (= idx 1) (asm-emit! asm (lit mov) x0 x20)
        (if (= idx 2) (asm-emit! asm (lit mov) x0 x21)
          (if (= idx 3) (asm-emit! asm (lit mov) x0 x22)
            (error "asm-compile: max 4 parameters supported")))))))

; Compile a call expression
(set! %asm-compile-call
  (fn (_ asm expr params)
    (def op (first expr))
    (def args (rest expr))

    (if (eq? op (lit +))
      (%asm-compile-binop asm (lit add) args params)
      (if (eq? op (lit -))
        (if (null? (rest args))
          ; Unary negate: 0 - x
          (do
            (%asm-compile-expr asm (first args) params)
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
                (error (str "asm-compile: unsupported form: "
                  (symbol->string op)))))))))))

; Compile binary operation: eval left, push to stack, eval right, pop, combine
(set! %asm-compile-binop
  (fn (_ asm insn args params)
    ; Evaluate left operand -> x0
    (%asm-compile-expr asm (first args) params)
    ; Push x0 to stack (str x0, [sp, #-16]!)
    (%emit-u32-le! asm 4162785248)   ; 0xF81F0FE0 = STR x0, [sp, #-16]!
    ; Evaluate right operand -> x0 (may clobber x21)
    (%asm-compile-expr asm (first (rest args)) params)
    ; Move right to x1
    (asm-emit! asm (lit mov) x1 x0)
    ; Pop left from stack into x0 (ldr x0, [sp], #16)
    (%emit-u32-le! asm 4165011424)   ; 0xF84107E0 = LDR x0, [sp], #16
    ; Combine: x0 = x0 op x1
    (asm-emit! asm insn x0 x0 x1)))

; Compile modulo: a % b = a - (a/b)*b
; Uses SDIV + MSUB with stack for safety
(set! %asm-compile-mod
  (fn (_ asm args params)
    ; Evaluate left -> x0, push to stack
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm 4162785248)     ; push x0
    ; Evaluate right -> x0
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm (lit mov) x1 x0)   ; right in x1
    (%emit-u32-le! asm 4165011424)     ; pop left into x0
    ; x2 = x0 / x1 (quotient)
    (asm-emit! asm (lit sdiv) x2 x0 x1)
    ; x0 = x0 - x2 * x1 (remainder via MSUB)
    (asm-emit! asm (lit msub) x0 x2 x1 x0)))

; Compile if: (if test then else)
; Evaluate test, compare to nil/false, branch
(set! %asm-compile-if
  (fn (_ asm args params)
    (def test-expr (first args))
    (def then-expr (first (rest args)))
    (def else-expr (if (null? (rest (rest args))) 0 (first (rest (rest args)))))

    ; Comparison operators: map op to inverse branch
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
        ; Evaluate left of comparison -> x21
        (%asm-compile-expr asm (first cmp-args) params)
        (asm-emit! asm (lit mov) x21 x0)
        ; Evaluate right of comparison -> x0
        (%asm-compile-expr asm (first (rest cmp-args)) params)
        ; Compare and branch to else if NOT true
        (asm-emit! asm (lit cmp) x21 x0)
        (asm-emit! asm (%cmp-branch cmp-op) (label (lit %else)))
        ; Then branch
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm (lit b) (label (lit %end)))
        ; Else branch
        (asm-label! asm (lit %else))
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm (lit %end)))

      ; Non-comparison if: test for nil (NULL = 0)
      (do
        (%asm-compile-expr asm test-expr params)
        (asm-emit! asm (lit cbz) x0 (label (lit %else)))
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm (lit b) (label (lit %end)))
        (asm-label! asm (lit %else))
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm (lit %end)))))))

; --- Public API ---

; compile-asm: (compile-asm '(fn (_ params...) body)) -> x-lang callable
; The JIT'd function operates on raw integers. A wrapper handles
; x-lang object boxing/unboxing.
(doc (def compile-asm
  (fn (_ expr)
    (if (not (eq? (first expr) (lit fn)))
      (error "compile-asm: expression must be (fn (_ params...) body)"))
    (def fn-params (first (rest expr)))
    (def fn-body (first (rest (rest expr))))
    ; Skip self param (_)
    (def params (rest fn-params))
    (def nparams (length params))

    (def asm (asm-new))
    ; Prologue: save callee-saved registers
    (asm-prologue! asm)
    ; Save input params (x0..x3) to callee-saved regs (x19..x22)
    (if (>= nparams 1) (asm-emit! asm (lit mov) x19 x0) ())
    (if (>= nparams 2) (asm-emit! asm (lit mov) x20 x1) ())
    (if (>= nparams 3) (asm-emit! asm (lit mov) x21 x2) ())
    (if (>= nparams 4) (asm-emit! asm (lit mov) x22 x3) ())

    ; Compile the body — result (raw integer) in x0
    (%asm-compile-expr asm fn-body params)

    ; Epilogue: restore frame, return raw integer
    (asm-epilogue! asm)

    (def raw-fn (asm-finalize! asm))

    ; Return a closure that wraps the JIT function.
    ; Extracts integer values from x-lang args, passes as raw longs,
    ; returns raw integer result.
    (if (= nparams 0)
      (fn (_ . call-args) (ptr-call raw-fn))
      (if (= nparams 1)
        (fn (_ . call-args) (ptr-call raw-fn (nth 0 call-args)))
        (if (= nparams 2)
          (fn (_ . call-args)
            (ptr-call raw-fn (nth 0 call-args) (nth 1 call-args)))
          (if (= nparams 3)
            (fn (_ . call-args)
              (ptr-call raw-fn (nth 0 call-args) (nth 1 call-args)
                               (nth 2 call-args)))
            (fn (_ . call-args)
              (ptr-call raw-fn (nth 0 call-args) (nth 1 call-args)
                               (nth 2 call-args) (nth 3 call-args)))))))))
  (returns CALLABLE "X-lang callable that JIT-executes the body")
  "JIT compile an x-lang (fn ...) expression to native machine code.")

(doc (provide x/asm-compile compile-asm)
  "JIT compiler: x-lang to native code via assembler.")
