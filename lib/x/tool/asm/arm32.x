; tool/asm/arm32.x -- 32-bit ARM (A32, VFPv3) opcode table and fixed-width
; encoder: the assembler's backend on a 4-byte word.  A private component of
; the assembler, loaded by tool/asm.x where the platform declares `arm`; it
; references (reg n) from asm.x.
;
; THE VOCABULARY IS THE FLOAT STUBS'.  A double does not fit this machine's
; word, so x/num/float.x's stubs take a double as TWO words and give one back
; through a pointer, and the rows here are what those stubs emit: the moves
; between the core and VFP banks, the four operations, the compares, the
; conversions, a store through a pointer, a call.  The compiler's vocabulary
; (branches, labels, the integer family) is not here: asm-emit! raises on a
; mnemonic the table lacks, which is how the probe ahead of every compile
; finds the lane closed and keeps the interpreted twin.
;
; Encodings checked against clang's assembler (-target armv7-linux-gnueabihf).

(import x/core/doors ptr-ref ptr-set!)

; --- Register aliases ---
; The portable model's names, on this machine's registers: r0-r3 carry a C
; call's first four words and r0 its answer; r4-r7 are callee-saved, and the
; prologue keeps them; ip (r12) is the call-target register, so x8 names it
; and a stub's call sequence is the same on every backend.
(def x0 (reg 0))  (def x1 (reg 1))  (def x2 (reg 2))  (def x3 (reg 3))
(def x4 (reg 4))  (def x5 (reg 5))  (def x6 (reg 6))  (def x7 (reg 7))
(def x8 (reg 12))
(def fp (reg 11)) (def sp (reg 13)) (def lr (reg 14)) (def pc (reg 15))

; The double registers d0-d7: a C call's double arguments and its answer in
; the hard-float convention.  An FP operand is a (reg n) like any other; the
; mnemonic says which bank its fields name.  The single s(2n) is the low half
; of d(n), which the conversions use as their scratch.
(def d0 (reg 0)) (def d1 (reg 1)) (def d2 (reg 2)) (def d3 (reg 3))
(def d4 (reg 4)) (def d5 (reg 5)) (def d6 (reg 6)) (def d7 (reg 7))

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

; --- Load a word-sized immediate: MOVW then MOVT ---
; The name is the portable model's: what loads an address on every backend.
; An imm16 is split as the encoding wants it, imm4 at [19:16] and imm12 at
; [11:0].
(def %arm32-imm16
  (fn (_ v) (| (<< (& (>> v 12) 15) 16) (& v 4095))))
(def asm-load-imm64!
  (fn (_ asm rd-reg val)
    (def rd (if (pair? rd-reg) (%op-value rd-reg) rd-reg))
    ; MOVW Rd, #imm16 = 0xE3000000 | imm4<<16 | Rd<<12 | imm12
    (%emit-u32-le! asm (| 3808428032 (| (<< (& rd 15) 12) (%arm32-imm16 (& val 65535)))))
    ; MOVT Rd, #imm16 = 0xE3400000
    (%emit-u32-le! asm (| 3812622336 (| (<< (& rd 15) 12) (%arm32-imm16 (& (>> val 16) 65535)))))))

