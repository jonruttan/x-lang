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
; AN ENTRY IS HELD IN THE HEAP AS WELL.  Every entry this process stores or
; loads is also kept as two objects: the code in an object whose payload is
; words, and its site table (see "sites").  Neither holds an address, so a state
; image carries them, and a process booted from that image pours from what it
; holds without the files.  See "entries held in the heap" below.
;
; Plain defs, not a class: this sits on the compile path beside asm.x and
; asm-compile.x, which are written the same way.
(module x/tool/asm-cache)

(import x/type/hash)
; The code buffers and the relocator, not the assembler: a hit pours bytes it
; already has, so the encoder and its opcode table load only with the compiler.
(import x/tool/asm-code)

; "XAC3" little-endian, read back as one 4-byte ptr-ref.  Bump it and every
; existing entry misses -- the format's own version, and the reason a format
; change can never be mistaken for a working entry.
(def %asm-cache-magic 859189592)
; The FIRST read of a record file, and the size the buffer grows by when a
; read fills it.  This was a cap once -- "the most a record file can be", a
; read that filled it was a miss -- sized for the node-capped entries of the
; day (a couple of kilobytes; the largest in the spec suite 256 bytes) with
; generous slack, because its own note saw the failure: an entry bigger than
; the cap misses forever and is re-stored every time.  When the node cap went
; (see "what is worth keying") that is precisely what happened: sha256-jit's
; fill body writes an 82KB record file, every probe read 64KB of it and
; called that a miss, and the engine build stayed at eleven seconds with its
; bytes sitting in the cache.  So the slurp reads in rounds now and an entry
; is whatever size it is; this number only decides how many rounds.
(def %asm-cache-slurp-chunk 65536)
; Labels, as they sit in the file.  A trampoline's name is the dlsym SYMBOL, an
; fvar's is the free variable's symbol, and a self-cell has no name -- there is
; one per compile and the loader mints its own.
(def %asm-cache-label-trampoline 0)
(def %asm-cache-label-fvar 1)
(def %asm-cache-label-self 2)
; The fixed part: magic, code size, record count, blob offset, then eight
; bytes per record (site offset, label).  Every name, and then the key text,
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
(def %asm-cache-obj-make (prim-ref 'obj 'make))
(def %asm-cache-copy! (prim-ref 'ptr 'copy!))
(def %asm-cache-make-str (prim-ref 'str 'make))
(def %asm-cache-str->ptr (prim-ref 'str '->ptr))
(def %asm-cache-ptr-ref-word (prim-ref 'ptr 'ref-word))
; The engine's integer division: `/` is the tower's once the tower has loaded,
; and answers a rational.
(def %asm-cache-int/ (prim-ref 'int '/))
; The integer doors, for the loops that run once per relocation record -- a
; parse, a pour and a group load each walk every site, and a lexer state has a
; dozen.  The generic + < = dispatch on their operands' types and allocate per
; call; every operand in those loops is a machine integer.
(def %asm-cache-i+ (prim-ref 'int '+))
(def %asm-cache-i* (prim-ref 'int '*))
(def %asm-cache-i< (prim-ref 'int '<))
(def %asm-cache-i= (prim-ref 'int '=))

(def %asm-libc-creat  (%asm-cache-dlsym %asm-cache-lib "creat"))
(def %asm-libc-open   (%asm-cache-dlsym %asm-cache-lib "open"))
(def %asm-libc-read   (%asm-cache-dlsym %asm-cache-lib "read"))
(def %asm-libc-write  (%asm-cache-dlsym %asm-cache-lib "write"))
(def %asm-libc-close  (%asm-cache-dlsym %asm-cache-lib "close"))
(def %asm-libc-rename (%asm-cache-dlsym %asm-cache-lib "rename"))
(def %asm-libc-unlink (%asm-cache-dlsym %asm-cache-lib "unlink"))
(def %asm-libc-malloc (%asm-cache-dlsym %asm-cache-lib "malloc"))
(def %asm-libc-realloc (%asm-cache-dlsym %asm-cache-lib "realloc"))
(def %asm-libc-free   (%asm-cache-dlsym %asm-cache-lib "free"))
(def %asm-libc-getpid (%asm-cache-dlsym %asm-cache-lib "getpid"))
(def %asm-libc-getenv (%asm-cache-dlsym %asm-cache-lib "getenv"))

; --- the key ----------------------------------------------------------------
; These are native bytes against one engine's ABI on one machine, so the key
; names the ENGINE AND MACHINE as well as the code.  A key blind to the engine
; is exactly how #590's cc cache served ABI-stale objects that silently
; misread numbers -- `2.5` came back as `2` followed by the symbol `.5`.  #597
; fixed that key by carrying x-release, which is ISA-declared and available at
; runtime; this is the same rule for this lane.
;
; The key names the compiler too, which is this library rather than the engine.
; Naming only the machine and the engine release lets an entry outlive a change
; to the emitter: a hit never reaches a compiler, so a compile whose acceptance
; or output has changed is served the bytes an earlier version produced.  A key
; blind to what produced the bytes serves stale bytes, which is the argument the
; engine half of the key already makes.
;
; x-lib-version covers a consumer, who gets a release.  The "g2" is the codegen
; epoch and covers development: bumping it is part of changing what the emitter
; accepts, refuses or emits, the rule %asm-cache-magic states for the record
; format.  It is a literal rather than a name of its own because a name here is
; another top-level %-global (tools/contract/percent-globals.x).
(def %asm-cache-identity
  (Str append x-machine x-release x-lib-version "g2"))

; The emitted code is not a function of the source alone, so the fvar table's
; ARRANGEMENT is part of the key.  Inside analyser mode a name absent from the table
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

; The directory the entries live in: X_ASM_CACHE_DIR when it is set and not
; empty, else /tmp, which every engine on the machine shares.  A process that
; must not share it names a directory of its own: tools/check/asan-boot.sh
; gives each of its boots an empty one, so every compile is cold and no other
; process's entries are read or moved.  Read on each call rather than at load,
; because a state image carries this module's globals from the process that
; wrote it.
(def %asm-cache-dir
  (fn (_)
    (def p (%asm-cache-pcall %asm-libc-getenv "X_ASM_CACHE_DIR"))
    (def d (if (= p 0) "" (%asm-cache-ptr->str (%asm-cache-int->ptr p))))
    (if (= (%asm-cache-byte-len d) 0) "/tmp" d)))

; Decimal, through write-to-str -- one native call.  The hex spelling the cc
; cache uses costs ~180,000 evals per key here (Str pad-left over the number
; formatter), which on this lane is a quarter of a whole compile.  A filename
; only has to be distinct and legal; a leading `-` from a negative hash is
; both.  Callers hold the answer and pass it down, because hashing the key
; text again for the sibling file would cost as much as hashing it did.
(def %asm-cache-path
  (fn (_ text)
    (Str append (%asm-cache-dir) "/x-asm-" (%asm-cache-wts (Hash fnv-1a text)))))

