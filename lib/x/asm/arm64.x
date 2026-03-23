; asm/arm64.x -- ARM64 opcode table and fixed-width encoder

; --- Register aliases ---
(def x0  (reg 0))  (def x1  (reg 1))  (def x2  (reg 2))  (def x3  (reg 3))
(def x4  (reg 4))  (def x5  (reg 5))  (def x6  (reg 6))  (def x7  (reg 7))
(def x8  (reg 8))  (def x9  (reg 9))  (def x10 (reg 10)) (def x11 (reg 11))
(def x12 (reg 12)) (def x13 (reg 13)) (def x14 (reg 14)) (def x15 (reg 15))
(def x16 (reg 16)) (def x17 (reg 17)) (def x18 (reg 18)) (def x19 (reg 19))
(def x20 (reg 20)) (def x21 (reg 21)) (def x22 (reg 22)) (def x23 (reg 23))
(def x24 (reg 24)) (def x25 (reg 25)) (def x26 (reg 26)) (def x27 (reg 27))
(def x28 (reg 28)) (def x29 (reg 29)) (def x30 (reg 30)) (def sp  (reg 31))
(def xzr (reg 31))
(def lr  (reg 30))

; --- Encoder: build 32-bit instruction word from descriptor ---
; Descriptor: (base-opcode (arg-idx bit-pos bit-width shift) ...)
(def %arm64-encode
  (fn (_ asm descriptor args)
    (def word (first descriptor))
    (def fields (rest descriptor))
    (def %enc
      (fn (_ flds w)
        (if (null? flds) w
          (do
            (def f (first flds))
            (def idx   (nth 0 f))
            (def pos   (nth 1 f))
            (def width (nth 2 f))
            (def sh    (nth 3 f))
            (def arg (nth idx args))
            (def val
              (if (eq? (%op-type arg) (lit label))
                (do (asm-patch! asm 4 (lit arm64-rel) (%op-value arg)) 0)
                (%op-value arg)))
            (def mask (- (<< 1 width) 1))
            (def bits (<< (& (>> val sh) mask) pos))
            (%enc (rest flds) (| w bits))))))
    (%emit-u32-le! asm (%enc fields word))))

; --- MOVZ encoder: load 16-bit immediate into register ---
(def %arm64-encode-movz
  (fn (_ asm descriptor args)
    (def rd (%op-value (nth 0 args)))
    (def val (%op-value (nth 1 args)))
    ; MOVZ X<d>, #<imm16> = 0xD2800000 | (imm16 << 5) | Rd
    (def word (| 3531603968 (| (<< (& val 65535) 5) (& rd 31))))
    (%emit-u32-le! asm word)))

; --- Opcode table ---
; Constants verified with: python3 -c "print(hex(N))"
(def %arm64-table
  (list
    ; RET (return via x30)
    (pair (lit ret) (list
      (pair (lit ||) (list 3596551104))))      ; 0xD65F03C0

    ; NOP
    (pair (lit nop) (list
      (pair (lit ||) (list 3573751839))))      ; 0xD503201F

    ; MOV Xd, Xm (alias: ORR Xd, XZR, Xm)
    (pair (lit mov) (list
      (pair (lit rr) (list 2852127712         ; 0xAA0003E0
        (list 0 0 5 0)       ; Rd [4:0]
        (list 1 16 5 0)))    ; Rm [20:16]
      (pair (lit ri) (lit movz))))             ; delegate to MOVZ encoder

    ; ADD Xd, Xn, Xm (shifted register, 64-bit)
    (pair (lit add) (list
      (pair (lit rrr) (list 2332033024        ; 0x8B000000
        (list 0 0 5 0)       ; Rd
        (list 1 5 5 0)       ; Rn
        (list 2 16 5 0)))    ; Rm
      (pair (lit rri) (list 2432696320        ; 0x91000000
        (list 0 0 5 0)       ; Rd
        (list 1 5 5 0)       ; Rn
        (list 2 10 12 0))))) ; imm12

    ; SUB Xd, Xn, Xm
    (pair (lit sub) (list
      (pair (lit rrr) (list 3405774848        ; 0xCB000000
        (list 0 0 5 0)
        (list 1 5 5 0)
        (list 2 16 5 0)))
      (pair (lit rri) (list 3506438144        ; 0xD1000000
        (list 0 0 5 0)
        (list 1 5 5 0)
        (list 2 10 12 0)))))

    ; LDR Xt, [Xn, #imm12*8] (unsigned offset, 64-bit)
    (pair (lit ldr) (list
      (pair (lit rm) (list 4181721088         ; 0xF9400000
        (list 0 0 5 0)       ; Rt
        (list 1 5 5 0)       ; Rn (from mem)
        (list 1 10 12 3))))) ; imm12 (offset>>3)

    ; STR Xt, [Xn, #imm12*8]
    (pair (lit str) (list
      (pair (lit rm) (list 4177526784         ; 0xF9000000
        (list 0 0 5 0)
        (list 1 5 5 0)
        (list 1 10 12 3)))))

    ; B (unconditional branch, PC-relative)
    (pair (lit b) (list
      (pair (lit l) (list 335544320           ; 0x14000000
        (list 0 0 26 2)))))   ; imm26, offset>>2

    ; BL (branch with link)
    (pair (lit bl) (list
      (pair (lit l) (list 2483027968          ; 0x94000000
        (list 0 0 26 2)))))

    ; BR Xn (branch to register)
    (pair (lit br) (list
      (pair (lit r) (list 3592355840          ; 0xD61F0000
        (list 0 5 5 0)))))

    ; BLR Xn (branch with link to register)
    (pair (lit blr) (list
      (pair (lit r) (list 3594452992          ; 0xD63F0000
        (list 0 5 5 0)))))
  ))

; --- Dispatch encoder ---
(def %arm64-dispatch
  (fn (_ asm descriptor args)
    (if (eq? descriptor (lit movz))
      (%arm64-encode-movz asm () args)
      (%arm64-encode asm descriptor args))))

; --- Patch resolver: ARM64 PC-relative branches ---
; For B/BL: imm26 = (target - offset) >> 2, OR'd into low 26 bits
(def %arm64-patch
  (fn (_ buf-ptr offset width ptype target)
    (if (eq? ptype (lit arm64-rel))
      (do
        ; Read existing instruction word
        (def word (ptr-ref buf-ptr offset 4))
        ; Compute PC-relative offset in instruction units (>> 2)
        (def rel (>> (- target offset) 2))
        ; Mask to 26 bits and OR into instruction
        (def patched (| (& word (~ (- (<< 1 26) 1))) (& rel (- (<< 1 26) 1))))
        (ptr-set! buf-ptr offset patched 4))
      ; Generic fallback
      (ptr-set! buf-ptr offset (- target (+ offset width)) width))))

; --- Export architecture: (table . encoder . resolver) ---
(set! %arch (list %arm64-table %arm64-dispatch %arm64-patch))
