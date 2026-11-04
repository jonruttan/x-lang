; base64-encode-jit.x -- the compiled base64 encoder behind encode-region.
;
; Loaded lazily by x/codec/base64, never on its import, as base64-jit is:
; this module pulls the JIT toolchain, and the codec stays loadable and
; correct on a host with no JIT.  The pure-x encode-region remains the
; reference and the fallback; the engine is adopted only after it encodes
; the codec's check inputs byte for byte as the pure one does.
;
; One compiled loop over the bytes: three a step, four characters out, and
; a last group of one or two bytes padded out with =.  The loop answers how
; many characters it wrote.
(module x/codec/base64-encode-jit)

(import x/tool/jit-group jit-group)
(import x/core/doors int/ ptr->int str->ptr str-make)

; --- the expression (generation time) ----------------------------------------

; byte i+k of the input
(def %bk-b (fn (_ k) (list (lit %mem-byte-ref-at) (lit src) (list (lit +) (lit i) k))))

; a 6-bit value's alphabet byte
(def %bk-e6
  (fn (_ v)
    (list (lit if) (list (lit <) v 26) (list (lit +) v 65)
      (list (lit if) (list (lit <) v 52) (list (lit +) v 71)
        (list (lit if) (list (lit <) v 62) (list (lit -) v 4)
          (list (lit if) (list (lit =) v 62) 43 47))))))

; character C at n+k of the output
(def %bk-put (fn (_ k c) (list (lit %mem-byte-set-at!) (lit dst) (list (lit +) (lit n) k) c)))

; a group's four values, from its bytes
(def %bk-v0 (list (lit >>) (%bk-b 0) 2))
(def %bk-v1 (list (lit |) (list (lit <<) (list (lit &) (%bk-b 0) 3) 4) (list (lit >>) (%bk-b 1) 4)))
(def %bk-v2 (list (lit |) (list (lit <<) (list (lit &) (%bk-b 1) 15) 2) (list (lit >>) (%bk-b 2) 6)))
(def %bk-v3 (list (lit &) (%bk-b 2) 63))
; the last group's, one or two bytes short
(def %bk-v1-last (list (lit <<) (list (lit &) (%bk-b 0) 3) 4))
(def %bk-v2-last (list (lit <<) (list (lit &) (%bk-b 1) 15) 2))

(def %bk-left (list (lit -) (lit len) (lit i)))

(def %bk-expr
  (list (lit fn) (lit (self src dst len i n))
    (list (lit if) (list (lit >) %bk-left 2)
      (list (lit do)
        (%bk-put 0 (%bk-e6 %bk-v0))
        (%bk-put 1 (%bk-e6 %bk-v1))
        (%bk-put 2 (%bk-e6 %bk-v2))
        (%bk-put 3 (%bk-e6 %bk-v3))
        (list (lit self) (lit src) (lit dst) (lit len) (list (lit +) (lit i) 3) (list (lit +) (lit n) 4)))
      (list (lit if) (list (lit =) %bk-left 2)
        (list (lit do)
          (%bk-put 0 (%bk-e6 %bk-v0))
          (%bk-put 1 (%bk-e6 %bk-v1))
          (%bk-put 2 (%bk-e6 %bk-v2-last))
          (%bk-put 3 61)
          (list (lit +) (lit n) 4))
        (list (lit if) (list (lit =) %bk-left 1)
          (list (lit do)
            (%bk-put 0 (%bk-e6 %bk-v0))
            (%bk-put 1 (%bk-e6 %bk-v1-last))
            (%bk-put 2 61)
            (%bk-put 3 61)
            (list (lit +) (lit n) 4))
          (lit n))))))

; --- the encoder over the compiled loop ----------------------------------------

; (fn (_ r)): encode-region's shape over the compiled loop.
(def %bk-encoder
  (fn (_ loop)
    (fn (_ r)
      (def len (first (rest (rest r))))
      (def m (* 4 (int/ (+ len 2) 3)))
      (def out (str-make (+ m 1)))
      (loop (+ (ptr->int (str->ptr (first r))) (first (rest r)))
            (ptr->int (str->ptr out)) len 0 0)
      (list out 0 m))))

; The compiled encoder, checked with agrees?, the codec's differential check.
(def base64-encode-jit-make
  (fn (_ agrees?)
    (jit-group "base64-encode-jit:1" (fn (_) (list %bk-expr))
      (fn (_ fns replayed?)
        (def encode (%bk-encoder (first fns)))
        (unless (if replayed? #t (agrees? encode))
          (Err raise (lit state) "base64-encode-jit: the compiled encoder disagrees with the pure-x encoder" ()))
        encode))))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit base64) (lit encode-jit-make) base64-encode-jit-make)

(doc (provide x/codec/base64-encode-jit base64-encode-jit-make)
  "The compiled base64 encoder (JIT, ARM64 and x86-64 backends) behind (Base64 encode-region): one loop over the bytes, adopted only after it encodes the check inputs byte for byte as the pure-x encoder does.")
