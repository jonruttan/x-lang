; codec/hex.x -- Hex: bytes <-> hexadecimal text.
;
; Two doors each way, the Base64 shape (#362):
;   encode / decode             string <-> string, the common case
;   encode-bytes / decode-bytes byte list <-> string, the binary-lossless door
; str values are C strings (bytes past NUL unobservable -- the x-lib ruling),
; so NUL-bearing payloads belong on the -bytes doors.
;
; Emission is lowercase (the binascii convention); decode accepts both
; cases. Decode is strict per #61: an odd-length input or a character
; outside [0-9a-fA-F] raises a kind-'value Err -- no whitespace tolerance
; (hex payloads are not line-wrapped the way PEM base64 is).
;
; Digest formatting is a different job: (Hash ->hex) renders one 64-bit
; INT as 16 hex chars; this codec transcodes byte sequences.
;
; Helpers live as method-local closures, not %-globals (budget 0) and not
; %-methods (per-character class dispatch is the measured overhead, #332).

(import x/type/class)
(import x/core/list)

(def-class Hex ()
  (doc "Hexadecimal transcoding: encode/decode carry strings; encode-bytes/decode-bytes carry byte lists -- the lossless door for payloads that may contain NUL. Lowercase out; either case in."
    (example "(Hex encode \"hi\")" "\"6869\"")
    (example "(Hex decode \"6869\")" "\"hi\"")
    (see encode) (see decode-bytes))
  (static
    (method encode-bytes (self (param bytes LIST "Byte values (0-255) to encode"))
      (doc "Encode a byte list as lowercase hex, two characters per byte."
        (returns STRING "Hex text")
        (example "(Hex encode-bytes (list 255 0 16))" "\"ff0010\""))
      ; nibble -> char code: 0-9 -> '0'-'9', 10-15 -> 'a'-'f'
      (def %n (fn (_ v) (if (< v 10) (+ 48 v) (+ 87 v))))
      (let go ((l bytes) (acc ()))
        (if (null? l) (bytes->str (%reverse acc))
          (let ((b (first l)))
            (go (rest l)
                (pair (%n (& b 15)) (pair (%n (>> b 4)) acc)))))))

    (method encode (self (param s STRING "Bytes to encode"))
      (doc "Encode a string's bytes as lowercase hex. A string's observable bytes end at the first NUL (the x-lib ruling) -- binary with NULs takes the encode-bytes door."
        (returns STRING "Hex text, two characters per input byte")
        (example "(Hex encode \"foobar\")" "\"666f6f626172\""))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def n (%blen s))
      (self encode-bytes
        (let go ((i (- n 1)) (acc ()))
          (if (< i 0) acc
            (go (- i 1) (pair (%c->i (%bref s i)) acc))))))

    (method decode-bytes (self (param hex STRING "Hex text to decode"))
      (doc "Decode hex text to a byte list -- the lossless door. Either case decodes; odd length or a character outside [0-9a-fA-F] raises a kind-'value Err (#61: no silent repair)."
        (returns LIST "Byte values (0-255)")
        (example "(Hex decode-bytes \"ff0010\")" "(255 0 16)"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Hex decode: " what) hex)))
      ; char code -> nibble value; raises on anything else
      (def %v (fn (_ c)
        (match
          ((if (>= c 48) (<= c 57) #f) (- c 48))
          ((if (>= c 97) (<= c 102) #f) (- c 87))
          ((if (>= c 65) (<= c 70) #f) (- c 55))
          (#t (%bad "character outside [0-9a-fA-F]")))))
      (def n (%blen hex))
      (when (= (% n 2) 1) (%bad "odd length"))
      (let go ((i (- n 2)) (acc ()))
        (if (< i 0) acc
          (go (- i 2)
              (pair (| (<< (%v (%c->i (%bref hex i))) 4)
                       (%v (%c->i (%bref hex (+ i 1)))))
                acc)))))

    (method decode (self (param hex STRING "Hex text to decode"))
      (doc "Decode hex text to a string. A decoded payload containing a 0 byte is only fully observable through decode-bytes (str values are C strings); same strictness as decode-bytes."
        (returns STRING "The decoded bytes as a string")
        (example "(Hex decode \"666f6f\")" "\"foo\""))
      (bytes->str (self decode-bytes hex)))))

(doc (provide x/codec/hex Hex)
  (note "Lowercase out, either case in, strict decode. The -bytes doors carry NUL-bearing binary losslessly; (Hash ->hex) stays the INT-digest formatter.")
  "Hexadecimal bytes<->text transcoding, homed on the Hex class.")
