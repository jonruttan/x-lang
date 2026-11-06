; tool/asm/arm32.x -- 32-bit ARM (A32, VFPv3) opcode table and encoder: the
; assembler's backend on a 4-byte word.  A private component of the
; assembler, loaded by tool/asm.x where the platform declares `arm`; it
; references (reg n) from asm.x.
;
; PARITY BACKEND, as x86_64.x is.  asm-compile.x emits ONE vocabulary --
; arm64 mnemonics, portable register names, its three-argument call
; protocol -- and this file lowers it to A32.  What A32 lacks is lowered
; here, not taught to the compiler:
;
;   immediates  A32's are eight rotated bits, arm64's twelve or sixteen.  A
;               value past eight bits goes through lr first, MOVW then MOVT.
;   cbz/cbnz    there are none: CMP Rt, #0, then B.EQ or B.NE.
;   orn, xzr    there is no ORN and no zero register: MVN, and RSB #0 for
;               the negation the compiler spells (sub d xzr s).
;   adr         ADD Rd, PC, lr after loading the distance into lr, which
;               reaches the whole address space.
;   widths      a word is four bytes, so ldr and ldrw are one load and
;               ldrsw is ldr; a halfword's offset is eight bits.
;
; lr is the scratch.  The prologue saves it, a call through blr writes it,
; and nothing between a prologue and its epilogue reads it, so a lowering
; may load it freely.  An offset or an immediate past what one instruction
; holds costs two more.
;
; The double rows are the float stubs' (x/num/float.x): a double does not fit
; this machine's word, so a stub takes a double as TWO words and gives one
; back through a pointer.
;
; Encodings checked against GNU as (-march=armv7-a -mfpu=vfpv3-d16).

(import x/core/doors ptr-ref ptr-set!)

; --- Register aliases ---
; The portable model on this machine's registers, by role, as x86_64.x maps
; it:
;   x0-x3    r0-r3: a C call's first four words, and r0 its answer
;   x8       r12 (ip): the call target
;   x19-x22  r4-r7: callee-saved, the prologue keeps them -- p_base, p_args,
;            the argument accumulator, the slot base
;   xzr      a PSEUDO register (99): A32 has no zero register
; x4-x7 name r4-r7 too, which the float stubs use as scratch inside their
; own prologue.
(def x0 (reg 0))  (def x1 (reg 1))  (def x2 (reg 2))  (def x3 (reg 3))
(def x4 (reg 4))  (def x5 (reg 5))  (def x6 (reg 6))  (def x7 (reg 7))
(def x8 (reg 12))
(def x19 (reg 4)) (def x20 (reg 5)) (def x21 (reg 6)) (def x22 (reg 7))
(def xzr (reg 99))
(def fp (reg 11)) (def sp (reg 13)) (def lr (reg 14)) (def pc (reg 15))

; The double registers d0-d7: a C call's double arguments and its answer in
; the hard-float convention.  An FP operand is a (reg n) like any other; the
; mnemonic says which bank its fields name.  The single s(2n) is the low half
; of d(n), which the conversions use as their scratch.
(def d0 (reg 0)) (def d1 (reg 1)) (def d2 (reg 2)) (def d3 (reg 3))
(def d4 (reg 4)) (def d5 (reg 5)) (def d6 (reg 6)) (def d7 (reg 7))


; --- Load a word-sized immediate: MOVW then MOVT ---
; The name is the portable model's: what loads an address on every backend.
; An imm16 is split as the encoding wants it, imm4 at [19:16] and imm12 at
; [11:0].  MOVW Rd = 0xE3000000, MOVT Rd = 0xE3400000.
(def %arm32-imm16
  (fn (_ v) (| (<< (& (>> v 12) 15) 16) (& v 4095))))
