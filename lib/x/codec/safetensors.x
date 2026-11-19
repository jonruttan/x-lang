; codec/safetensors.x -- Safetensors: read and write safetensors files.
;
; A safetensors file holds named tensors:
;
;   8 bytes    N, the header's length, an unsigned little-endian integer
;   N bytes    the header, JSON text
;   the rest   the data, every tensor's elements end to end
;
; The header is an object of one entry per tensor,
;
;   "NAME": {"dtype": "F32", "shape": [2, 3], "data_offsets": [BEGIN, END]}
;
; where BEGIN and END are byte positions within the data, and an optional
; entry "__metadata__", an object of strings.  A tensor's elements are
; little-endian and in row-major order.
;
;   (Safetensors open path)        -> an open file, its header read
;   (f names)                      -> the tensors' names, sorted
;   (f ref name)                   -> the named tensor, read from the file
;   (f extent name)                -> its extent, with nothing read
;   (f encoding name)              -> its encoding, with nothing read
;   (f metadata)                   -> the metadata, a Dict of strings
;   (f close)                      -> the file closed
;   (Safetensors decode r)         -> a Dict of every tensor in the region r
;   (Safetensors encode tensors)   -> a region holding a file of the Dict's tensors
;   (Safetensors write path tensors)
;
; An open file reads a tensor's bytes when ref asks for it, straight into
; the tensor's own data: a file of any size costs its header until then,
; and a tensor is in memory once.  decode takes the whole file as a region
; (BUF START LEN), as x/codec/bytes makes and takes them, and copies each
; tensor out of it; encode answers one.  A file's bytes hold zeros, and a
; string has no length of its own past its first, so the length is kept
; beside the buffer.
;
; The encodings are those Tensor has and the format names: F64 is f64,
; F32 is f32 and I64 is i64.  A tensor of another dtype is listed by names,
; and ref raises a label 'type for it; encode raises a label 'type for a
; c128 tensor, which the format has no dtype for.  The hosts this runs on
; are little-endian, so the bytes are a tensor's data as it stands.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/codec/safetensors)
(import x/type/class)
(import x/type/dict)
(import x/type/list)
(import x/codec/json)
(import x/num/tensor)
(import x/sys/file)
(import x/core/doors int% int* int+ int- int->ptr int< int= mem-copy obj-ref ptr->int ptr-ref ptr-set!
  str->ptr str-byte-len str-byte-sub str-make type-of type?)

; The format's dtype for each encoding it shares with Tensor.
(def %st-dtypes (list (pair "F64" (lit f64)) (pair "F32" (lit f32)) (pair "I64" (lit i64))))

; The header's length is 8 bytes; the high 4 are 0 for any header a
; machine holds, and reading the two halves suits a 4-byte word as well.
(def %st-prefix 8)

(def %st-bad (fn (_ msg data) (Err raise (lit value) (Str8 append "Safetensors: " msg) data)))

