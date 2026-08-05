; asm-compile.x -- JIT compiler: x-lang expressions to native machine code
; Produces proper x-lang prims that work with map, fold, closures, etc.
(import x/core/list)
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj->ptr (prim-ref 'obj '->ptr))
(def %make-callable (prim-ref 'obj 'make-callable))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str->symbol (prim-ref 'str '->sym))

(import x/tool/asm)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->int (prim-ref 'ptr '->int))
(def %ptr-set-word! (prim-ref 'ptr 'set-word!))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))



; --- Resolve JIT runtime helpers (non-variadic wrappers in jit.c) ---
(def %jit-lib (%dlopen () 1))
(def %jit-mkint    (%ptr->int (%dlsym %jit-lib "jit_mkint")))
(def %jit-mkpair   (%ptr->int (%dlsym %jit-lib "jit_mkpair")))
(def %jit-firstobj (%ptr->int (%dlsym %jit-lib "jit_firstobj")))
(def %jit-restobj  (%ptr->int (%dlsym %jit-lib "jit_restobj")))
(def %jit-atomint  (%ptr->int (%dlsym %jit-lib "jit_atomint")))
(def %jit-eval-arg (%ptr->int (%dlsym %jit-lib "jit_eval_arg")))
(def %jit-build-args (%ptr->int (%dlsym %jit-lib "jit_build_args")))
(def %jit-make-callable (%dlsym %jit-lib "jit_make_prim"))
(def %jit-score-set (%ptr->int (%dlsym %jit-lib "jit_score_set")))
(def %jit-buffer-unread (%ptr->int (%dlsym %jit-lib "jit_buffer_unread")))
(def %jit-buffer-len (%ptr->int (%dlsym %jit-lib "jit_buffer_len")))