(def %arm32-movw (fn (_ rd v) (| 0xE3000000 (| (<< (& rd 15) 12) (%arm32-imm16 (& v 65535))))))
(def %arm32-movt (fn (_ rd v) (| 0xE3400000 (| (<< (& rd 15) 12) (%arm32-imm16 (& (>> v 16) 65535))))))
(def asm-load-imm64!
  (fn (_ asm rd-reg val)
    (def rd (if (pair? rd-reg) (%op-value rd-reg) rd-reg))
    (%emit-u32-le! asm (%arm32-movw rd val))
    (%emit-u32-le! asm (%arm32-movt rd val))))

; --- Opcode table ---
; Every row is condition AL.  A symbol names a lowering in the dispatch
; below; a list is a descriptor for the field encoder.  The double registers
; here are d0-d15, which need no D, N or M extension bit.
(def %arm32-table
  (list
    (pair 'ret (list (pair '|| 'ret)))
    (pair 'nop (list (pair '|| 'nop)))
    (pair 'mov (list (pair 'rr 'mov) (pair 'ri 'movi)))

    ; The three-address integer family, the register and immediate forms
    (pair 'add  (list (pair 'rrr 'add) (pair 'rri 'addi)))
    (pair 'sub  (list (pair 'rrr 'sub) (pair 'rri 'subi)))
    (pair 'and  (list (pair 'rrr 'and)))
    (pair 'orr  (list (pair 'rrr 'orr)))
    (pair 'eor  (list (pair 'rrr 'eor)))
    (pair 'orn  (list (pair 'rrr 'orn)))
    (pair 'mul  (list (pair 'rrr 'mul)))
    (pair 'lslv (list (pair 'rrr 'lslv)))
    (pair 'lsrv (list (pair 'rrr 'lsrv)))
    (pair 'asrv (list (pair 'rrr 'asrv)))
    (pair 'sdiv (list (pair 'rrr 'sdiv)))
    (pair 'msub (list (pair 'rrrr 'msub)))
    (pair 'cmp  (list (pair 'rr 'cmp) (pair 'ri 'cmpi)))

    ; Loads and stores against (mem base offset), at every width the
    ; compiler names
    (pair 'ldr   (list (pair 'rm 'ldr)))
    (pair 'str   (list (pair 'rm 'str)))
    (pair 'ldrw  (list (pair 'rm 'ldr)))
    (pair 'ldrsw (list (pair 'rm 'ldr)))
    (pair 'strw  (list (pair 'rm 'str)))
    (pair 'ldrb  (list (pair 'rm 'ldrb)))
    (pair 'strb  (list (pair 'rm 'strb)))
    (pair 'ldrsb (list (pair 'rm 'ldrsb)))
    (pair 'ldrh  (list (pair 'rm 'ldrh)))
    (pair 'ldrsh (list (pair 'rm 'ldrsh)))
    (pair 'strh  (list (pair 'rm 'strh)))

    ; Branches.  B = 0xEA000000, BL = 0xEB000000, B<cond> = cond<<28 |
    ; 0x0A000000; each takes the 24-bit word offset the patcher fills in.
    (pair 'b    (list (pair 'l (list 0xEA000000 (list 0 0 24 0)))))
    (pair 'bl   (list (pair 'l (list 0xEB000000 (list 0 0 24 0)))))
    (pair 'b/eq (list (pair 'l (list 167772160 (list 0 0 24 0)))))      ; EQ 0
    (pair 'b/ne (list (pair 'l (list 436207616 (list 0 0 24 0)))))      ; NE 1
    (pair 'b/ge (list (pair 'l (list 0xAA000000 (list 0 0 24 0)))))     ; GE 10
    (pair 'b/lt (list (pair 'l (list 0xBA000000 (list 0 0 24 0)))))     ; LT 11
    (pair 'b/gt (list (pair 'l (list 0xCA000000 (list 0 0 24 0)))))     ; GT 12
    (pair 'b/le (list (pair 'l (list 0xDA000000 (list 0 0 24 0)))))     ; LE 13
    (pair 'cbz  (list (pair 'rl 'cbz)))
    (pair 'cbnz (list (pair 'rl 'cbnz)))
    (pair 'adr  (list (pair 'rl 'adr)))

    ; BLX Rm, BX Rm: the calls and jumps through a register
    (pair 'blr (list (pair 'r (list 0xE12FFF30 (list 0 0 4 0)))))       ; 0xE12FFF30
    (pair 'br  (list (pair 'r (list 0xE12FFF10 (list 0 0 4 0)))))       ; 0xE12FFF10

    (pair 'push (list (pair 'r 'push)))
    (pair 'pop  (list (pair 'r 'pop)))

    ; --- The VFP bank ---
    ; VMOV Dm, Rt, Rt2: two words into a double, the low word first
    (pair 'fmov/d2 (list
      (pair 'rrr (list 0xEC400B10         ; 0xEC400B10
        (list 0 0 4 0)       ; Dm
        (list 1 12 4 0)      ; Rt (low word)
        (list 2 16 4 0)))))  ; Rt2 (high word)
    ; VMOV Rt, Rt2, Dm: a double out as two words, the low word first
    (pair 'fmov/x2 (list
      (pair 'rrr (list 0xEC500B10         ; 0xEC500B10
        (list 0 12 4 0)      ; Rt (low word)
        (list 1 16 4 0)      ; Rt2 (high word)
        (list 2 0 4 0)))))   ; Dm

    ; VADD/VSUB/VMUL/VDIV.F64 Dd, Dn, Dm
    (pair 'fadd (list
      (pair 'rrr (list 0xEE300B00         ; 0xEE300B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fsub (list
      (pair 'rrr (list 0xEE300B40         ; 0xEE300B40
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fmul (list
      (pair 'rrr (list 0xEE200B00         ; 0xEE200B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fdiv (list
      (pair 'rrr (list 0xEE800B00         ; 0xEE800B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))

    ; VSTR Dd, [Rn, #imm8*4] / VLDR: a double through a pointer
    (pair 'fstr (list
      (pair 'rm (list 0xED800B00          ; 0xED800B00
        (list 0 12 4 0)      ; Dd
        (list 1 16 4 0)      ; Rn from mem base
        (list 1 0 8 2 1))))) ; imm8 from mem offset, >>2
    (pair 'fldr (list
      (pair 'rm (list 0xED900B00          ; 0xED900B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 1 0 8 2 1)))))

    ; The conversions and compares are lowerings: each is two or three
    ; instructions through the single s(2n) that is d(n)'s low half, which
    ; they clobber.
    (pair 'scvtf (list (pair 'rr 'scvtf)))       ; Dd <- Xn (int -> double)
    (pair 'fcvtzs (list (pair 'rr 'fcvtzs)))     ; Xd <- Dn (double -> int, toward zero)
    (pair 'fcvt/s (list (pair 'rr 'fcvt/s)))     ; Xd <- Dn (double -> a single's bits)
    (pair 'fcvt/d (list (pair 'rr 'fcvt/d)))     ; Dd <- Xn (a single's bits -> double)
    (pair 'scvtf/s (list (pair 'rr 'scvtf/s)))   ; Xd <- Xn (int -> a single's bits)
    (pair 'flt (list (pair 'rrr 'flt)))          ; Xd = Dn < Dm
    (pair 'feq (list (pair 'rrr 'feq)))          ; Xd = Dn = Dm
  ))

; --- Prologue/epilogue helpers ---
; asm-push!/asm-pop!: one register to or from a 16-byte stack slot, the
; slot arm64 and x86-64 push, so the compiler's slot arithmetic is the same
; on every backend.  STR Rt, [SP, #-16]! = 0xE52D0010 | Rt<<12; LDR Rt,
; [SP], #16 = 0xE49D0010 | Rt<<12.
(def asm-push!
  (fn (_ asm r)
    (%emit-u32-le! asm (| 0xE52D0010 (<< (& (first (rest r)) 15) 12)))))
(def asm-pop!
  (fn (_ asm r)
    (%emit-u32-le! asm (| 0xE49D0010 (<< (& (first (rest r)) 15) 12)))))

; asm-prologue!: PUSH {r4-r7, r11, lr}; MOV r11, sp.  Six words, so the
; stack stays 8-byte aligned as the convention asks at a call, and a
; caller's fifth word argument is at [sp, #24] from here on.
(def asm-prologue!
  (fn (_ asm)
    (%emit-u32-le! asm 0xE92D48F0)    ; push {r4, r5, r6, r7, r11, lr} 0xE92D48F0
    (%emit-u32-le! asm 0xE1A0B00D)))  ; mov r11, sp                   0xE1A0B00D

; The byte offset of a caller's Nth word argument (from 0) from sp inside
; the prologue's frame: the first four travel in r0-r3, the rest at [sp]
; on entry, which the push moved by 24.
(def asm-stack-arg
  (fn (_ n) (+ 24 (* 4 (- n 4)))))

; asm-frame-base!: x22 (r7) = sp, the base of the parameter slots a function
; pushes after its prologue.  MOV r7, sp = 0xE1A0700D.
(def asm-frame-base!
  (fn (_ asm)
    (%emit-u32-le! asm 0xE1A0700D)))

; asm-epilogue!: POP {r4-r7, r11, pc}: the return is the pop into pc.
(def asm-epilogue!
  (fn (_ asm)
    (%emit-u32-le! asm 0xE8BD88F0)))  ; pop {r4, r5, r6, r7, r11, pc} 0xE8BD88F0

; --- The lowerings ---
; One closure holds the encoder, the lowerings and their tables, and answers
; the dispatch: they bind nowhere else.
(def %arm32-dispatch
  ((fn (_)
    (def %arm32-zr 99)
    (def %arm32-lr 14)

    (def %arm32-nth
      (fn (self n xs) (if (= n 0) (first xs) (self (- n 1) (rest xs)))))

    ; --- Encoder: build a 32-bit instruction word from a descriptor ---
    ; Descriptor: (base-opcode (arg-idx bit-pos bit-width shift [sub]) ...); sub
    ; picks into a mem operand, 0 the base register and 1 the offset.
    (def %arm32-encode
      (fn (_ asm descriptor args)
        (def word (first descriptor))
        (def fields (rest descriptor))
        (def %enc
          (fn (self flds w)
            (if (null? flds) w
              (let ((f (first flds)))
                (def r1 (rest f))
                (def r2 (rest r1))
                (def r3 (rest r2))
                (def r4 (rest r3))
                (def idx   (first f))
                (def pos   (first r1))
                (def width (first r2))
                (def sh    (first r3))
                (def arg (%arm32-nth idx args))
                (def sub (if (null? r4) 0 (first r4)))
                (def val
                  (if (eq? (%op-type arg) 'label)
                    (do (asm-patch! asm 4 'arm32-rel24 (%op-value arg)) 0)
                    (if (= sub 0)
                      (%op-value arg)
                      (%arm32-nth (+ sub 1) arg))))
                (def mask (- (<< 1 width) 1))
                (def bits (<< (& (>> val sh) mask) pos))
                (self (rest flds) (| w bits))))))
        (%emit-u32-le! asm (%enc fields word))))

    (def %arm32-w! (fn (_ asm word) (%emit-u32-le! asm word)))

    ; A data-processing word: OP | Rn<<16 | Rd<<12 | Rm.
    (def %arm32-dp
      (fn (_ op rd rn rm) (| op (| (<< rn 16) (| (<< rd 12) rm)))))

    ; A source register, with the zero register loaded into lr: MOV lr, #0 =
    ; 0xE3A0E000.
    (def %arm32-src!
      (fn (_ asm r)
        (if (= r %arm32-zr) (do (%arm32-w! asm 0xE3A0E000) %arm32-lr) r)))

    ; VALUE into lr, whole, and lr's number back.
    (def %arm32-lr!
      (fn (_ asm v)
        (do (%arm32-w! asm (%arm32-movw %arm32-lr v))
            (%arm32-w! asm (%arm32-movt %arm32-lr v))
            %arm32-lr)))

    ; Rd = Rn OP #imm where an eight-bit immediate holds it (IMM-OP), else
    ; through lr (REG-OP).
    (def %arm32-imm-op!
      (fn (_ asm imm-op reg-op rd rn v)
        (if (and (>= v 0) (<= v 255))
          (%arm32-w! asm (| imm-op (| (<< rn 16) (| (<< rd 12) v))))
          (%arm32-w! asm (%arm32-dp reg-op rd rn (%arm32-lr! asm v))))))

    ; A load or store of a word or a byte: LDR/STR Rt, [Rn, #+-imm12].  BASE is
    ; the word with U clear (an offset below zero); U is bit 23.  An offset past
    ; twelve bits is added into lr first.
    (def %arm32-ls!
      (fn (_ asm base rt rn off)
        (if (and (> off -4096) (< off 4096))
          (%arm32-w! asm (| base (| (if (< off 0) 0 8388608)
                              (| (<< rn 16) (| (<< rt 12) (if (< off 0) (- 0 off) off))))))
          (do (%arm32-lr! asm off)
              (%arm32-w! asm (%arm32-dp 0xE0800000 %arm32-lr rn %arm32-lr))   ; add lr, rn, lr
              (%arm32-w! asm (| base (| 8388608 (| (<< %arm32-lr 16) (<< rt 12)))))))))

    ; The halfword and signed-byte forms: the offset is eight bits, split
    ; imm4H at [11:8] and imm4L at [3:0].
    (def %arm32-ls-half!
      (fn (_ asm base rt rn off)
        (if (and (> off -256) (< off 256))
          ((fn (_ a)
             (%arm32-w! asm (| base (| (if (< off 0) 0 8388608)
                                 (| (<< rn 16) (| (<< rt 12) (| (<< (>> a 4) 8) (& a 15))))))))
           (if (< off 0) (- 0 off) off))
          (do (%arm32-lr! asm off)
              (%arm32-w! asm (%arm32-dp 0xE0800000 %arm32-lr rn %arm32-lr))
              (%arm32-w! asm (| base (| 8388608 (| (<< %arm32-lr 16) (<< rt 12)))))))))

    ; LOAD-STORE: a mem lowering's base word and its encoder.
    (def %arm32-mem-forms
      (list (pair 'ldr   (pair 0xE5100000 %arm32-ls!))       ; 0xE5100000
            (pair 'str   (pair 0xE5000000 %arm32-ls!))       ; 0xE5000000
            (pair 'ldrb  (pair 0xE5500000 %arm32-ls!))       ; 0xE5500000
            (pair 'strb  (pair 0xE5400000 %arm32-ls!))       ; 0xE5400000
            (pair 'ldrh  (pair 0xE15000B0 %arm32-ls-half!))  ; 0xE15000B0
            (pair 'strh  (pair 0xE14000B0 %arm32-ls-half!))  ; 0xE14000B0
            (pair 'ldrsb (pair 0xE15000D0 %arm32-ls-half!))  ; 0xE15000D0
            (pair 'ldrsh (pair 0xE15000F0 %arm32-ls-half!)))) ; 0xE15000F0

    ; The register-to-register family: Rd = Rn OP Rm.
    (def %arm32-rrr-forms
      (list (pair 'add 0xE0800000)     ; 0xE0800000
            (pair 'sub 0xE0400000)     ; 0xE0400000
            (pair 'and 0xE0000000)     ; 0xE0000000
            (pair 'orr 0xE1800000)     ; 0xE1800000
            (pair 'eor 0xE0200000)))   ; 0xE0200000

    ; The shifts by a register: MOV Rd, Rn, <shift> Rm = OP | Rd<<12 | Rm<<8 | Rn.
    (def %arm32-shift-forms
      (list (pair 'lslv 0xE1A00010)    ; 0xE1A00010
            (pair 'lsrv 0xE1A00030)    ; 0xE1A00030
            (pair 'asrv 0xE1A00050)))  ; 0xE1A00050

    ; A branch on CONDITION to LABEL, patched once the label is placed.
    (def %arm32-branch!
      (fn (_ asm cnd lname)
        (do (asm-patch! asm 4 'arm32-rel24 lname)
            (%arm32-w! asm (| 167772160 (<< cnd 28))))))

    ; The row of the form tables whose key is K, or ().
    (def %arm32-row
      (fn (self k xs)
        (if (null? xs) ()
          (if (eq? (first (first xs)) k) (first xs) (self k (rest xs))))))

    ; --- Dispatch encoder ---
    ; The double lowerings: VMOV Sn, Rt = 0xEE000A10 | Vn<<16 | Rt<<12 (N bit
    ; zero: Sn is s(2d), even), VMOV Rt, Sn = 0xEE100A10 likewise; VCVT.F64.S32
    ; Dd, Sm = 0xEEB80BC0 | Dd<<12 | Vm; VCVT.S32.F64 Sd, Dm = 0xEEBD0BC0 | Vd<<12
    ; | Dm (rounds toward zero); VCVT.F32.F64 Sd, Dm = 0xEEB70BC0; VCVT.F64.F32
    ; Dd, Sm = 0xEEB70AC0; VCVT.F32.S32 Sd, Sm = 0xEEB80AC0.  flt/feq: VCMP.F64
    ; Dn, Dm = 0xEEB40B40 | Dn<<12 | Dm, VMRS APSR_nzcv, FPSCR = 0xEEF1FA10, then
    ; MOV<cond> Rd, #1 and MOV<cond'> Rd, #0 on the pair a NaN leaves false, MI/PL
    ; for <, EQ/NE for =: MOV<c> Rd, #imm = 0x03A00000 | cond<<28 | Rd<<12 | imm.
    (fn (_ asm descriptor args)
      (if (pair? descriptor) (%arm32-encode asm descriptor args)
        (let ()
          ; The operands, as far as there are operands: rest of () raises, so
          ; each step is guarded by the one before it.  A mem operand's value
          ; is its base; its offset is A2's place in it.
          (def r1 (if (null? args) () (rest args)))
          (def r2 (if (null? r1) () (rest r1)))
          (def r3 (if (null? r2) () (rest r2)))
          (def a0 (if (null? args) 0 (%op-value (first args))))
          (def a1 (if (null? r1) 0 (%op-value (first r1))))
          (def a2 (if (null? r2) 0 (%op-value (first r2))))
          (def a3 (if (null? r3) 0 (%op-value (first r3))))
          (def rrr (%arm32-row descriptor %arm32-rrr-forms))
          (def shift (%arm32-row descriptor %arm32-shift-forms))
          (def memf (%arm32-row descriptor %arm32-mem-forms))
          (match
            ((not (null? memf))
              ((rest (rest memf)) asm (first (rest memf)) a0 a1 (first (rest (rest (first r1))))))
            ; sub d xzr s is the negation: RSB Rd, Rm, #0 = 0xE2600000
            ((and (eq? descriptor 'sub) (= a1 %arm32-zr))
              (%arm32-w! asm (| 0xE2600000 (| (<< a2 16) (<< a0 12)))))
            ((not (null? rrr))
              (%arm32-w! asm (%arm32-dp (rest rrr) a0 (%arm32-src! asm a1) (%arm32-src! asm a2))))
            ((not (null? shift))
              (%arm32-w! asm (| (rest shift) (| (<< a0 12) (| (<< (%arm32-src! asm a2) 8) (%arm32-src! asm a1))))))
            ; orn d xzr s is the complement: MVN Rd, Rm = 0xE1E00000; any other
            ; orn is MVN into lr, then ORR
            ((eq? descriptor 'orn)
              (if (= a1 %arm32-zr)
                (%arm32-w! asm (%arm32-dp 0xE1E00000 a0 0 a2))
                (do (%arm32-w! asm (%arm32-dp 0xE1E00000 %arm32-lr 0 a2))
                    (%arm32-w! asm (%arm32-dp 0xE1800000 a0 a1 %arm32-lr)))))
            ; MUL Rd, Rn, Rm = 0xE0000090 | Rd<<16 | Rm<<8 | Rn
            ((eq? descriptor 'mul)
              (%arm32-w! asm (| 0xE0000090 (| (<< a0 16) (| (<< a2 8) a1)))))
            ; SDIV Rd, Rn, Rm = 0xE710F010 | Rd<<16 | Rm<<8 | Rn
            ((eq? descriptor 'sdiv)
              (%arm32-w! asm (| 0xE710F010 (| (<< a0 16) (| (<< a2 8) a1)))))
            ; MLS Rd, Rn, Rm, Ra = 0xE0600090 | Rd<<16 | Ra<<12 | Rm<<8 | Rn:
            ; Rd = Ra - Rn*Rm, which is msub's
            ((eq? descriptor 'msub)
              (%arm32-w! asm (| 0xE0600090 (| (<< a0 16) (| (<< a3 12) (| (<< a2 8) a1))))))
            ((eq? descriptor 'addi) (%arm32-imm-op! asm 0xE2800000 0xE0800000 a0 a1 a2))
            ((eq? descriptor 'subi) (%arm32-imm-op! asm 0xE2400000 0xE0400000 a0 a1 a2))
            ; MOV Rd, Rm = 0xE1A00000; the zero register is MOV Rd, #0
            ((eq? descriptor 'mov)
              (if (= a1 %arm32-zr) (%arm32-w! asm (| 0xE3A00000 (<< a0 12)))
                (%arm32-w! asm (%arm32-dp 0xE1A00000 a0 0 a1))))
            ; MOVW takes what arm64's MOVZ does, sixteen bits; anything else is
            ; the whole word
            ((eq? descriptor 'movi)
              (if (and (>= a1 0) (<= a1 65535))
                (%arm32-w! asm (%arm32-movw a0 a1))
                (asm-load-imm64! asm a0 a1)))
            ; CMP Rn, Rm = 0xE1500000; CMP Rn, #imm8 = 0xE3500000
            ((eq? descriptor 'cmp)
              (%arm32-w! asm (%arm32-dp 0xE1500000 0 (%arm32-src! asm a0) (%arm32-src! asm a1))))
            ((eq? descriptor 'cmpi)
              (if (and (>= a1 0) (<= a1 255))
                (%arm32-w! asm (| 0xE3500000 (| (<< a0 16) a1)))
                (%arm32-w! asm (%arm32-dp 0xE1500000 0 a0 (%arm32-lr! asm a1)))))
            ; CMP Rt, #0, then B.EQ or B.NE
            ((eq? descriptor 'cbz)
              (do (%arm32-w! asm (| 0xE3500000 (<< a0 16))) (%arm32-branch! asm 0 a1)))
            ((eq? descriptor 'cbnz)
              (do (%arm32-w! asm (| 0xE3500000 (<< a0 16))) (%arm32-branch! asm 1 a1)))
            ; The distance into lr, then ADD Rd, PC, lr = 0xE08F0000 | Rd<<12 |
            ; 14; the patch, at the MOVW, fills the pair once the label is placed
            ((eq? descriptor 'adr)
              (do (asm-patch! asm 12 'arm32-adr a1)
                  (%arm32-w! asm (%arm32-movw %arm32-lr 0))
                  (%arm32-w! asm (%arm32-movt %arm32-lr 0))
                  (%arm32-w! asm (| 0xE08F0000 (| (<< a0 12) %arm32-lr)))))
            ((eq? descriptor 'push) (asm-push! asm (first args)))
            ((eq? descriptor 'pop) (asm-pop! asm (first args)))
            ((eq? descriptor 'ret) (%arm32-w! asm 0xE12FFF1E))       ; BX LR 0xE12FFF1E
            ((eq? descriptor 'nop) (%arm32-w! asm 0xE320F000))       ; 0xE320F000
            ((eq? descriptor 'scvtf)
              (do (%arm32-w! asm (| 0xEE000A10 (| (<< a0 16) (<< a1 12))))    ; vmov s(2d), r
                  (%arm32-w! asm (| 0xEEB80BC0 (| (<< a0 12) a0)))))          ; vcvt.f64.s32 d, s(2d)
            ((eq? descriptor 'fcvtzs)
              (do (%arm32-w! asm (| 0xEEBD0BC0 (| (<< a1 12) a1)))            ; vcvt.s32.f64 s(2d), d
                  (%arm32-w! asm (| 0xEE100A10 (| (<< a1 16) (<< a0 12))))))  ; vmov r, s(2d)
            ((eq? descriptor 'fcvt/s)
              (do (%arm32-w! asm (| 0xEEB70BC0 (| (<< a1 12) a1)))            ; vcvt.f32.f64 s(2d), d
                  (%arm32-w! asm (| 0xEE100A10 (| (<< a1 16) (<< a0 12))))))  ; vmov r, s(2d)
            ((eq? descriptor 'fcvt/d)
              (do (%arm32-w! asm (| 0xEE000A10 (| (<< a0 16) (<< a1 12))))    ; vmov s(2d), r
                  (%arm32-w! asm (| 0xEEB70AC0 (| (<< a0 12) a0)))))          ; vcvt.f64.f32 d, s(2d)
            ((eq? descriptor 'scvtf/s)
              ; through s0, the scratch, since the answer is an integer register
              (do (%arm32-w! asm (| 0xEE000A10 (<< a1 12)))                   ; vmov s0, r
                  (%arm32-w! asm 0xEEB80AC0)                                  ; vcvt.f32.s32 s0, s0
                  (%arm32-w! asm (| 0xEE100A10 (<< a0 12)))))                 ; vmov r, s0
            ((or (eq? descriptor 'flt) (eq? descriptor 'feq))
              (let ((yes (if (eq? descriptor 'flt) 4 0))     ; MI, EQ
                    (no  (if (eq? descriptor 'flt) 5 1)))    ; PL, NE
                (%arm32-w! asm (| 0xEEB40B40 (| (<< a1 12) a2)))              ; vcmp.f64 dn, dm
                (%arm32-w! asm 0xEEF1FA10)                                    ; vmrs APSR_nzcv, fpscr
                (%arm32-w! asm (| 60817409 (| (<< yes 28) (<< a0 12))))       ; mov<yes> rd, #1
                (%arm32-w! asm (| 60817408 (| (<< no 28) (<< a0 12))))))      ; mov<no> rd, #0
            (#t (Err raise 'value (Str append "asm: arm32 has no lowering " (symbol->str descriptor)) ())))))))))

; --- An address in reach of the whole executable ---
; adr already reaches every address on a 4-byte word, so the far form is it.
(def asm-adr-far!
  (fn (_ asm rd-reg lname)
    (asm-emit! asm 'adr (if (pair? rd-reg) rd-reg (reg rd-reg)) (label lname))))

; --- Patch resolver ---
; B/BL/B<cond>: the 24-bit word offset from the pipeline's pc, eight bytes
; on.  adr: the distance from the ADD's pc (the MOVW at OFFSET, the ADD
; eight bytes on, its pc eight more) into the MOVW/MOVT pair, the register
; read back from the MOVW.
(def %arm32-patch
  ((fn (_ i- i& i| i>> i+)
     (fn (_ buf-ptr offset width ptype target)
       (match
         ((eq? ptype 'arm32-rel24)
           (ptr-set! buf-ptr offset
             (i| (i& (ptr-ref buf-ptr offset 4) -16777216)
                 (i& (i>> (i- target (i+ offset 8)) 2) 16777215))
             4))
         ((eq? ptype 'arm32-adr)
           ((fn (_ d rd)
              (do (ptr-set! buf-ptr offset (%arm32-movw rd d) 4)
                  (ptr-set! buf-ptr (i+ offset 4) (%arm32-movt rd d) 4)))
            (i- target (i+ offset 16))
            (i& (i>> (ptr-ref buf-ptr offset 4) 12) 15)))
         (#t (ptr-set! buf-ptr offset (- target (+ offset width)) width)))))
   (prim-ref 'int '-) (prim-ref 'int '&) (prim-ref 'int '|) (prim-ref 'int '>>) (prim-ref 'int '+)))

; --- Export architecture: (table encoder patcher relocator) ---
(set! %arch (list %arm32-table %arm32-dispatch %arm32-patch %asm-reloc))
