; asm/x86_64.x -- x86_64 opcode table and variable-length encoder

; --- Register aliases (hardware encoding numbers) ---
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
; modrm-spec: () | (reg-arg rm-arg) | (slash-val rm-arg)
; extras: list of (kind arg-idx) for immediates/displacements

(def %x86_64-encode
  (fn (_ asm descriptor args)
    (def prefixes  (nth 0 descriptor))
    (def opcode    (nth 1 descriptor))
    (def modrm-spec (nth 2 descriptor))
    (def extras    (nth 3 descriptor))

    ; Emit REX prefix (handle regs > 7)
    (for-each (fn (_ b) (%emit-u8! asm b)) prefixes)

    ; Emit opcode
    (if (and (pair? opcode) (eq? (first opcode) (lit opreg)))
      ; Register encoded in low 3 bits of opcode byte
      (do
        (def base (nth 1 opcode))
        (def rn (%op-value (nth (nth 2 opcode) args)))
        (%emit-u8! asm (| base (& rn 7))))
      ; Normal opcode byte sequence
      (for-each (fn (_ b) (%emit-u8! asm b)) opcode))

    ; Emit ModR/M if specified
    (if (not (null? modrm-spec))
      (do
        (def reg-src (nth 0 modrm-spec))
        (def rm-idx  (nth 1 modrm-spec))
        (def rm-arg (nth rm-idx args))
        (def reg-val
          (if (number? reg-src)
            reg-src                           ; /digit extension
            (%op-value (nth reg-src args))))   ; register arg
        (if (eq? (%op-type rm-arg) (lit reg))
          ; reg-reg: mod=11
          (%emit-u8! asm (%modrm 3 reg-val (%op-value rm-arg)))
          ; mem: [base+disp]
          (do
            (def base (%op-value rm-arg))
            (def disp (nth 2 (nth rm-idx args)))
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
        (def kind (nth 0 spec))
        (def idx  (nth 1 spec))
        (def val (%op-value (nth idx args)))
        (if (eq? kind (lit imm8))  (%emit-u8! asm (& val 255)))
        (if (eq? kind (lit imm32)) (%emit-u32-le! asm val))
        (if (eq? kind (lit imm64)) (%emit-u64-le! asm val))
        (if (eq? kind (lit rel32))
          (do (asm-patch! asm 4 (lit rel) (%op-value (nth idx args)))
              (%emit-u32-le! asm 0))))
      extras)))

; --- Opcode table ---
(def %x86_64-table
  (list
    ; RET
    (pair (lit ret) (list
      (pair (lit ||) (list () (list 195) () ()))))   ; 0xC3

    ; NOP
    (pair (lit nop) (list
      (pair (lit ||) (list () (list 144) () ()))))   ; 0x90

    ; MOV r64, r64  (REX.W 89 /r)
    (pair (lit mov) (list
      (pair (lit rr) (list
        (list (%rex 1 0 0 0))    ; REX.W
        (list 137)               ; 0x89
        (list 1 0)               ; ModR/M: reg=arg1, rm=arg0
        ()))
      ; MOV r64, imm64 (REX.W B8+rd imm64)
      (pair (lit ri) (list
        (list (%rex 1 0 0 0))
        (list (lit opreg) 184 0)  ; 0xB8 + rd
        ()
        (list (list (lit imm64) 1))))))

    ; ADD r64, r64 (REX.W 01 /r)
    (pair (lit add) (list
      (pair (lit rr) (list
        (list (%rex 1 0 0 0))
        (list 1)                 ; 0x01
        (list 1 0)               ; reg=arg1, rm=arg0
        ()))
      (pair (lit ri) (list
        (list (%rex 1 0 0 0))
        (list 129)               ; 0x81
        (list 0 0)               ; /0 = ADD, rm=arg0
        (list (list (lit imm32) 1))))))

    ; SUB r64, r64 (REX.W 29 /r)
    (pair (lit sub) (list
      (pair (lit rr) (list
        (list (%rex 1 0 0 0))
        (list 41)                ; 0x29
        (list 1 0)
        ()))
      (pair (lit ri) (list
        (list (%rex 1 0 0 0))
        (list 129)               ; 0x81
        (list 5 0)               ; /5 = SUB
        (list (list (lit imm32) 1))))))

    ; JMP rel32
    (pair (lit jmp) (list
      (pair (lit l) (list () (list 233) ()           ; 0xE9
        (list (list (lit rel32) 0))))))

    ; CALL rel32
    (pair (lit call) (list
      (pair (lit l) (list () (list 232) ()           ; 0xE8
        (list (list (lit rel32) 0))))))
  ))

; --- Patch resolver: x86_64 rel32 ---
(def %x86_64-patch
  (fn (_ buf-ptr offset width ptype target)
    (def val (- target (+ offset width)))
    (ptr-set! buf-ptr offset val width)))

; --- Export architecture ---
(set! %arch (list %x86_64-table %x86_64-encode %x86_64-patch))