; Stack push/pop constants
(def %PUSH 4162785248)   ; STR x0, [sp, #-16]!
(def %POP  4165011424)   ; LDR x0, [sp], #16

; --- Emit helpers: call JIT runtime functions ---
; All use BLR x8. Preserves x19 (p_base), x20 (p_args).

(def %emit-call!
  (fn (_ asm addr)
    (asm-load-imm64! asm x8 addr)
    (asm-emit! asm 'blr x8)))

; jit_firstobj(p): x0 = firstobj(x0)
(def %emit-firstobj!
  (fn (_ asm)
    (%emit-call! asm %jit-firstobj)))

; jit_restobj(p): x0 = restobj(x0)
(def %emit-restobj!
  (fn (_ asm)
    (%emit-call! asm %jit-restobj)))

; jit_atomint(p): x0 = atomint(x0) (raw integer)
(def %emit-atomint!
  (fn (_ asm)
    (%emit-call! asm %jit-atomint)))

; jit_mkint(base, value): x0 = boxed atom. Expects x1 = raw value.
(def %emit-mkint!
  (fn (_ asm)
    (asm-emit! asm 'mov x1 x0)     ; x1 = raw value
    (asm-emit! asm 'mov x0 x19)    ; x0 = p_base
    (%emit-call! asm %jit-mkint)))

; jit_mkpair(base, a, b): x0 = pair. Expects x1 = a, x2 = b.
(def %emit-mkpair!
  (fn (_ asm)
    (asm-emit! asm 'mov x0 x19)    ; x0 = p_base
    (%emit-call! asm %jit-mkpair)))

; jit_eval_arg(base, expr): x0 = eval'd. Expects x0 = base, x1 = expr.
(def %emit-eval-arg!
  (fn (_ asm)
    (%emit-call! asm %jit-eval-arg)))

; --- Forward declarations ---
(def %asm-compile-expr ())
(def %asm-compile-param ())
(def %asm-compile-call ())
(def %asm-compile-binop ())
(def %asm-compile-mod ())
(def %asm-compile-if ())
(def %asm-compile-funcall ())
(def %asm-self-cell ())
; The name bound to the function being compiled (its self parameter).
; Only a call to THAT name is self-recursion; anything else is an
; unsupported form and must say so -- see %asm-compile-funcall.
(def %asm-self-name ())
(def %asm-label-counter 0)

; Generate unique label names (for nested if/else)
(def %asm-genlabel
  (fn (_ prefix)
    (set! %asm-label-counter (+ %asm-label-counter 1))
    (%str->symbol (Str append prefix (%number->str %asm-label-counter)))))

; --- Code generation ---
; Convention: result always in x0 as a RAW INTEGER.
; x19 = p_base (callee-saved), x20 = p_args (callee-saved).
; All intermediate values are raw integers; boxing happens at the end.

; Emit code for an expression
(set! %asm-compile-expr
  (fn (_ asm expr params)
    (if (null? expr)
      (asm-emit! asm 'mov x0 (imm 0))    ; nil = NULL = 0
      (if (number? expr)
        ; `mov Xd, #imm` is MOVZ: 16 bits, and the encoder MASKS the rest
        ; away (& val 65535) -- so a literal above 65535 silently compiled
        ; to a wrong constant ((+ x 100000) computed x + 34464, no error).
        ; Anything that does not fit takes the MOVZ+MOVK sequence instead;
        ; negatives too, whose two's complement needs all four halfwords.
        (if (and (>= expr 0) (<= expr 65535))
          (asm-emit! asm 'mov x0 (imm expr))
          (asm-load-imm64! asm x0 expr))
        (if (symbol? expr)
          (%asm-compile-param asm expr params)
          (if (pair? expr)
            (%asm-compile-call asm expr params)
            (Err raise 'value (Str append "asm-compile: unsupported: " (%write-to-str expr)) ())))))))

; Compile parameter access from x-lang args list
; p_args = (self arg0 arg1 ...) — walk rest N+1 times, first, eval, atomint
; If symbol is a free variable (fvar), load its pointer as a 64-bit immediate.
(set! %asm-compile-param
  (fn (_ asm name params)
    (def %find
      (fn (self ps idx)
        (if (null? ps)
          (Err raise 'value (Str append "asm-compile: unbound: " (symbol->str name)) ())
          (if (eq? name (first ps)) idx (self (rest ps) (+ idx 1))))))
    ; Check fvars first (before params, since fvar symbols may shadow)
    (def fv-entry (%compile-fvar-lookup name))
    (if (not (null? fv-entry))
      ; Load fvar pointer as raw 64-bit immediate
      (let ((val (rest fv-entry)))
        (if (null? val)
          (asm-emit! asm 'mov x0 (imm 0))
          (asm-load-imm64! asm x0 (%ptr->int (%obj->ptr val)))))
      ; Not a fvar: load from params
      (let ((idx (%find params 0)))
        (asm-emit! asm 'mov x0 x20)
        (def %skip
          (fn (self n)
            (unless (< n 0)
              (do (%emit-restobj! asm) (self (- n 1))))))
        (%skip idx)
        (%emit-firstobj! asm)
        (asm-emit! asm 'mov x1 x0)
        (asm-emit! asm 'mov x0 x19)
        (%emit-eval-arg! asm)
        (%emit-atomint! asm)))))

; Compile (or a b ...): short-circuit, returns first truthy value
(def %asm-compile-or
  (fn (_ asm args params)
    (def lbl-end (%asm-genlabel "%or_end"))
    (%asm-compile-expr asm (first args) params)
    (def %or-rest
      (fn (self as)
        (unless (null? as)
          (do
            (asm-emit! asm 'cbnz x0 (label lbl-end))
            (%asm-compile-expr asm (first as) params)
            (self (rest as))))))
    (%or-rest (rest args))
    (asm-label! asm lbl-end)))

; Compile (and a b ...): short-circuit, returns 0 on first falsy
(def %asm-compile-and
  (fn (_ asm args params)
    (def lbl-end (%asm-genlabel "%and_end"))
    (%asm-compile-expr asm (first args) params)
    (def %and-rest
      (fn (self as)
        (unless (null? as)
          (do
            (asm-emit! asm 'cbz x0 (label lbl-end))
            (%asm-compile-expr asm (first as) params)
            (self (rest as))))))
    (%and-rest (rest args))
    (asm-label! asm lbl-end)))

; Compile (not x): 0 -> 1, nonzero -> 0
(def %asm-compile-not
  (fn (_ asm args params)
    (def lbl-zero (%asm-genlabel "%not_z"))
    (def lbl-end  (%asm-genlabel "%not_e"))
    (%asm-compile-expr asm (first args) params)
    (asm-emit! asm 'cbz x0 (label lbl-zero))
    (asm-emit! asm 'mov x0 (imm 0))
    (asm-emit! asm 'b (label lbl-end))
    (asm-label! asm lbl-zero)
    (asm-emit! asm 'mov x0 (imm 1))
    (asm-label! asm lbl-end)))

; --- Scratch memory: the JIT's state mechanism -------------------------
; The compiler keeps every value in x0 as a raw integer, so an
; expression cannot hold state across steps.  These two forms give it
; state WITHOUT a register allocator: the caller passes a raw address
; (an integer -- obtained x-lang-side from a string's data pointer), and
; slots are addressed by a CONSTANT word index, so each access is one
; instruction against the already-encoded scaled-offset ldr/str.
;
;   (%mem-ref  ADDR-EXPR INDEX)        -> word at ADDR[INDEX]
;   (%mem-set! ADDR-EXPR INDEX VALUE)  -> stores, yields VALUE
;
; INDEX is a literal (imm12 scaled by 8: 0..4095 words).  No bounds
; check exists and none is possible -- this is the raw-pointer tier,
; the same trust model as (obj ref); the caller owns the buffer.
(def %asm-mem-offset
  (fn (_ idx)
    (if (not (number? idx))
      (Err raise 'value "asm-compile: %mem index must be a literal" ()))
    (if (or (< idx 0) (> idx 4095))
      (Err raise 'value "asm-compile: %mem index out of range (0..4095)" ()))
    (* idx 8)))

(def %asm-compile-mem-ref
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)      ; x0 = base address
    (asm-emit! asm (lit ldr) x0 (mem 0 (%asm-mem-offset (first (rest args)))))))

(def %asm-compile-mem-set
  (fn (_ asm args params)
    (def %off (%asm-mem-offset (first (rest args))))
    (%asm-compile-expr asm (first args) params)      ; base
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)
    (%emit-u32-le! asm %POP)                         ; x0 = base
    (asm-emit! asm (lit str) x1 (mem 0 %off))
    (asm-emit! asm 'mov x0 x1)))                     ; yield the value

; --- Variable-index scratch access ------------------------------------
; The constant-index forms above cover fixed slots; these take the index
; as an EXPRESSION, which is what a loop needs (K[t], W[t & 15]) -- and
; a loop is what keeps a generated body small enough to compile.  No new
; encoding: scale the index by 8 with lslv, add it to the base, then the
; same ldr/str at offset 0.
;
;   (%mem-ref-at  ADDR IDX)        -> word at ADDR[IDX]
;   (%mem-set-at! ADDR IDX VALUE)  -> stores, yields VALUE
;
; Unchecked, like the constant-index pair: the caller owns the buffer.
(def %asm-emit-scale-index!
  (fn (_ asm)
    ; x0 = index -> x1 = index * 8
    (asm-emit! asm 'mov x2 (imm 3))
    (asm-emit! asm 'lslv x0 x0 x2)
    (asm-emit! asm 'mov x1 x0)))

(def %asm-compile-mem-ref-at
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)          ; base
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)   ; index
    (%asm-emit-scale-index! asm)                         ; x1 = index*8
    (%emit-u32-le! asm %POP)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)
    (asm-emit! asm (lit ldr) x0 (mem 0 0))))

(def %asm-compile-mem-set-at
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)          ; base
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)   ; index
    (%asm-emit-scale-index! asm)
    (%emit-u32-le! asm %POP)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)                        ; x0 = address
    (%emit-u32-le! asm %PUSH)                            ; save address
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)                           ; x1 = value
    (%emit-u32-le! asm %POP)                             ; x0 = address
    (asm-emit! asm (lit str) x1 (mem 0 0))
    (asm-emit! asm 'mov x0 x1)))                         ; yield the value

; Compile (do a b ...): evaluate each in order, result is the last.
; %seq below is the tokenizer's internal TWO-arg form; `do` is the
; language's own sequencing form, and the JIT lacked it entirely -- a
; compiled (do ...) body fell through to the function-call path and
; failed obscurely.  Any number of forms; none yields nil.
(def %asm-compile-do
  (fn (_ asm args params)
    (if (null? args)
      (asm-emit! asm 'mov x0 (imm 0))
      (let ()
        (def %go
          (fn (self as)
            (do
              (%asm-compile-expr asm (first as) params)
              (unless (null? (rest as)) (self (rest as))))))
        (%go args)))))

; Compile (%seq a b): evaluate a, discard, evaluate b, return
(def %asm-compile-seq
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (%asm-compile-expr asm (first (rest args)) params)))

; Compile (%score-set score sign buffer): jit_score_set(score, sign, buffer)
; score and buffer are x_obj_t* (fvars or params), sign is raw int
(def %asm-compile-score-set
  (fn (_ asm args params)
    ; Eval score -> push
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    ; Eval buffer -> push
    (%asm-compile-expr asm (first (rest (rest args))) params)
    (%emit-u32-le! asm %PUSH)
    ; sign is a literal number
    (def sign-val (first (rest args)))
    ; Call jit_score_set(score, sign, buffer)
    (%emit-u32-le! asm %POP)                   ; x0 = buffer
    (asm-emit! asm 'mov x2 x0)           ; x2 = buffer
    (%emit-u32-le! asm %POP)                   ; x0 = score
    (asm-emit! asm 'mov x1 (imm sign-val)) ; x1 = sign
    (%emit-call! asm %jit-score-set)))

; Compile (%buffer-unread buffer): jit_buffer_unread(buffer)
(def %asm-compile-buffer-unread
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-call! asm %jit-buffer-unread)))

; Compile (%buffer-len buffer): jit_buffer_len(buffer) -> raw int
(def %asm-compile-buffer-len
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-call! asm %jit-buffer-len)))

; Compile standalone comparison: (= a b) -> 1 or 0
(def %asm-compile-cmp
  (fn (_ asm cond-insn args params)
    (def lbl-true (%asm-genlabel "%cmp_t"))
    (def lbl-end  (%asm-genlabel "%cmp_e"))
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (%emit-u32-le! asm %POP)
    (asm-emit! asm 'cmp x0 x1)
    (asm-emit! asm cond-insn (label lbl-true))
    (asm-emit! asm 'mov x0 (imm 0))
    (asm-emit! asm 'b (label lbl-end))
    (asm-label! asm lbl-true)
    (asm-emit! asm 'mov x0 (imm 1))
    (asm-label! asm lbl-end)))

; The bitwise/shift family: op -> the ARM64 instruction its two operands
; feed.  A TABLE, not more if-nesting -- the chain below is already
; twenty deep, and these all share the binop shape (both operands to
; registers, one instruction).  Shifts take a register amount (LSLV/
; LSRV), so a shift by an expression works like any other operand.
(def %asm-bitwise-ops
  (list (pair '&  'and)
        (pair '|  'orr)
        (pair '^  'eor)
        (pair '<< 'lslv)
        (pair '>> 'lsrv)))

; Compile a call expression
(set! %asm-compile-call
  (fn (_ asm expr params)
    (def op (first expr))
    (def args (rest expr))
    (def %bitwise (List assq op %asm-bitwise-ops))
    (if (not (null? %bitwise))
      (%asm-compile-binop asm (rest %bitwise) args params)
    (if (eq? op '~)
      ; MVN Xd, Xm is ORN Xd, XZR, Xm
      (do (%asm-compile-expr asm (first args) params)
          (asm-emit! asm 'orn x0 xzr x0))
    (if (eq? op '%mem-ref-at)
      (%asm-compile-mem-ref-at asm args params)
    (if (eq? op '%mem-set-at!)
      (%asm-compile-mem-set-at asm args params)
    (if (eq? op '%mem-ref)
      (%asm-compile-mem-ref asm args params)
    (if (eq? op '%mem-set!)
      (%asm-compile-mem-set asm args params)
    (if (eq? op 'do)
      (%asm-compile-do asm args params)
    (if (eq? op '+)
      (%asm-compile-binop asm 'add args params)
      (if (eq? op '-)
        (if (null? (rest args))
          (do (%asm-compile-expr asm (first args) params)
              (asm-emit! asm 'sub x0 xzr x0))
          (%asm-compile-binop asm 'sub args params))
        (if (eq? op '*)
          (%asm-compile-binop asm 'mul args params)
          (if (eq? op '/)
            (%asm-compile-binop asm 'sdiv args params)
            (if (eq? op '%)
              (%asm-compile-mod asm args params)
              (if (eq? op 'if)
                (%asm-compile-if asm args params)
                (if (eq? op 'or)
                  (%asm-compile-or asm args params)
                  (if (eq? op 'and)
                    (%asm-compile-and asm args params)
                    (if (eq? op 'not)
                      (%asm-compile-not asm args params)
                      (if (eq? op '%seq)
                        (%asm-compile-seq asm args params)
                        (if (eq? op '%score-set)
                          (%asm-compile-score-set asm args params)
                          (if (eq? op '%buffer-unread)
                            (%asm-compile-buffer-unread asm args params)
                            (if (eq? op '%buffer-len)
                              (%asm-compile-buffer-len asm args params)
                              (if (eq? op '=)
                                (%asm-compile-cmp asm 'b/eq args params)
                                (if (eq? op '<)
                                  (%asm-compile-cmp asm 'b/lt args params)
                                  (if (eq? op '>)
                                    (%asm-compile-cmp asm 'b/gt args params)
                                    (if (eq? op '<=)
                                      (%asm-compile-cmp asm 'b/le args params)
                                      (if (eq? op '>=)
                                        (%asm-compile-cmp asm 'b/ge args params)
                                        (%asm-compile-funcall asm op args params))))))))))))))))))))))))))))

; Binary operation: push left, eval right, pop left, combine
(set! %asm-compile-binop
  (fn (_ asm insn args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (%emit-u32-le! asm %POP)
    (asm-emit! asm insn x0 x0 x1)))

; Modulo: SDIV + MSUB
(set! %asm-compile-mod
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (%emit-u32-le! asm %PUSH)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (%emit-u32-le! asm %POP)
    (asm-emit! asm 'sdiv x2 x0 x1)
    (asm-emit! asm 'msub x0 x2 x1 x0)))

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
        (if (eq? op '=)  'b/ne
          (if (eq? op '<)  'b/ge
            (if (eq? op '>)  'b/le
              (if (eq? op '<=) 'b/gt
                (when (eq? op '>=) 'b/lt)))))))

    (if (and (pair? test-expr) (not (null? (%cmp-branch (first test-expr)))))
      (let ((cmp-op (first test-expr))
            (cmp-args (rest test-expr)))
        (%asm-compile-expr asm (first cmp-args) params)
        (%emit-u32-le! asm %PUSH)
        (%asm-compile-expr asm (first (rest cmp-args)) params)
        (asm-emit! asm 'mov x1 x0)
        (%emit-u32-le! asm %POP)
        (asm-emit! asm 'cmp x0 x1)
        (asm-emit! asm (%cmp-branch cmp-op) (label lbl-else))
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm 'b (label lbl-end))
        (asm-label! asm lbl-else)
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm lbl-end))
      (do
        (%asm-compile-expr asm test-expr params)
        (asm-emit! asm 'cbz x0 (label lbl-else))
        (%asm-compile-expr asm then-expr params)
        (asm-emit! asm 'b (label lbl-end))
        (asm-label! asm lbl-else)
        (%asm-compile-expr asm else-expr params)
        (asm-label! asm lbl-end)))))

; Self-recursive call via trampoline
; The trampoline cell holds the prim's address. Save/restore x19/x20
; across the call since the callee uses them too.
(set! %asm-compile-funcall
  (fn (_ asm fn-name args params)
    (if (null? %asm-self-cell)
      (Err raise 'value (Str append "asm-compile: unknown function: " (symbol->str fn-name)) ()))
    ; Anything reaching here that is NOT the function's own name is an
    ; operator the JIT does not implement -- a bitwise op on a build
    ; without them, a typo, a library call.  This used to compile it AS
    ; A SELF-CALL: the code ran, recursed on itself forever, and died
    ; with a segfault far from the cause.  Silently wrong is the worst
    ; failure mode a compiler has; refuse at generation instead.
    (if (not (eq? fn-name %asm-self-name))
      (Err raise 'value
        (Str append "asm-compile: unsupported form: " (symbol->str fn-name)) ()))
    (def nargs (%length args))
    (if (> nargs 4) (Err raise 'value "asm-compile: max 4 args for recursive calls" ()))

    ; Evaluate each arg to raw integer, push to stack
    (%for-each
      (fn (_ arg)
        (%asm-compile-expr asm arg params)
        (%emit-u32-le! asm %PUSH))
      args)

    ; Build args list: pop each, mkint, mkpair to build (nil a0 a1 ...)
    ; Build right-to-left: start with nil, prepend each arg
    (asm-emit! asm 'mov x0 (imm 0))       ; x0 = nil (accumulator)
    (%emit-u32-le! asm %PUSH)                    ; save nil on stack
    (def %build-arg
      (fn (self i)
        (unless (< i 0)
          (do
            ; Pop raw value from deep stack position
            ; Stack: [accum] [argN-1] ... [arg0] — pop arg at position i
            ; Actually we need to pop in reverse. Args were pushed left-to-right.
            ; Stack top has last arg. Pop each into x1, mkint, then mkpair with accum.
            (%emit-u32-le! asm %POP)            ; pop accum -> x0
            ; x21, not x3: the accumulator has to survive the jit_mkint
            ; call below, and x3 is CALLER-saved (AAPCS64) -- the C
            ; function was free to clobber it, so the pair got built on
            ; garbage and the call segfaulted.  x21 is callee-saved and
            ; this compiler's prologue already spills it.
            (asm-emit! asm 'mov x21 x0)   ; x21 = accum (save)
            (%emit-u32-le! asm %POP)            ; pop raw arg -> x0
            (%emit-mkint! asm)                  ; x0 = atom(raw) via jit_mkint
            (asm-emit! asm 'mov x1 x0)    ; x1 = a (atom)
            (asm-emit! asm 'mov x2 x21)   ; x2 = d (accum)
            (asm-emit! asm 'mov x0 x19)   ; x0 = p_base
            (%emit-call! asm %jit-mkpair)      ; x0 = (atom . accum)
            (%emit-u32-le! asm %PUSH)           ; push new accum
            (self (- i 1))))))
    (%build-arg (- nargs 1))
    ; Pop final list, prepend nil as self
    (%emit-u32-le! asm %POP)                    ; x0 = (a0 a1 ... aN)
    (asm-emit! asm 'mov x2 x0)            ; x2 = d (args list)
    (asm-emit! asm 'mov x1 (imm 0))       ; x1 = a (nil = self)
    (asm-emit! asm 'mov x0 x19)           ; x0 = p_base
    (%emit-call! asm %jit-mkpair)              ; x0 = (nil a0 a1 ...)

    ; Call self: x0=p_base, x1=p_args
    (asm-emit! asm 'mov x1 x0)           ; p_args
    (asm-emit! asm 'mov x0 x19)          ; p_base
    (asm-load-imm64! asm x8 (%ptr->int %asm-self-cell))
    ; (mem BASE off) takes the base as a raw register NUMBER, not a
    ; (reg n) operand -- passing x8 handed the encoder a list to shift,
    ; so every self-recursive call died at GENERATION with ">>: operands
    ; must be integers".  Recursion had simply never run.
    (asm-emit! asm 'ldr x8 (mem 8 0))
    (asm-emit! asm 'blr x8)

    ; x0 = boxed result. Unbox to raw integer (inline LDR).
    (%emit-atomint! asm)))

; --- Public API ---

(def compile-asm
  (fn (_ expr . %asm-rest)
    (if (not (eq? (first expr) 'fn))
      (Err raise 'type "compile-asm: expression must be (fn (_ params...) body)" ()))
    (set! %compile-fvars (unless (null? %asm-rest) (first %asm-rest)))
    (def fn-params (first (rest expr)))
    (def fn-body (first (rest (rest expr))))
    (def params (rest fn-params))  ; skip self (_)

    ; Allocate trampoline cell for self-recursion
    (def c-malloc (%dlsym (%dlopen () 1) "malloc"))
    (def self-cell (%ptr-call c-malloc 8))
    (%ptr-set-word! self-cell 0 0)
    (set! %asm-self-cell self-cell)
    (set! %asm-self-name (first fn-params))

    ; Size the code buffer to the expression: asm-new's 4096-byte
    ; default is 1024 instructions, and a GENERATED body (an unrolled
    ; loop, a table of cases) blows past it -- which used to mean a
    ; segfault, not an error.  Each node costs at most a few
    ; instructions, so 128 bytes/node is generous; mmap is cheap, and
    ; %emit-u8!'s guard catches any underestimate loudly.
    (def %node-count
      (fn (self e)
        (if (pair? e) (+ (self (first e)) (self (rest e))) 1)))
    (def asm (asm-new (+ 4096 (* 128 (%node-count expr)))))

    ; Prologue: save callee-saved registers
    (asm-prologue! asm)
    ; Save p_base and p_args
    (asm-emit! asm 'mov x19 x0)    ; p_base
    (asm-emit! asm 'mov x20 x1)    ; p_args

    ; Compile body
    (%asm-compile-expr asm fn-body params)

    ; Box result only for pure integer functions (no fvars).
    ; Fvar functions (analysers) return x_obj_t* directly — no boxing.
    (if (null? %compile-fvars)
      (%emit-mkint! asm))

    ; Epilogue
    (asm-epilogue! asm)

    (def raw-fn (asm-finalize! asm))

    ; Patch trampoline with actual address
    (%ptr-set-word! self-cell 0 (%ptr->int raw-fn))
    (set! %asm-self-cell ())
    (set! %asm-self-name ())
    (set! %compile-fvars ())

    ; Create proper x-lang prim from the raw function pointer
    (%make-callable raw-fn)))
(doc compile-asm
  (returns CALLABLE "X-lang callable prim")
  "JIT compile an x-lang (fn ...) expression to a native prim.
   Accepts optional fvar alist for free variable support.
   The compiled function works with map, fold, closures, etc.")

(doc (provide x/tool/asm-compile compile-asm)
  "JIT compiler: x-lang to native code via assembler.")
