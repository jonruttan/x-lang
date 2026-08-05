; tool/asm/x86_64.x -- x86-64 opcode table and encoder (a private component
; of the assembler: raw-included by tool/asm.x, not importable standalone
; -- it references (reg n) from asm.x)
;
; PARITY BACKEND.  asm-compile.x emits ONE vocabulary -- arm64 mnemonics,
; portable register names, its own three-arg call protocol -- and this
; backend lowers that vocabulary to x86-64 instead of asking the compiler
; to know two architectures.  Three seams absorb every ABI difference:
;
;   entry    the prologue ends by moving SysV's arg registers into the
;            portable model (x0 <- rdi; x1 is rsi already), so compiled
;            code sees the same machine state it sees on arm64;
;   calls    'blr marshals the portable arg registers into SysV's
;            (rdi/rsi/rdx <- x0/x1/x2) before CALL, and the return
;            lands in rax = x0 on both architectures;
;   3-adr    arm64's three-address ops lower to x86's two-address forms
;            (mov dst,src1 when they differ, then op dst,src2), and the
;            special-register constraints -- shift amounts in CL,
;            division through RAX/RDX -- are dodged by the register
;            mapping below or handled inside the lowering.

; Fetch the ptr prims from the catalog (ns `ptr` is de-registered, R5).
(def %ptr-set! (prim-ref 'ptr 'set!))

; --- Register aliases (hardware encoding numbers) ---
(def rax (reg 0))  (def rcx (reg 1))  (def rdx (reg 2))  (def rbx (reg 3))
(def rsp (reg 4))  (def rbp (reg 5))  (def rsi (reg 6))  (def rdi (reg 7))
(def r8  (reg 8))  (def r9  (reg 9))  (def r10 (reg 10)) (def r11 (reg 11))
(def r12 (reg 12)) (def r13 (reg 13)) (def r14 (reg 14)) (def r15 (reg 15))

