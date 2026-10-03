; asm-code.x -- native code buffers: map, relocate, protect, free
;
; The part of the assembler that a function's bytes need once they exist,
; whoever produced them: a buffer mapped writable, the relocation records
; that say where its per-process addresses went, the relocator that writes
; those addresses again for this process, and the protect that makes the
; buffer executable.  The byte cache (asm-cache.x) pours a stored function
; into a fresh buffer with nothing else, so a process whose compiles all hit
; loads this file and not the encoder: asm.x and its backend's opcode table
; (lib/x/tool/asm/<arch>.x) come in only with the compiler, on a miss.
;
; Not a scoped module, for the same reason asm.x is not one: its names --
; asm-new, the relocation records, the facts about the function produced
; last -- are the assembler's own, and asm.x, the backends and the compiler
; read them as they always did.
(import x/core/list)
(import x/type/str)
(import x/platform/syscall)

; Fetch the raw-object, type and ptr/ffi prims from the catalogue (ns `obj`,
; `type`, `ptr` and `ffi` are de-registered, R5).
(def %make-obj (prim-ref 'obj 'make))
(def %obj-ref (prim-ref 'obj 'ref))
(def %obj-set! (prim-ref 'obj 'set!))
(def %make-type (prim-ref 'type 'make))
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->int (prim-ref 'ptr '->int))
(def %ptr-set! (prim-ref 'ptr 'set!))
(def %ptr-ref  (prim-ref 'ptr 'ref))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))

; --- Platform detection ---
; Read from the platform layer, not sniffed from x-machine here.  This module
; used to parse the triple itself, and it was the only one of three readers that
; knew Darwin spells A64 "arm64" while GNU triplets spell it "aarch64" -- so the
; knowledge lived in whichever file happened to need it most recently.  One
; parse, in lib/x/platform/syscall.x; tools/check/platform-seam.sh holds it there.
(def %asm-darwin? os-darwin?)
(def %asm-arm64? arch-arm64?)

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

; --- Assembler type ---
; 7 slots: buf-addr buf-pos buf-cap labels patches arch relocs.  Calling one
; emits through it, with asm.x's asm-emit!, which asm.x files in this slot when
; it loads -- the %asm-compiler pattern below, for the same reason: a buffer
; poured from the cache is made without asm.x, and is never called.
(def %asm-emit ())
(def %asm-type
  (%make-type "ASM"
    (list
      (pair 'write
        (fn (_ self)
          (display "<asm pos=" (%obj-ref self 1) ">")))
      (pair 'call
        (fn (_ self . args)
          (apply %asm-emit (pair self args)))))))

