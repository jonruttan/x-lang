; codec/base64.x -- Base64: RFC 4648 standard-alphabet encode/decode.
;
; Two doors each way (#362):
;   encode / decode             string <-> string, the common case
;   encode-bytes / decode-bytes byte list <-> string, the binary-lossless door
; str values are C strings (bytes past NUL unobservable -- the x-lib ruling),
; so a payload that may contain a 0 byte belongs on the -bytes doors; the
; byte list is the library's established binary carrier ((Sys fd-read),
; (StrUtf8 encode)).
;
; Decode is strict per #61 (no silent repair): a character outside the
; alphabet raises a label 'value Err, as do misplaced padding and a short
; final group. The one tolerance is whitespace (space/tab/CR/LF), skipped
; before decoding so PEM-style wrapped payloads decode directly.
;
; No lookup tables: both directions map 6-bit value <-> alphabet character
; arithmetically. Helpers live as method-local closures, not %-globals
; (this file's percent-globals budget is 0) and not %-methods (a per-
; character class dispatch is the measured 8-30x overhead, #332).

(module x/codec/base64)
(import x/type/class)
(import x/core/list)
(import x/codec/bytes)
; The compiled decoder is on Compiled's list.
(import x/tool/compiled)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(import x/core/doors char->int int& int- int/ int<< int>> int| ptr-set! str->ptr str-byte-len str-byte-ref str-make)
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))


; The region decoder's prims: a byte in, a byte out, no list between.

