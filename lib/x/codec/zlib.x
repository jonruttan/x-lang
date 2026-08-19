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
;
; Payloads ride BYTE LISTS both ways (the lossless carrier, #362):
; compressed data is binary and strings truncate observably at NUL. The
; FFI buffers are (str make N) regions -- NUL-blind through byte-ref/ptr
; access with every length EXPLICIT, so the string tier's limits never
; touch the data.
;
; Failures raise kind-'value with zlib's code in the payload (corrupt
; input is Z_DATA_ERROR -3); gz file troubles raise kind-'io. Cold paths
; throughout: symbols resolve per call ((Zlib %sym) -- dlopen re-returns
; the cached handle), keeping the file at zero top-level %-globals.

(import x/type/class)
(import x/core/list)

(def-class Zlib ()
  (doc "Compression via the system zlib over the dlopen FFI: compress/decompress (zlib format, byte lists both ways) and the gzip file doors gz-read-all/gz-write-all."
    (example "(Zlib decompress (Zlib compress (list 104 105)))" "(104 105)")
    (see compress) (see gz-read-all))
  (static
    ; Resolve one libz symbol, per call (cold; dlopen caches the handle).
    (method %sym (self (param name STRING "libz function name"))
      (doc "The named libz symbol, resolving libz.so.1 / libz.dylib / the current process, in that order."
        (returns PTR "The function pointer"))
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
    (method %from-buf (self (param p PTR "Buffer pointer") (param n INT "Byte count"))
      (doc "Read n bytes from a buffer into a byte list."
        (returns LIST "Byte values (0-255)"))
      (def %pref (prim-ref (lit ptr) (lit ref)))
      (let go ((i (- n 1)) (acc ()))
        (if (< i 0) acc
          (go (- i 1) (pair (& (%pref p i 1) 255) acc)))))

    ; Write a machine word little-endian into a length cell; read it back.
    ; uLongf is unsigned long = the machine word on both target OSes.
    (method %len-cell! (self (param p PTR "Cell pointer") (param v INT "Value"))
      (doc "Store v as the platform word in a length in/out cell."
        (returns ANY "nil"))
      (def %pset-word (prim-ref (lit ptr) (lit set-word!)))
      (%pset-word p 0 v)
      ())
    (method %len-cell (self (param p PTR "Cell pointer"))
      (doc "Read the platform word from a length in/out cell."
        (returns INT "The stored value"))
      (def %pref-word (prim-ref (lit ptr) (lit ref-word)))
      (%pref-word p 0))

    (method compress (self (param bytes LIST "Bytes to compress")
                           . (param level INT "zlib level 0-9; default 6"))
      (doc "Compress a byte list (zlib format, RFC 1950) at the given level. Raises kind-'value with zlib's code on failure."
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
                             . (param hint INT "Expected output size; default 4x the input (the buffer doubles on shortfall either way)"))
      (doc "Decompress zlib-format bytes. The format carries no output size, so the destination starts at hint (or 4x the input) and DOUBLES on Z_BUF_ERROR until it fits. Corrupt input raises kind-'value with zlib's code (Z_DATA_ERROR is -3)."
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

    (method gz-read-all (self (param path STRING "A .gz file to read"))
      (doc "The whole decompressed content of a gzip file, as a byte list (gzopen/gzread in 64KB slabs). Raises kind-'io when the file cannot be opened; corrupt content raises kind-'value."
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
                               . (param level INT "zlib level 1-9; default 6"))
      (doc "Write a byte list as a gzip file. Raises kind-'io on open or short-write failure; returns the byte count written."
        (returns INT "Bytes written (the uncompressed count)")
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