; --- Opcode table ---
; Every row is condition AL.  The double registers here are d0-d15, which
; need no D, N or M extension bit; the fields leave those bits zero.
(def %arm32-table
  (list
    ; BX LR
    (pair 'ret (list
      (pair '|| (list 3778019102))))       ; 0xE12FFF1E

    ; MOV Rd, Rm
    (pair 'mov (list
      (pair 'rr (list 3785359360          ; 0xE1A00000
        (list 0 12 4 0)      ; Rd
        (list 1 0 4 0)))     ; Rm
      ; MOV Rd, #imm8 (an unrotated 8-bit immediate)
      (pair 'ri (list 3818913792          ; 0xE3A00000
        (list 0 12 4 0)      ; Rd
        (list 1 0 8 0)))))   ; imm8

    ; LDR Rt, [Rn, #imm12] / STR
    (pair 'ldr (list
      (pair 'rm (list 3851419648          ; 0xE5900000
        (list 0 12 4 0)      ; Rt
        (list 1 16 4 0)      ; Rn from mem base (sub=0)
        (list 1 0 12 0 1))))) ; imm12 from mem offset (sub=1)
    (pair 'str (list
      (pair 'rm (list 3850371072          ; 0xE5800000
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 1 0 12 0 1)))))

    ; BLX Rm: the call through a register, as blr is on arm64
    (pair 'blr (list
      (pair 'r (list 3778019120           ; 0xE12FFF30
        (list 0 0 4 0)))))

    ; --- The VFP bank ---
    ; VMOV Dm, Rt, Rt2: two words into a double, the low word first
    (pair 'fmov/d2 (list
      (pair 'rrr (list 3963620112         ; 0xEC400B10
        (list 0 0 4 0)       ; Dm
        (list 1 12 4 0)      ; Rt (low word)
        (list 2 16 4 0)))))  ; Rt2 (high word)
    ; VMOV Rt, Rt2, Dm: a double out as two words, the low word first
    (pair 'fmov/x2 (list
      (pair 'rrr (list 3964668688         ; 0xEC500B10
        (list 0 12 4 0)      ; Rt (low word)
        (list 1 16 4 0)      ; Rt2 (high word)
        (list 2 0 4 0)))))   ; Dm

    ; VADD/VSUB/VMUL/VDIV.F64 Dd, Dn, Dm
    (pair 'fadd (list
      (pair 'rrr (list 3996125952         ; 0xEE300B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fsub (list
      (pair 'rrr (list 3996126016         ; 0xEE300B40
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fmul (list
      (pair 'rrr (list 3995077376         ; 0xEE200B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))
    (pair 'fdiv (list
      (pair 'rrr (list 4001368832         ; 0xEE800B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 2 0 4 0)))))

    ; VSTR Dd, [Rn, #imm8*4] / VLDR: a double through a pointer
    (pair 'fstr (list
      (pair 'rm (list 3984591616          ; 0xED800B00
        (list 0 12 4 0)      ; Dd
        (list 1 16 4 0)      ; Rn from mem base
        (list 1 0 8 2 1))))) ; imm8 from mem offset, >>2
    (pair 'fldr (list
      (pair 'rm (list 3985640192          ; 0xED900B00
        (list 0 12 4 0)
        (list 1 16 4 0)
        (list 1 0 8 2 1)))))

    ; The conversions and compares are lowerings (the dispatch below): each is
    ; two or three instructions through the single s(2n) that is d(n)'s low
    ; half, which they clobber.
    (pair 'scvtf (list (pair 'rr 'scvtf)))       ; Dd <- Xn (int -> double)
    (pair 'fcvtzs (list (pair 'rr 'fcvtzs)))     ; Xd <- Dn (double -> int, toward zero)
    (pair 'fcvt/s (list (pair 'rr 'fcvt/s)))     ; Xd <- Dn (double -> a single's bits)
    (pair 'fcvt/d (list (pair 'rr 'fcvt/d)))     ; Dd <- Xn (a single's bits -> double)
    (pair 'scvtf/s (list (pair 'rr 'scvtf/s)))   ; Xd <- Xn (int -> a single's bits)
    (pair 'flt (list (pair 'rrr 'flt)))          ; Xd = Dn < Dm
    (pair 'feq (list (pair 'rrr 'feq)))          ; Xd = Dn = Dm
  ))

; --- Prologue/epilogue helpers ---
; asm-push!/asm-pop!: one register to or from the stack.
; PUSH {Rt} = STR Rt, [SP, #-4]! = 0xE52D0004 | Rt<<12
; POP {Rt} = LDR Rt, [SP], #4 = 0xE49D0004 | Rt<<12
(def asm-push!
  (fn (_ asm r)
    (%emit-u32-le! asm (| 3844931588 (<< (& (first (rest r)) 15) 12)))))
(def asm-pop!
  (fn (_ asm r)
    (%emit-u32-le! asm (| 3835494404 (<< (& (first (rest r)) 15) 12)))))

; asm-prologue!: PUSH {r4-r7, r11, lr}; MOV r11, sp.  Six words, so the
; stack stays 8-byte aligned as the convention asks at a call, and a
; caller's fifth word argument is at [sp, #24] from here on.
(def asm-prologue!
  (fn (_ asm)
    (%emit-u32-le! asm 3912059120)    ; push {r4, r5, r6, r7, r11, lr} 0xE92D48F0
    (%emit-u32-le! asm 3785404429)))  ; mov r11, sp                   0xE1A0B00D

; The byte offset of a caller's Nth word argument (from 0) from sp inside
; the prologue's frame: the first four travel in r0-r3, the rest at [sp]
; on entry, which the push moved by 24.
(def asm-stack-arg
  (fn (_ n) (+ 24 (* 4 (- n 4)))))

; asm-epilogue!: POP {r4-r7, r11, pc}: the return is the pop into pc.
(def asm-epilogue!
  (fn (_ asm)
    (%emit-u32-le! asm 3904735472)))  ; pop {r4, r5, r6, r7, r11, pc} 0xE8BD88F0

; --- Dispatch encoder ---
; The lowerings.  VMOV Sn, Rt = 0xEE000A10 | Vn<<16 | Rt<<12 (N bit zero: Sn
; is s(2d), even), VMOV Rt, Sn = 0xEE100A10 likewise; VCVT.F64.S32 Dd, Sm =
; 0xEEB80BC0 | Dd<<12 | Vm; VCVT.S32.F64 Sd, Dm = 0xEEBD0BC0 | Vd<<12 | Dm
; (rounds toward zero); VCVT.F32.F64 Sd, Dm = 0xEEB70BC0; VCVT.F64.F32 Dd,
; Sm = 0xEEB70AC0; VCVT.F32.S32 Sd, Sm = 0xEEB80AC0.  flt/feq: VCMP.F64 Dn,
; Dm = 0xEEB40B40 | Dn<<12 | Dm, VMRS APSR_nzcv, FPSCR = 0xEEF1FA10, then
; MOV<cond> Rd, #1 and MOV<cond'> Rd, #0 on the pair a NaN leaves false, MI/PL
; for <, EQ/NE for =: MOV<c> Rd, #imm = 0x03A00000 | cond<<28 | Rd<<12 | imm.
(def %arm32-dispatch
  (fn (_ asm descriptor args)
    ; The operands' values, as far as there are operands: rest of () raises,
    ; so each step is guarded by the one before it.
    (def r1 (if (null? args) () (rest args)))
    (def r2 (if (null? r1) () (rest r1)))
    (def a0 (if (null? args) 0 (%op-value (first args))))
    (def a1 (if (null? r1) 0 (%op-value (first r1))))
    (def a2 (if (null? r2) 0 (%op-value (first r2))))
    (match
      ((eq? descriptor 'scvtf)
        (do (%emit-u32-le! asm (| 3992979984 (| (<< a0 16) (<< a1 12))))    ; vmov s(2d), r
            (%emit-u32-le! asm (| 4005039040 (| (<< a0 12) a0)))))          ; vcvt.f64.s32 d, s(2d)
      ((eq? descriptor 'fcvtzs)
        (do (%emit-u32-le! asm (| 4005366720 (| (<< a1 12) a1)))            ; vcvt.s32.f64 s(2d), d
            (%emit-u32-le! asm (| 3994028560 (| (<< a1 16) (<< a0 12))))))  ; vmov r, s(2d)
      ((eq? descriptor 'fcvt/s)
        (do (%emit-u32-le! asm (| 4004973504 (| (<< a1 12) a1)))            ; vcvt.f32.f64 s(2d), d
            (%emit-u32-le! asm (| 3994028560 (| (<< a1 16) (<< a0 12))))))  ; vmov r, s(2d)
      ((eq? descriptor 'fcvt/d)
        (do (%emit-u32-le! asm (| 3992979984 (| (<< a0 16) (<< a1 12))))    ; vmov s(2d), r
            (%emit-u32-le! asm (| 4004973248 (| (<< a0 12) a0)))))          ; vcvt.f64.f32 d, s(2d)
      ((eq? descriptor 'scvtf/s)
        ; through s0, the scratch, since the answer is an integer register
        (do (%emit-u32-le! asm (| 3992979984 (<< a1 12)))                   ; vmov s0, r
            (%emit-u32-le! asm 4005038784)                                  ; vcvt.f32.s32 s0, s0
            (%emit-u32-le! asm (| 3994028560 (<< a0 12)))))                 ; vmov r, s0
      ((or (eq? descriptor 'flt) (eq? descriptor 'feq))
        (let ((yes (if (eq? descriptor 'flt) 4 0))     ; MI, EQ
              (no  (if (eq? descriptor 'flt) 5 1)))    ; PL, NE
          (%emit-u32-le! asm (| 4004776768 (| (<< a1 12) a2)))              ; vcmp.f64 dn, dm
          (%emit-u32-le! asm 4008835600)                                    ; vmrs APSR_nzcv, fpscr
          (%emit-u32-le! asm (| 60817409 (| (<< yes 28) (<< a0 12))))       ; mov<yes> rd, #1
          (%emit-u32-le! asm (| 60817408 (| (<< no 28) (<< a0 12))))))      ; mov<no> rd, #0
      (#t (%arm32-encode asm descriptor args)))))

; --- Patch resolver: B/BL's 24-bit word offset, from the pipeline's pc ---
(def %arm32-patch
  ((fn (_ i- i& i| i>>)
     (fn (_ buf-ptr offset width ptype target)
       (match
         ((eq? ptype 'arm32-rel24)
           (ptr-set! buf-ptr offset
             (i| (i& (ptr-ref buf-ptr offset 4) -16777216)
                 (i& (i>> (i- target (+ offset 8)) 2) 16777215))
             4))
         (#t (ptr-set! buf-ptr offset (- target (+ offset width)) width)))))
   (prim-ref 'int '-) (prim-ref 'int '&) (prim-ref 'int '|) (prim-ref 'int '>>)))

; --- Export architecture: (table encoder patcher relocator) ---
(set! %arch (list %arm32-table %arm32-dispatch %arm32-patch %asm-reloc))