(def %st-enc-of
  (fn (go name l)
    (match ((null? l) ()) ((equal? (first (first l)) name) (rest (first l))) (#t (go name (rest l))))))

(def %st-dtype-of
  (fn (go enc l)
    (match ((null? l) ()) ((eq? (rest (first l)) enc) (first (first l))) (#t (go enc (rest l))))))

(def %st-width (fn (_ enc) (if (eq? enc (lit f32)) 4 8)))

(def %st-count (fn (go ext) (if (null? ext) 1 (int* (first ext) (go (rest ext))))))

(def %st-list? (fn (_ x) (if (null? x) #t (pair? x))))

(def %st-addr (fn (_ s at) (int->ptr (int+ (ptr->int (str->ptr s)) at))))

; The header's length, from a file's first bytes at p, len of them.
(def %st-length
  (fn (_ p len)
    (if (int< len %st-prefix) (%st-bad "the file is shorter than its length field" ())
      (if (int= (ptr-ref p 4 4) 0) (ptr-ref p 0 4)
        (%st-bad "the header's length is not one a file has" ())))))

; One header entry as (DTYPE ENC EXTENT BEGIN END), ENC nil for a dtype
; Tensor has no encoding for.  room is the data's length in bytes.
(def %st-entry
  (fn (_ name e room)
    (if (Dict dict? e) () (%st-bad "an entry is not an object" name))
    (let ((dtype (e get "dtype")) (ext (e get "shape")) (at (e get "data_offsets")))
      (if (if (str? dtype) (if (%st-list? ext) (if (pair? at) (int= (List length at) 2) #f) #f) #f) ()
        (%st-bad "an entry lacks dtype, shape or data_offsets" name))
      (if (List all? (fn (_ n) (if (type? n (type-of 0)) (if (int< n 0) #f #t) #f)) (List append ext at)) ()
        (%st-bad "a shape or an offset is not a whole number" name))
      (let ((enc (%st-enc-of dtype %st-dtypes)) (b (first at)) (end (first (rest at))))
        (if (if (int< end b) #t (int< room end)) (%st-bad "an entry's bytes lie outside the data" name) ())
        (if (null? enc) ()
          (if (int= (int- end b) (int* (%st-width enc) (%st-count ext))) ()
            (%st-bad "an entry's bytes are not its shape's" name)))
        (list dtype enc ext b end)))))

; A header's text as (METADATA . ENTRIES), each a Dict.
(def %st-header
  (fn (_ text room)
    (let ((h (Json parse text)) (entries (Dict make)) (meta (Dict make)))
      (if (Dict dict? h) () (%st-bad "the header is not an object" ()))
      (h for-each
        (fn (_ kv)
          (if (equal? (first kv) "__metadata__")
            (if (Dict dict? (rest kv)) ((rest kv) for-each (fn (_ m) (meta set! (first m) (rest m)))) ())
            (entries set! (first kv) (%st-entry (first kv) (rest kv) room)))))
      (pair meta entries))))

; A fresh tensor state for an entry; the encoding is checked as Tensor
; checks one a caller names, so i64 is refused on a 4-byte word.
(def %st-state
  (fn (_ name entry)
    (if (null? (first (rest entry)))
      (Err raise (lit type) (Str8 append "Safetensors: no encoding for dtype " (first entry)) name)
      ((obj-ref (Tensor %fast) 4) (Tensor %enc-or (list (first (rest entry))) ()) (first (rest (rest entry)))))))

(def %st-bytes (fn (_ entry) (int- (List ref 4 entry) (List ref 3 entry))))

(def %st-sorted (fn (_ names) (List sort (fn (_ a b) (Str8 <? a b)) names)))

; A tensor as (DTYPE EXTENT ADDRESS BYTES KEEP): its elements contiguous
; at ADDRESS, in a state KEEP holds for as long as the address is used.
(def %st-part
  (fn (_ name t)
    (if (if (object? t) (instance-of? t Tensor) #f) () (Err raise (lit type) "Safetensors: not a tensor" name))
    (let ((f (Tensor %fast)) (st (t %st)))
      (let ((dtype (%st-dtype-of (first st) %st-dtypes)))
        (if (null? dtype)
          (Err raise (lit type) "Safetensors: the format has no dtype for this encoding" (first st)) ())
        (let ((c (if ((obj-ref f 3) st) st ((obj-ref f 10) st (first st)))))
          (list dtype (List ref 1 c) ((obj-ref f 13) c)
                (int* (%st-width (first st)) (%st-count (List ref 1 c))) c))))))

(def %st-ints
  (fn (_ l) (Str8 append "[" (Str8 join "," (List map (fn (_ n) (Json emit n)) l)) "]")))

(def-class Safetensors ()
  (doc "The safetensors file format: named tensors behind a JSON header. An open file reads each tensor when asked; decode and encode work on a whole file's bytes."
    (note "F64, F32 and I64 are read as f64, f32 and i64 tensors. A tensor of another dtype is listed, and ref raises a label 'type for it.")
    (note "A malformed file raises a label 'value; a file that cannot be opened or read raises a label 'io.")
    (example "(((Safetensors decode (Safetensors encode (Dict from-plist (list \"w\" (Tensor from '(1.5 2.5) 'f32))))) get \"w\") ->list)" "(1.5 2.5)")
    (see open) (see ref) (see decode) (see encode) (see write))

  fd        ; the file descriptor, nil once closed
  start     ; the data's byte position in the file
  meta      ; the metadata, a Dict of strings
  entries   ; name -> (DTYPE ENC EXTENT BEGIN END)

  (static
    (method open (self (param path STRING "A safetensors file"))
      (doc "Open a safetensors file and read its header. No tensor is read until ref asks for one."
        (returns Safetensors "The open file; close it when done")
        (sample "(Safetensors open \"model.safetensors\")" "the open file"))
      (let ((size (Assoc get (lit size) (File stat path))) (fd (File open path (lit rdonly))))
        (if (int< fd 0) (Err raise (lit io) "Safetensors: the file does not open" path) ())
        (guard (e (do (File close fd) (error e)))
          (let ((head (str-make %st-prefix)))
            (if (int= (File read fd head %st-prefix) %st-prefix) ()
              (%st-bad "the file is shorter than its length field" path))
            (let ((n (%st-length (str->ptr head) %st-prefix)))
              (if (int< (int- size %st-prefix) n) (%st-bad "the header runs past the file's end" path) ())
              (let ((text (str-make n)))
                (if (int= (File read fd text n) n) ()
                  (Err raise (lit io) "Safetensors: the header does not read" path))
                (let ((h (%st-header text (int- size (int+ %st-prefix n)))))
                  (new-from self
                    (list (lit fd) fd (lit start) (int+ %st-prefix n)
                          (lit meta) (first h) (lit entries) (rest h))))))))))

    (method decode (self (param r LIST "A region (BUF START LEN) holding a safetensors file"))
      (doc "Every tensor in a safetensors file's bytes."
        (returns Dict "Each name and its tensor")
        (example "(((Safetensors decode (Safetensors encode (Dict from-plist (list \"w\" (Tensor from '(1.5 2.5) 'f32))))) get \"w\") encoding)" "'f32"))
      (if (if (pair? r) (int= (List length r) 3) #f) ()
        (Err raise (lit type) "Safetensors: decode takes a region (BUF START LEN)" r))
      (let ((s (first r)) (at (List ref 1 r)) (len (List ref 2 r)) (out (Dict make)))
        (def n (%st-length (%st-addr s at) len))
        (if (int< (int- len %st-prefix) n) (%st-bad "the header runs past the bytes' end" ()) ())
        (let ((start (int+ at (int+ %st-prefix n))))
          (let ((h (%st-header (str-byte-sub s (int+ at %st-prefix) n) (int- len (int+ %st-prefix n)))))
            ((rest h) for-each
              (fn (_ kv)
                (let ((st (%st-state (first kv) (rest kv))) (bytes (%st-bytes (rest kv))))
                  (if (int< 0 bytes)
                    (mem-copy (str->ptr (List ref 4 st)) (%st-addr s (int+ start (List ref 3 (rest kv)))) bytes)
                    ())
                  (out set! (first kv) (Tensor %make st)))))
            out))))

    (method encode (self (param tensors Dict "Each name and its tensor")
                         . (param metadata Dict "Optional metadata: strings under string keys"))
      (doc "The bytes of a safetensors file holding the tensors, in the order of their names. The header is padded with spaces so the data starts on an 8-byte boundary."
        (returns LIST "The file's bytes, a region (BUF 0 LEN)")
        (example "((Safetensors decode (Safetensors encode (Dict from-plist (list \"w\" (Tensor from '(1.5 2.5) 'f32))))) keys)" "(\"w\")"))
      (let ((names (%st-sorted (tensors keys))) (at (pair 0 ())))
        (let ((parts (List map (fn (_ name) (%st-part name (tensors get name))) names)))
          (let ((rows
                  (List map
                    (fn (_ name p)
                      (let ((b (first at)))
                        (%set-first! at (int+ b (List ref 3 p)))
                        (Str8 append (Json emit name) ":{\"dtype\":" (Json emit (first p))
                          ",\"shape\":" (%st-ints (List ref 1 p))
                          ",\"data_offsets\":" (%st-ints (list b (first at))) "}")))
                    names parts))
                (meta
                  (if (null? metadata) ()
                    (list (Str8 append "\"__metadata__\":{"
                            (Str8 join ","
                              (List map
                                (fn (_ k) (Str8 append (Json emit k) ":" (Json emit ((first metadata) get k))))
                                (%st-sorted ((first metadata) keys))))
                            "}")))))
            (let ((text (Str8 append "{" (Str8 join "," (List append meta rows)) "}")))
              (let ((n (let ((n (str-byte-len text))) (int+ n (int- 7 (int% (int+ n 7) 8))))))
                (let ((total (int+ (int+ %st-prefix n) (first at))) (out (str-make (int+ (int+ %st-prefix n) (first at)))))
                  (ptr-set! (str->ptr out) 0 n 4)
                  (ptr-set! (str->ptr out) 4 0 4)
                  (mem-copy (%st-addr out %st-prefix) (str->ptr text) (str-byte-len text))
                  ((fn (go i) (if (int< i n) (do (ptr-set! (str->ptr out) (int+ %st-prefix i) 32 1) (go (int+ i 1))) ()))
                    (str-byte-len text))
                  ((fn (go ps to)
                     (if (null? ps) ()
                       (do (if (int< 0 (List ref 3 (first ps)))
                             (mem-copy (%st-addr out to) (int->ptr (List ref 2 (first ps))) (List ref 3 (first ps)))
                             ())
                           (go (rest ps) (int+ to (List ref 3 (first ps)))))))
                    parts (int+ %st-prefix n))
                  (list out 0 total))))))))

    (method write (self (param path STRING "The file to write, created or truncated")
                        (param tensors Dict "Each name and its tensor")
                        . (param metadata Dict "Optional metadata: strings under string keys"))
      (doc "Write a safetensors file holding the tensors."
        (returns INTEGER "Bytes written")
        (sample "(Safetensors write \"out.safetensors\" (Dict from-plist (list \"w\" (Tensor zeros 4 'f32))))" "80"))
      (let ((r (if (null? metadata) (Safetensors encode tensors) (Safetensors encode tensors (first metadata))))
            (fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420)))
        (if (int< fd 0) (Err raise (lit io) "Safetensors: the file does not open for writing" path) ())
        (let ((n (File write fd (first r) (List ref 2 r))))
          (File close fd)
          (if (int= n (List ref 2 r)) n
            (Err raise (lit io) "Safetensors: the file's bytes do not write" path))))))

  (method names (self)
    (doc "The names of the file's tensors, sorted."
      (returns LIST "The names, strings")
      (sample "(f names)" "(\"wpe.weight\" \"wte.weight\")"))
    (%st-sorted ((field (lit entries)) keys)))

  (method metadata (self)
    (doc "The file's metadata."
      (returns Dict "Strings under string keys; empty when the file has none")
      (sample "((f metadata) get \"format\")" "\"pt\""))
    (field (lit meta)))

  (method extent (self (param name STRING "A tensor's name"))
    (doc "The named tensor's extent, from the header."
      (returns LIST "The length of each axis, or nil for a name the file lacks")
      (sample "(f extent \"wte.weight\")" "(50257 768)"))
    (let ((e ((field (lit entries)) get name))) (if (null? e) () (List ref 2 e))))

  (method encoding (self (param name STRING "A tensor's name"))
    (doc "The encoding the named tensor is read as, from the header."
      (returns SYMBOL "f64, f32 or i64; nil for a name the file lacks or a dtype Tensor has no encoding for")
      (sample "(f encoding \"wte.weight\")" "'f32"))
    (let ((e ((field (lit entries)) get name))) (if (null? e) () (List ref 1 e))))

  (method ref (self (param name STRING "A tensor's name"))
    (doc "The named tensor, its elements read from the file into a fresh tensor."
      (returns Tensor "The tensor, or nil for a name the file lacks")
      (sample "((f ref \"wte.weight\") extent)" "(50257 768)"))
    (let ((e ((field (lit entries)) get name)) (fd (field (lit fd))))
      (if (null? e) ()
        (do
          (if (null? fd) (Err raise (lit state) "Safetensors: the file is closed" name) ())
          (let ((st (%st-state name e)) (bytes (%st-bytes e)))
            (if (int< 0 bytes)
              (do (File seek fd (int+ (field (lit start)) (List ref 3 e)))
                  (if (int= (File read fd (List ref 4 st) bytes) bytes) ()
                    (Err raise (lit io) "Safetensors: the tensor's bytes do not read" name)))
              ())
            (Tensor %make st))))))

  (method close (self)
    (doc "Close the file. Tensors already read stay; ref then raises a label 'state."
      (returns NIL "Nothing")
      (sample "(f close)" "nothing"))
    (if (null? (field (lit fd))) ()
      (do (File close (field (lit fd))) (set-field! (lit fd) ())))
    ()))

(doc (provide x/codec/safetensors Safetensors)
  (example "(((Safetensors decode (Safetensors encode (Dict from-plist (list \"w\" (Tensor from '(1.5 2.5) 'f32))))) get \"w\") ->list)" "(1.5 2.5)")
  "Safetensors: named tensors in a file behind a JSON header, read one at a time from an open file or all at once from its bytes, and written back.")
