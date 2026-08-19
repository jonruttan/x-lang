; asm.x -- Data-driven assembler: JIT machine code generation
(import x/core/list)
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %make-obj (prim-ref 'obj 'make))
(def %obj-ref (prim-ref 'obj 'ref))
(def %obj-set! (prim-ref 'obj 'set!))
(def %make-type (prim-ref 'type 'make))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))
(def %str->symbol (prim-ref 'str '->sym))

(import x/type/str)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->int (prim-ref 'ptr '->int))
(def %ptr-set! (prim-ref 'ptr 'set!))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))


; --- Platform detection ---
(def %asm-darwin? (Str includes? "darwin" x-machine))
; Darwin spells the A64 arch "arm64", GNU triplets spell it "aarch64".
(def %asm-arm64?
  (if (Str includes? "arm64" x-machine) #t
    (Str includes? "aarch64" x-machine)))


; --- mmap flags ---
(def %MAP-FLAGS
  (if %asm-darwin?
    (| 2 4096)    ; MAP_PRIVATE|MAP_ANON
    (| 2 32)))    ; MAP_PRIVATE|MAP_ANON (Linux)

; --- Memory management via C library (more portable than raw syscalls) ---
(def %libc (%dlopen () 1))
(def %c-mmap     (%dlsym %libc "mmap"))
(def %c-mprotect (%dlsym %libc "mprotect"))
(def %c-munmap   (%dlsym %libc "munmap"))
(def %c-icache   (%dlsym %libc "sys_icache_invalidate"))

(def %asm-mmap
  (fn (_ size)
    (%ptr-call %c-mmap 0 size 3 %MAP-FLAGS -1 0)))  ; PROT_READ|PROT_WRITE=3

(def %asm-mprotect-rx!
  (fn (_ ptr size)
    ; Flush icache on ARM (no-op if unavailable)
    (when (not (null? %c-icache))
      (%ptr-call %c-icache (%ptr->int ptr) size))
    ; Switch to read+execute
    (%ptr-call %c-mprotect (%ptr->int ptr) size 5)))  ; PROT_READ|PROT_EXEC=5

(def %asm-munmap
  (fn (_ ptr size)
    (%ptr-call %c-munmap (%ptr->int ptr) size)))

