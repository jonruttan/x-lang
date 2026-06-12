; string.x -- Boot string operations (bootstrap)
;
; Basic string functions needed by the module system.
; Uses match instead of if (if not yet available).

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))
(def %str-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))

(def not (fn (_ x) (match (x #f) (#t #t))))
(def list (fn (_ . args) args))

; str-ref / str-length / substring are the BYTE accessors (current "raw"
; protocol). They bind to the str-byte-* C primitives, NOT the ambient (s i)
; call -- so they stay byte-level even when a code-point handler is pushed on
; the string call, and every caller built on them (str=?, str->number, readers)
; stays byte-safe automatically. Use the bare (s i) call for the ambient
; protocol, or the Str8 / StrUTF8 classes for an explicit one.
(def str-ref %str-byte-ref)
(def str-length %str-byte-len)
(def substring (fn (_ s start end) (%str-byte-sub s start (- end start))))
(def newline (fn (_ ) (display "\n")))

; str=?: string equality, compared by BYTES (str-byte-*). Byte equality is the
; same answer as code-point equality, and staying byte keeps it O(n) and immune
; to any pushed string-call handler.
(def %str-eq-loop
  (fn (self a b i len)
    (match
      ((= i len) #t)
      ((= (char->integer (%str-byte-ref a i)) (char->integer (%str-byte-ref b i)))
        (self a b (+ i 1) len))
      (#t #f))))
(def str=?
  (fn (_ a b)
    (match
      ((= (%str-byte-len a) (%str-byte-len b))
        (%str-eq-loop a b 0 (%str-byte-len a)))
      (#t #f))))

; number->str: (number->str n [radix]) -> string
(def %n2s/ /)
(def %n2s% %)
(def number->str
  (fn (self n . rest)
    (def radix (match ((eq? rest ()) 10) (#t (first rest))))
    (def %d "0123456789abcdefghijklmnopqrstuvwxyz")
    (match
      ((= n 0) "0")
      ((< n 0) (%str-append "-" (self (- 0 n) radix)))
      (#t
        (let ((rem (%n2s% n radix)))
          (match
            ((< n radix) (list->str (list (%str-byte-ref %d rem))))
            (#t (%str-append
                  (self (%n2s/ n radix) radix)
                  (list->str (list (%str-byte-ref %d rem)))))))))))

; str->number: (str->number str [radix]) -> integer or ()
; str->number parses an ASCII numeric string; all indexing is byte-level
; (str-byte-*) since digits/signs are single bytes.
(def str->number
  (fn (_ s . rest)
    (def radix (match ((eq? rest ()) 10) (#t (first rest))))
    (def len (%str-byte-len s))
    (match
      ((= len 0) ())
      (#t
        (let ((%0 (char->integer (%str-byte-ref "0" 0))))
          (def %digit
            (fn (_ ch)
              (def c (char->integer ch))
              (match
                ((match ((not (< c %0)) (not (< (+ %0 9) c))) (#t #f))
                  (- c %0))
                ((match ((not (< c (char->integer (%str-byte-ref "a" 0))))
                         (not (< (+ (char->integer (%str-byte-ref "a" 0)) 25) c))) (#t #f))
                  (+ 10 (- c (char->integer (%str-byte-ref "a" 0)))))
                ((match ((not (< c (char->integer (%str-byte-ref "A" 0))))
                         (not (< (+ (char->integer (%str-byte-ref "A" 0)) 25) c))) (#t #f))
                  (+ 10 (- c (char->integer (%str-byte-ref "A" 0)))))
                (#t ()))))
          (def c0 (char->integer (%str-byte-ref s 0)))
          (def neg (= c0 (char->integer (%str-byte-ref "-" 0))))
          (def start
            (match
              (neg 1)
              ((= c0 (char->integer (%str-byte-ref "+" 0))) 1)
              (#t 0)))
          (match
            ((= start len) ())
            (#t
              (let* ((%parse
                      (fn (self i acc)
                        (match
                          ((= i len) acc)
                          (#t
                            (let ((d (%digit (%str-byte-ref s i))))
                              (match
                                ((eq? d ()) ())
                                ((< d radix) (self (+ i 1) (+ (* acc radix) d)))
                                (#t ())))))))
                     (result (%parse start 0)))
                (match
                  ((eq? result ()) ())
                  (neg (- 0 result))
                  (#t result))))))))))
