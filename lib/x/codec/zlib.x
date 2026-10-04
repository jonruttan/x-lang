; codec/zlib.x -- Zlib: compression through the system zlib, via FFI (#373).
;
; The ruled strategy (issue comment, 2026-08-20): bind libz the way Float
; binds libm and Sys binds libc -- dlopen/dlsym/ptr-call, pure x, no new C.
; libz ships on both target OSes (libz.dylib / libz.so.1).
;
;   (Zlib compress bytes [level])   -> byte list, zlib format (RFC 1950)
;   (Zlib decompress bytes [hint])  -> byte list; the destination grows by
;                                      doubling on Z_BUF_ERROR (the zlib
;                                      format carries no size), seeded by
;                                      hint or 4x the input
;   (Zlib gz-read-all path)         -> byte list from a .gz file
;   (Zlib gz-write-all path bytes [level]) -> byte count written to a .gz
;   (Zlib deflater level format)    -> a deflate stream; format zlib, gzip
;   (Zlib inflater format)             or raw (no wrapper)
;   (Zlib step s in off n out at room finish) -> (USED MADE STATUS)
;   (Zlib end s)                    -> frees the stream's zlib state
;   (Zlib crc32 crc buf n)          -> the CRC-32 gzip carries
;
; The one-shots' payloads ride BYTE LISTS both ways (the lossless carrier,
; #362): compressed data is binary and strings truncate observably at NUL. A
; stream reads and fills strings in place, every count explicit. The
; FFI buffers are (str make N) regions -- NUL-blind through byte-ref/ptr
; access with every length EXPLICIT, so the string profile's limits never
; touch the data.
;
; Failures raise a label 'value with zlib's code in the payload (corrupt
; input is Z_DATA_ERROR -3); gz file troubles raise a label 'io. Cold paths
; throughout: symbols resolve per call ((Zlib %sym) -- dlopen re-returns
; the cached handle), keeping the file at zero top-level %-globals.

(module x/codec/zlib)
(import x/type/class)
(import x/core/list)

(def-class Zlib ()
  (doc "Compression via the system zlib over the dlopen FFI: compress/decompress (zlib format, byte lists both ways), the gzip file doors gz-read-all/gz-write-all, and streams (deflater, inflater, step, end) that deflate and inflate buffers in place, with crc32."
    (example "(Zlib decompress (Zlib compress (list 104 105)))" "(104 105)")
    (see compress) (see gz-read-all) (see step))
  (static
    ; Resolve one libz symbol, per call (cold; dlopen caches the handle).
    (method %sym (self (param name STRING "libz function name"))
      (doc "The named libz symbol, resolving libz.so.1 / libz.dylib / the current process, in that order."
        (returns POINTER "The function pointer"))
      (def %dlopen (prim-ref (lit ffi) (lit dlopen)))
      (def %dlsym (prim-ref (lit ffi) (lit dlsym)))
      (def h
        (let ((h1 (%dlopen "libz.so.1" 1)))
          (if h1 h1
            (let ((h2 (%dlopen "libz.dylib" 1)))
              (if h2 h2 (%dlopen () 1))))))
      (%dlsym h name))

    ; Byte list -> a fresh (str make) region + its raw ptr; the region is
    ; GC-owned. Returns (region . ptr); the caller keeps the region live.
    (method %to-buf (self (param bytes LIST "Byte values"))
      (doc "Copy a byte list into a GC-owned buffer region."
        (returns PAIR "(region-string . raw-ptr)"))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %pset (prim-ref (lit ptr) (lit set!)))
      (def n (List length bytes))
      (def region (%make-str (if (= n 0) 1 n)))
      (def p (%str->ptr region))
      (let go ((l bytes) (i 0))
        (unless (null? l)
          (do (%pset p i (first l) 1)
              (go (rest l) (+ i 1)))))
      (pair region p))

    ; buffer ptr -> byte list of the first n bytes.
    (method %from-buf (self (param p POINTER "Buffer pointer") (param n INTEGER "Byte count"))
      (doc "Read n bytes from a buffer into a byte list."
        (returns LIST "Byte values (0-255)"))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (let go ((i (- n 1)) (acc ()))
        (if (< i 0) acc
          (go (- i 1) (pair (& (%pref p i 1) 255) acc)))))

    ; Write a machine word little-endian into a length cell; read it back.
    ; uLongf is unsigned long = the machine word on both target OSes.
    (method %len-cell! (self (param p POINTER "Cell pointer") (param v INTEGER "Value"))
      (doc "Store v as the platform word in a length in/out cell."
        (returns ANY "nil"))
      (def %pset-word (prim-ref (lit ptr) (lit set-word!)))
      (%pset-word p 0 v)
      ())
    (method %len-cell (self (param p POINTER "Cell pointer"))
      (doc "Read the platform word from a length in/out cell."
        (returns INTEGER "The stored value"))
      (def %pref-word (prim-ref (lit ptr) (lit ref-word)))
      (%pref-word p 0))

    (method compress (self (param bytes LIST "Bytes to compress")
                           . (param level INTEGER "zlib level 0-9; default 6"))
      (doc "Compress a byte list (zlib format, RFC 1950) at the given level. Raises a label 'value with zlib's code on failure."
        (returns LIST "The compressed bytes")
        (example "(Zlib decompress (Zlib compress (list 1 2 3 1 2 3 1 2 3)))" "(1 2 3 1 2 3 1 2 3)"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def n (List length bytes))
      (def src (Zlib %to-buf bytes))
      ; compressBound(n): the worst-case destination size
      (def cap (%call (Zlib %sym "compressBound") n))
      (def dst-region (%make-str cap))
      (def dst (%str->ptr dst-region))
      (def lencell-region (%make-str 8))
      (def lencell (%str->ptr lencell-region))
      (Zlib %len-cell! lencell cap)
      ; int returns arrive zero-extended (the %sys-fold rule, locally)
      (def r (let ((raw (%call (Zlib %sym "compress2") dst lencell (rest src) n
                          (if (null? level) 6 (first level)))))
               (if (> raw 2147483647) (- raw 4294967296) raw)))
      (when (not (= r 0))
        (Err raise (lit value) "Zlib compress: zlib error" r))
      (Zlib %from-buf dst (Zlib %len-cell lencell)))

    (method decompress (self (param bytes LIST "zlib-format bytes to decompress")
                             . (param hint INTEGER "Expected output size; default 4x the input (the buffer doubles on shortfall either way)"))
      (doc "Decompress zlib-format bytes. The format carries no output size, so the destination starts at hint (or 4x the input) and DOUBLES on Z_BUF_ERROR until it fits. Corrupt input raises a label 'value with zlib's code (Z_DATA_ERROR is -3)."
        (returns LIST "The decompressed bytes")
        (example "(Zlib decompress (Zlib compress (list 104 105)))" "(104 105)"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def n (List length bytes))
      (when (= n 0)
        (Err raise (lit value) "Zlib decompress: empty input" ()))
      (def src (Zlib %to-buf bytes))
      (def lencell-region (%make-str 8))
      (def lencell (%str->ptr lencell-region))
      (let attempt ((cap (if (null? hint) (* 4 n) (first hint))))
        (let ((dst-region (%make-str cap)))
          (let ((dst (%str->ptr dst-region)))
            (Zlib %len-cell! lencell cap)
            (let ((r (let ((raw (%call (Zlib %sym "uncompress") dst lencell (rest src) n)))
                       (if (> raw 2147483647) (- raw 4294967296) raw))))
              (match
                ((= r 0) (Zlib %from-buf dst (Zlib %len-cell lencell)))
                ; Z_BUF_ERROR (-5): the guess was small -- double and retry
                ((= r -5) (attempt (* 2 cap)))
                (#t (Err raise (lit value) "Zlib decompress: zlib error" r))))))))

    ; --- streams: deflate and inflate a buffer at a time ---------------------
    ; A stream is (KIND . REGION): KIND 'deflate or 'inflate, REGION a
    ; (str make) block holding zlib's z_stream (112 bytes on LP64; zlib's own
    ; state hangs off it, malloc'd, until end). The block never moves. Fields
    ; written and read: next_in 0, avail_in 8 (u32), next_out 24, avail_out 32
    ; (u32), msg 48.

    ; windowBits for a format: zlib's header, gzip's, or none
    (method %window (self (param format SYMBOL "zlib, gzip or raw"))
      (doc "zlib's windowBits for a stream format."
        (returns INTEGER "15, 31 or -15"))
      (match
        ((eq? format (lit zlib)) 15)
        ((eq? format (lit gzip)) 31)
        ((eq? format (lit raw)) -15)
        (#t (Err raise (lit value) "Zlib: the format is zlib, gzip or raw" format))))

    ; an int return, its u32 top half folded back to negative
    (method %int (self (param raw INTEGER "A zero-extended int return"))
      (doc "Fold a zero-extended C int return to its signed value."
        (returns INTEGER "The signed value"))
      (if (> raw 2147483647) (- raw 4294967296) raw))

    (method %stream (self (param kind SYMBOL "deflate or inflate")
                          (param init STRING "deflateInit2_ or inflateInit2_")
                          (param args LIST "The init call's arguments after the stream"))
      (doc "A fresh z_stream block, initialised by the named libz call."
        (returns PAIR "(KIND . REGION)"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %pset-word (prim-ref (lit ptr) (lit set-word!)))
      (def region (%make-str 112))
      (def p (%str->ptr region))
      ; zalloc, zfree and opaque nil: zlib's malloc and free
      (let clear ((off 0))
        (when (< off 112) (do (%pset-word p off 0) (clear (+ off 8)))))
      (def version (%call (Zlib %sym "zlibVersion")))
      (def r (Zlib %int (match
                          ((= (List length args) 1)
                            (%call (Zlib %sym init) p (first args) version 112))
                          (#t
                            (%call (Zlib %sym init) p (first args) 8 (first (rest args)) 8 0
                              version 112)))))
      (when (not (= r 0))
        (Err raise (lit value) "Zlib: the stream could not be made" r))
      (pair kind region))

    (method deflater (self (param level INTEGER "zlib level 0-9, or -1 for zlib's default")
                           (param format SYMBOL "zlib, gzip or raw"))
      (doc "A deflate stream: feed it with step, finish it with step's FINISH, free it with end. FORMAT is the wrapper written round the data: zlib's (RFC 1950), gzip's (RFC 1952, as zlib writes it) or none (RFC 1951)."
        (returns PAIR "The stream")
        (example "(Zlib %kind (Zlib deflater 6 (lit raw)))" "'deflate"))
      (Zlib %stream (lit deflate) "deflateInit2_" (list level (Zlib %window format))))

    (method inflater (self (param format SYMBOL "zlib, gzip or raw"))
      (doc "An inflate stream for data in FORMAT: zlib's wrapper, gzip's, or none. Free it with end."
        (returns PAIR "The stream")
        (example "(Zlib %kind (Zlib inflater (lit raw)))" "'inflate"))
      (Zlib %stream (lit inflate) "inflateInit2_" (list (Zlib %window format))))

    (method %kind (self (param s PAIR "A stream"))
      (doc "A stream's kind."
        (returns SYMBOL "deflate or inflate"))
      (first s))

    (method step (self (param s PAIR "A stream from deflater or inflater")
                       (param in STRING "Input buffer")
                       (param off INTEGER "Where the input starts in it")
                       (param n INTEGER "Input byte count")
                       (param out STRING "Output buffer")
                       (param at INTEGER "Where the output goes in it")
                       (param room INTEGER "How many bytes may go there")
                       (param finish BOOL "No more input follows (deflate)"))
      (doc "One deflate or inflate call: up to N bytes from IN at OFF, up to ROOM bytes into OUT at AT. Answers how much was used and made, and 'end when the stream is complete, 'stuck when no progress was possible (more input or more room is needed), else 'ok. Call again, OFF and AT moved on, until the input is used and a call leaves room unused; with FINISH, until 'end. Bad data raises a label 'value with zlib's code and message."
        (returns LIST "(USED MADE STATUS)")
        (example "(let ((s (Zlib deflater 6 (lit raw))) (o ((prim-ref (lit str) (lit make)) 64))) (first (rest (rest (Zlib step s \"hi\" 0 2 o 0 64 #t)))))" "'end"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
      (def %int->ptr (prim-ref (lit int) (lit ->ptr)))
      (def %pset (prim-ref (lit ptr) (lit set!)))
      (def %pset-word (prim-ref (lit ptr) (lit set-word!)))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (def %pref-word (prim-ref (lit ptr) (lit ref-word)))
      (def %ptr->str (prim-ref (lit ptr) (lit ->str)))
      (def p (%str->ptr (rest s)))
      (def deflate? (eq? (first s) (lit deflate)))
      (%pset-word p 0 (+ (%ptr->int (%str->ptr in)) off))
      (%pset p 8 n 4)
      (%pset-word p 24 (+ (%ptr->int (%str->ptr out)) at))
      (%pset p 32 room 4)
      ; Z_FINISH 4, else Z_NO_FLUSH 0
      (def r (Zlib %int (%call (Zlib %sym (if deflate? "deflate" "inflate")) p
                          (if (if deflate? finish #f) 4 0))))
      (def used (- n (& (%pref p 8 4) 4294967295)))
      (def made (- room (& (%pref p 32 4) 4294967295)))
      (match
        ((= r 0) (list used made (lit ok)))
        ((= r 1) (list used made (lit end)))
        ; Z_BUF_ERROR: nothing could be done with what was given
        ((= r -5) (list used made (lit stuck)))
        (#t
          (let ((msg (%pref-word p 48)))
            (Err raise (lit value)
              (if (= msg 0) "Zlib: zlib error"
                (Str8 append "Zlib: " (%ptr->str (%int->ptr msg))))
              r)))))

    (method end (self (param s PAIR "A stream"))
      (doc "Free a stream's zlib state. The stream is not used again."
        (returns ANY "nil"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (%call (Zlib %sym (if (eq? (first s) (lit deflate)) "deflateEnd" "inflateEnd"))
        (%str->ptr (rest s)))
      ())

    (method crc32 (self (param crc INTEGER "The CRC so far; 0 to start")
                        (param buf STRING "Bytes")
                        (param n INTEGER "How many, from its start"))
      (doc "The CRC-32 (ISO 3309, as gzip and zip carry it) of CRC's data followed by N bytes of BUF."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Zlib crc32 0 \"123456789\" 9)" "3421780262"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (& (%call (Zlib %sym "crc32") crc (%str->ptr buf) n) 4294967295))

    (method gz-read-all (self (param path STRING "A .gz file to read"))
      (doc "The whole decompressed content of a gzip file, as a byte list (gzopen/gzread in 64KB slabs). Raises a label 'io when the file cannot be opened; corrupt content raises a label 'value."
        (returns LIST "The decompressed bytes")
        (sample "(bytes->str (Zlib gz-read-all \"notes.txt.gz\"))" "the text, when the content is textual"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def gz (%call (Zlib %sym "gzopen") path "rb"))
      (when (= gz 0)
        (Err raise (lit io) (Str8 append "Zlib gz-read-all: cannot open " path) ()))
      (def slab-region (%make-str 65536))
      (def slab (%str->ptr slab-region))
      (def out
        (let go ((acc ()))
          ; gzread returns bytes read, 0 at EOF, negative on error; the
          ; return is an int -- fold the u32 top half back to negative
          ; (the %sys-fold rule, locally).
          (let ((got (let ((raw (%call (Zlib %sym "gzread") gz slab 65536)))
                       (if (> raw 2147483647) (- raw 4294967296) raw))))
            (match
              ((< got 0)
                (let ()
                  (%call (Zlib %sym "gzclose") gz)
                  (Err raise (lit value) "Zlib gz-read-all: corrupt gzip data" got)))
              ((= got 0) acc)
              (#t (go (pair (Zlib %from-buf slab got) acc)))))))
      (%call (Zlib %sym "gzclose") gz)
      (List flat-map (fn (_ chunk) chunk) (%reverse out)))

    (method gz-write-all (self (param path STRING "The .gz file to write (created/truncated)")
                               (param bytes LIST "Bytes to compress into it")
                               . (param level INTEGER "zlib level 1-9; default 6"))
      (doc "Write a byte list as a gzip file. Raises a label 'io on open or short-write failure; returns the byte count written."
        (returns INTEGER "Bytes written (the uncompressed count)")
        (sample "(Zlib gz-write-all \"notes.txt.gz\" (Str8 char->bytes ...))" "the byte count"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def mode (Str8 append "wb" (%number->str (if (null? level) 6 (first level)))))
      (def gz (%call (Zlib %sym "gzopen") path mode))
      (when (= gz 0)
        (Err raise (lit io) (Str8 append "Zlib gz-write-all: cannot open " path) ()))
      (def n (List length bytes))
      (def src (Zlib %to-buf bytes))
      (def wrote
        (let ((raw (%call (Zlib %sym "gzwrite") gz (rest src) n)))
          (if (> raw 2147483647) (- raw 4294967296) raw)))
      (%call (Zlib %sym "gzclose") gz)
      (when (if (> n 0) (not (= wrote n)) #f)
        (Err raise (lit io) "Zlib gz-write-all: short write" wrote))
      n)))

(doc (provide x/codec/zlib Zlib)
  (note "The system zlib over the dlopen FFI -- the libm precedent, no new C (#373's ruled strategy). Byte lists both ways; zlib-format one-shots plus the gzip file doors. A pure-x inflate remains possible later if a self-contained amalgam story needs it.")
  "Compression through the system zlib, homed on the Zlib class.")