; --- Operand constructors ---
(def reg   (fn (_ n)        (list 'reg n)))
(def imm   (fn (_ v)        (list 'imm v)))
; A mem base may be a raw register NUMBER or a (reg n) OPERAND -- the
; alias form carries each backend's register mapping (x8 is r10 on
; x86-64), which retires the (mem x0 off)-vs-(mem 0 off) trap class:
; both spellings now mean the same thing.
(def mem   (fn (_ base off) (list 'mem (if (pair? base) (first (rest base)) base) off)))
(def label (fn (_ name)     (list 'label name)))

(def %op-type  (fn (_ op) (first op)))
(def %op-value (fn (_ op) (first (rest op))))

; Operand signature: (reg _) -> r, (imm _) -> i, (mem _ _) -> m, (label _) -> l
(def %op-sig
  (fn (_ op)
    (def t (first op))
    (if (eq? t 'reg) "r"
      (if (eq? t 'imm) "i"
        (if (eq? t 'mem) "m" "l")))))

; This file's emit path is the assembler's inner loop: every instruction
; of every compiled function goes through it, and a GENERATED body runs
; to thousands of instructions.  Class-dispatched helpers cost roughly
; 200us a call here against 11-26us for the identical work on raw prims
; -- (Assoc entry) measured at 226us against a hand-rolled walk over the
; same list at 26us, so ~90% of it is dispatch, not lookup.  Hence the
; raw walk below.  Same lesson as the digest's Vector access (#123): in
; a hot pure-x loop the scaffolding is the cost, not the work.
(def %asm-assq
  (fn (self k xs)
    (if (null? xs) ()
      (if (eq? (first (first xs)) k) (first xs) (self k (rest xs))))))

; A small integer key for the operand shape: base-5 digits, seeded at 1
; so leading operands stay significant.
(def %op-code
  (fn (_ op)
    (def t (first op))
    (if (eq? t 'reg) 1 (if (eq? t 'imm) 2 (if (eq? t 'mem) 3 4)))))
(def %args-key
  (fn (self args acc)
    (if (null? args) acc
      (self (rest args) (+ (* acc 5) (%op-code (first args)))))))

; Signature symbols are built ONCE per distinct operand shape.  The old
; path appended a fresh string per operand and interned the result on
; EVERY emit; the whole instruction set uses a handful of shapes, so the
; second and later emits of each shape now cost a walk over that handful.
(def %sig-cache ())
(def %asm-sig-intern
  (fn (_ k args)
    (def sym (%str->symbol
      (%fold (fn (_ acc op) (%str-append acc (%op-sig op))) "" args)))
    (set! %sig-cache (pair (pair k sym) %sig-cache))
    sym))
(def %args-sig
  (fn (_ args)
    (def k (%args-key args 1))
    (def hit (%asm-assq k %sig-cache))
    (if (null? hit) (%asm-sig-intern k args) (rest hit))))

; --- Buffer byte emitters ---
(def %emit-u8!
  (fn (_ asm byte)
    (def pos (%obj-ref asm 1))
    ; The buffer is ONE mmap'd region and nothing checked it: emitting
    ; past the capacity wrote into whatever followed the mapping and
    ; died with a segfault somewhere unrelated.  A function that
    ; outgrows its buffer has to say so instead.
    (if (>= pos (%obj-ref asm 2))
      (Err raise 'state "asm: code buffer full (raise the asm-new capacity)" ()))
    (%ptr-set! (%obj-ref asm 0) pos (& byte 255) 1)
    (%obj-set! asm 1 (+ pos 1))))

; A whole instruction at a time.  Going through %emit-u8! four times
; re-read the position, the capacity and the buffer pointer, and wrote
; the position back, for EVERY byte -- twenty prim calls to store four.
; The bookkeeping is done once here and the four stores share it, which
; is the bulk of what an emit costs once the encoder stops dispatching.
;
; The bound is checked ONCE, against the last byte of the word, so a
; word that would straddle the end still raises before anything is
; written -- a stricter guarantee than the per-byte check it replaces,
; which could write a partial instruction and then raise.
(def %emit-u32-le!
  (fn (_ asm val)
    (def pos (%obj-ref asm 1))
    (if (>= (+ pos 3) (%obj-ref asm 2))
      (Err raise 'state "asm: code buffer full (raise the asm-new capacity)" ()))
    (def buf (%obj-ref asm 0))
    (%ptr-set! buf pos            (& val 255) 1)
    (%ptr-set! buf (+ pos 1) (& (>> val 8) 255) 1)
    (%ptr-set! buf (+ pos 2) (& (>> val 16) 255) 1)
    (%ptr-set! buf (+ pos 3) (& (>> val 24) 255) 1)
    (%obj-set! asm 1 (+ pos 4))))

; A LIST of bytes in one call: single capacity check against the last
; byte, one position update.  The x86-64 backend's variable-length
; instructions emit through this -- per-BYTE %emit-u8! calls cost an
; interpreted call each (the #196 lesson: the scaffolding is the cost),
; and a 7-byte instruction was paying seven of them plus seven capacity
; checks and position writes.
(def %emit-bytes!
  (fn (_ asm bytes)
    (def n ((fn (self k xs) (if (null? xs) k (self (+ k 1) (rest xs)))) 0 bytes))
    (def pos (%obj-ref asm 1))
    (if (>= (+ pos (- n 1)) (%obj-ref asm 2))
      (Err raise 'state "asm: code buffer full (raise the asm-new capacity)" ()))
    (def buf (%obj-ref asm 0))
    ((fn (self p xs)
       (unless (null? xs)
         (do (%ptr-set! buf p (& (first xs) 255) 1)
             (self (+ p 1) (rest xs))))) pos bytes)
    (%obj-set! asm 1 (+ pos n))))

(def %emit-u64-le!
  (fn (_ asm val)
    (%emit-u32-le! asm (& val 4294967295))
    (%emit-u32-le! asm (>> val 32))))

; --- Assembler type ---
; 6 slots: buf-addr buf-pos buf-cap labels patches arch
(def %asm-type
  (%make-type "ASM"
    (list
      (pair 'write
        (fn (_ self)
          (display "<asm pos=" (%obj-ref self 1) ">")))
      (pair 'call
        (fn (_ self . args)
          (apply asm-emit! (pair self args)))))))

; GC: ASM objects are 6 fixed slots (labels/patches alists are heap
; pairs); without units the mark hook never traced them (same class as
; the vector-payload gap).
((prim-ref 'type 'set-units!) ((prim-ref 'type 'by-atom) %asm-type) 6)

; --- Architecture loading ---
; Each arch module sets %arch to (table . encoder)
(def %arch ())

; --- Public API ---

(def asm-new
  (fn (_ . rest)
    (def cap (if (null? rest) 4096 (first rest)))
    (def ptr (%asm-mmap cap))
    (if (null? ptr) (Err raise 'io "asm-new: mmap failed" ()))
    (def a (%make-obj %asm-type 6))
    (%obj-set! a 0 ptr)      ; buf-ptr (from ptr-call, PTR type)
    (%obj-set! a 1 0)        ; buf-pos
    (%obj-set! a 2 cap)      ; buf-cap
    (%obj-set! a 3 ())       ; labels
    (%obj-set! a 4 ())       ; patches
    (%obj-set! a 5 %arch)    ; (table . encoder)
    a))

(def asm-emit!
  (fn (_ asm mnemonic . args)
    (def arch (%obj-ref asm 5))
    (def entry (%asm-assq mnemonic (first arch)))
    (if (null? entry) (Err raise 'value (Str append "asm: unknown mnemonic: " (symbol->str mnemonic)) ()))
    ; Match operand signature
    (def sig (if (null? args) '|| (%args-sig args)))
    (def variant (%asm-assq sig (rest entry)))
    (if (null? variant)
      (Err raise 'value (Str append "asm: no variant " (symbol->str sig) " for " (symbol->str mnemonic)) ()))
    ; arch is (table encoder); the encoder is its second element.
    ((first (rest arch)) asm (rest variant) args)))

(def asm-label!
  (fn (_ asm name)
    (%obj-set! asm 3 (pair (pair name (%obj-ref asm 1)) (%obj-ref asm 3)))))

(def asm-patch!
  (fn (_ asm width type label-name)
    (def offset (%obj-ref asm 1))
    (%obj-set! asm 4
      (pair (list offset width type label-name) (%obj-ref asm 4)))))

(def asm-pos
  (fn (_ asm) (%obj-ref asm 1)))

(def asm-finalize!
  (fn (_ asm)
    (def labels (%obj-ref asm 3))
    (def patches (%obj-ref asm 4))
    (def buf-ptr (%obj-ref asm 0))
    ; Resolve patches (arch-specific resolver in slot 2 of arch)
    (def arch (%obj-ref asm 5))
    (def resolver (when (> (%length arch) 2) (List ref 2 arch)))
    (%for-each
      (fn (_ patch)
        (def offset (List ref 0 patch))
        (def width  (List ref 1 patch))
        (def ptype  (List ref 2 patch))
        (def lname  (List ref 3 patch))
        (def target-entry (Assoc entry lname labels))
        (if (null? target-entry)
          (Err raise 'value (Str append "asm: unresolved label: " (symbol->str lname)) ()))
        (def target (rest target-entry))
        (if (not (null? resolver))
          (resolver buf-ptr offset width ptype target)
          ; Generic fallback: relative offset
          (let ((val (if (eq? ptype 'rel)
                       (- target (+ offset width))
                       target)))
            (%ptr-set! buf-ptr offset val width))))
      patches)
    ; Make executable (includes icache flush on ARM)
    (%asm-mprotect-rx! buf-ptr (%obj-ref asm 2))
    ; Return the pointer (callable via ptr-call)
    buf-ptr))

(def asm-free!
  (fn (_ asm)
    (%asm-munmap (%obj-ref asm 0) (%obj-ref asm 2))
    ()))

; --- Load architecture ---
; import, not a path literal: resolves through the import roots so the
; backend loads in an installed tree too.
(if %asm-arm64?
  (import x/tool/asm/arm64)
  (import x/tool/asm/x86_64))

(doc (provide x/asm
  asm-new asm-emit! asm-label! asm-patch! asm-pos asm-finalize! asm-free!
  reg imm mem label)
  "Data-driven assembler with JIT execution via mmap.")
