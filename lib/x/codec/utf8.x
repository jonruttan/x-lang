; codec/utf8.x -- UTF-8 byte <-> code-point codec (protocol-agnostic primitives)
;
; The single shared UTF-8 transform, used by both the boot string layer
; (str->list in x/type/string) and the protocol layer (the Utf8 class in
; x/protocol/str/utf8). Pure functions over the byte-level string primitives
; (str-ref / str-length operate on bytes) plus bitwise ops -- no object system,
; so it loads at boot, below everything that consumes it.
;
; Uses nested `if`, never `cond`: these functions are intended to also run
; inside tokenizer analyse/read callbacks (for #\<utf8> literals), where a
; library macro that allocates can trigger GC mid-parse and corrupt the C stack
; (see the tokenizer-callback constraints in project memory).

; Number of bytes in the UTF-8 sequence introduced by lead byte b (0-255).
(def utf8-seq-len
  (fn (_ b)
    (if (< b 192) 1        ; 0xxxxxxx  ASCII (or a stray continuation byte)
    (if (< b 224) 2        ; 110xxxxx
    (if (< b 240) 3        ; 1110xxxx
      4)))))               ; 11110xxx

; Decode the UTF-8 sequence at byte index i of s -> (code-point . next-index).
; The shifted lead/continuation parts occupy disjoint bit ranges, so | merges
; them losslessly.
(def utf8-decode
  (fn (_ s i)
    (def b0 (char->integer (str-ref s i)))
    (def n (utf8-seq-len b0))
    (def cont (fn (_ k) (& (char->integer (str-ref s (+ i k))) 63)))   ; low 6 bits
    (pair
      (if (= n 1) b0
      (if (= n 2) (| (<< (& b0 31) 6) (cont 1))
      (if (= n 3) (| (| (<< (& b0 15) 12) (<< (cont 1) 6)) (cont 2))
        (| (| (| (<< (& b0 7) 18) (<< (cont 1) 12)) (<< (cont 2) 6)) (cont 3)))))
      (+ i n))))

; --- Allocation-light accessors (no pair, no inner closure) ---
;
; utf8-decode conses a (cp . next) pair and builds a `cont` closure per call.
; That allocation is unsafe inside tokenizer reader callbacks (it can trigger GC
; mid-parse -- see project memory). These two split the same computation so a
; caller takes only the part it needs with NOTHING heap-allocated in the body:
; just str-ref reads and bitwise ops. Continuation reads are inlined (no helper).

; Byte width of the sequence at byte index i (1-4). No allocation.
(def utf8-width (fn (_ s i) (utf8-seq-len (char->integer (str-ref s i)))))

; Code point at byte index i. No allocation (continuation bytes inlined).
(def utf8-cp-at
  (fn (_ s i)
    (def b0 (char->integer (str-ref s i)))
    (if (< b0 128) b0
    (if (< b0 224)
      (| (<< (& b0 31) 6)
         (& (char->integer (str-ref s (+ i 1))) 63))
    (if (< b0 240)
      (| (| (<< (& b0 15) 12)
            (<< (& (char->integer (str-ref s (+ i 1))) 63) 6))
         (& (char->integer (str-ref s (+ i 2))) 63))
      (| (| (| (<< (& b0 7) 18)
               (<< (& (char->integer (str-ref s (+ i 1))) 63) 12))
            (<< (& (char->integer (str-ref s (+ i 2))) 63) 6))
         (& (char->integer (str-ref s (+ i 3))) 63)))))))

; Encode code point cp as a list of its 1-4 UTF-8 byte values (0-255). Out-of-
; range code points emit U+FFFD (the replacement character), matching the C
; encoder this replaces. Returns bare integers, not CHARACTERs: callers map
; integer->char to byte-pack via list->str, or use the bytes directly.
(def utf8-encode
  (fn (self cp)
    (if (if (< cp 0) #t (> cp 1114111))   ; out of range -> U+FFFD
      (self 65533)
    (if (< cp 128)
      (list cp)                            ; 0xxxxxxx
    (if (< cp 2048)
      (list (| 192 (>> cp 6))              ; 110xxxxx
            (| 128 (& cp 63)))
    (if (< cp 65536)
      (list (| 224 (>> cp 12))             ; 1110xxxx
            (| 128 (& (>> cp 6) 63))
            (| 128 (& cp 63)))
      (list (| 240 (>> cp 18))             ; 11110xxx
            (| 128 (& (>> cp 12) 63))
            (| 128 (& (>> cp 6) 63))
            (| 128 (& cp 63)))))))))

(doc (provide x/codec/utf8
  utf8-seq-len utf8-decode utf8-encode utf8-width utf8-cp-at)
  "UTF-8 codec: convert between bytes and Unicode code points (protocol-agnostic primitives).")
