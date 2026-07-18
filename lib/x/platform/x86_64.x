; asm/x86_64.x -- x86_64 opcode table and variable-length encoder

; --- Register aliases (hardware encoding numbers) ---
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-set! (prim-ref 'ptr 'set!))

(def rax (reg 0))  (def rcx (reg 1))  (def rdx (reg 2))  (def rbx (reg 3))
(def rsp (reg 4))  (def rbp (reg 5))  (def rsi (reg 6))  (def rdi (reg 7))
(def r8  (reg 8))  (def r9  (reg 9))  (def r10 (reg 10)) (def r11 (reg 11))
(def r12 (reg 12)) (def r13 (reg 13)) (def r14 (reg 14)) (def r15 (reg 15))

; --- Helper: ModR/M byte ---
(def %modrm (fn (_ mod-val reg-val rm-val)
  (| (<< mod-val 6) (| (<< (& reg-val 7) 3) (& rm-val 7)))))

; --- Helper: REX prefix ---
(def %rex (fn (_ w r x b)
  (| 64 (| (<< w 3) (| (<< r 2) (| (<< x 1) b))))))

; --- Encoder ---
; Descriptor: (prefixes opcode modrm-spec extras)
; prefixes: list of prefix bytes
; opcode: list of opcode bytes (or (base-byte . opreg-arg-idx))
; modrm-spec: () | (reg-arg rm-arg) | ((/ digit) rm-arg)
;   A bare number is an ARGUMENT INDEX whose register fills the reg
;   field; the Intel /digit opcode extension is spelled (/ n). The two
;   were both bare numbers once, and number? dispatch made every
;   register-arg form encode as a /digit -- mov rax, rdi silently
;   became mov rax, rcx.
; extras: list of (kind arg-idx) for immediates/displacements

