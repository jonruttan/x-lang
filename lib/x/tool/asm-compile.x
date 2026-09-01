; asm-compile.x -- JIT compiler: x-lang expressions to native machine code
; Produces proper x-lang prims that work with map, fold, closures, etc.
; lint-known: %compile-fvars %compile-fvar-lookup
; (defined in tool/compile/emit.x; compile.x's include order supplies them)
(import x/core/list)
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj->ptr (prim-ref 'obj '->ptr))
(def %make-callable (prim-ref 'obj 'make-callable))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str->symbol (prim-ref 'str '->sym))

(import x/tool/asm)
; Collection is explicit-trigger-only, and a GENERATED build is the
; hottest allocator in the system: each emitted instruction costs
; interpreted-call scaffolding, and a 3500-node engine build peaked at
; ~700MB of uncollected garbage natively -- roughly double under ASan
; redzones, which is more than a CI runner has.  The compiler collects
; every %asm-gc-window nodes, so a build's peak is the WINDOW's garbage,
; not the whole build's; small compiles (under a window) never collect.
(import x/sys/gc)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->int (prim-ref 'ptr '->int))
(def %ptr-set-word! (prim-ref 'ptr 'set-word!))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))



; --- Resolve JIT runtime helpers (non-variadic wrappers in jit.c) ---
;
; EVERY helper must resolve, and an unresolved one must REFUSE, not
; coast: dlsym answers nil, %ptr->int turns that into 0, and the
; compiler then happily emits `blr` to address 0 -- machine code that
; segfaults on its first call, arbitrarily far from the cause.  That is
; exactly what a bare-`strip`ped install did (it drops the exported
; symbol table that `strip -x` keeps, so an INSTALLED engine had no
; jit_* symbols at all while the repo build was fine): the JIT compiled
; happily and died inside jit_atomint (x-lang#201).
;
; The refusal is RECORDED here and raised by compile-asm, not raised
; here: this runs inside `import`, and unwinding a raise out of a nested
; module load leaves the loader mid-file (observed: correct answers
; followed by a stray error and exit 1).  Loading always succeeds;
; the entry point checks before it emits anything, so the raise happens
; in an ordinary call that Sha256's adoption guard turns into "stay
; pure-x" -- correct, merely slower.
(def %jit-lib (%dlopen () 1))
(def %jit-missing ())
(def %jit-sym
  (fn (_ name)
    (def p (%dlsym %jit-lib name))
    (when (null? p) (set! %jit-missing (pair name %jit-missing)))
    p))
(def %jit-addr
  (fn (_ name)
    (def p (%jit-sym name))
    (if (null? p) 0 (%ptr->int p))))
(def %jit-mkint    (%jit-addr "jit_mkint"))
(def %jit-mkpair   (%jit-addr "jit_mkpair"))
(def %jit-firstobj (%jit-addr "jit_firstobj"))
(def %jit-restobj  (%jit-addr "jit_restobj"))
(def %jit-atomint  (%jit-addr "jit_atomint"))
(def %jit-eval-arg (%jit-addr "jit_eval_arg"))
(def %jit-score-set (%jit-addr "jit_score_set"))
(def %jit-buffer-unread (%jit-addr "jit_buffer_unread"))
(def %jit-buffer-len (%jit-addr "jit_buffer_len"))

; Stack push/pop ride the per-arch asm-push!/asm-pop! FUNCTIONS: each
; backend owns its 16-byte discipline (arm64 pre/post-indexed str/ldr;
; x86-64 keeps rsp 16-aligned for SysV calls at any push depth), and the
; function form costs one call -- these bracket every binop, and routing
; them through the mnemonic dispatch tripled a big build's allocation.

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

(def %asm-gc-window 128)
(def %asm-gc-tick (pair 0 ()))
; Cached int prim (#335): the tick check runs per compiled expression.
(def %asm-int% (prim-ref (lit int) (lit %)))

; Emit code for an expression
(set! %asm-compile-expr
  (fn (_ asm expr params)
    (%set-first! %asm-gc-tick (+ (first %asm-gc-tick) 1))
    (when (= 0 (%asm-int% (first %asm-gc-tick) %asm-gc-window)) (Heap collect))
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
; p_args = (self arg0 arg1 ...) — walk rest N+1 times, first, eval, atomint.
; If symbol is a free variable (fvar), load its pointer as a 64-bit immediate.
;
; TWO MODES, because two kinds of parameter exist.  An arithmetic operand wants
; the raw machine word, so the default unboxes with atomint.  An OBJECT operand
; -- the score and buffer an analyse callback receives -- must stay a pointer:
; atomint on a buffer reads its first word as an integer, and jit_score_set
; then dereferences that garbage.  That is exactly what killed every compiled
; analyser while plain integer functions worked, and the %score-set emitter's
; own comment ("score and buffer are x_obj_t*") had promised the object case
; all along without the loader implementing it.
(set! %asm-compile-param
  (fn (_ asm name params . %mode)
    (def unbox (if (null? %mode) #t (first %mode)))
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
        ; TWO CALLING WORLDS, discriminated the way the return path already
        ; discriminates them: FVARS PRESENT MEANS ANALYSER.
        ;
        ; An integer function is called from x, and the prim ABI hands the
        ; callee UNEVALUATED argument expressions -- so its params must
        ; eval-arg, then unbox.  An analyse callback is invoked from C's
        ; scoring loop with LIVE VALUES built on the C stack: typeless satoms
        ; and spair chains the evaluator was never meant to see.  Evaluating
        ; one is undefined -- measured as an allocation spin that ends at the
        ; ceiling -- and unnecessary, because they are already values.  So in
        ; analyser mode nothing evals: an unboxed param (chr) reads its raw
        ; word straight off the atom, and an object param (score, buffer)
        ; stays the pointer it arrived as.
        (if (null? %compile-fvars)
          (do
            (asm-emit! asm 'mov x1 x0)
            (asm-emit! asm 'mov x0 x19)
            (%emit-eval-arg! asm)
            (when unbox (%emit-atomint! asm)))
          (when unbox (%emit-atomint! asm)))))))

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
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)
    (asm-pop! asm x0)                         ; x0 = base
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
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)   ; index
    (%asm-emit-scale-index! asm)                         ; x1 = index*8
    (asm-pop! asm x0)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)
    (asm-emit! asm (lit ldr) x0 (mem 0 0))))

(def %asm-compile-mem-set-at
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)          ; base
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)   ; index
    (%asm-emit-scale-index! asm)
    (asm-pop! asm x0)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)                        ; x0 = address
    (asm-push! asm x0)                            ; save address
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)                           ; x1 = value
    (asm-pop! asm x0)                             ; x0 = address
    (asm-emit! asm (lit str) x1 (mem 0 0))
    (asm-emit! asm 'mov x0 x1)))                         ; yield the value

; --- Byte-width scratch access -----------------------------------------
; The word family above addresses the JIT's own scratch state; this
; family reads and writes BYTES, which is what a compiled function needs
; to consume input that arrives as a string's data pointer (a digest's
; message, a codec's buffer).  Same trust model, same shapes, two
; differences: the index counts bytes (imm12 unscaled, 0..4095; no *8),
; and the width is one byte -- LDRB zero-extends into the value, STRB
; stores the value's LOW byte and ignores the rest, so a store yields
; the full value it was given, not the truncated byte.
;
;   (%mem-byte-ref     ADDR INDEX)        (%mem-byte-ref-at  ADDR IDX-EXPR)
;   (%mem-byte-set!    ADDR INDEX VALUE)  (%mem-byte-set-at! ADDR IDX-EXPR VALUE)
(def %asm-mem-byte-offset
  (fn (_ idx)
    (if (not (number? idx))
      (Err raise 'value "asm-compile: %mem-byte index must be a literal" ()))
    (if (or (< idx 0) (> idx 4095))
      (Err raise 'value "asm-compile: %mem-byte index out of range (0..4095)" ()))
    idx))

(def %asm-compile-mem-byte-ref
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)      ; x0 = base address
    (asm-emit! asm (lit ldrb) x0 (mem 0 (%asm-mem-byte-offset (first (rest args)))))))

(def %asm-compile-mem-byte-set
  (fn (_ asm args params)
    (def %off (%asm-mem-byte-offset (first (rest args))))
    (%asm-compile-expr asm (first args) params)      ; base
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)
    (asm-pop! asm x0)                         ; x0 = base
    (asm-emit! asm (lit strb) x1 (mem 0 %off))
    (asm-emit! asm 'mov x0 x1)))                     ; yield the value

(def %asm-compile-mem-byte-ref-at
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)          ; base
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)   ; index (bytes)
    (asm-emit! asm 'mov x1 x0)                           ; no scaling
    (asm-pop! asm x0)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)
    (asm-emit! asm (lit ldrb) x0 (mem 0 0))))

(def %asm-compile-mem-byte-set-at
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)          ; base
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)   ; index (bytes)
    (asm-emit! asm 'mov x1 x0)                           ; no scaling
    (asm-pop! asm x0)                             ; x0 = base
    (asm-emit! asm 'add x0 x0 x1)                        ; x0 = address
    (asm-push! asm x0)                            ; save address
    (%asm-compile-expr asm (first (rest (rest args))) params) ; value
    (asm-emit! asm 'mov x1 x0)                           ; x1 = value
    (asm-pop! asm x0)                             ; x0 = address
    (asm-emit! asm (lit strb) x1 (mem 0 0))
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
    ; Eval score -> push (OBJECT: jit_score_set writes through it; a symbol
    ; loads via the no-unbox param mode, anything else the generic path)
    (if (symbol? (first args))
      (%asm-compile-param asm (first args) params #f)
      (%asm-compile-expr asm (first args) params))
    (asm-push! asm x0)
    ; Eval buffer -> push (OBJECT: jit_score_set reads its length)
    (if (symbol? (first (rest (rest args))))
      (%asm-compile-param asm (first (rest (rest args))) params #f)
      (%asm-compile-expr asm (first (rest (rest args))) params))
    (asm-push! asm x0)
    ; sign is a literal number -- with the house style folded and everything
    ; else refused BY NAME.  This codebase writes negative literals as
    ; (- 0 1) in analyser code (tokens.x throughout), and a pair fed to the
    ; old emitter reached the encoder's masking arithmetic, which raised
    ; "&: operands must be integers" -- an operation the caller's code never
    ; performs, worn by machinery two layers down.  Two sessions chased that
    ; as an emitter defect.  Fold the (- a b) constant shape; refuse anything
    ; else non-numeric with the contract's own words.
    (def %sign-raw (first (rest args)))
    (def sign-val
      (if (number? %sign-raw) %sign-raw
        (if (and (pair? %sign-raw) (eq? (first %sign-raw) '-)
                 (number? (first (rest %sign-raw)))
                 (number? (first (rest (rest %sign-raw)))))
          (- (first (rest %sign-raw)) (first (rest (rest %sign-raw))))
          (Err raise 'type
            "asm-compile: score-set sign must be a literal integer (or (- a b) of literals)"
            %sign-raw))))
    ; Call jit_score_set(score, sign, buffer)
    (asm-pop! asm x0)                   ; x0 = buffer
    (asm-emit! asm 'mov x2 x0)           ; x2 = buffer
    (asm-pop! asm x0)                   ; x0 = score
    ; SIGN -1 IS THE COMMON CASE and mov-immediate cannot hold it: MOVZ
    ; zero-extends 16 bits, so (imm -1) reached the register as 65535 and
    ; every negative (discard) score-set scored POSITIVE 65535*len -- one
    ; giant accepted token swallowing the tail (lldb: x1 = 0xffff at
    ; jit_score_set, one call for a whole multi-token input).  The general
    ; constant emitter already routes negatives through the 64-bit load;
    ; the sign must too.
    (if (and (>= sign-val 0) (<= sign-val 65535))
      (asm-emit! asm 'mov x1 (imm sign-val))
      (asm-load-imm64! asm x1 sign-val))  ; x1 = sign
    (%emit-call! asm %jit-score-set)))

; Compile (%buffer-unread buffer): jit_buffer_unread(buffer)
(def %asm-compile-buffer-unread
  (fn (_ asm args params)
    (if (symbol? (first args))
      (%asm-compile-param asm (first args) params #f)
      (%asm-compile-expr asm (first args) params))
    (%emit-call! asm %jit-buffer-unread)))

; Compile (%buffer-len buffer): jit_buffer_len(buffer) -> raw int
(def %asm-compile-buffer-len
  (fn (_ asm args params)
    (if (symbol? (first args))
      (%asm-compile-param asm (first args) params #f)
      (%asm-compile-expr asm (first args) params))
    (%emit-call! asm %jit-buffer-len)))

; Compile standalone comparison: (= a b) -> 1 or 0
(def %asm-compile-cmp
  (fn (_ asm cond-insn args params)
    (def lbl-true (%asm-genlabel "%cmp_t"))
    (def lbl-end  (%asm-genlabel "%cmp_e"))
    (%asm-compile-expr asm (first args) params)
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (asm-pop! asm x0)
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
; ASRV), so a shift by an expression works like any other operand.
;
; `>>` is ASRV, not LSRV: the interpreter's `>>` is C's on a signed
; word, so it sign-extends -- (>> -16 2) is -4.  A logical shift here
; would answer 4611686018427387900 and disagree with the interpreted
; definition of the same function, which is the one contract the JIT
; has.  On the masked non-negative values a digest loop shifts, the
; two are identical anyway.
(def %asm-bitwise-ops
  (list (pair '&  'and)
        (pair '|  'orr)
        (pair '^  'eor)
        (pair '<< 'lslv)
        (pair '>> 'asrv)))

; Compile a call expression
(set! %asm-compile-call
  (fn (_ asm expr params)
    (def op (first expr))
    (def args (rest expr))
    (def %bitwise (Assoc entry op %asm-bitwise-ops))
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
    (if (eq? op '%mem-byte-ref-at)
      (%asm-compile-mem-byte-ref-at asm args params)
    (if (eq? op '%mem-byte-set-at!)
      (%asm-compile-mem-byte-set-at asm args params)
    (if (eq? op '%mem-byte-ref)
      (%asm-compile-mem-byte-ref asm args params)
    (if (eq? op '%mem-byte-set!)
      (%asm-compile-mem-byte-set asm args params)
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
                                        (%asm-compile-funcall asm op args params))))))))))))))))))))))))))))))))

