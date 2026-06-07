; asm.x -- Data-driven assembler: JIT machine code generation
(import x/core/list)
(import x/type/str)

; --- Platform detection ---
(def %asm-darwin? (Str contains? "darwin" x-machine))
(def %asm-arm64? (Str contains? "arm64" x-machine))

; --- Syscall numbers ---
(def %SYS-mmap     (if %asm-darwin? 197 9))
(def %SYS-mprotect (if %asm-darwin? 74 10))
(def %SYS-munmap   (if %asm-darwin? 73 11))

; --- mmap flags ---
(def %MAP-FLAGS
  (if %asm-darwin?
    (| 2 4096)    ; MAP_PRIVATE|MAP_ANON
    (| 2 32)))    ; MAP_PRIVATE|MAP_ANON (Linux)

; --- Memory management via C library (more portable than raw syscalls) ---
(def %libc (dlopen () 1))
(def %c-mmap     (dlsym %libc "mmap"))
(def %c-mprotect (dlsym %libc "mprotect"))
(def %c-munmap   (dlsym %libc "munmap"))
(def %c-icache   (dlsym %libc "sys_icache_invalidate"))

(def %asm-mmap
  (fn (_ size)
    (ptr-call %c-mmap 0 size 3 %MAP-FLAGS -1 0)))  ; PROT_READ|PROT_WRITE=3

(def %asm-mprotect-rx!
  (fn (_ ptr size)
    ; Flush icache on ARM (no-op if unavailable)
    (if (not (null? %c-icache))
      (ptr-call %c-icache (ptr->int ptr) size) ())
    ; Switch to read+execute
    (ptr-call %c-mprotect (ptr->int ptr) size 5)))  ; PROT_READ|PROT_EXEC=5

(def %asm-munmap
  (fn (_ ptr size)
    (ptr-call %c-munmap (ptr->int ptr) size)))

; --- Operand constructors ---
(def reg   (fn (_ n)        (list (lit reg) n)))
(def imm   (fn (_ v)        (list (lit imm) v)))
(def mem   (fn (_ base off) (list (lit mem) base off)))
(def label (fn (_ name)     (list (lit label) name)))

(def %op-type  (fn (_ op) (first op)))
(def %op-value (fn (_ op) (first (rest op))))

; Operand signature: (reg _) -> r, (imm _) -> i, (mem _ _) -> m, (label _) -> l
(def %op-sig
  (fn (_ op)
    (def t (first op))
    (if (eq? t (lit reg)) "r"
      (if (eq? t (lit imm)) "i"
        (if (eq? t (lit mem)) "m" "l")))))

; Build signature symbol from operand list: (reg _) (reg _) (imm _) -> rri
(def %args-sig
  (fn (_ args)
    (str->symbol
      (fold (fn (_ acc op) (str-append acc (%op-sig op))) "" args))))

; --- Buffer byte emitters ---
(def %emit-u8!
  (fn (_ asm byte)
    (def pos (obj-ref asm 1))
    (ptr-set! (obj-ref asm 0) pos (& byte 255) 1)
    (obj-set! asm 1 (+ pos 1))))

(def %emit-u32-le!
  (fn (_ asm val)
    (%emit-u8! asm (& val 255))
    (%emit-u8! asm (& (>> val 8) 255))
    (%emit-u8! asm (& (>> val 16) 255))
    (%emit-u8! asm (& (>> val 24) 255))))

(def %emit-u64-le!
  (fn (_ asm val)
    (%emit-u32-le! asm (& val 4294967295))
    (%emit-u32-le! asm (>> val 32))))

; --- Assembler type ---
; 6 slots: buf-addr buf-pos buf-cap labels patches arch
(def %asm-type
  (make-type "ASM"
    (list
      (pair (lit write)
        (fn (_ self)
          (display "<asm pos=")
          (display (obj-ref self 1))
          (display ">")))
      (pair (lit call)
        (fn (_ self . args)
          (apply asm-emit! (pair self args)))))))

; --- Architecture loading ---
; Each arch module sets %arch to (table . encoder)
(def %arch ())

; --- Public API ---

(def asm-new
  (fn (_ . rest)
    (def cap (if (null? rest) 4096 (first rest)))
    (def ptr (%asm-mmap cap))
    (if (null? ptr) (error "asm-new: mmap failed"))
    (def a (make-obj %asm-type 6))
    (obj-set! a 0 ptr)      ; buf-ptr (from ptr-call, PTR type)
    (obj-set! a 1 0)        ; buf-pos
    (obj-set! a 2 cap)      ; buf-cap
    (obj-set! a 3 ())       ; labels
    (obj-set! a 4 ())       ; patches
    (obj-set! a 5 %arch)    ; (table . encoder)
    a))

(def asm-emit!
  (fn (_ asm mnemonic . args)
    (def arch (obj-ref asm 5))
    (def table (nth 0 arch))
    (def encode (nth 1 arch))
    (def entry (List assq mnemonic table))
    (if (null? entry) (error (Str append "asm: unknown mnemonic: " (symbol->str mnemonic))))
    ; Match operand signature
    (def sig (if (null? args) (lit ||) (%args-sig args)))
    (def variant (List assq sig (rest entry)))
    (if (null? variant)
      (error (Str append "asm: no variant " (symbol->str sig) " for " (symbol->str mnemonic))))
    (encode asm (rest variant) args)))

(def asm-label!
  (fn (_ asm name)
    (obj-set! asm 3 (pair (pair name (obj-ref asm 1)) (obj-ref asm 3)))))

(def asm-patch!
  (fn (_ asm width type label-name)
    (def offset (obj-ref asm 1))
    (obj-set! asm 4
      (pair (list offset width type label-name) (obj-ref asm 4)))))

(def asm-pos
  (fn (_ asm) (obj-ref asm 1)))

(def asm-finalize!
  (fn (_ asm)
    (def labels (obj-ref asm 3))
    (def patches (obj-ref asm 4))
    (def buf-ptr (obj-ref asm 0))
    ; Resolve patches (arch-specific resolver in slot 2 of arch)
    (def arch (obj-ref asm 5))
    (def resolver (if (> (length arch) 2) (nth 2 arch) ()))
    (for-each
      (fn (_ patch)
        (def offset (nth 0 patch))
        (def width  (nth 1 patch))
        (def ptype  (nth 2 patch))
        (def lname  (nth 3 patch))
        (def target-entry (List assq lname labels))
        (if (null? target-entry)
          (error (Str append "asm: unresolved label: " (symbol->str lname))))
        (def target (rest target-entry))
        (if (not (null? resolver))
          (resolver buf-ptr offset width ptype target)
          ; Generic fallback: relative offset
          (let ((val (if (eq? ptype (lit rel))
                       (- target (+ offset width))
                       target)))
            (ptr-set! buf-ptr offset val width))))
      patches)
    ; Make executable (includes icache flush on ARM)
    (%asm-mprotect-rx! buf-ptr (obj-ref asm 2))
    ; Return the pointer (callable via ptr-call)
    buf-ptr))

(def asm-free!
  (fn (_ asm)
    (%asm-munmap (obj-ref asm 0) (obj-ref asm 2))
    ()))

; --- Load architecture ---
(if %asm-arm64?
  (include "lib/x/platform/arm64.x")
  (include "lib/x/platform/x86_64.x"))

(doc (provide x/asm
  asm-new asm-emit! asm-label! asm-patch! asm-pos asm-finalize! asm-free!
  reg imm mem label)
  "Data-driven assembler with JIT execution via mmap.")
