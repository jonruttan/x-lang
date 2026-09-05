; asm-cache.x -- a byte cache for the compile-asm lane (x-lang#590).
;
; Compiling is expensive and the compiler is itself interpreted x-lang: one
; compile-asm call costs ~650K evals, the same the second time, and a xenon
; boot pays that eleven times over -- 7.2M evals of a 52M boot.  None of that
; work is per-process EXCEPT the addresses the emitted code bakes in, and
; asm.x records exactly where those went (#598).  So the bytes can be kept and
; poured into a fresh buffer, with every baked address re-encoded for the
; process loading them.
;
; ONE RULE GOVERNS EVERY LINE HERE: NOTHING IN THIS MODULE MAY WALK BYTES.
; An interpreted per-byte loop costs hundreds to thousands of evals per byte,
; which on a lane where the whole compile is ~650K eats the saving whole.  Two
; earlier versions of this module died on exactly that, in two different
; places, and both deaths are worth keeping written down:
;
;   * The code was hex-encoded a byte at a time -- two Str8 sub plus a Str8
;     append, ~24,000 evals per byte.  Storing a 180-byte function cost 4.39M
;     evals, 4.7x what compiling it costs, and wiring it in took a xenon boot
;     from 52M evals to 216M.
;   * With the code moved to raw fd I/O, the RECORD FILE was still text, and
;     parsing its handful of short lines by hand -- a digit loop and a
;     scan-to-newline -- cost 2.71M evals across eleven loads, ~880 evals per
;     byte parsed.  That one file format was, on its own, more than a third of
;     what the cache saved.
;
; So both files are raw.  The code goes straight out of the mmap'd buffer
; through libc write(2) and straight back into the fresh buffer through
; read(2), via ptr-call, which passes a pointer object as the pointer those
; calls want; the x-level cost of moving the code is a constant handful of
; evals no matter how big it is.  The record file is fixed-stride binary read
; with ptr-ref, and its strings are NUL-terminated so ptr->str lifts each one
; out in a single native call.  Nowhere does a loop run once per byte.
;
; The reader and the number formatter are barred here for the same reason: a
; single number literal read properly costs ~11,000 evals, and `%cvt N %string`
; ~180,000 for a 16-digit hex rendering.  write-to-str is the one cheap door.
;
; TWO FILES PER ENTRY.  <key>.bin holds the raw code; <key>.asm holds the
; relocation records and the key text.  Both are written to a pid-unique temp
; and PUBLISHED with a rename, the atomic-publish rule the cc cache follows
; (#391) -- a half-written entry read by another process is native code with a
; hole in it.  The CODE is published first and the record second, because the
; record is what a reader probes: by the time it exists, the bytes it names
; are already whole.
;
; Plain defs, not a class: this sits on the compile path beside asm.x and
; asm-compile.x, which are written the same way.
(import x/type/hash)
(import x/tool/asm)

(def %asm-cache-dir "/tmp/x-asm-")
; "XAC3" little-endian, read back as one 4-byte ptr-ref.  Bump it and every
; existing entry misses -- the format's own version, and the reason a format
; change can never be mistaken for a working entry.
(def %asm-cache-magic 859189592)
; The most a record file can be, and the size of the buffer every probe
; allocates to read one.  It is slack, not a budget: the node cap below bounds
; an entry to a printed expression of a couple of kilobytes plus its records,
; and the largest written by the whole spec suite is 256 bytes.  A read that
; fills the buffer exactly is treated as a miss rather than a truncation, so
; the cost of it being too small would be an entry that misses forever and is
; re-stored every time -- which is why the slack is generous even though the
; bound is known.
(def %asm-cache-cap 65536)
; Kinds, as they sit in the file.  A trampoline's name is the dlsym SYMBOL, an
; fvar's is the free variable's symbol, and a self-cell has no name -- there is
; one per compile and the loader mints its own.
(def %asm-cache-kind-trampoline 0)
(def %asm-cache-kind-fvar 1)
(def %asm-cache-kind-self 2)
; The fixed part: magic, code size, record count, blob offset, then eight
; bytes per record (site offset, kind).  Every name, and then the key text,
; follows NUL-terminated in the blob, in record order.
(def %asm-cache-head-bytes 16)
(def %asm-cache-rec-bytes 8)

; --- doors ------------------------------------------------------------------
(def %asm-cache-lib ((prim-ref 'ffi 'dlopen) () 1))
(def %asm-cache-dlsym (prim-ref 'ffi 'dlsym))
(def %asm-cache-pcall (prim-ref 'ptr 'call))
(def %asm-cache-ptr->int (prim-ref 'ptr '->int))
(def %asm-cache-int->ptr (prim-ref 'int '->ptr))
(def %asm-cache-ptr->str (prim-ref 'ptr '->str))
(def %asm-cache-obj->ptr (prim-ref 'obj '->ptr))
(def %asm-cache-ptr-ref (prim-ref 'ptr 'ref))
(def %asm-cache-ptr-set! (prim-ref 'ptr 'set!))
(def %asm-cache-ptr-set-word! (prim-ref 'ptr 'set-word!))
(def %asm-cache-make-callable (prim-ref 'obj 'make-callable))
; write-to-str, not the converter: this is the cheap way to spell an integer.
(def %asm-cache-wts (prim-ref 'io 'write-to-str))
(def %asm-cache-byte-len (prim-ref 'str 'byte-len))
(def %asm-cache-str->sym (prim-ref 'str '->sym))

(def %asm-libc-creat  (%asm-cache-dlsym %asm-cache-lib "creat"))
(def %asm-libc-open   (%asm-cache-dlsym %asm-cache-lib "open"))
(def %asm-libc-read   (%asm-cache-dlsym %asm-cache-lib "read"))
(def %asm-libc-write  (%asm-cache-dlsym %asm-cache-lib "write"))
(def %asm-libc-close  (%asm-cache-dlsym %asm-cache-lib "close"))
(def %asm-libc-rename (%asm-cache-dlsym %asm-cache-lib "rename"))
(def %asm-libc-unlink (%asm-cache-dlsym %asm-cache-lib "unlink"))
(def %asm-libc-malloc (%asm-cache-dlsym %asm-cache-lib "malloc"))
(def %asm-libc-free   (%asm-cache-dlsym %asm-cache-lib "free"))
(def %asm-libc-getpid (%asm-cache-dlsym %asm-cache-lib "getpid"))

; --- the key ----------------------------------------------------------------
; These are native bytes against one engine's ABI on one machine, so the key
; names the ENGINE AND MACHINE as well as the code.  A key blind to the engine
; is exactly how #590's cc cache served ABI-stale objects that silently
; misread numbers -- `2.5` came back as `2` followed by the symbol `.5`.  #597
; fixed that key by carrying x-release, which is ISA-declared and available at
; runtime; this is the same rule for this lane.
(def %asm-cache-identity (Str append x-machine x-release))

; The emitted code is not a function of the source alone, so the fvar table's
; SHAPE is part of the key.  Inside analyser mode a name absent from the table
; is read as a PARAMETER, while a name present-but-nil is emitted as a literal
; zero with no relocation at all -- two different bodies for one source text.
; Names and nil-ness, then; the VALUES are per-process, and re-resolving those
; by name is what the relocation records are for.
;
; AND THE CALLING WORLD, which used to be readable off the table (empty meant
; an integer function whose result is boxed, non-empty meant an analyser
; returning an object) and no longer is: an integer function may now carry an
; fvar naming a callee it calls.  So ANALYSER? is keyed in its own right.
; Leaving it out would let one source text with one fvar table hit an entry
; compiled in the OTHER world -- the wrong body, handed back as a hit, which
; is the one thing a cache must never do.
(def %asm-cache-mode
  (fn (_ fvars analyser?)
    ((fn (self fs acc)
       (if (null? fs) acc
         (self (rest fs)
           (Str append acc "|" (symbol->str (first (first fs)))
             (if (null? (rest (first fs))) "=" ":")))))
      fvars (if analyser? "!a" "!i"))))

; The full text a hit must match.  It is both hashed into the filename and
; STORED IN THE ENTRY, so a 64-bit collision costs a miss rather than handing
; back the wrong function: the load compares this text before it trusts a byte.
(def %asm-cache-text
  (fn (_ expr fvars analyser?)
    (Str append %asm-cache-identity (%asm-cache-mode fvars analyser?)
                (%asm-cache-wts expr))))

; Decimal, through write-to-str -- one native call.  The hex spelling the cc
; cache uses costs ~180,000 evals per key here (Str pad-left over the number
; formatter), which on this lane is a quarter of a whole compile.  A filename
; only has to be distinct and legal; a leading `-` from a negative hash is
; both.  Callers hold the answer and pass it down, because hashing the key
; text again for the sibling file would cost as much as hashing it did.
(def %asm-cache-path
  (fn (_ text) (Str append %asm-cache-dir (%asm-cache-wts (Hash fnv-1a text)))))

; --- what is worth keying --------------------------------------------------
; A key has to name the expression, and the only exact name available is the
; printer's -- and the printer is SUPERLINEAR.  Measured: a 35-node analyser
; prints in 48K evals (1.4K per node); a 400-node generated body prints in
; 3.55M (8.9K per node), because building the text is a string append per
; step.  Compiling, by contrast, is roughly linear.  So the probe is a small
; fraction of a compile for a small expression and a multiple of it for a
; large one, and sha256-jit's ~3500-node round schedule is far enough out that
; printing it once exhausted the interpreter mid-batch.
;
; The cache is therefore for the expressions the boot compiles over and over:
; the numeric analysers, measured at 9 to 42 nodes each.  A GENERATED body --
; an unrolled loop, a round schedule -- takes the uncached path it always had,
; and this walk stops as soon as it knows that, so a huge expression costs a
; bounded look rather than a full traverse.
;
; The cap is on NODES, not bytes, because it has to be decided before anything
; is printed.  128 is three times the largest expression the boot compiles and
; keeps the print under half a compile; lifting it wants a canonical
; serialiser cheaper than the printer, which is a different piece of work.
(def %asm-cache-max-nodes 128)

; Answers the budget left after walking EXPR, or a negative number as soon as
; the walk costs more than N -- it never traverses further than the cap.
(def %asm-cache-node-budget
  (fn (self e n)
    (if (< n 0) n
      (if (pair? e) (self (rest e) (self (first e) (- n 1))) (- n 1)))))

; The compiler, loaded on the line that needs it.  This is the only place
; x/tool/asm-compile is reached from, and every path that declines to use the
; cache comes through here.
(def %asm-cache-uncached
  (fn (_ expr fvars analyser?)
    (import x/tool/asm-compile)
    (%asm-compiler expr fvars analyser?)))

; Two reasons to leave the cache out of it entirely.
;
; The expression is too big to key, per the note above.
;
; Or a JIT runtime helper would not resolve when asm-compile.x loaded, in
; which case the compiler is going to REFUSE (#201: an unresolved helper is
; address 0, and compiled code calling 0 is a SIGSEGV arbitrarily far from the
; cause).  That refusal belongs to the entry point, so it must not be
; sidestepped by an expression that happens to be in the cache.  Before
; asm-compile.x loads the list is empty, which is correct rather than merely
; convenient: on such an engine dlsym fails for every recorded trampoline, so
; the load misses and the compiler refuses on the far side of it.
(def %asm-cache-stand-aside?
  (fn (_ expr)
    (if (not (null? %jit-missing)) #t
      (< (%asm-cache-node-budget expr %asm-cache-max-nodes) 0))))

; --- raw fd I/O -------------------------------------------------------------
; 0644 is 420 decimal.  creat(2) rather than open(2) with a mode, because open
; is variadic and Apple's arm64 ABI passes variadic arguments on the STACK --
; a mode handed to it in a register is garbage, and the file's permissions
; would be whatever happened to be lying there.
(def %asm-cache-creat
  (fn (_ path) (%asm-cache-pcall %asm-libc-creat path 420)))

; BYTES is a str or a raw pointer; ptr-call passes either as the pointer
; write(2) wants, which is the entire point of this module -- the code never
; passes through x.  A string is written with its own NUL when N includes it.
(def %asm-cache-put
  (fn (_ fd bytes n) (= (%asm-cache-pcall %asm-libc-write fd bytes n) n)))

(def %asm-cache-put-str
  (fn (_ fd s) (%asm-cache-put fd s (+ (%asm-cache-byte-len s) 1))))

; --- store ------------------------------------------------------------------
(def %asm-cache-kind-int
  (fn (_ k)
    (if (eq? k 'trampoline) %asm-cache-kind-trampoline
      (if (eq? k 'fvar) %asm-cache-kind-fvar %asm-cache-kind-self))))

; asm.x records a trampoline's name as a dlsym string and an fvar's as the
; free variable's SYMBOL; a self-cell has none.  The file carries all three as
; text, so a self-cell's is the empty string.
(def %asm-cache-name-str
  (fn (_ nm) (if (null? nm) "" (if (str? nm) nm (symbol->str nm)))))

; The fixed part, built with ptr-set! -- four native stores for the header and
; two per record, none of them a loop over bytes.
(def %asm-cache-head-buf
  (fn (_ size relocs nrel)
    (def bytes (+ %asm-cache-head-bytes (* %asm-cache-rec-bytes nrel)))
    (def hb (%asm-cache-int->ptr (%asm-cache-pcall %asm-libc-malloc bytes)))
    (%asm-cache-ptr-set! hb 0 %asm-cache-magic 4)
    (%asm-cache-ptr-set! hb 4 size 4)
    (%asm-cache-ptr-set! hb 8 nrel 4)
    (%asm-cache-ptr-set! hb 12 bytes 4)
    ((fn (self rs i)
       (unless (null? rs)
         (do (def at (+ %asm-cache-head-bytes (* %asm-cache-rec-bytes i)))
             (%asm-cache-ptr-set! hb at (first (first rs)) 4)
             (%asm-cache-ptr-set! hb (+ at 4)
               (%asm-cache-kind-int (first (rest (first rs)))) 4)
             (self (rest rs) (+ i 1)))))
      relocs 0)
    (pair hb bytes)))

; Every name, then the key text, each NUL-terminated and in record order.  The
; loader lifts them back out with ptr->str, which stops at the NUL -- so no
; length table is needed and nothing has to be escaped, including a newline
; the printer may have left inside a string literal in the key.
(def %asm-cache-put-blob
  (fn (_ fd relocs text)
    (def ok
      ((fn (self rs)
         (if (null? rs) #t
           (if (not (%asm-cache-put-str fd
                      (%asm-cache-name-str (first (rest (rest (first rs)))))))
             #f
             (self (rest rs)))))
        relocs))
    (if ok (%asm-cache-put-str fd text) #f)))

; TEXT is the key text, BASE the path prefix the caller already hashed, BUF the
; mmap'd code buffer.  Answers #t when the entry is published.  A store that
; fails is not a failure: the caller already holds its function, so every path
; out of here is quiet.
(def %asm-cache-store!
  (fn (_ text base size relocs buf)
    (guard (_ ())
      (do
        (def bin (Str append base ".bin"))
        (def rec (Str append base ".asm"))
        (def uniq (Str append "." (%asm-cache-wts (%asm-cache-pcall %asm-libc-getpid)) ".tmp"))
        (def bin-tmp (Str append bin uniq))
        (def rec-tmp (Str append rec uniq))
        (if (not (%asm-cache-store-bin! bin-tmp buf size))
          (do (%asm-cache-pcall %asm-libc-unlink bin-tmp) #f)
          (if (not (%asm-cache-store-rec! rec-tmp text relocs size))
            (do (%asm-cache-pcall %asm-libc-unlink bin-tmp)
                (%asm-cache-pcall %asm-libc-unlink rec-tmp) #f)
            (do
              ; Code first, record second: the record is the probe, so once it
              ; is in place the bytes it names are already whole.
              (%asm-cache-pcall %asm-libc-rename bin-tmp bin)
              (%asm-cache-pcall %asm-libc-rename rec-tmp rec)
              #t)))))))

(def %asm-cache-store-bin!
  (fn (_ path buf size)
    (def fd (%asm-cache-creat path))
    (if (< fd 0) #f
      (do (def ok (%asm-cache-put fd buf size))
          (%asm-cache-pcall %asm-libc-close fd)
          ok))))

(def %asm-cache-store-rec!
  (fn (_ path text relocs size)
    (def fd (%asm-cache-creat path))
    (if (< fd 0) #f
      (do
        (def nrel (%length relocs))
        (def hp (%asm-cache-head-buf size relocs nrel))
        (def ok (%asm-cache-put fd (first hp) (rest hp)))
        (%asm-cache-pcall %asm-libc-free (first hp))
        (def all (if ok (%asm-cache-put-blob fd relocs text) #f))
        (%asm-cache-pcall %asm-libc-close fd)
        all))))

; --- load -------------------------------------------------------------------
; A miss, spelled once.  A miss is never an error: the caller compiles instead,
; so every doubt here resolves to this -- absent file, wrong magic, a key that
; does not match byte for byte, a short read, an unresolvable name.
(def %asm-cache-miss (fn (_) ()))

; A miss that happens after a buffer was already mapped for the bytes.  The
; map is the one thing here the collector cannot reclaim -- asm-new takes it
; from mmap, not the heap -- so a miss on the far side of it has to hand it
; back rather than leave it to the process.
(def %asm-cache-miss-mapped (fn (_ a) (asm-free! a) ()))

; The whole record file in one malloc'd buffer.  open(2) answering -1 IS the
; existence probe: a separate stat door would cost another call to learn what
; the open is about to say anyway.  Answers (ptr . length), or ().
(def %asm-cache-slurp
  (fn (_ path)
    (def fd (%asm-cache-pcall %asm-libc-open path 0))
    (if (< fd 0) ()
      (do
        (def buf (%asm-cache-int->ptr
                   (%asm-cache-pcall %asm-libc-malloc (+ %asm-cache-cap 1))))
        (def got (%asm-cache-pcall %asm-libc-read fd buf %asm-cache-cap))
        (%asm-cache-pcall %asm-libc-close fd)
        (if (if (< got %asm-cache-head-bytes) #t (>= got %asm-cache-cap))
          (do (%asm-cache-pcall %asm-libc-free buf) ())
          ; The buffer is a byte longer than the cap for exactly this: a NUL
          ; after the last byte read, so that ptr->str on a corrupt blob stops
          ; at the end of the file rather than walking into whatever malloc
          ; handed back.  The offsets are checked below as well; this is the
          ; backstop, because reading past the end here is a segfault, not an
          ; error.
          (do (%asm-cache-ptr-set! buf got 0 1) (pair buf got)))))))

; The i-th NUL-terminated string in the blob, lifted whole by ptr->str -- which
; strndups, so what comes back is ours and the buffer stays the file's.
; Answers (string . next-offset).
(def %asm-cache-blob-at
  (fn (_ buf at end)
    (if (>= at end) ()
      (do
        (def s (%asm-cache-ptr->str
                 (%asm-cache-int->ptr (+ (%asm-cache-ptr->int buf) at))))
        (pair s (+ at (+ (%asm-cache-byte-len s) 1)))))))

; Walk the fixed-stride records and the blob together: two ptr-refs and one
; ptr->str per record, no loop over bytes anywhere.  Answers
; (records . key-text), records as (offset kind name) oldest first.
(def %asm-cache-parse
  (fn (_ buf nrel blob end)
    (def r
      ((fn (self i at acc)
         (if (null? at) ()
           (if (>= i nrel) (pair acc at)
             (do
               (def rec (+ %asm-cache-head-bytes (* %asm-cache-rec-bytes i)))
               (def sn (%asm-cache-blob-at buf at end))
               (if (null? sn) ()
                 (self (+ i 1) (rest sn)
                   (pair (list (%asm-cache-ptr-ref buf rec 4)
                               (%asm-cache-ptr-ref buf (+ rec 4) 4)
                               (first sn))
                     acc)))))))
        0 blob ()))
    (if (null? r) ()
      (do (def kt (%asm-cache-blob-at buf (rest r) end))
          (if (null? kt) () (pair (%asm-cache-rev (first r) ()) (first kt)))))))

(def %asm-cache-rev
  (fn (self xs acc) (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))

; fvars arrive as (symbol . value) and the records name them as text, so the
; symbols are spelled ONCE per load rather than once per relocation site: an
; analyser has a handful of fvars and scores of sites, and symbol->str
; allocates a fresh string every time it is asked.
(def %asm-cache-fvar-table
  (fn (_ fvars)
    ((fn (self fs acc)
       (if (null? fs) acc
         (self (rest fs)
           (pair (pair (symbol->str (first (first fs))) (rest (first fs))) acc))))
      fvars ())))

(def %asm-cache-fvar
  (fn (self nm table)
    (if (null? table) ()
      (if (str=? nm (first (first table))) (first table)
        (self nm (rest table))))))

; The address a record names, in THIS process.  () means unresolvable, which
; makes the whole load a miss.
(def %asm-cache-value
  (fn (_ kind nm table cell)
    (if (= kind %asm-cache-kind-trampoline)
      (do (def p (%asm-cache-dlsym %asm-cache-lib nm))
          (if (null? p) () (%asm-cache-ptr->int p)))
      (if (= kind %asm-cache-kind-fvar)
        (do (def hit (%asm-cache-fvar nm table))
            (if (null? hit) () (%asm-cache-ptr->int (%asm-cache-obj->ptr (rest hit)))))
        (if (null? cell) () (%asm-cache-ptr->int cell))))))

; A fresh self-call trampoline cell -- one per load, exactly as the compile
; path mints one per compile.
(def %asm-cache-self-cell
  (fn (_)
    (guard (_ ())
      (%asm-cache-int->ptr (%asm-cache-pcall %asm-libc-malloc 8)))))

; TEXT is the key text and BASE the path prefix the caller already hashed.
; Answers the callable, or () on any miss.
(def %asm-cache-load
  (fn (_ text base fvars)
    (guard (_ ())
      (do
        (def sl (%asm-cache-slurp (Str append base ".asm")))
        (if (null? sl) (%asm-cache-miss)
          (do
            (def buf (first sl))
            (def r (%asm-cache-read-entry buf (rest sl) text))
            (%asm-cache-pcall %asm-libc-free buf)
            (if (null? r) (%asm-cache-miss)
              (%asm-cache-pour base (first r) (rest r) fvars))))))))

; The header says where the records end and the blob begins, and every read of
; the entry is an OFFSET taken from it.  A file that disagrees with itself --
; a record count that does not match the stride, a blob starting past the end
; of what was read, a code size of nothing -- is not an entry.  The magic rules
; out another format; this rules out a damaged one, and reading past the end
; of the buffer would be a segfault rather than an error.
(def %asm-cache-header-sane?
  (fn (_ buf got)
    (def blob (%asm-cache-ptr-ref buf 12 4))
    (if (not (= (%asm-cache-ptr-ref buf 0 4) %asm-cache-magic)) #f
      (if (< (%asm-cache-ptr-ref buf 4 4) 1) #f
        (if (not (= blob (+ %asm-cache-head-bytes
                            (* %asm-cache-rec-bytes (%asm-cache-ptr-ref buf 8 4)))))
          #f
          (<= blob got))))))

; Everything that reads the record buffer, so the caller can free it on one
; path whatever the answer.  Answers (size . records), or () for a miss.
(def %asm-cache-read-entry
  (fn (_ buf got text)
    (if (not (%asm-cache-header-sane? buf got)) ()
      (do
        (def pr (%asm-cache-parse buf (%asm-cache-ptr-ref buf 8 4)
                                      (%asm-cache-ptr-ref buf 12 4) got))
        ; The key text is stored whole and compared whole.  The filename is a
        ; 64-bit hash, and a hash is an invitation to collide; this is what
        ; makes a collision cost a recompile instead of handing back a
        ; function compiled from different source, for a different fvar shape,
        ; or by a different engine -- the exact failure #590 was.
        (if (null? pr) ()
          (if (not (str=? text (rest pr))) ()
            (pair (%asm-cache-ptr-ref buf 4 4) (first pr))))))))

; Pour the bytes into a fresh buffer, re-encode every baked address for THIS
; process, then protect.  THE ORDER IS FORCED: asm-finalize! mprotects the page
; R+X, and a write after that is a segfault, not an error.
(def %asm-cache-pour
  (fn (_ base size recs fvars)
    (def fd (%asm-cache-pcall %asm-libc-open (Str append base ".bin") 0))
    (if (< fd 0) (%asm-cache-miss)
      (do
        (def a (asm-new (+ size 256)))
        ; One read(2) straight into the mmap'd buffer -- the whole reason this
        ; module exists.  A short read means a truncated entry: miss.
        (def got (%asm-cache-pcall %asm-libc-read fd (%obj-ref a 0) size))
        (%asm-cache-pcall %asm-libc-close fd)
        (if (not (= got size)) (%asm-cache-miss-mapped a)
          (do
            (%obj-set! a 1 size)
            (def cell (%asm-cache-self-cell))
            (def table (%asm-cache-fvar-table fvars))
            ; The relocator and the buffer are fetched ONCE and the sites walked
            ; against them.  asm-reloc-apply! re-finds both per call, and a
            ; loaded analyser has scores of sites -- the lookup alone was more
            ; than half the cost of a hit.
            (def reloc (asm-relocator a))
            (def code-buf (%obj-ref a 0))
            (def ok
              (if (null? reloc) #f
                ((fn (self rs)
                   (if (null? rs) #t
                     (do (def r (first rs))
                       (def val (%asm-cache-value (first (rest r))
                                  (first (rest (rest r))) table cell))
                       (if (null? val) #f
                         (do (reloc code-buf (first r) val) (self (rest rs)))))))
                  recs)))
            (if (not ok) (%asm-cache-miss-mapped a)
              (do
                (def code (asm-finalize! a))
                (unless (null? cell)
                  (%asm-cache-ptr-set-word! cell 0 (%asm-cache-ptr->int code)))
                (%asm-cache-publish! recs size code)
                (%asm-cache-make-callable code)))))))))

; Records in the shape asm.x hands them out -- kind as a SYMBOL, a self-cell's
; name as nil, an fvar's as a symbol -- so that %asm-last-relocs says the same
; thing after a load as after a compile.  The file carries kinds as small
; integers because the relocation loop compares them once per site; this runs
; once per load, at the seam where the two shapes meet.
(def %asm-cache-kind-sym
  (fn (_ k)
    (if (= k %asm-cache-kind-trampoline) 'trampoline
      (if (= k %asm-cache-kind-fvar) 'fvar 'self-cell))))

(def %asm-cache-publish!
  (fn (_ recs size code)
    (set! %asm-last-size size)
    (set! %asm-last-buf code)
    (set! %asm-last-relocs
      (%asm-cache-rev
        ((fn (self rs acc)
           (if (null? rs) acc
             (do (def r (first rs))
               (def k (first (rest r)))
               (def nm (first (rest (rest r))))
               (self (rest rs)
                 (pair (list (first r) (%asm-cache-kind-sym k)
                         (if (= k %asm-cache-kind-self) ()
                           (if (= k %asm-cache-kind-fvar) (%asm-cache-str->sym nm) nm)))
                   acc)))))
          recs ())
        ()))))

; --- the public door --------------------------------------------------------
; THE CACHE IS THE DOOR AND THE COMPILER IS WHAT IT FALLS BACK TO, which is the
; whole point of putting it here rather than inside asm-compile.x.  Loading the
; compiler costs 2.5M evals before it emits a single instruction -- a third
; again of what the eleven compiles in a xenon boot cost to run.  Probing first
; means a warm process never pays it: compile.x's lazy stub imports THIS
; module, this module imports asm.x (which the loader needs), and
; x/tool/asm-compile is imported only on the line below that actually needs a
; compiler, and reached through the %asm-compiler slot it fills in -- a slot,
; not a lazily-bound name, so that no load order can leave this file holding a
; forward declaration instead of the real thing.
;
; The probe is cheap on purpose (~55K evals: print the expression, hash it,
; open a file), because the miss path pays it on top of a full compile.  And
; every doubt is a MISS, never an error -- an absent entry, a stale format, a
; key that does not match byte for byte, a symbol that will not resolve -- so
; the worst a broken cache can do is make this the uncached compiler it
; replaced.  That includes the JIT-runtime refusal: a missing trampoline makes
; dlsym answer nil, which misses, which reaches %asm-compile-fresh, which
; raises the same "JIT runtime unavailable" it always did.
(def compile-asm
  (fn (_ expr . %asm-rest)
    (def fvars (unless (null? %asm-rest) (first %asm-rest)))
    ; THE CALLING WORLD IS DECIDED HERE, at the door, and nowhere else.  An
    ; absent third argument keeps the historical reading -- fvars present
    ; means analyser -- which is what every caller written before there was
    ; a third argument means.  It is settled here rather than downstream so
    ; that the key below and the compile below name the same answer.
    (def analyser?
      (if (null? %asm-rest) #f
        (if (null? (rest %asm-rest))
          (not (null? fvars))
          (first (rest %asm-rest)))))
    ; Whether to stand aside is decided FIRST, before the printer is asked for
    ; anything: on that path this module gets out of the way entirely and the
    ; expression takes the route it took before there was a cache.
    (if (%asm-cache-stand-aside? expr)
      (%asm-cache-uncached expr fvars analyser?)
      (do
        ; The key text and the path hashed from it are computed ONCE and handed
        ; down: hashing the same text again for the store, or for the sibling
        ; file, would cost as much as hashing it did the first time.
        (def text (%asm-cache-text expr fvars analyser?))
        (def base (%asm-cache-path text))
        (def hit (%asm-cache-load text base fvars))
        (if (not (null? hit)) hit
          (do
            (def f (%asm-cache-uncached expr fvars analyser?))
            (%asm-cache-store! text base %asm-last-size %asm-last-relocs %asm-last-buf)
            f))))))

(doc compile-asm
  (returns CALLABLE "X-lang callable prim")
  "JIT compile an x-lang (fn ...) expression to a native prim, through a
   persistent byte cache.  Accepts an optional fvar alist for free variable
   support, and an optional third argument declaring analyser mode (default:
   fvars present).  An fvar holding a prim may be CALLED by name; (%call HEAD
   arg ...) calls a prim the code computes, and refuses at run time if the
   head is not one.
   The compiled function works with map, fold, closures, etc.")

(doc (provide x/tool/asm-cache compile-asm)
  "The compile-asm door: a persistent cache of emitted native code, over the
   JIT compiler it falls back to.")