; An alphabet byte's six bits; -1 for whitespace, -2 for =, -3 for anything else.
(def %b64-value
  (fn (_ c)
    (match
      ((if (>= c 65) (<= c 90) #f) (- c 65))
      ((if (>= c 97) (<= c 122) #f) (- c 71))
      ((if (>= c 48) (<= c 57) #f) (+ c 4))
      ((= c 43) 62)
      ((= c 47) 63)
      ((= c 61) -2)
      ((or (= c 32) (or (= c 9) (or (= c 10) (= c 13)))) -1)
      (#t -3))))

; Decode a region of text into a fresh buffer: the bytes as (BUF 0 LEN).
; Six bits a character accumulate and leave a byte each time eight are in
; hand; whitespace is skipped; = ends the payload, after which only = and
; whitespace may follow, and the characters must make whole groups of four.
(def %b64-decode-region
  (fn (_ r)
    (def s (first r))
    (def start (first (rest r)))
    (def end (+ start (first (rest (rest r)))))
    (def out (str-make (+ 1 (int/ (* 3 (- end start)) 4))))
    (def p (str->ptr out))
    (def %bad (fn (_ what) (Err raise (lit value) (Str8 append "Base64 decode: " what) r)))
    ((fn (self i acc nbits n chars pads)
       (if (= i end)
         (do (unless (= (int& (+ chars pads) 3) 0) (%bad "length is not a multiple of 4"))
             (when (> pads 2) (%bad "misplaced = padding"))
             (list out 0 n))
         (do (def v (%b64-value (char->int (str-byte-ref s i))))
             (match
               ((= v -1) (self (+ i 1) acc nbits n chars pads))
               ((= v -2) (self (+ i 1) acc nbits n chars (+ pads 1)))
               ((= v -3) (%bad "character outside the alphabet"))
               ((> pads 0) (%bad "= padding before the final group"))
               (#t
                 (do (def acc2 (int| (int<< acc 6) v))
                     (def nbits2 (+ nbits 6))
                     (if (>= nbits2 8)
                       (do (ptr-set! p n (int& (int>> acc2 (- nbits2 8)) 255) 1)
                           (self (+ i 1) (int& acc2 (- (int<< 1 (- nbits2 8)) 1)) (- nbits2 8) (+ n 1) (+ chars 1) pads))
                       (self (+ i 1) acc2 nbits2 n (+ chars 1) pads))))))))
     start 0 0 0 0 0)))

; --- the compiled decoder, adopted only when it proves out ------------------
;
; An entry of Compiled's (lib/x/tool/compiled.x), made the first time
; (Base64 jit!) asks: x/codec/base64-jit is imported then, never on this
; module's import, and its decoder replaces the pure one above only
; after agreeing with it on bytes and refusals.  decode-region asks the
; entry which to call; a state image reloads with the entry interpreted.

(def %b64-entry ())
(def %b64-jit-try!
  (fn (_)
    (when (null? %b64-entry)
      (set! %b64-entry
        (Compiled make-on-demand (lit base64) %b64-decode-region
          (fn (_)
            (import x/codec/base64-jit)
            ((prim-ref (lit base64) (lit jit-make)) %b64-decode-region))
          (fn (_ v) ()))))
    ; the entry is sent to through a parameter: the linter reads a send to a
    ; global as a call with names for arguments
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %b64-entry)))

; The decoder to call: the compiled one while the entry holds it.
(def %b64-decode
  (fn (_)
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         (entry compiled)
         %b64-decode-region))
     %b64-entry)))

(def-class Base64 ()
  (doc "RFC 4648 base64 (standard alphabet, = padding). encode/decode carry strings; encode-bytes/decode-bytes carry byte lists -- the lossless door for payloads that may contain NUL."
    (example "(Base64 encode \"foobar\")" "\"Zm9vYmFy\"")
    (example "(Base64 decode \"Zm9vYmFy\")" "\"foobar\"")
    (see encode) (see decode-bytes))
  (static
    (method encode-bytes (self (param bytes LIST "Byte values (0-255) to encode"))
      (doc "Encode a byte list as a base64 string."
        (returns STRING "Base64 text, = padded")
        (example "(Base64 encode-bytes (list 102 111 111))" "\"Zm9v\""))
      ; 6-bit value -> alphabet byte, arithmetically: A-Z a-z 0-9 + /
      (def %e6 (fn (_ v)
        (match
          ((< v 26) (+ 65 v))
          ((< v 52) (+ 71 v))
          ((< v 62) (- v 4))
          ((= v 62) 43)
          (#t 47))))
      (let go ((l bytes) (acc ()))
        (match
          ((null? l) (bytes->str (%reverse acc)))
          ; one input byte left -> two chars + ==
          ((null? (rest l))
           (let ((b0 (first l)))
             (bytes->str (%reverse
               (pair 61 (pair 61
                 (pair (%e6 (int& (int<< b0 4) 63))
                   (pair (%e6 (int>> b0 2)) acc))))))))
          ; two left -> three chars + =
          ((null? (rest (rest l)))
           (let ((b0 (first l)) (b1 (first (rest l))))
             (bytes->str (%reverse
               (pair 61
                 (pair (%e6 (int& (int<< b1 2) 63))
                   (pair (%e6 (int& (int| (int<< b0 4) (int>> b1 4)) 63))
                     (pair (%e6 (int>> b0 2)) acc))))))))
          ; full 3-byte group -> four chars
          (#t
           (let ((b0 (first l)) (b1 (first (rest l))) (b2 (first (rest (rest l)))))
             (go (rest (rest (rest l)))
                 (pair (%e6 (int& b2 63))
                   (pair (%e6 (int& (int| (int<< b1 2) (int>> b2 6)) 63))
                     (pair (%e6 (int& (int| (int<< b0 4) (int>> b1 4)) 63))
                       (pair (%e6 (int>> b0 2)) acc))))))))))

    (method encode (self (param s STRING "Bytes to encode"))
      (doc "Encode a string's bytes as base64. A string's observable bytes end at the first NUL (the x-lib ruling) -- binary with NULs takes the encode-bytes door."
        (returns STRING "Base64 text, = padded")
        (example "(Base64 encode \"hi\")" "\"aGk=\""))
      (def n (str-byte-len s))
      (self encode-bytes
        (let go ((i (- n 1)) (acc ()))
          (if (< i 0) acc
            (go (- i 1) (pair (char->int (str-byte-ref s i)) acc))))))

    (method decode-bytes (self (param b64 STRING "Base64 text to decode"))
      (doc "Decode base64 text to a byte list -- the lossless door. Whitespace (space/tab/CR/LF) is skipped; any other character outside the alphabet, misplaced =, or a short final group raises a label 'value Err (#61: no silent repair)."
        (returns LIST "Byte values (0-255)")
        (example "(Base64 decode-bytes \"Zm9v\")" "(102 111 111)"))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Base64 decode: " what) b64)))
      ; alphabet byte -> 6-bit value; -1 outside the alphabet
      (def %d6 (fn (_ c)
        (match
          ((if (>= c 65) (<= c 90) #f) (- c 65))
          ((if (>= c 97) (<= c 122) #f) (- c 71))
          ((if (>= c 48) (<= c 57) #f) (+ c 4))
          ((= c 43) 62)
          ((= c 47) 63)
          (#t -1))))
      (def %ws? (fn (_ c) (or (= c 32) (or (= c 9) (or (= c 10) (= c 13))))))
      (def n (str-byte-len b64))
      ; strip whitespace up front so groups-of-4 sees only payload + padding
      (def clean
        (let go ((i (- n 1)) (acc ()))
          (if (< i 0) acc
            (let ((c (char->int (str-byte-ref b64 i))))
              (go (- i 1) (if (%ws? c) acc (pair c acc)))))))
      ; MATCH ARMS ARE SINGLE-FORM (adjacent children are not a sequence);
      ; every multi-step arm body rides a let, the file.x pattern.
      (let go ((l clean) (acc ()))
        (match
          ((null? l) (%reverse acc))
          ((or (null? (rest l))
               (or (null? (rest (rest l))) (null? (rest (rest (rest l))))))
           (%bad "length is not a multiple of 4"))
          (#t
           (let ((c0 (first l)) (c1 (first (rest l)))
                 (c2 (first (rest (rest l)))) (c3 (first (rest (rest (rest l)))))
                 (tail (rest (rest (rest (rest l))))))
             (let ((v0 (%d6 c0)) (v1 (%d6 c1)))
               (when (or (< v0 0) (< v1 0)) (%bad "character outside the alphabet"))
               (match
                 ; xx== -> one byte; must be the final group
                 ((if (= c2 61) (= c3 61) #f)
                  (let ()
                    (unless (null? tail) (%bad "= padding before the final group"))
                    (go tail (pair (int| (int<< v0 2) (int>> v1 4)) acc))))
                 ; xxx= -> two bytes; must be the final group
                 ((= c3 61)
                  (let ((v2 (%d6 c2)))
                    (when (< v2 0) (%bad "character outside the alphabet"))
                    (unless (null? tail) (%bad "= padding before the final group"))
                    (go tail
                        (pair (int| (int<< (int& v1 15) 4) (int>> v2 2))
                          (pair (int| (int<< v0 2) (int>> v1 4)) acc)))))
                 ((= c2 61) (%bad "misplaced = padding"))
                 ; full group -> three bytes
                 (#t
                  (let ((v2 (%d6 c2)) (v3 (%d6 c3)))
                    (when (or (< v2 0) (< v3 0)) (%bad "character outside the alphabet"))
                    (go tail
                        (pair (int| (int<< (int& v2 3) 6) v3)
                          (pair (int| (int<< (int& v1 15) 4) (int>> v2 2))
                            (pair (int| (int<< v0 2) (int>> v1 4)) acc)))))))))))))

    (method decode-region (self (param text ANY "Base64 text: a region (BUF START LEN), or a STRING up to its first NUL"))
      (doc "Decode to a fresh buffer, the bytes as a region (BUF 0 LEN): the lossless door for binary, with no list in between. Whitespace is skipped; any other character outside the alphabet, misplaced =, or a short final group raises a label 'value Err. Pure x, or the compiled decoder once (Base64 jit!) has adopted it."
        (returns LIST "(BUF 0 LEN)")
        (example "(Bytes hex (Base64 decode-region \"aGk=\"))" "\"6869\""))
      ((%b64-decode) (Bytes of text)))
    (method jit! (self)
      (doc "Build and adopt the compiled decoder (JIT; ARM64 and x86-64 backends) now, if it proves itself against the pure-x decode-region. Idempotent; answers whether the compiled decoder is active."
        (returns BOOL "#t when the compiled decoder is active"))
      (%b64-jit-try!))
    (method decode (self (param b64 STRING "Base64 text to decode"))
      (doc "Decode base64 text to a string. A decoded payload containing a 0 byte is only fully observable through decode-bytes (str values are C strings); same strictness as decode-bytes."
        (returns STRING "The decoded bytes as a string")
        (example "(Base64 decode \"aGk=\")" "\"hi\""))
      (bytes->str (self decode-bytes b64)))))

(doc (provide x/codec/base64 Base64)
  (note "Standard alphabet only (+ /); = padding required; whitespace skipped on decode. The -bytes doors carry NUL-bearing binary losslessly.")
  "RFC 4648 base64 encode/decode, homed on the Base64 class.")