; --- The portable register model ---
; asm-compile.x speaks x0/x1/x2/x8/x19-x22/xzr; each lands on the x86
; register whose constraints fit its ROLE:
;   x0  -> rax   the value register; C return lands here on both arches
;   x1  -> rsi   binop right operand -- also SysV arg1, so the call
;                marshal's middle move is free; NOT rdx, which idiv
;                clobbers while x1 (the divisor) must survive sdiv
;   x2  -> rcx   scratch and shift amount -- x86 shifts only by CL, so
;                lslv/lsrv/asrv x0 x0 x2 needs no amount shuffle at all
;   x8  -> r10   call target (caller-saved, not an arg register)
;   x19 -> rbx   p_base   (callee-saved, prologue spills)
;   x20 -> r12   p_args   (callee-saved)
;   x21 -> r13   arg-list accumulator (callee-saved -- the #192 lesson)
;   x22 -> r14   reserved (callee-saved, spilled for parity)
;   xzr -> a PSEUDO register (99): x86 has no zero register, so the two
;          xzr idioms lower specially (sub d zr s -> neg; orn d zr s -> not)
(def x0  rax) (def x1  rsi) (def x2  rcx) (def x8  r10)
(def x19 rbx) (def x20 r12) (def x21 r13) (def x22 r14)
(def xzr (reg 99))
(def %x86-zr 99)

; Positional access on RAW prims -- same de-dispatch as the arm64
; encoder (#196): (List ref) costs ~226us a call against ~26us for the
; walk itself, and this encoder runs once per emitted instruction.
(def %x86-nth
  (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))

; --- Helper: ModR/M byte ---
(def %modrm (fn (_ mod-val reg-val rm-val)
  (| (<< mod-val 6) (| (<< (& reg-val 7) 3) (& rm-val 7)))))

; --- Raw-byte helpers for the lowerings ---
; REX with W=1 and R/B computed from the operands -- the one thing the
; old table got wrong: its prefixes were STATIC per-descriptor, so any
; r8-r15 operand encoded as its low-3-bit shadow (r12 became rsp).
; op dst, src (reg-reg, REX.W <op> /r with reg=src, rm=dst -- the
; 0x01/0x09/0x21/0x29/0x31/0x89 store-form direction)
(def %x86-rex (fn (_ reg-val rm-val)
  (| 72 (| (if (> reg-val 7) 4 0) (if (> rm-val 7) 1 0)))))
(def %x86-rr!
  (fn (_ asm op src dst)
    (%emit-bytes! asm (list (%x86-rex src dst) op (%modrm 3 src dst)))))

; mov dst, src -- skipped entirely when they are the same register
(def %x86-mov!
  (fn (_ asm dst src)
    (unless (= dst src) (%x86-rr! asm 137 src dst))))

; REX.W F7 /ext r/m64 -- the NEG/NOT/IDIV group
(def %x86-f7!
  (fn (_ asm ext rm)
    (%emit-bytes! asm (list (%x86-rex 0 rm) 247 (%modrm 3 ext rm)))))

; --- Three-address lowering ---
; arm64's op dst, src1, src2 on a two-address machine: land src1 in dst,
; then combine with src2.  The one shape this cannot express is
; dst==src2 with dst!=src1 (the mov clobbers src2 first); asm-compile
; never emits it, and the guard makes that a loud error instead of a
; silent miscompile if it ever does.
(def %x86-alu3!
  (fn (_ asm op dst src1 src2)
    (if (and (= dst src2) (not (= dst src1)))
      (Err raise 'value "x86_64: unsupported 3-address shape (dst==src2)" ()))
    (%x86-mov! asm dst src1)
    (%x86-rr! asm op src2 dst)))

; --- Encoder ---
; Descriptor: (prefixes opcode modrm-spec extras), or a bare SYMBOL
; naming a lowering (dispatched below), mirroring arm64's 'movz.
; prefixes: list of prefix bytes; REX-family bytes (0x40..0x4F) get
;   their R and B bits OR'd in from the actual operands, so r8-r15
;   encode correctly with the same descriptors.
; opcode: list of opcode bytes (or (opreg base-byte arg-idx))
; modrm-spec: () | (reg-arg rm-arg) | ((/ digit) rm-arg)
;   A bare number is an ARGUMENT INDEX whose register fills the reg
;   field; the Intel /digit opcode extension is spelled (/ n).
; extras: list of (kind arg-idx) for immediates/displacements
;
; The mem path handles the two ModR/M escapes the compiled code can
; reach: a base whose low bits are 100 (rsp/r12) needs a SIB byte, and
; 101 (rbp/r13) has no disp-less form -- mod=00 there means RIP-relative
; -- so it takes the disp8=0 form instead.

(def %x86_64-encode
  (fn (_ asm descriptor args)
    (def prefixes  (%x86-nth 0 descriptor))
    (def opcode    (%x86-nth 1 descriptor))
    (def modrm-spec (%x86-nth 2 descriptor))
    (def extras    (%x86-nth 3 descriptor))

    ; Resolve the ModR/M operands FIRST: the REX bits depend on them.
    (def reg-val
      (if (null? modrm-spec) 0
        (let ((reg-src (%x86-nth 0 modrm-spec)))
          (if (pair? reg-src)
            (%x86-nth 1 reg-src)                       ; (/ n) extension
            (%op-value (%x86-nth reg-src args))))))
    (def rm-arg (if (null? modrm-spec) () (%x86-nth (%x86-nth 1 modrm-spec) args)))
    (def rm-base (if (null? rm-arg) 0 (%op-value rm-arg)))
    (def opreg-val
      (if (and (pair? opcode) (eq? (first opcode) 'opreg))
        (%op-value (%x86-nth (%x86-nth 2 opcode) args))
        0))

    ; One byte LIST for prefixes + opcode + ModR/M (+SIB +disp8): a
    ; single %emit-bytes! instead of a per-byte interpreted call each --
    ; the difference between the x86 build fitting the standard
    ; allocation budget and blowing through it.
    (def %bytes
      (let ()
        ; prefixes, with dynamic R (modrm reg) and B (rm base / opreg)
        (def pfx
          ((fn (self xs)
             (if (null? xs) ()
               (pair (let ((b (first xs)))
                       (if (and (>= b 64) (<= b 79))
                         (| b (| (if (> reg-val 7) 4 0)
                                 (if (or (> rm-base 7) (> opreg-val 7)) 1 0)))
                         b))
                     (self (rest xs))))) prefixes))
        (def ops
          (if (and (pair? opcode) (eq? (first opcode) 'opreg))
            (list (| (%x86-nth 1 opcode) (& opreg-val 7)))
            opcode))
        (def tail
          (if (null? modrm-spec) ()
            (if (eq? (%op-type rm-arg) 'reg)
              (list (%modrm 3 reg-val (%op-value rm-arg)))
              ; mem: [base+disp], with the SIB and RIP escapes handled
              (let ((base (%op-value rm-arg))
                    (disp (%x86-nth 2 rm-arg)))
                (def low (& base 7))
                (def sib (if (= low 4) (list (| 32 low)) ()))
                (def force-disp8 (and (= low 5) (= disp 0)))
                (match
                  ((and (= disp 0) (not force-disp8))
                    (pair (%modrm 0 reg-val base) sib))
                  ((and (>= disp -128) (<= disp 127))
                    (%append (pair (%modrm 1 reg-val base) sib)
                             (list (& disp 255))))
                  (#t
                    (%append (pair (%modrm 2 reg-val base) sib)
                             (list (& disp 255)
                                   (& (>> disp 8) 255)
                                   (& (>> disp 16) 255)
                                   (& (>> disp 24) 255)))))))))
        (%append pfx (%append ops tail))))
    (%emit-bytes! asm %bytes)

    ; Immediates / relocations
    (%for-each
      (fn (_ spec)
        (def kind (%x86-nth 0 spec))
        (def idx  (%x86-nth 1 spec))
        (def val (%op-value (%x86-nth idx args)))
        (if (eq? kind 'imm8)  (%emit-u8! asm (& val 255)))
        (if (eq? kind 'imm32) (%emit-u32-le! asm val))
        (if (eq? kind 'imm64) (%emit-u64-le! asm val))
        (if (eq? kind 'rel32)
          (do (asm-patch! asm 4 'rel val)
              (%emit-u32-le! asm 0))))
      extras)))

; --- Lowerings (symbol-delegated from the table) ---

; alu3 family: (op dst src1 src2), all registers
(def %x86-lower-alu3
  (fn (_ asm op args)
    (def dst  (%op-value (%x86-nth 0 args)))
    (def src1 (%op-value (%x86-nth 1 args)))
    (def src2 (%op-value (%x86-nth 2 args)))
    ; the xzr idiom: sub d, zr, s = negate
    (match
      ((and (= op 41) (= src1 %x86-zr))
        (do (%x86-mov! asm dst src2)
            (%x86-f7! asm 3 dst)))               ; NEG
      (#t (%x86-alu3! asm op dst src1 src2)))))

; orn d, zr, s = bitwise NOT (the only orn shape the compiler emits)
(def %x86-lower-orn
  (fn (_ asm args)
    (def dst  (%op-value (%x86-nth 0 args)))
    (def src1 (%op-value (%x86-nth 1 args)))
    (def src2 (%op-value (%x86-nth 2 args)))
    (if (not (= src1 %x86-zr))
      (Err raise 'value "x86_64: orn supported only as (orn d xzr s)" ()))
    (%x86-mov! asm dst src2)
    (%x86-f7! asm 2 dst)))                       ; NOT

; imul dst, src (0F AF /r -- reg field is the DESTINATION)
(def %x86-lower-mul
  (fn (_ asm args)
    (def dst  (%op-value (%x86-nth 0 args)))
    (def src1 (%op-value (%x86-nth 1 args)))
    (def src2 (%op-value (%x86-nth 2 args)))
    (if (and (= dst src2) (not (= dst src1)))
      (Err raise 'value "x86_64: unsupported 3-address shape (dst==src2)" ()))
    (%x86-mov! asm dst src1)
    (%emit-bytes! asm (list (%x86-rex dst src2) 15 175 (%modrm 3 dst src2)))))

; shifts: amount must be in CL.  x2 maps to rcx, so the only emitted
; shape (op x0 x0 x2) needs no amount move; any other amount register
; is moved in, with dst==rcx refused (the mov would clobber the amount).
(def %x86-lower-shift
  (fn (_ asm ext args)
    (def dst  (%op-value (%x86-nth 0 args)))
    (def src1 (%op-value (%x86-nth 1 args)))
    (def amt  (%op-value (%x86-nth 2 args)))
    (if (and (= dst 1) (not (= amt 1)))
      (Err raise 'value "x86_64: shift destination cannot be rcx" ()))
    (%x86-mov! asm 1 amt)                        ; rcx = amount
    (%x86-mov! asm dst src1)
    (%emit-bytes! asm (list (%x86-rex 0 dst) 211 (%modrm 3 ext dst))))) ; D3 /ext: by CL

; sdiv dst, src1, src2: CQO + IDIV.  src1 is always x0 (rax) as emitted;
; when the destination is elsewhere, rax is preserved around the divide
; -- the mod sequence reads x0 again after sdiv x2 x0 x1.  rdx is
; clobbered by design (nothing lives there; x1 is rsi for this reason).
(def %x86-lower-sdiv
  (fn (_ asm args)
    (def dst  (%op-value (%x86-nth 0 args)))
    (def src1 (%op-value (%x86-nth 1 args)))
    (def src2 (%op-value (%x86-nth 2 args)))
    (if (not (= src1 0))
      (Err raise 'value "x86_64: sdiv supported only with src1 = x0" ()))
    (if (or (= src2 0) (= src2 2))
      (Err raise 'value "x86_64: sdiv divisor cannot be rax/rdx" ()))
    (if (= dst 0)
      (do (%emit-bytes! asm (list 72 153))               ; CQO
          (%x86-f7! asm 7 src2))                         ; IDIV
      (do (%x86-mov! asm 11 0)                           ; r11 = rax
          (%emit-bytes! asm (list 72 153))               ; CQO
          (%x86-f7! asm 7 src2)
          (%x86-mov! asm dst 0)                          ; dst = quotient
          (%x86-mov! asm 0 11)))))                       ; rax restored

; msub d, a, b, c = c - a*b, with d==c (the only emitted shape); a is
; scratch afterwards, so the multiply lands in it.
(def %x86-lower-msub
  (fn (_ asm args)
    (def d (%op-value (%x86-nth 0 args)))
    (def a (%op-value (%x86-nth 1 args)))
    (def b (%op-value (%x86-nth 2 args)))
    (def c (%op-value (%x86-nth 3 args)))
    (if (not (= d c))
      (Err raise 'value "x86_64: msub supported only as (msub d a b d)" ()))
    (%emit-bytes! asm (list (%x86-rex a b) 15 175 (%modrm 3 a b))) ; a = a*b
    (%x86-rr! asm 41 a d)))                      ; d = d - a

; cbz/cbnz: TEST reg,reg then Jcc rel32
(def %x86-lower-cb
  (fn (_ asm jcc args)
    (def r (%op-value (%x86-nth 0 args)))
    (%x86-rr! asm 133 r r)                       ; TEST r, r
    (%emit-u8! asm 15) (%emit-u8! asm jcc)
    (asm-patch! asm 4 'rel (%op-value (%x86-nth 1 args)))
    (%emit-u32-le! asm 0)))

; blr: marshal the portable arg registers into SysV and CALL.
; x1 is rsi (arg1 already); x0 -> rdi, x2 -> rdx.  The return arrives
; in rax = x0, which is the whole reason x0 maps there.
(def %x86-lower-blr
  (fn (_ asm args)
    (def tgt (%op-value (%x86-nth 0 args)))
    (%emit-bytes! asm
      (%append
        (list (%x86-rex 0 7) 137 (%modrm 3 0 7)  ; rdi = rax  (arg0)
              (%x86-rex 1 2) 137 (%modrm 3 1 2)) ; rdx = rcx  (arg2)
        (%append (if (> tgt 7) (list 65) ())     ; REX.B
                 (list 255 (%modrm 3 2 tgt)))))))  ; CALL r/m64 (/2)

; push/pop: 16 bytes at a time, matching arm64's pre/post-indexed pair
; slots -- SysV needs rsp % 16 == 0 at every CALL, and a compiled
; expression calls helpers at ARBITRARY push depth, so an 8-byte push
; would misalign every other call site.  [rsp] addressing needs the SIB
; escape (low bits 100).
(def %x86-lower-push
  (fn (_ asm args)
    (def r (%op-value (%x86-nth 0 args)))
    (%emit-bytes! asm
      (list 72 131 236 16                                  ; sub rsp,16
            (%x86-rex r 0) 137 (%modrm 0 r 4) 36))))       ; mov [rsp], r
(def %x86-lower-pop
  (fn (_ asm args)
    (def r (%op-value (%x86-nth 0 args)))
    (%emit-bytes! asm
      (list (%x86-rex r 0) 139 (%modrm 0 r 4) 36           ; mov r, [rsp]
            72 131 196 16))))                              ; add rsp,16

; --- Dispatch encoder: symbol descriptors name lowerings ---
(def %x86_64-dispatch
  (fn (_ asm descriptor args)
    (match
      ((eq? descriptor 'add3)  (%x86-lower-alu3 asm 1 args))
      ((eq? descriptor 'sub3)  (%x86-lower-alu3 asm 41 args))
      ((eq? descriptor 'and3)  (%x86-lower-alu3 asm 33 args))
      ((eq? descriptor 'orr3)  (%x86-lower-alu3 asm 9 args))
      ((eq? descriptor 'eor3)  (%x86-lower-alu3 asm 49 args))
      ((eq? descriptor 'orn3)  (%x86-lower-orn asm args))
      ((eq? descriptor 'mul3)  (%x86-lower-mul asm args))
      ((eq? descriptor 'lslv3) (%x86-lower-shift asm 4 args))
      ((eq? descriptor 'lsrv3) (%x86-lower-shift asm 5 args))
      ((eq? descriptor 'asrv3) (%x86-lower-shift asm 7 args))
      ((eq? descriptor 'sdiv3) (%x86-lower-sdiv asm args))
      ((eq? descriptor 'msub4) (%x86-lower-msub asm args))
      ((eq? descriptor 'cbz1)  (%x86-lower-cb asm 132 args))   ; JZ
      ((eq? descriptor 'cbnz1) (%x86-lower-cb asm 133 args))   ; JNZ
      ((eq? descriptor 'blr1)  (%x86-lower-blr asm args))
      ((eq? descriptor 'push1) (%x86-lower-push asm args))
      ((eq? descriptor 'pop1)  (%x86-lower-pop asm args))
      (#t (%x86_64-encode asm descriptor args)))))

; --- Opcode table ---
(def %x86_64-table
  (list
    ; RET
    (pair 'ret (list
      (pair '|| (list () (list 195) () ()))))   ; 0xC3

    ; NOP
    (pair 'nop (list
      (pair '|| (list () (list 144) () ()))))   ; 0x90

    ; MOV r64, r64  (REX.W 89 /r)
    (pair 'mov (list
      (pair 'rr (list
        (list 72)                ; REX.W (R/B filled dynamically)
        (list 137)               ; 0x89
        (list 1 0)               ; ModR/M: reg=arg1, rm=arg0
        ()))
      ; MOV r64, imm64 (REX.W B8+rd imm64)
      (pair 'ri (list
        (list 72)
        (list 'opreg 184 0)  ; 0xB8 + rd
        ()
        (list (list 'imm64 1))))))

    ; Three-address ALU family: lowered (mov dst,src1; op dst,src2).
    ; The two-operand rr forms remain for HAND-WRITTEN x86 code (the
    ; asm.x86_64 specs speak native two-address style); the compiler
    ; only ever emits rrr.
    (pair 'add (list
      (pair 'rrr 'add3)
      (pair 'rr (list
        (list 72)
        (list 1)                 ; 0x01 ADD r/m64, r64
        (list 1 0)
        ()))
      (pair 'ri (list
        (list 72)
        (list 129)               ; 0x81 /0 ADD r/m64, imm32 (two-operand)
        (list (list '/ 0) 0)
        (list (list 'imm32 1))))
      (pair 'rri (list
        (list 72)
        (list 129)               ; 0x81
        (list (list '/ 0) 0)     ; /0 = ADD, rm=arg0 (dst==src1 form)
        (list (list 'imm32 2))))))
    (pair 'sub (list
      (pair 'rrr 'sub3)
      (pair 'rr (list
        (list 72)
        (list 41)                ; 0x29 SUB r/m64, r64
        (list 1 0)
        ()))
      (pair 'ri (list
        (list 72)
        (list 129)               ; 0x81 /5 SUB r/m64, imm32 (two-operand)
        (list (list '/ 5) 0)
        (list (list 'imm32 1))))
      (pair 'rri (list
        (list 72)
        (list 129)
        (list (list '/ 5) 0)     ; /5 = SUB
        (list (list 'imm32 2))))))
    (pair 'and (list (pair 'rrr 'and3)))
    (pair 'orr (list (pair 'rrr 'orr3)))
    (pair 'eor (list (pair 'rrr 'eor3)))
    (pair 'orn (list (pair 'rrr 'orn3)))
    (pair 'mul (list (pair 'rrr 'mul3)))
    (pair 'lslv (list (pair 'rrr 'lslv3)))
    (pair 'lsrv (list (pair 'rrr 'lsrv3)))
    (pair 'asrv (list (pair 'rrr 'asrv3)))
    (pair 'sdiv (list (pair 'rrr 'sdiv3)))
    (pair 'msub (list (pair 'rrrr 'msub4)))

    ; Loads/stores against (mem base disp): word and byte widths.
    ; ldr/ldrb reg field = DESTINATION (8B / 0F B6 load direction);
    ; str/strb reg field = SOURCE (89 / 88 store direction).  ldrb is
    ; MOVZX -- zero-extension is the arm64 semantic the byte family's
    ; specs pin (0xFF reads 255, never -1).
    (pair 'ldr (list
      (pair 'rm (list (list 72) (list 139) (list 0 1) ()))))       ; 8B /r
    (pair 'str (list
      (pair 'rm (list (list 72) (list 137) (list 0 1) ()))))       ; 89 /r
    (pair 'ldrb (list
      (pair 'rm (list (list 72) (list 15 182) (list 0 1) ()))))    ; 0F B6 /r
    (pair 'strb (list
      (pair 'rm (list (list 72) (list 136) (list 0 1) ()))))       ; 88 /r

    ; CMP r64, r64 (REX.W 39 /r) -- flags from arg0 - arg1, matching
    ; arm64's operand order (cmp left right)
    (pair 'cmp (list
      (pair 'rr (list
        (list 72)
        (list 57)                ; 0x39
        (list 1 0)               ; reg=arg1, rm=arg0
        ()))
      (pair 'ri (list
        (list 72)
        (list 129)               ; 0x81
        (list (list '/ 7) 0) ; /7 = CMP
        (list (list 'imm32 1))))))

    ; JMP rel32
    (pair 'jmp (list
      (pair 'l (list () (list 233) ()           ; 0xE9
        (list (list 'rel32 0))))))

    ; B -- arm64's name for the unconditional branch; same encoding as JMP
    ; so branchy code keeps one mnemonic vocabulary across backends
    (pair 'b (list
      (pair 'l (list () (list 233) ()           ; 0xE9
        (list (list 'rel32 0))))))

    ; Conditional branches: Jcc rel32 (0F 8x). Named after arm64's B.cond
    ; so per-arch specs and generated code share mnemonics. Signed
    ; conditions (JL/JG), matching B.LT/B.GT.
    (pair 'b/eq (list
      (pair 'l (list () (list 15 132) ()        ; 0F 84 = JE
        (list (list 'rel32 0))))))
    (pair 'b/ne (list
      (pair 'l (list () (list 15 133) ()        ; 0F 85 = JNE
        (list (list 'rel32 0))))))
    (pair 'b/lt (list
      (pair 'l (list () (list 15 140) ()        ; 0F 8C = JL
        (list (list 'rel32 0))))))
    (pair 'b/ge (list
      (pair 'l (list () (list 15 141) ()        ; 0F 8D = JGE
        (list (list 'rel32 0))))))
    (pair 'b/gt (list
      (pair 'l (list () (list 15 143) ()        ; 0F 8F = JG
        (list (list 'rel32 0))))))
    (pair 'b/le (list
      (pair 'l (list () (list 15 142) ()        ; 0F 8E = JLE
        (list (list 'rel32 0))))))

    ; Zero-test branches and the indirect call, all lowered
    (pair 'cbz  (list (pair 'rl 'cbz1)))
    (pair 'cbnz (list (pair 'rl 'cbnz1)))
    (pair 'blr  (list (pair 'r 'blr1)))

    ; 16-byte stack push/pop (see the lowerings for the alignment story)
    (pair 'push (list (pair 'r 'push1)))
    (pair 'pop  (list (pair 'r 'pop1)))

    ; CALL rel32
    (pair 'call (list
      (pair 'l (list () (list 232) ()           ; 0xE8
        (list (list 'rel32 0))))))
  ))

; asm-push!/asm-pop!: the function forms of the 'push/'pop lowerings --
; the compiler's hottest emission, one call instead of a dispatch walk.
(def asm-push! (fn (_ asm r) (%x86-lower-push asm (list r))))
(def asm-pop!  (fn (_ asm r) (%x86-lower-pop asm (list r))))

; --- Prologue/epilogue helpers ---
; Mirror arm64's asm-prologue!/asm-epilogue!: frame pointer plus four
; callee-saved registers (rbx r12 r13 r14 here, x19-x22 there). At entry
; rsp % 16 == 8 (the return address); five 8-byte pushes make it 0, and
; every push/pop mnemonic moves 16 bytes, so rsp % 16 == 0 holds at every
; CALL site (SysV requires it).
;
; The prologue's last move puts the machine in the PORTABLE entry state:
; x0 (rax) = arg0.  SysV delivers arg0 in rdi and arg1 in rsi -- and rsi
; IS x1, so only arg0 needs moving.  From here on, compiled code sees
; the same register model on both architectures.
(def asm-prologue!
  (fn (_ asm)
    (%emit-bytes! asm
      (list 85                ; push rbp
            72 137 229        ; mov rbp, rsp
            83                ; push rbx
            65 84             ; push r12
            65 85             ; push r13
            65 86             ; push r14
            72 137 248))))    ; mov rax, rdi

(def asm-epilogue!
  (fn (_ asm)
    (%emit-bytes! asm
      (list 65 94             ; pop r14
            65 93             ; pop r13
            65 92             ; pop r12
            91                ; pop rbx
            93                ; pop rbp
            195))))           ; ret

; --- Load 64-bit immediate into register (REX.W B8+rd imm64) ---
; Counterpart of arm64's MOVZ+MOVK sequence; REX.B extends to r8-r15.
(def asm-load-imm64!
  (fn (_ asm rd-reg val)
    (def rd (if (pair? rd-reg) (%op-value rd-reg) rd-reg))
    (%emit-bytes! asm (list (if (> rd 7) 73 72)   ; 0x48 REX.W / 0x49 REX.WB
                            (| 184 (& rd 7))))    ; 0xB8+rd
    (%emit-u64-le! asm val)))

; --- Patch resolver: x86_64 rel32 ---
(def %x86_64-patch
  (fn (_ buf-ptr offset width ptype target)
    (def val (- target (+ offset width)))
    (%ptr-set! buf-ptr offset val width)))

; --- Export architecture ---
(set! %arch (list %x86_64-table %x86_64-dispatch %x86_64-patch))