; GC: ASM objects are 7 fixed slots (labels/patches/relocs alists are heap
; pairs); without units the mark hook never traced them (same class as
; the vector-payload gap).
;
; THIS NUMBER MUST MATCH asm-new's %make-obj, and it did not.  It said 6 while
; asm-new made 7, from the commit that added the relocations slot (#598) -- so
; slot 6, the relocation records, was the one thing on a live builder the
; collector could not see.  One (Heap collect) with three records held turned
; them into a single nil: not a leak, a use-after-free, waiting for a
; collection to land between recording a site and reading it back.
((prim-ref 'type 'set-units!) ((prim-ref 'type 'by-atom) %asm-type) 7)

; --- Architecture ---
; The backend sets %arch to (table encoder patcher relocator) when it loads,
; with asm.x.  It is bound here, and bound only when it is not bound already:
; a second load of this file -- an amalgam that inlines it and a run-time
; import that finds it again -- must not empty a table the backend filled,
; which is the crash an amalgam once had when asm.x loaded twice.
(def %arch (guard (_ ()) %arch))

; The JIT runtime helpers asm-compile.x could not resolve.  It RECORDS them
; while it loads and refuses at the entry point rather than mid-import (#201);
; the name lives here so the entry point -- compile-asm, in asm-cache.x -- can
; consult it without loading the compiler to find out.  Empty is the honest
; answer before that file loads: nothing has tried to resolve anything yet,
; and a genuinely missing helper makes every cached trampoline fail to
; re-resolve, so the load misses and reaches the compiler's refusal anyway.
(def %jit-missing ())

; The fresh compiler, registered by asm-compile.x when it loads -- the same
; pattern as %arch above, and for the same reason: the seam has to be nameable
; by a file that does not import the one filling it in.  asm-cache.x is the
; compile-asm door and reaches the compiler only when the byte cache misses,
; so it imports asm-compile.x on that line and calls whatever landed HERE.
; A slot rather than a lazily-bound name because a name would have to be
; forward-declared, and a forward declaration loaded in the wrong order would
; overwrite the real definition with nil -- which in x does not raise: calling
; nil silently answers the form as data.
(def %asm-compiler ())

; --- The facts about the most recently produced native function -----------
; Set by whichever path produced it: asm-compile.x after it emits, asm-cache.x
; after it loads.  They live HERE, not in asm-compile.x where they started,
; because a warm cache never loads asm-compile.x -- and a reader of these
; (the relocation specs, a byte cache) must not have to care which path ran.
; The assembler object itself does not outlive either path, so these are the
; only way out for what it knew.  Read them immediately after a compile or not
; at all.
(def %asm-last-relocs ())
(def %asm-last-size 0)
; The code buffer itself, not a copy: the cache stores the bytes with one
; write(2) straight out of it.
(def %asm-last-buf ())

; --- Buffers ---
(def asm-new
  (fn (_ . rest)
    (def cap (if (null? rest) 4096 (first rest)))
    (def ptr (%asm-mmap cap))
    (if (null? ptr) (Err raise 'io "asm-new: mmap failed" ()))
    (def a (%make-obj %asm-type 7))
    (%obj-set! a 0 ptr)      ; buf-ptr (from ptr-call, PTR type)
    (%obj-set! a 1 0)        ; buf-pos
    (%obj-set! a 2 cap)      ; buf-cap
    (%obj-set! a 3 ())       ; labels
    (%obj-set! a 4 ())       ; patches
    (%obj-set! a 5 %arch)    ; (table encoder patcher relocator), or () before asm.x
    (%obj-set! a 6 ())       ; relocs: (offset label name), newest first
    a))

; --- Relocations: the per-process addresses baked into the code ----------
;
; A 64-bit immediate is how this assembler names anything outside the code
; it is emitting: a jit_* trampoline resolved by dlsym, an fvar's object
; pointer, the self-call trampoline cell.  Every one of those is an address
; valid only in the process that compiled -- which is exactly what stops the
; emitted bytes from being reusable.  Recording each site as
; (offset label name) is what makes them reusable: a loader can pour the same
; bytes into a fresh buffer and re-encode each immediate for the process it
; is loading into.  Nothing here changes what is emitted; it only writes down
; where the addresses went.
;
; LABEL is `trampoline` (NAME is the dlsym symbol), `fvar` (NAME is the free
; variable's symbol) or `self-cell` (NAME is nil -- there is one per compile).
(def asm-reloc!
  (fn (_ asm offset label name)
    (%obj-set! asm 6 (pair (list offset label name) (%obj-ref asm 6)))))

; Oldest-first, which is the order a loader wants to walk them.
(def asm-relocs
  (fn (_ asm)
    ((fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc))))
      (%obj-ref asm 6) ())))

; --- Relocate a 64-bit immediate in place: ARM64 (MOVZ + 3x MOVK) ---------
; The value is spread 16 bits to a word, so all four words are rewritten.
; The destination register is READ BACK from the existing MOVZ (its low five
; bits) rather than passed in: the site already encodes which register it
; loads, and re-deriving it keeps a relocation record down to an offset.
;
; The bit work goes through the integer primitives, not the generic operators:
; a cache hit runs this once per relocation site, and a lexer state has around
; thirty.  The generic & | << >> + dispatch on their operands' types; every
; operand here is a machine integer.  Thirty sites cost 3.3 ms generic and
; 0.57 ms through the primitives, the same bytes either way.
(def %arm64-reloc
  ((fn (_ band bor bshl bshr iadd)
     (fn (_ buf-ptr offset val)
       (def rd (band (%ptr-ref buf-ptr offset 4) 31))
       (%ptr-set! buf-ptr offset
         (bor 3531603968 (bor (bshl (band val 65535) 5) rd)) 4)
       (%ptr-set! buf-ptr (iadd offset 4)
         (bor 4070572032 (bor (bshl (band (bshr val 16) 65535) 5) rd)) 4)
       (%ptr-set! buf-ptr (iadd offset 8)
         (bor 4072669184 (bor (bshl (band (bshr val 32) 65535) 5) rd)) 4)
       (%ptr-set! buf-ptr (iadd offset 12)
         (bor 4074766336 (bor (bshl (band (bshr val 48) 65535) 5) rd)) 4)))
   (prim-ref 'int '&) (prim-ref 'int '|) (prim-ref 'int '<<)
   (prim-ref 'int '>>) (prim-ref 'int '+)))

; --- Relocate a 64-bit immediate in place: x86-64 (REX.W B8+rd imm64) -----
; The opcode is two bytes (REX.W, then B8+rd) and the immediate is stored
; flat after it, so one 8-byte store does the whole job -- no register to
; re-derive, unlike the ARM64 MOVZ/MOVK spread.
(def %x86_64-reloc
  (fn (_ buf-ptr offset val)
    (%ptr-set! buf-ptr (+ offset 2) val 8)))

; The host's relocator.  The backend lists it as its fourth part as well, but a
; buffer poured from the cache is made before -- and usually without -- the
; backend, so the relocator answers from here, not from the buffer's %arch.
(def %asm-reloc (if %asm-arm64? %arm64-reloc %x86_64-reloc))

; Re-encode the 64-bit immediate at OFFSET to VAL, in place.  MUST run while
; the buffer is still writable: asm-finalize! mprotects it R+X, and a write
; after that is a segfault, not an error.
; The relocator is fetched apart from the call so a loader can hoist it out of
; its loop and call the answer directly; asm-reloc-apply! is the one-shot form.
(def asm-relocator
  (fn (_ asm) %asm-reloc))

(def asm-reloc-apply!
  (fn (_ asm offset val)
    (%asm-reloc (%obj-ref asm 0) offset val)))

(def asm-finalize!
  (fn (_ asm)
    (def labels (%obj-ref asm 3))
    (def patches (%obj-ref asm 4))
    (def buf-ptr (%obj-ref asm 0))
    ; Resolve patches (arch-specific resolver in slot 2 of arch).  A buffer
    ; poured from the cache has none, so its arch may be () here.
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

(doc (provide x/tool/asm-code
  asm-new asm-finalize! asm-free! asm-reloc! asm-relocs asm-relocator asm-reloc-apply!)
  "Native code buffers: map, relocate, protect and free -- what a function's bytes need, without the encoder.")