; --- what is worth keying: everything ----------------------------------------
; A key has to name the expression, and the only exact name available is its
; printed text.  The first version of this module capped that at 128 nodes,
; because the printer it measured was the interpreted one -- SUPERLINEAR, a
; string append per step, 8.9K evals a node at 400 nodes -- and a generated
; body (sha256-jit's round schedule) exhausted the interpreter mid-batch just
; being printed.  But the key text is spelled by `io write-to-str` (the C
; door, %asm-cache-wts) and hashed by FNV over its bytes, and both are linear:
; measured 2026-09-12, sha256-jit's fill body -- 12,241 nodes, 22KB of text --
; prints in 0.6s and hashes in 0.1s, against a 9-second compile.  The probe is
; a fixed small fraction of a compile at ANY size, so there is no size at
; which standing aside pays, and the cap was costing exactly the expressions
; that hurt most: with it, every process that digested more than 64KB paid the
; eleven-second engine build again -- `Pin bundle` and `Pin install` in the
; pin gate, six and two times a run.
;
; What still stands aside is decided by the engine, not the size: see below.

; The compiler, loaded on the line that needs it.  This is the only place
; x/tool/asm-compile is reached from, and every path that declines to use the
; cache comes through here.
(def %asm-cache-uncached
  (fn (_ expr fvars analyser?)
    (import x/tool/asm-compile)
    (%asm-compiler expr fvars analyser?)))

; One reason to leave the cache out of it entirely.
;
; A JIT runtime helper would not resolve when asm-compile.x loaded, in
; which case the compiler is going to REFUSE (#201: an unresolved helper is
; address 0, and compiled code calling 0 is a SIGSEGV arbitrarily far from the
; cause).  That refusal belongs to the entry point, so it must not be
; sidestepped by an expression that happens to be in the cache.  Before
; asm-compile.x loads the list is empty, which is correct rather than merely
; convenient: on such an engine dlsym fails for every recorded trampoline, so
; the load misses and the compiler refuses on the far side of it.
(def %asm-cache-stand-aside?
  (fn (_)
    (not (null? %jit-missing))))

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
(def %asm-cache-label-int
  (fn (_ k)
    (if (eq? k 'trampoline) %asm-cache-label-trampoline
      (if (eq? k 'fvar) %asm-cache-label-fvar %asm-cache-label-self))))

; asm.x records a trampoline's name as a dlsym string and an fvar's as the
; free variable's SYMBOL; a self-cell has none.  The file carries all three as
; text, so a self-cell's is the empty string.
(def %asm-cache-name-str
  (fn (_ nm) (if (null? nm) "" (if (str? nm) nm (symbol->str nm)))))

; The fixed part, built with ptr-set! -- four native stores for the header and
; two per record, none of them a loop over bytes.  RELOCS are in the file's
; layout, (offset label name) with the label an integer and the name a string:
; a store converts asm.x's records once, and a group writes what it holds.
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
             (%asm-cache-ptr-set! hb (+ at 4) (first (rest (first rs))) 4)
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
           (if (not (%asm-cache-put-str fd (first (rest (rest (first rs))))))
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
        (def ok (%asm-cache-put-rec fd text (%asm-cache-file-recs relocs) size))
        (%asm-cache-pcall %asm-libc-close fd)
        ok))))

; One entry's record part -- header, records, names and key text -- written to
; FD from records in the file's layout: a single entry's .asm file.
(def %asm-cache-put-rec
  (fn (_ fd text recs size)
    (def hp (%asm-cache-head-buf size recs (%length recs)))
    (def ok (%asm-cache-put fd (first hp) (rest hp)))
    (%asm-cache-pcall %asm-libc-free (first hp))
    (if ok (%asm-cache-put-blob fd recs text) #f)))

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
; the open is about to say anyway.  Read in rounds of a chunk: a read that
; comes back short is the end of the file, a read that fills what was asked
; grows the buffer and goes again -- so the file's size is never assumed, and
; a big entry costs a few read(2) calls rather than a miss.  No byte is
; walked here; the bytes land where read(2) puts them.  Answers
; (ptr . length), or ().
(def %asm-cache-slurp
  (fn (_ path)
    (def fd (%asm-cache-pcall %asm-libc-open path 0))
    (if (< fd 0) ()
      (do
        (def r
          ((fn (self buf room got)
             (def want (- room got))
             (def n (%asm-cache-pcall %asm-libc-read fd
                      (%asm-cache-int->ptr (+ (%asm-cache-ptr->int buf) got)) want))
             (if (< n 0) (do (%asm-cache-pcall %asm-libc-free buf) ())
               (if (< n want) (pair buf (+ got n))
                 ; Full: a byte of room past the chunk stays for the NUL
                 ; backstop below, whatever the final size.
                 (do
                   (def nb (%asm-cache-pcall %asm-libc-realloc buf
                             (+ (+ room %asm-cache-slurp-chunk) 1)))
                   (if (= nb 0) (do (%asm-cache-pcall %asm-libc-free buf) ())
                     (self (%asm-cache-int->ptr nb) (+ room %asm-cache-slurp-chunk) (+ got n)))))))
           (%asm-cache-int->ptr
             (%asm-cache-pcall %asm-libc-malloc (+ %asm-cache-slurp-chunk 1)))
           %asm-cache-slurp-chunk 0))
        (%asm-cache-pcall %asm-libc-close fd)
        (if (null? r) ()
          (do
            (def buf (first r))
            (def got (rest r))
            (if (< got %asm-cache-head-bytes)
              (do (%asm-cache-pcall %asm-libc-free buf) ())
              ; The buffer is a byte longer than what was read for exactly
              ; this: a NUL after the last byte, so that ptr->str on a corrupt
              ; blob stops at the end of the file rather than walking into
              ; whatever malloc handed back.  The offsets are checked below as
              ; well; this is the backstop, because reading past the end here
              ; is a segfault, not an error.
              (do (%asm-cache-ptr-set! buf got 0 1) (pair buf got)))))))))

; The i-th NUL-terminated string in the blob, lifted whole by ptr->str -- which
; strndups, so what comes back is ours and the buffer stays the file's.
; Answers (string . next-offset).
(def %asm-cache-blob-at
  (fn (_ buf at end)
    (if (%asm-cache-i< at end)
      (do
        (def s (%asm-cache-ptr->str
                 (%asm-cache-int->ptr (%asm-cache-i+ (%asm-cache-ptr->int buf) at))))
        (pair s (%asm-cache-i+ at (%asm-cache-i+ (%asm-cache-byte-len s) 1))))
      ())))

; Walk the fixed-stride records and the blob together: two ptr-refs and one
; ptr->str per record, no loop over bytes anywhere.  Answers
; (records key-text . end), records as (offset label name) oldest first and
; END the offset just past the key text's NUL, where a group file's code for
; the entry begins.
(def %asm-cache-parse
  (fn (_ buf nrel blob end)
    (def r
      ((fn (self i at acc)
         (if (null? at) ()
           (if (%asm-cache-i< i nrel)
             (do
               (def rec (%asm-cache-i+ %asm-cache-head-bytes (%asm-cache-i* %asm-cache-rec-bytes i)))
               (def sn (%asm-cache-blob-at buf at end))
               (if (null? sn) ()
                 (self (%asm-cache-i+ i 1) (rest sn)
                   (pair (list (%asm-cache-ptr-ref buf rec 4)
                               (%asm-cache-ptr-ref buf (%asm-cache-i+ rec 4) 4)
                               (first sn))
                     acc))))
             (pair acc at))))
        0 blob ()))
    (if (null? r) ()
      (do (def kt (%asm-cache-blob-at buf (rest r) end))
          (if (null? kt) () (pair (%asm-cache-rev (first r) ()) kt))))))

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
  (fn (_ label nm table cell)
    (match
      ((%asm-cache-i= label %asm-cache-label-trampoline)
        (do (def p (%asm-cache-dlsym %asm-cache-lib nm))
            (if (null? p) () (%asm-cache-ptr->int p))))
      ((%asm-cache-i= label %asm-cache-label-fvar)
        (do (def hit (%asm-cache-fvar nm table))
            (if (null? hit) () (%asm-cache-ptr->int (%asm-cache-obj->ptr (rest hit))))))
      ((null? cell) ())
      (#t (%asm-cache-ptr->int cell)))))

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
              (%asm-cache-pour (%asm-cache-fill-file base) (first r) (%asm-cache-sites (rest r)) fvars #t))))))))

; The header says where the records end and the blob begins, and every read of
; the entry is an OFFSET taken from it.  A file that disagrees with itself --
; a record count that does not match the stride, a blob starting past the end
; of what was read, a code size of nothing -- is not an entry.  The magic rules
; out another format; this rules out a damaged one, and reading past the end
; of the buffer would be a segfault rather than an error.
(def %asm-cache-header-sane?
  (fn (_ buf got)
    (def blob (%asm-cache-ptr-ref buf 12 4))
    (match
      ((not (= (%asm-cache-ptr-ref buf 0 4) %asm-cache-magic)) #f)
      ((< (%asm-cache-ptr-ref buf 4 4) 1) #f)
      ((not (= blob (+ %asm-cache-head-bytes
                            (* %asm-cache-rec-bytes (%asm-cache-ptr-ref buf 8 4)))))
        #f)
      (#t (<= blob got)))))

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
        ; function compiled from different source, for a different fvar arrangement,
        ; or by a different engine -- the exact failure #590 was.
        (if (null? pr) ()
          (if (not (str=? text (first (rest pr)))) ()
            (pair (%asm-cache-ptr-ref buf 4 4) (first pr))))))))

; --- sites ------------------------------------------------------------------
; An entry names a handful of addresses at scores of sites: a lexer state's
; forty sites name six trampolines, its free variables and its self-cell.  So
; the records are kept as a SITE TABLE, (slots sites n): SLOTS the distinct
; (label . name) pairs, oldest first, and SITES N pairs of 4-byte words, (site
; offset, slot), one pair to a word.  A pour resolves each slot once and
; patches every site from the slots' values in one walk -- the compiled
; patcher's, when this process has one -- and a group file carries the sites
; as the bytes they are.
;
; The sites are held in a code object, whose word units an image carries
; whole: a string is rebuilt up to its first NUL, and an offset or a slot is
; mostly zero bytes.  An engine with no code type holds no entries, and a
; string serves the one pour.
(def %asm-cache-words
  (fn (_ n)
    (if (null? %asm-cache-code-type) (%asm-cache-make-str (%asm-cache-i* 8 (if (%asm-cache-i= n 0) 1 n)))
      (do (def b (%asm-cache-obj-make %asm-cache-code-type (%asm-cache-i+ n 1)))
          (%obj-set! b 0 n)
          b))))

(def %asm-cache-words-at
  (fn (_ b) (if (str? b) (%asm-cache-str->ptr b) (%asm-cache-code-at b))))

(def %asm-cache-sites
  (fn (_ recs)
    (def n (%length recs))
    (def sites (%asm-cache-words n))
    (def sp (%asm-cache-words-at sites))
    ; (label name k) newest first, and how many
    (def slots (pair () 0))
    (def slot!
      (fn (_ label nm)
        (def hit
          ((fn (self l)
             (if (null? l) ()
               (if (if (%asm-cache-i= (first (first l)) label) (str=? (first (rest (first l))) nm) #f)
                 (first l) (self (rest l)))))
           (first slots)))
        (if (null? hit)
          (do (def k (rest slots))
              (%set-first! slots (pair (list label nm k) (first slots)))
              (%set-rest! slots (%asm-cache-i+ k 1))
              k)
          (first (rest (rest hit))))))
    ((fn (self rs at)
       (unless (null? rs)
         (do (def r (first rs))
             (%asm-cache-ptr-set! sp at (first r) 4)
             (%asm-cache-ptr-set! sp (%asm-cache-i+ at 4) (slot! (first (rest r)) (first (rest (rest r)))) 4)
             (self (rest rs) (%asm-cache-i+ at 8)))))
     recs 0)
    (list ((fn (self l acc) (if (null? l) acc (self (rest l) (pair (pair (first (first l)) (first (rest (first l)))) acc))))
           (first slots) ())
          sites n)))

(def %asm-cache-nth
  (fn (self l i) (if (%asm-cache-i= i 0) (first l) (self (rest l) (%asm-cache-i+ i -1)))))

; The records of a site table, in the file's layout and site order.
(def %asm-cache-site-recs
  (fn (_ st)
    (def slots (first st))
    (def sp (%asm-cache-words-at (first (rest st))))
    (def end (%asm-cache-i* 8 (first (rest (rest st)))))
    ((fn (self at acc)
       (if (%asm-cache-i= at end) (%asm-cache-rev acc ())
         (do (def s (%asm-cache-nth slots (%asm-cache-ptr-ref sp (%asm-cache-i+ at 4) 4)))
             (self (%asm-cache-i+ at 8)
               (pair (list (%asm-cache-ptr-ref sp at 4) (first s) (rest s)) acc)))))
     0 ())))

; Every site of table ST patched in the code at CODE-BUF from VALS, a string of
; one word per slot.  The x walk is the reference; the compiled patcher does
; the same in one call per run of sites.
(def %asm-cache-patch-x
  (fn (_ code-buf sp vp n)
    ((fn (self at end)
       (unless (%asm-cache-i= at end)
         (do (%asm-reloc code-buf (%asm-cache-ptr-ref sp at 4)
               (%asm-cache-ptr-ref-word vp (%asm-cache-i* 8 (%asm-cache-ptr-ref sp (%asm-cache-i+ at 4) 4))))
             (self (%asm-cache-i+ at 8) end))))
     0 (%asm-cache-i* 8 n))))

; The patcher's self-call is a real call, so a run is cut to this many sites.
(def %asm-cache-patch-run 64)

(def %asm-cache-patch!
  (fn (_ code-buf st vals)
    (def sp (%asm-cache-words-at (first (rest st))))
    (def vp (%asm-cache-str->ptr vals))
    (def n (first (rest (rest st))))
    (def native (%asm-cache-patcher))
    (if (null? native) (%asm-cache-patch-x code-buf sp vp n)
      ((fn (self code sites vals k)
         (unless (%asm-cache-i= k 0)
           (do
             (def run (if (%asm-cache-i< k %asm-cache-patch-run) k %asm-cache-patch-run))
             (native code sites vals run)
             (self code (%asm-cache-i+ sites (%asm-cache-i* 8 run)) vals (%asm-cache-i+ k (%asm-cache-i* -1 run))))))
       (%asm-cache-ptr->int code-buf) (%asm-cache-ptr->int sp) (%asm-cache-ptr->int vp) n))))

; --- the compiled patcher ----------------------------------------------------
; (fn (self code sites vals n)): the N sites at address SITES, last first, each
; patched in the code at address CODE from the word VALS holds for its slot --
; the host relocator's encoding, written as two 8-byte stores (A64: MOVZ and
; three MOVKs, sixteen bits each, the register read back from the MOVZ) or one
; (x86-64: the imm64 after a two-byte opcode).
(def %asm-cache-patcher-expr
  ((fn (_ site)
     (def at (list '+ 'code (list '& site 4294967295)))
     (def val (list '%mem-ref-at 'vals (list '>> site 32)))
     (def rd (list '& (list '%mem-ref at 0) 31))
     (def half (fn (_ op shift) (list '| op (list '| (list '<< (list '& (list '>> val shift) 65535) 5) rd))))
     (def body
       (if %asm-arm64?
         (list 'do
           (list '%mem-set! at 0 (list '| (half 3531603968 0) (list '<< (half 4070572032 16) 32)))
           (list '%mem-set! (list '+ at 8) 0 (list '| (half 4072669184 32) (list '<< (half 4074766336 48) 32))))
         (list '%mem-set! (list '+ at 2) 0 val)))
     (list 'fn '(self code sites vals n)
       (list 'if '(= n 0) 0
         (list 'do body '(self code sites vals (- n 1))))))
   '(%mem-ref-at sites (- n 1))))

; () before this process has looked, the patcher once it has one, #f when it
; looked and none was cached (a compile may still make one), 'none when the
; lane would not compile it.  The patcher's own pour runs while this is #f, so
; it takes the x walk.  A state image carries no code: the image drops it.
(def %asm-cache-patcher-cell (pair () ()))
((fn (_ door) (unless (null? door) (door (fn (_) (%set-first! %asm-cache-patcher-cell ())))))
 (prim-ref 'image 'transient!))

(def %asm-cache-patcher-text
  (fn (_) (%asm-cache-text %asm-cache-patcher-expr () #f)))

; The patcher, or () for the x walk: looked for once a process, held or cached,
; never compiled here -- a pour must not load the compiler.
(def %asm-cache-patcher
  (fn (_)
    (def c (first %asm-cache-patcher-cell))
    (if (null? c)
      (do
        (%set-first! %asm-cache-patcher-cell #f)
        (%asm-cache-patcher-adopt!
          (%asm-cache-keeping-last
            (fn (_)
              (def text (%asm-cache-patcher-text))
              (def held (%asm-cache-held-load text () #f))
              (if (not (null? held)) held
                (do
                  (def base (%asm-cache-path text))
                  (def hit (%asm-cache-load text base ()))
                  (unless (null? hit)
                    (%asm-cache-hold! text %asm-last-size %asm-last-relocs %asm-last-buf))
                  hit)))))
        (%asm-cache-patcher))
      (if (if (eq? c #f) #t (eq? c (lit none))) () c))))

; After a compile, while the compiler is loaded: compile the patcher too when
; none is held or cached, so the processes after this one find it.
(def %asm-cache-patcher-compile!
  (fn (_)
    (when (if (null? (%asm-cache-patcher)) (eq? (first %asm-cache-patcher-cell) #f) #f)
      (%set-first! %asm-cache-patcher-cell (lit none))
      (%asm-cache-patcher-adopt!
        (%asm-cache-keeping-last
          (fn (_)
            (def text (%asm-cache-patcher-text))
            (def f (%asm-cache-uncached %asm-cache-patcher-expr () #f))
            (%asm-cache-store! text (%asm-cache-path text) %asm-last-size %asm-last-relocs %asm-last-buf)
            (%asm-cache-hold! text %asm-last-size %asm-last-relocs %asm-last-buf)
            f))))))

; Run THUNK, answering what it answers or () on a raise, with the facts about
; the last function as they were before it.
(def %asm-cache-keeping-last
  (fn (_ thunk)
    (def size %asm-last-size)
    (def relocs %asm-last-relocs)
    (def buf %asm-last-buf)
    (def out (guard (_ ()) (thunk)))
    (set! %asm-last-size size)
    (set! %asm-last-relocs relocs)
    (set! %asm-last-buf buf)
    out))

; Take patcher F only when it agrees with the x walk on two sites of a scratch
; buffer, each address with every sixteen bits set.
(def %asm-cache-patcher-adopt!
  (fn (_ f)
    (unless (null? f)
      (guard (_ ())
        (do
          (def st (%asm-cache-sites (list (list 0 0 "a") (list 16 1 "b"))))
          (def vals (%asm-cache-make-str 16))
          (def vp (%asm-cache-str->ptr vals))
          (%asm-cache-ptr-set-word! vp 0 1311768467463790320)
          (%asm-cache-ptr-set-word! vp 8 9141386507638288912)
          (def scratch
            (fn (_)
              (def s (%asm-cache-make-str 32))
              (def p (%asm-cache-str->ptr s))
              (%asm-cache-ptr-set! p 0 3531603971 4)
              (%asm-cache-ptr-set! p 16 3531603985 4)
              s))
          (def a (scratch))
          (def b (scratch))
          (def sp (%asm-cache-words-at (first (rest st))))
          (%asm-cache-patch-x (%asm-cache-str->ptr a) sp vp 2)
          (f (%asm-cache-ptr->int (%asm-cache-str->ptr b)) (%asm-cache-ptr->int sp)
             (%asm-cache-ptr->int vp) 2)
          (def pa (%asm-cache-str->ptr a))
          (def pb (%asm-cache-str->ptr b))
          (when ((fn (self at)
                   (if (%asm-cache-i= at 32) #t
                     (if (%asm-cache-i= (%asm-cache-ptr-ref-word pa at) (%asm-cache-ptr-ref-word pb at))
                       (self (%asm-cache-i+ at 8)) #f)))
                 0)
            (%set-first! %asm-cache-patcher-cell f)))))))

; Pour the bytes into a fresh buffer, re-encode every baked address for THIS
; process, then protect.  THE ORDER IS FORCED: asm-finalize! mprotects the page
; R+X, and a write after that is a segfault, not an error.
;
; FILL is (fn (_ dst size)) and puts SIZE bytes of code at DST, answering #f
; when it cannot: the bytes come from a file or from an entry held in the heap,
; and everything after them is the same.  ST is the entry's site table.
; PUBLISH? says whether the facts about the last function are set from it, as
; a compile sets them: a load by key asked for no compile, and the facts cost
; more per site than the relocation.
(def %asm-cache-pour
  (fn (_ fill size st fvars publish?)
    (def a (asm-new (+ size 256)))
    (if (not (fill (%obj-ref a 0) size)) (%asm-cache-miss-mapped a)
      (do
        (%obj-set! a 1 size)
        (def cell (%asm-cache-self-cell))
        (def table (%asm-cache-fvar-table fvars))
        ; one word a slot; a slot that will not resolve is a miss
        (def vals (%asm-cache-make-str (%asm-cache-i* 8 (%asm-cache-i+ (%length (first st)) 1))))
        (def vp (%asm-cache-str->ptr vals))
        (def ok
          ((fn (self ss at)
             (if (null? ss) #t
               (do (def val (%asm-cache-value (first (first ss)) (rest (first ss)) table cell))
                 (if (null? val) #f
                   (do (%asm-cache-ptr-set-word! vp at val)
                       (self (rest ss) (%asm-cache-i+ at 8)))))))
           (first st) 0))
        (if (not ok) (%asm-cache-miss-mapped a)
          (do
            (%asm-cache-patch! (%obj-ref a 0) st vals)
            (def code (asm-finalize! a))
            (unless (null? cell)
              (%asm-cache-ptr-set-word! cell 0 (%asm-cache-ptr->int code)))
            (when publish? (%asm-cache-publish! (%asm-cache-site-recs st) size code))
            (%asm-cache-make-callable code)))))))

; The fill for an entry's file: one read(2) straight into the mmap'd buffer --
; the whole reason this module exists.  A file that will not open, or a short
; read, which means a truncated entry, is a miss.
(def %asm-cache-fill-file
  (fn (_ base)
    (fn (_ dst size)
      (def fd (%asm-cache-pcall %asm-libc-open (Str append base ".bin") 0))
      (if (< fd 0) #f
        (do
          (def got (%asm-cache-pcall %asm-libc-read fd dst size))
          (%asm-cache-pcall %asm-libc-close fd)
          (= got size))))))

; Records in the layout asm.x hands them out -- label as a SYMBOL, a self-cell's
; name as nil, an fvar's as a symbol -- so that %asm-last-relocs says the same
; thing after a load as after a compile.  The file carries labels as small
; integers because the relocation loop compares them once per site; this runs
; once per load, at the seam where the two layouts meet.
(def %asm-cache-label-sym
  (fn (_ k)
    (if (= k %asm-cache-label-trampoline) 'trampoline
      (if (= k %asm-cache-label-fvar) 'fvar 'self-cell))))

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
                 (pair (list (first r) (%asm-cache-label-sym k)
                         (if (= k %asm-cache-label-self) ()
                           (if (= k %asm-cache-label-fvar) (%asm-cache-str->sym nm) nm)))
                   acc)))))
          recs ())
        ()))))

; --- entries held in the heap -------------------------------------------------
; The code object's first unit is its length in words, an INTEGER, and the
; units after it are labelled `word`: the collector does not follow them, and
; an image writes and rebuilds them as they are, zero bytes included.  An
; engine without (type set-unit-labels!) cannot describe such an object, and
; this module then holds no entries.
(def %asm-cache-code-type
  (if (null? (prim-ref 'type 'set-unit-labels!)) ()
    ((fn (_ handle)
       (Type set-unit-labels! (Type by-atom handle) -1 '(ref word))
       handle)
     ((prim-ref 'type 'make) "ASM-CODE" ()))))

; Each entry is (text size code st): the key text a hit must match, the code's
; size in bytes, the code object, and the entry's site table (see "sites").
(def %asm-cache-held ())

(def %asm-cache-held-find
  (fn (self text l)
    (if (null? l) ()
      (if (str=? text (first (first l))) (first l)
        (self text (rest l))))))

; Where a code object's bytes begin: its second unit.
(def %asm-cache-code-at
  (fn (_ code)
    (%asm-cache-int->ptr
      (+ (%asm-cache-ptr->int (%asm-cache-obj->ptr code)) (%data-word-off 1)))))

; Records as asm.x hands them out, in the file's layout.
(def %asm-cache-file-recs
  (fn (_ relocs)
    ((fn (self rs acc)
       (if (null? rs) (%asm-cache-rev acc ())
         (self (rest rs)
           (pair (list (first (first rs))
                       (%asm-cache-label-int (first (rest (first rs))))
                       (%asm-cache-name-str (first (rest (rest (first rs))))))
             acc))))
      relocs ())))

; Hold the entry for TEXT: SIZE bytes of code at BUF, moved by one block copy,
; and RELOCS as asm.x hands them out.  The last word is cleared first, since
; the code need not fill it.  A text already held is left as it is.
(def %asm-cache-hold!
  (fn (_ text size relocs buf)
    (if (null? %asm-cache-code-type) ()
      (if (not (null? (%asm-cache-held-find text %asm-cache-held))) ()
        (%asm-cache-hold-sites! text size (%asm-cache-sites (%asm-cache-file-recs relocs)) buf)))))

; The same, from a site table -- what a group file carries.  Nothing here
; checks whether TEXT is held: the callers do.
(def %asm-cache-hold-sites!
  (fn (_ text size st buf)
    (if (null? %asm-cache-code-type) ()
      (guard (_ ())
        (do
          (def words (%asm-cache-int/ (+ size (- %word-size 1)) %word-size))
          (def code (%asm-cache-obj-make %asm-cache-code-type (+ words 1)))
          (%obj-set! code 0 words)
          (%asm-cache-ptr-set-word! (%asm-cache-obj->ptr code) (%data-word-off words) 0)
          (%asm-cache-copy! (%asm-cache-code-at code) buf size)
          (set! %asm-cache-held
            (pair (list text size code st) %asm-cache-held))
          ())))))

; --- groups: many entries in one file ----------------------------------------
; A caller that compiles the same set of functions in every process -- a
; lexer's states, made from one rule list -- pays the per-entry cost of a hit
; once per function: print and hash the key, open, read and parse two files.
; That is ~6 ms of a ~11 ms hit, and a lexer has a score of states.  A GROUP
; names the set: (compile asm-cache-group) runs a thunk with every compile in
; it noted, and keeps the entries it noted in ONE file, keyed by the caller's
; key.  The next process loads that file before the thunk runs, in one read,
; into the entries held in the heap, so each compile in the thunk hits the
; heap: no hash of its key, no file.
;
; The file is a run of entries, each a held entry as bytes: a header (this
; magic, the code's size, the slots and the sites), each slot's label as four
; bytes, the sites as the table holds them, each slot's name and then the key
; text NUL-terminated, then the code.  So a load reads a slot at a time and
; moves the sites in one copy.  The file is a SUPERSET of nothing and trusted
; for nothing: every entry is still matched to a compile by its whole key
; text, as a held entry always is, so a group file from older rules, an older
; compiler or another engine loads entries no compile asks for, and the
; compiles miss to the per-entry files as before.  When any compile in the
; thunk was not among the entries the file held, the file is written again
; from what the heap holds now.
(def %asm-cache-group-magic 843530584)   ; "XAG2" little-endian
(def %asm-cache-group-entry-magic 843399512)   ; "XAE2" little-endian
; After the entries a group file may carry the caller's EXTRA: this magic, its
; length, and its text with a NUL.  A loader that predates it stops after the
; count of entries and never reads it.
(def %asm-cache-group-extra-magic 1481130328)   ; "XAGX" little-endian

; () when no group is open, else (texts) -- the key texts noted, newest first.
(def %asm-cache-group-open (pair () ()))

(def %asm-cache-group-note!
  (fn (_ text)
    (def g (first %asm-cache-group-open))
    (unless (null? g)
      (unless (%asm-cache-member? text (first g))
        (%set-first! g (pair text (first g)))))))

(def %asm-cache-member?
  (fn (self s l)
    (if (null? l) #f (if (str=? s (first l)) #t (self s (rest l))))))

(def %asm-cache-group-path
  (fn (_ key)
    (Str append (%asm-cache-dir) "/x-asmg-"
      (%asm-cache-wts (Hash fnv-1a (Str append %asm-cache-identity key))))))

; Hold every entry of the group file at PATH that is not held already.
; Answers the key texts the file carried, or () when there is no usable file.
(def %asm-cache-group-load!
  (fn (_ path) (first (%asm-cache-group-read! path))))

; The entry at EB, ROOM bytes of the file from it, held unless its text is:
; answers (text . length), or () when it is not a whole entry.  Every offset
; is checked against ROOM before it is read, as the per-entry header is.
(def %asm-cache-group-entry!
  (fn (_ eb room)
    (if (if (%asm-cache-i< room %asm-cache-head-bytes) #t
          (not (%asm-cache-i= (%asm-cache-ptr-ref eb 0 4) %asm-cache-group-entry-magic)))
      ()
      (do
        (def size (%asm-cache-ptr-ref eb 4 4))
        (def nslots (%asm-cache-ptr-ref eb 8 4))
        (def n (%asm-cache-ptr-ref eb 12 4))
        (def at-sites (%asm-cache-i+ %asm-cache-head-bytes (%asm-cache-i* 4 nslots)))
        (def at-blob (%asm-cache-i+ at-sites (%asm-cache-i* 8 n)))
        (if (%asm-cache-i< room at-blob) ()
          (do
            ; the slots, newest first, then the key text; () when the blob ends
            ; short
            (def named
              ((fn (self k at acc)
                 (if (%asm-cache-i= k nslots)
                   (do (def kt (%asm-cache-blob-at eb at room))
                       (if (null? kt) () (list acc (first kt) (rest kt))))
                   (do (def sn (%asm-cache-blob-at eb at room))
                       (if (null? sn) ()
                         (self (%asm-cache-i+ k 1) (rest sn)
                           (pair (pair (%asm-cache-ptr-ref eb (%asm-cache-i+ %asm-cache-head-bytes (%asm-cache-i* 4 k)) 4)
                                       (first sn))
                                 acc))))))
               0 at-blob ()))
            (if (null? named) ()
              (do
                (def text (first (rest named)))
                (def end (first (rest (rest named))))
                (if (%asm-cache-i< room (%asm-cache-i+ end size)) ()
                  (do
                    (when (null? (%asm-cache-held-find text %asm-cache-held))
                      (do
                        (def sites (%asm-cache-words n))
                        (%asm-cache-copy! (%asm-cache-words-at sites)
                          (%asm-cache-int->ptr (%asm-cache-i+ (%asm-cache-ptr->int eb) at-sites))
                          (%asm-cache-i* 8 n))
                        (%asm-cache-hold-sites! text size
                          (list (%asm-cache-rev (first named) ()) sites n)
                          (%asm-cache-int->ptr (%asm-cache-i+ (%asm-cache-ptr->int eb) end)))))
                    (pair text (%asm-cache-i+ end size))))))))))))

; The same, answering (TEXTS . EXTRA): the key texts, newest first, and the
; extra the file carried after its entries, or () for none.  A file cut short
; or damaged among its entries carries no extra.
(def %asm-cache-group-read!
  (fn (_ path)
    (guard (_ (pair () ()))
      (do
        (def sl (%asm-cache-slurp path))
        (if (null? sl) (pair () ())
          (do
            (def buf (first sl))
            (def got (rest sl))
            (def base (%asm-cache-ptr->int buf))
            ; (texts . at) when every entry was read, AT just past the last;
            ; (texts) when the walk stopped short
            (def walked
              (if (not (%asm-cache-i= (%asm-cache-ptr-ref buf 0 4) %asm-cache-group-magic)) (pair () ())
                ((fn (self i n at acc)
                   (if (not (%asm-cache-i< i n)) (pair acc at)
                     (do
                       (def r (%asm-cache-group-entry! (%asm-cache-int->ptr (%asm-cache-i+ base at)) (- got at)))
                       (if (null? r) (pair acc ())
                         (self (%asm-cache-i+ i 1) n (%asm-cache-i+ at (rest r)) (pair (first r) acc))))))
                  0 (%asm-cache-ptr-ref buf 4 4) 8 ())))
            (def at (rest walked))
            (def extra
              (if (null? at) ()
                (if (%asm-cache-i< (- got at) 9) ()
                  (if (%asm-cache-i= (%asm-cache-ptr-ref (%asm-cache-int->ptr (%asm-cache-i+ base at)) 0 4)
                        %asm-cache-group-extra-magic)
                    (%asm-cache-ptr->str (%asm-cache-int->ptr (%asm-cache-i+ base (%asm-cache-i+ at 8))))
                    ()))))
            (%asm-cache-pcall %asm-libc-free buf)
            (pair (first walked) extra)))))))

; Held entry E to FD, as a group file carries it.
(def %asm-cache-put-entry
  (fn (_ fd e)
    (def size (first (rest e)))
    (def st (first (rest (rest (rest e)))))
    (def slots (first st))
    (def n (first (rest (rest st))))
    (def nslots (%length slots))
    (def hbytes (%asm-cache-i+ %asm-cache-head-bytes (%asm-cache-i* 4 nslots)))
    (def hb (%asm-cache-int->ptr (%asm-cache-pcall %asm-libc-malloc hbytes)))
    (%asm-cache-ptr-set! hb 0 %asm-cache-group-entry-magic 4)
    (%asm-cache-ptr-set! hb 4 size 4)
    (%asm-cache-ptr-set! hb 8 nslots 4)
    (%asm-cache-ptr-set! hb 12 n 4)
    ((fn (self ss at)
       (unless (null? ss)
         (do (%asm-cache-ptr-set! hb at (first (first ss)) 4)
             (self (rest ss) (%asm-cache-i+ at 4)))))
     slots %asm-cache-head-bytes)
    (def ok (%asm-cache-put fd hb hbytes))
    (%asm-cache-pcall %asm-libc-free hb)
    (if (not ok) #f
      (if (not (if (%asm-cache-i= n 0) #t (%asm-cache-put fd (%asm-cache-words-at (first (rest st))) (%asm-cache-i* 8 n)))) #f
        (if (not ((fn (self ss) (if (null? ss) #t (if (%asm-cache-put-str fd (rest (first ss))) (self (rest ss)) #f)))
                  slots))
          #f
          (if (%asm-cache-put-str fd (first e))
            (%asm-cache-put fd (%asm-cache-code-at (first (rest (rest e)))) size)
            #f))))))

; Write the held entries for TEXTS (oldest first) to PATH as a group file,
; through a pid-unique temp and a rename, and EXTRA after them when it is a
; string.  A text with no held entry is left out; quiet on any failure, as a
; store is.
(def %asm-cache-group-store!
  (fn (_ path texts . more)
    (def extra (if (null? more) () (first more)))
    (guard (_ ())
      (do
        (def es
          ((fn (self ts acc)
             (if (null? ts) (%asm-cache-rev acc ())
               (self (rest ts)
                 ((fn (_ e) (if (null? e) acc (pair e acc)))
                  (%asm-cache-held-find (first ts) %asm-cache-held)))))
            texts ()))
        (unless (null? es)
          (do
            (def tmp (Str append path "." (%asm-cache-wts (%asm-cache-pcall %asm-libc-getpid)) ".tmp"))
            (def fd (%asm-cache-creat tmp))
            (unless (< fd 0)
              (do
                (def hb (%asm-cache-int->ptr (%asm-cache-pcall %asm-libc-malloc 8)))
                (%asm-cache-ptr-set! hb 0 %asm-cache-group-magic 4)
                (%asm-cache-ptr-set! hb 4 (%length es) 4)
                (def ok0 (%asm-cache-put fd hb 8))
                (%asm-cache-pcall %asm-libc-free hb)
                (def ok
                  ((fn (self l)
                     (if (null? l) #t
                       (if (%asm-cache-put-entry fd (first l)) (self (rest l)) #f)))
                    (if ok0 es ())))
                (def ok-extra
                  (if (if ok (str? extra) #f)
                    (do
                      (def xb (%asm-cache-int->ptr (%asm-cache-pcall %asm-libc-malloc 8)))
                      (%asm-cache-ptr-set! xb 0 %asm-cache-group-extra-magic 4)
                      (%asm-cache-ptr-set! xb 4 (%asm-cache-byte-len extra) 4)
                      (def okx (%asm-cache-put fd xb 8))
                      (%asm-cache-pcall %asm-libc-free xb)
                      (if okx (%asm-cache-put-str fd extra) #f))
                    #t))
                (%asm-cache-pcall %asm-libc-close fd)
                (if (if ok0 (if ok ok-extra #f) #f)
                  (%asm-cache-pcall %asm-libc-rename tmp path)
                  (%asm-cache-pcall %asm-libc-unlink tmp))))))))))

; Each group this heap has loaded or written, (key texts held extra) with the
; texts newest first, as a load answers them, HELD the list of held entries
; just after, and EXTRA the group's extra or ().  A group met again -- the same
; rules remade, or a process booted from a state image the group was made in --
; needs no file while its entries are still held: entries are only ever consed
; onto the front of the held list, so they are while that list still ends in
; HELD.  A held list set back to nil, as a spec does to stand for a fresh
; process, ends in nothing of the kind, and the file is read as before.
(def %asm-cache-groups ())

; (TEXTS . EXTRA) for KEY when this heap holds its entries, else ().
(def %asm-cache-group-known
  (fn (self key l)
    (if (null? l) ()
      (if (str=? key (first (first l)))
        (if (%asm-cache-tail? %asm-cache-held (first (rest (rest (first l)))))
          (pair (first (rest (first l))) (first (rest (rest (rest (first l))))))
          ())
        (self key (rest l))))))

; Whether list L ends in list TAIL, by identity.
(def %asm-cache-tail?
  (fn (self l tail)
    (if (eq? l tail) #t (if (null? l) #f (self (rest l) tail)))))

(def %asm-cache-group-remember!
  (fn (_ key texts extra)
    (set! %asm-cache-groups
      (pair (list key texts %asm-cache-held extra)
        ((fn (self l)
           (if (null? l) ()
             (if (str=? key (first (first l))) (rest l)
               (pair (first l) (self (rest l))))))
         %asm-cache-groups)))))

; Whether NOTED and HAD name the same entries.  A remake compiles in the order
; the group was written, so the two lists usually match pair by pair, which
; costs one string compare an entry; any other order falls back to membership.
(def %asm-cache-same-texts?
  (fn (_ noted had)
    (if (not (%asm-cache-i= (%length noted) (%length had))) #f
      (if ((fn (self a b)
             (if (null? a) #t (if (str=? (first a) (first b)) (self (rest a) (rest b)) #f)))
           noted had)
        #t
        ((fn (self l) (if (null? l) #t (if (%asm-cache-member? (first l) had) (self (rest l)) #f)))
         noted)))))

; Run THUNK with its compiles grouped under KEY, and answer what it answers.
; Groups do not nest: a group opened inside another runs its thunk in the
; outer one.  An engine whose heap cannot hold an entry has no groups either:
; the thunk runs and its compiles take the per-entry path.
;
; The open group is (NOTED HAD EXTRA OUT): the texts noted so far, newest
; first; the texts the group already held, oldest first, the order they were
; compiled in; the extra it carried; and a cell for an extra the thunk sets.
; The file is written again when the texts noted differ from those held, or
; the thunk set an extra other than the one carried.
(def asm-cache-group
  (fn (_ key thunk)
    (if (if (null? %asm-cache-code-type) #t
          (if (%asm-cache-stand-aside?) #t
            (not (null? (first %asm-cache-group-open)))))
      (thunk)
      (do
        ; A group this heap already holds is not read again; its file's path
        ; -- a hash of the key -- is wanted only to read or write the file.
        (def known (%asm-cache-group-known key %asm-cache-groups))
        (def got (if (null? known) (%asm-cache-group-read! (%asm-cache-group-path key)) known))
        (def had (first got))
        (def g (list () (%asm-cache-rev had ()) (rest got) (pair () ())))
        (%set-first! %asm-cache-group-open g)
        (def out
          (guard (e (do (%set-first! %asm-cache-group-open ()) (error e)))
            (thunk)))
        (%set-first! %asm-cache-group-open ())
        (def noted (first g))
        (def set-extra (first (first (rest (rest (rest g))))))
        (def extra (if (null? set-extra) (rest got) set-extra))
        (unless (if (%asm-cache-same-texts? noted had)
                  (if (null? set-extra) #t (if (str? (rest got)) (str=? set-extra (rest got)) #f))
                  #f)
          (%asm-cache-group-store! (%asm-cache-group-path key) (%asm-cache-rev noted ()) extra))
        ; a thunk that compiled nothing says nothing about the group
        (unless (null? noted)
          (%asm-cache-group-remember! key noted extra))
        out))))

; (TEXTS . EXTRA) of the open group: the texts it already held, oldest first,
; and the extra it carried -- or () when no group is open.
(def asm-cache-group-held
  (fn (_)
    (def g (first %asm-cache-group-open))
    (if (null? g) () (pair (first (rest g)) (first (rest (rest g)))))))

; Set the open group's extra, a string, which the group writes with its
; entries.  Answers #f when no group is open.
(def asm-cache-group-extra!
  (fn (_ extra)
    (def g (first %asm-cache-group-open))
    (if (null? g) #f
      (do (%set-first! (first (rest (rest (rest g)))) extra) #t))))

; The key text of the last compile through the door, or nil once one stood
; aside: a caller that will load the same entry again by key -- a Lexer
; recording the plan it replays -- reads it after each compile.
(def %asm-cache-last-text (pair () ()))

(def asm-cache-last-text (fn (_) (first %asm-cache-last-text)))

; The callable for the held entry whose key text is TEXT, poured with FVARS,
; or () when none is held: a load by key with no expression to print.  The
; text is noted in the open group, as a compile's is.  The facts about the last
; function are left as they were: no compile was asked for.
(def asm-cache-held-pour
  (fn (_ text fvars)
    (%asm-cache-group-note! text)
    (%asm-cache-held-load text fvars #f)))

; The callable for TEXT from the entry held for it, or () on any miss; PUBLISH?
; as %asm-cache-pour takes it.
(def %asm-cache-held-load
  (fn (_ text fvars publish?)
    (guard (_ ())
      (do
        (def e (%asm-cache-held-find text %asm-cache-held))
        (if (null? e) (%asm-cache-miss)
          (%asm-cache-pour
            (fn (_ dst size)
              (%asm-cache-copy! dst (%asm-cache-code-at (first (rest (rest e)))) size)
              #t)
            (first (rest e)) (first (rest (rest (rest e)))) fvars publish?))))))

; --- the public door --------------------------------------------------------
; THE CACHE IS THE DOOR AND THE COMPILER IS WHAT IT FALLS BACK TO, which is the
; whole point of putting it here rather than inside asm-compile.x.  Loading the
; compiler costs 2.5M evals before it emits a single instruction -- a third
; again of what the eleven compiles in a xenon boot cost to run.  Probing first
; means a warm process never pays it: compile.x's lazy stub imports THIS
; module, this module imports asm-code.x (which the loader needs), and
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
; dlsym answer nil, which misses, which reaches asm-compile-fresh, which
; raises the same "JIT runtime unavailable" it always did.
(def asm-compile-cached
  (fn (_ expr . %asm-rest)
    (def fvars (unless (null? %asm-rest) (first %asm-rest)))
    ; The calling world is settled here, at the door, and nowhere else.  It is
    ; declared, never read off the fvar table: an fvar is a handoff target in an
    ; analyser and a callee in an integer function (#603), so a table says
    ; nothing about which world a body is written for.  With no third argument,
    ; a compile without fvars is an integer function and one with fvars
    ; refuses, naming both declarations.  This is a check on the call, not a
    ; cache doubt, so it raises before the cache is asked anything.  Settling
    ; it here rather than downstream keeps the key below and the compile below
    ; naming the same answer.
    (def analyser?
      (match
        ((null? %asm-rest) #f)
        ((pair? (rest %asm-rest)) (first (rest %asm-rest)))
        ((null? fvars) #f)
        (#t (Err raise 'value
              (Str append "compile-asm: fvars passed without declaring the calling "
                "world.  Pass #t as compile-asm's third argument for an analyse "
                "callback the tokenizer calls, or #f for an integer function "
                "called from x.") ()))))
    ; Whether to stand aside is decided FIRST, before the printer is asked for
    ; anything: on that path this module gets out of the way entirely and the
    ; expression takes the route it took before there was a cache.
    (if (%asm-cache-stand-aside?)
      (do (%set-first! %asm-cache-last-text ())
          (%asm-cache-uncached expr fvars analyser?))
      (do
        ; The key text and the path hashed from it are computed ONCE and handed
        ; down: hashing the same text again for the store, or for the sibling
        ; file, would cost as much as hashing it did the first time.
        (def text (%asm-cache-text expr fvars analyser?))
        (%set-first! %asm-cache-last-text text)
        (%asm-cache-group-note! text)
        ; The entry this process holds comes first: it costs no file, and in
        ; a process booted from a state image it is the entry the image
        ; carried.
        (def held (%asm-cache-held-load text fvars #t))
        (if (not (null? held)) held
          (do
            (def base (%asm-cache-path text))
            (def hit (%asm-cache-load text base fvars))
            (if (not (null? hit))
              (do (%asm-cache-hold! text %asm-last-size %asm-last-relocs %asm-last-buf)
                  hit)
              (do
                (def f (%asm-cache-uncached expr fvars analyser?))
                (%asm-cache-store! text base %asm-last-size %asm-last-relocs %asm-last-buf)
                (%asm-cache-hold! text %asm-last-size %asm-last-relocs %asm-last-buf)
                (%asm-cache-patcher-compile!)
                f))))))))

(doc asm-compile-cached
  (returns CALLABLE "X-lang callable prim")
  "JIT compile an x-lang (fn ...) expression to a native prim, through a
   persistent byte cache.  This is the function behind compile-asm, the door
   in x/tool/compile, which loads this module on its first call and hands
   every call here.  Accepts an optional fvar alist for free variable
   support, and a third argument declaring the calling mode: #f for an
   integer function called from x, #t for an analyse callback the tokenizer
   calls.  A compile with fvars must declare it and refuses without it; one
   with neither fvars nor a declaration is an integer function.  In analyser
   mode nothing evaluates the arguments and the result is not boxed, and
   arithmetic or an ordered comparison on a leading param refuses rather than
   answering.
   An fvar holding a prim may be called by name; (%call HEAD arg ...) calls a
   prim the code computes, and refuses at run time if the head is not one.
   The compiled function works with map, fold, closures, etc.
   The cache keeps two files per entry, in /tmp or in the directory the
   X_ASM_CACHE_DIR environment variable names, and holds each entry in the
   heap as well, where a state image carries it.")

; Filed in the catalogue for the compile-asm door in x/tool/compile: that module
; loads this one on first use and cannot name a function of a module it has
; not loaded, so it fetches the entry after the import.
(prim-reg! (lit compile) (lit asm-cached) asm-compile-cached)
(prim-reg! (lit compile) (lit asm-cache-group) asm-cache-group)
(prim-reg! (lit compile) (lit asm-cache-group-held) asm-cache-group-held)
(prim-reg! (lit compile) (lit asm-cache-group-extra!) asm-cache-group-extra!)
(prim-reg! (lit compile) (lit asm-cache-held-pour) asm-cache-held-pour)
(prim-reg! (lit compile) (lit asm-cache-last-text) asm-cache-last-text)

(doc asm-cache-group
  (returns ANY "What THUNK answers")
  "Run THUNK, a (fn (_)), with every compile-asm in it grouped under KEY, a
   string naming the set: the same key in a later process loads every entry
   the group kept from one file into the heap before THUNK runs, so each of
   its compiles hits without hashing its key or opening a file.  Every entry
   is still matched by its whole key text, so a stale group costs misses, never
   a wrong function.  Groups do not nest.")

(doc asm-cache-group-held
  (returns ANY "(TEXTS . EXTRA), or nil outside a group")
  "Inside a group's thunk, the key texts the group already held, oldest first
   -- the order they were compiled in -- and the extra the group carried, a
   string or nil.")

(doc asm-cache-group-extra!
  (returns BOOL "#f outside a group")
  "Inside a group's thunk, set the string the group writes after its entries,
   which a later process reads back through asm-cache-group-held.")

(doc asm-cache-held-pour
  (returns ANY "X-lang callable prim, or nil")
  "The held entry whose key text is TEXT, poured with FVARS: a load by key, with
   no expression printed or hashed.  Nil when no entry is held for the text.
   The text is noted in the open group, as a compile's is.")

(doc asm-cache-last-text
  (returns ANY "A string, or nil")
  "The key text of the last compile-asm through the cache, which
   asm-cache-held-pour takes to load the same entry again; nil when that
   compile stood aside from the cache.")

(doc (provide x/tool/asm-cache asm-compile-cached asm-cache-group asm-cache-group-held asm-cache-group-extra! asm-cache-held-pour asm-cache-last-text)
  "The cache behind the compile-asm door: persistent emitted native code, over
   the JIT compiler it falls back to.")
