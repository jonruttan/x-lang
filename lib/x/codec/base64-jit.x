; base64-jit.x -- the compiled base64 decoder behind (Base64 jit!).
;
; Loaded lazily by x/codec/base64, never on its import: this module pulls
; the JIT toolchain, and the codec stays loadable and correct on a host
; with no JIT.  The pure-x decode-region remains the reference and the
; fallback; the engine is adopted only after it agrees with it, bytes and
; refusals alike.
;
; One compiled loop over the text's bytes: six bits a character
; accumulate and leave a byte each time eight are in hand, whitespace is
; skipped, = ends the payload.  The lane has no locals, so a character's
; value is found in one step and carried to the next through a parameter.
; The loop answers how many bytes it wrote, or a refusal: -1 a character
; outside the alphabet, -2 a character after =, -3 a length that is not a
; multiple of four, -4 more than two =.  A trusted root's PEM block is
; 2.6 KB: a third of a second in x, microseconds here.
(module x/codec/base64-jit)

(import x/tool/jit-group jit-group)
(import x/codec/bytes)

(import x/core/doors int/ ptr->int str->ptr str-make)

; --- the expression (generation time) ----------------------------------------

(def %bj-c (list (lit %mem-byte-ref-at) (lit src) (lit i)))
(def %bj-self
  (fn (_ i acc nbits n chars pads ph v)
    (list (lit self) (lit src) (lit dst) (lit len) i acc nbits n chars pads ph v)))
(def %bj-neg (fn (_ k) (list (lit -) 0 k)))
(def %bj-in (fn (_ lo hi) (list (lit if) (list (lit >=) %bj-c lo) (list (lit <=) %bj-c hi) 0)))

; The six bits of the character at i; -1 outside the alphabet.
(def %bj-value
  (list (lit if) (%bj-in 65 90) (list (lit -) %bj-c 65)
    (list (lit if) (%bj-in 97 122) (list (lit -) %bj-c 71)
      (list (lit if) (%bj-in 48 57) (list (lit +) %bj-c 4)
        (list (lit if) (list (lit =) %bj-c 43) 62
          (list (lit if) (list (lit =) %bj-c 47) 63 (%bj-neg 1)))))))

(def %bj-ws?
  (list (lit or) (list (lit =) %bj-c 32)
    (list (lit or) (list (lit =) %bj-c 9) (list (lit or) (list (lit =) %bj-c 10) (list (lit =) %bj-c 13)))))

; acc with v's six bits appended
(def %bj-acc6 (list (lit |) (list (lit <<) (lit acc) 6) (lit v)))

(def %bj-expr
  (list (lit fn) (lit (self src dst len i acc nbits n chars pads ph v))
    (list (lit if) (list (lit =) (lit ph) 0)
      ; phase 0: the character at i, or the end
      (list (lit if) (list (lit =) (lit i) (lit len))
        (list (lit if) (list (lit =) (list (lit &) (list (lit +) (lit chars) (lit pads)) 3) 0)
          (list (lit if) (list (lit >) (lit pads) 2) (%bj-neg 4) (lit n))
          (%bj-neg 3))
        (list (lit if) %bj-ws?
          (%bj-self (list (lit +) (lit i) 1) (lit acc) (lit nbits) (lit n) (lit chars) (lit pads) 0 0)
          (list (lit if) (list (lit =) %bj-c 61)
            (%bj-self (list (lit +) (lit i) 1) (lit acc) (lit nbits) (lit n) (lit chars) (list (lit +) (lit pads) 1) 0 0)
            (%bj-self (lit i) (lit acc) (lit nbits) (lit n) (lit chars) (lit pads) 1 %bj-value))))
      ; phase 1: v in hand
      (list (lit if) (list (lit <) (lit v) 0) (%bj-neg 1)
        (list (lit if) (list (lit >) (lit pads) 0) (%bj-neg 2)
          (list (lit if) (list (lit >=) (list (lit +) (lit nbits) 6) 8)
            (list (lit do)
              (list (lit %mem-byte-set-at!) (lit dst) (lit n)
                    (list (lit &) (list (lit >>) %bj-acc6 (list (lit -) (lit nbits) 2)) 255))
              (%bj-self (list (lit +) (lit i) 1)
                        (list (lit &) %bj-acc6 (list (lit -) (list (lit <<) 1 (list (lit -) (lit nbits) 2)) 1))
                        (list (lit -) (lit nbits) 2) (list (lit +) (lit n) 1) (list (lit +) (lit chars) 1) (lit pads) 0 0))
            (%bj-self (list (lit +) (lit i) 1) %bj-acc6 (list (lit +) (lit nbits) 6) (lit n) (list (lit +) (lit chars) 1) (lit pads) 0 0)))))))

; --- the decoder over the compiled loop ----------------------------------------

(def %bj-bad
  (fn (_ what r) (Err raise (lit value) (Str8 append "Base64 decode: " what) r)))

; (fn (_ r)): decode-region's shape over the compiled loop.
(def %bj-decoder
  (fn (_ loop)
    (fn (_ r)
      (def s (first r))
      (def start (first (rest r)))
      (def len (first (rest (rest r))))
      (def out (str-make (+ 1 (int/ (* 3 len) 4))))
      (def n (loop (+ (ptr->int (str->ptr s)) start) (ptr->int (str->ptr out)) len 0 0 0 0 0 0 0 0))
      (if (>= n 0) (list out 0 n)
        (%bj-bad (if (= n -1) "character outside the alphabet"
                   (if (= n -2) "= padding before the final group"
                     (if (= n -3) "length is not a multiple of 4" "misplaced = padding")))
                 r)))))

; The differential check: the compiled decoder against the pure one on
; whole groups, both paddings, the full alphabet, line breaks and spaces,
; and on each refusal, which must raise the same words.
(def %bj-check
  (fn (_ decode pure)
    (def %same
      (fn (_ text)
        (def a (decode (Bytes of text)))
        (def b (pure (Bytes of text)))
        (unless (Bytes same? a b)
          (Err raise (lit state) "base64-jit: the compiled decoder disagrees with the pure-x decoder" text))))
    (def %refuses
      (fn (_ text)
        (def a (guard (e (e msg)) (do (decode (Bytes of text)) "")))
        (def b (guard (e (e msg)) (do (pure (Bytes of text)) "")))
        (unless (str=? a b)
          (Err raise (lit state) "base64-jit: the compiled decoder refuses differently from the pure-x decoder" text))))
    (%same "Zm9v")
    (%same "Zm9vYg==")
    (%same "Zm9vYmE=")
    (%same "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    (%same "Zm9v\nYmFy\r\n IGJh\tej==\n")
    (%same "")
    (%refuses "Zm9")
    (%refuses "Zm=9")
    (%refuses "Zm9!")
    (%refuses "Zm9v===")
    (%refuses "Zm9vYg===")))

; The compiled decoder, checked against pure, the pure decode-region.
(def base64-jit-make
  (fn (_ pure)
    (jit-group "base64-jit:1" (fn (_) (list %bj-expr))
      (fn (_ fns replayed?)
        (def decode (%bj-decoder (first fns)))
        (unless replayed? (%bj-check decode pure))
        decode))))

(prim-reg! (lit base64) (lit jit-make) base64-jit-make)

(doc (provide x/codec/base64-jit base64-jit-make)
  "The compiled base64 decoder (JIT, ARM64 and x86-64 backends) behind (Base64 jit!): one loop over the text's bytes, adopted only after it agrees with the pure-x decode-region on bytes and refusals.")