; Binary operation: push left, eval right, pop left, combine
(set! %asm-compile-binop
  (fn (_ asm insn args params)
    (%asm-compile-expr asm (first args) params)
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (asm-pop! asm x0)
    (asm-emit! asm insn x0 x0 x1)))

; Modulo: SDIV + MSUB
(set! %asm-compile-mod
  (fn (_ asm args params)
    (%asm-compile-expr asm (first args) params)
    (asm-push! asm x0)
    (%asm-compile-expr asm (first (rest args)) params)
    (asm-emit! asm 'mov x1 x0)
    (asm-pop! asm x0)
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
        (asm-push! asm x0)
        (%asm-compile-expr asm (first (rest cmp-args)) params)
        (asm-emit! asm 'mov x1 x0)
        (asm-pop! asm x0)
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
        (asm-push! asm x0))
      args)

    ; Build args list: pop each, mkint, mkpair to build (nil a0 a1 ...)
    ; Build right-to-left: start with nil, prepend each arg
    (asm-emit! asm 'mov x0 (imm 0))       ; x0 = nil (accumulator)
    (asm-push! asm x0)                    ; save nil on stack
    (def %build-arg
      (fn (self i)
        (unless (< i 0)
          (do
            ; Pop raw value from deep stack position
            ; Stack: [accum] [argN-1] ... [arg0] — pop arg at position i
            ; Actually we need to pop in reverse. Args were pushed left-to-right.
            ; Stack top has last arg. Pop each into x1, mkint, then mkpair with accum.
            (asm-pop! asm x0)            ; pop accum -> x0
            ; x21, not x3: the accumulator has to survive the jit_mkint
            ; call below, and x3 is CALLER-saved (AAPCS64) -- the C
            ; function was free to clobber it, so the pair got built on
            ; garbage and the call segfaulted.  x21 is callee-saved and
            ; this compiler's prologue already spills it.
            (asm-emit! asm 'mov x21 x0)   ; x21 = accum (save)
            (asm-pop! asm x0)            ; pop raw arg -> x0
            (%emit-mkint! asm)                  ; x0 = atom(raw) via jit_mkint
            (asm-emit! asm 'mov x1 x0)    ; x1 = a (atom)
            (asm-emit! asm 'mov x2 x21)   ; x2 = d (accum)
            (asm-emit! asm 'mov x0 x19)   ; x0 = p_base
            (%emit-call! asm %jit-mkpair)      ; x0 = (atom . accum)
            (asm-push! asm x0)           ; push new accum
            (self (- i 1))))))
    (%build-arg (- nargs 1))
    ; Pop final list, prepend nil as self
    (asm-pop! asm x0)                    ; x0 = (a0 a1 ... aN)
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
    (asm-emit! asm 'ldr x8 (mem x8 0))
    (asm-emit! asm 'blr x8)

    ; x0 = boxed result. Unbox to raw integer (inline LDR).
    (%emit-atomint! asm)))

; --- Public API ---

(def compile-asm
  (fn (_ expr . %asm-rest)
    ; Refuse before emitting anything when the JIT runtime is not
    ; reachable.  An unresolved helper is address 0, and a compiled call
    ; to 0 is a SIGSEGV arbitrarily far from the cause -- which is what a
    ; bare-`strip`ped install produced (x-lang#201).
    (unless (null? %jit-missing)
      (Err raise 'state
        (Str append "asm-compile: JIT runtime unavailable (unresolved symbol "
          (Str append (first %jit-missing)
            "); engine built without its exported symbols?")) ()))
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
    ; the emitters' capacity guard catches any underestimate loudly.
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