(def %x86_64-encode
  (fn (_ asm descriptor args)
    (def prefixes  (List ref 0 descriptor))
    (def opcode    (List ref 1 descriptor))
    (def modrm-spec (List ref 2 descriptor))
    (def extras    (List ref 3 descriptor))

    ; Emit REX prefix (handle regs > 7)
    (for-each (fn (_ b) (%emit-u8! asm b)) prefixes)

    ; Emit opcode
    (if (and (pair? opcode) (eq? (first opcode) 'opreg))
      ; Register encoded in low 3 bits of opcode byte
      (do
        (def base (List ref 1 opcode))
        (def rn (%op-value (List ref (List ref 2 opcode) args)))
        (%emit-u8! asm (| base (& rn 7))))
      ; Normal opcode byte sequence
      (for-each (fn (_ b) (%emit-u8! asm b)) opcode))

    ; Emit ModR/M if specified
    (if (not (null? modrm-spec))
      (do
        (def reg-src (List ref 0 modrm-spec))
        (def rm-idx  (List ref 1 modrm-spec))
        (def rm-arg (List ref rm-idx args))
        (def reg-val
          (if (pair? reg-src)
            (List ref 1 reg-src)              ; (/ n) opcode extension
            (%op-value (List ref reg-src args))))   ; register arg index
        (if (eq? (%op-type rm-arg) 'reg)
          ; reg-reg: mod=11
          (%emit-u8! asm (%modrm 3 reg-val (%op-value rm-arg)))
          ; mem: [base+disp]
          (do
            (def base (%op-value rm-arg))
            (def disp (List ref 2 (List ref rm-idx args)))
            (if (= disp 0)
              (%emit-u8! asm (%modrm 0 reg-val base))
              (if (and (>= disp -128) (<= disp 127))
                (do (%emit-u8! asm (%modrm 1 reg-val base))
                    (%emit-u8! asm (& disp 255)))
                (do (%emit-u8! asm (%modrm 2 reg-val base))
                    (%emit-u32-le! asm disp))))))))

    ; Emit immediates/extras
    (for-each
      (fn (_ spec)
        (def kind (List ref 0 spec))
        (def idx  (List ref 1 spec))
        (def val (%op-value (List ref idx args)))
        (if (eq? kind 'imm8)  (%emit-u8! asm (& val 255)))
        (if (eq? kind 'imm32) (%emit-u32-le! asm val))
        (if (eq? kind 'imm64) (%emit-u64-le! asm val))
        (if (eq? kind 'rel32)
          (do (asm-patch! asm 4 'rel (%op-value (List ref idx args)))
              (%emit-u32-le! asm 0))))
      extras)))

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
        (list (%rex 1 0 0 0))    ; REX.W
        (list 137)               ; 0x89
        (list 1 0)               ; ModR/M: reg=arg1, rm=arg0
        ()))
      ; MOV r64, imm64 (REX.W B8+rd imm64)
      (pair 'ri (list
        (list (%rex 1 0 0 0))
        (list 'opreg 184 0)  ; 0xB8 + rd
        ()
        (list (list 'imm64 1))))))

    ; ADD r64, r64 (REX.W 01 /r)
    (pair 'add (list
      (pair 'rr (list
        (list (%rex 1 0 0 0))
        (list 1)                 ; 0x01
        (list 1 0)               ; reg=arg1, rm=arg0
        ()))
      (pair 'ri (list
        (list (%rex 1 0 0 0))
        (list 129)               ; 0x81
        (list (list '/ 0) 0) ; /0 = ADD, rm=arg0
        (list (list 'imm32 1))))))

    ; SUB r64, r64 (REX.W 29 /r)
    (pair 'sub (list
      (pair 'rr (list
        (list (%rex 1 0 0 0))
        (list 41)                ; 0x29
        (list 1 0)
        ()))
      (pair 'ri (list
        (list (%rex 1 0 0 0))
        (list 129)               ; 0x81
        (list (list '/ 5) 0) ; /5 = SUB
        (list (list 'imm32 1))))))

    ; CMP r64, r64 (REX.W 39 /r) — flags from arg0 - arg1, matching
    ; arm64's operand order (cmp left right)
    (pair 'cmp (list
      (pair 'rr (list
        (list (%rex 1 0 0 0))
        (list 57)                ; 0x39
        (list 1 0)               ; reg=arg1, rm=arg0
        ()))
      (pair 'ri (list
        (list (%rex 1 0 0 0))
        (list 129)               ; 0x81
        (list (list '/ 7) 0) ; /7 = CMP
        (list (list 'imm32 1))))))

    ; JMP rel32
    (pair 'jmp (list
      (pair 'l (list () (list 233) ()           ; 0xE9
        (list (list 'rel32 0))))))

    ; B — arm64's name for the unconditional branch; same encoding as JMP
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

    ; CALL rel32
    (pair 'call (list
      (pair 'l (list () (list 232) ()           ; 0xE8
        (list (list 'rel32 0))))))
  ))

; --- Prologue/epilogue helpers ---
; Mirror arm64's asm-prologue!/asm-epilogue!: frame pointer plus four
; callee-saved registers (rbx r12 r13 r14 here, x19-x22 there). The even
; push count keeps rsp 16-byte aligned for any nested call (SysV requires
; rsp % 16 == 0 at each CALL site).
(def asm-prologue!
  (fn (_ asm)
    (%emit-u8! asm 85)                                          ; push rbp
    (%emit-u8! asm 72) (%emit-u8! asm 137) (%emit-u8! asm 229)  ; mov rbp, rsp
    (%emit-u8! asm 83)                                          ; push rbx
    (%emit-u8! asm 65) (%emit-u8! asm 84)                       ; push r12
    (%emit-u8! asm 65) (%emit-u8! asm 85)                       ; push r13
    (%emit-u8! asm 65) (%emit-u8! asm 86)))                     ; push r14

(def asm-epilogue!
  (fn (_ asm)
    (%emit-u8! asm 65) (%emit-u8! asm 94)                       ; pop r14
    (%emit-u8! asm 65) (%emit-u8! asm 93)                       ; pop r13
    (%emit-u8! asm 65) (%emit-u8! asm 92)                       ; pop r12
    (%emit-u8! asm 91)                                          ; pop rbx
    (%emit-u8! asm 93)                                          ; pop rbp
    (%emit-u8! asm 195)))                                       ; ret

; --- Load 64-bit immediate into register (REX.W B8+rd imm64) ---
; Counterpart of arm64's MOVZ+MOVK sequence; REX.B extends to r8-r15.
(def asm-load-imm64!
  (fn (_ asm rd-reg val)
    (def rd (if (pair? rd-reg) (%op-value rd-reg) rd-reg))
    (%emit-u8! asm (if (> rd 7) 73 72))     ; 0x48 REX.W / 0x49 REX.WB
    (%emit-u8! asm (| 184 (& rd 7)))        ; 0xB8+rd
    (%emit-u64-le! asm val)))

; --- Patch resolver: x86_64 rel32 ---
(def %x86_64-patch
  (fn (_ buf-ptr offset width ptype target)
    (def val (- target (+ offset width)))
    (%ptr-set! buf-ptr offset val width)))

; --- Export architecture ---
(set! %arch (list %x86_64-table %x86_64-encode %x86_64-patch))
