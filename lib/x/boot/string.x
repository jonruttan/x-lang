; string.x -- Boot string operations (bootstrap)
;
; Basic string functions needed by the module system.
; Uses match instead of if (if not yet available).

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))
(def %str-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %str-byte-sub (prim-ref (lit str) (lit byte-sub)))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))


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

; display/write live in boot/printer.x (loaded just before this file); the
; old variadic-display shim over the C prim is gone with the C printers.
; newline resolves `display` at call time, so it may live here unchanged.
(def newline (fn (_ ) (display "\n")))

; str=?: string equality by BYTES -- one (mem cmp) block-compare after the
; length check (was an interpreted per-byte loop, ~10 evals/byte on every
; string compare in the system).  Byte equality is the same answer as
; code-point equality, and staying byte keeps it immune to any pushed
; string-call handler.  GC-safe: the raw ptrs live only inside the one
; expression, and collection is explicit-only.
(def %mem-cmp  (prim-ref (lit mem) (lit cmp)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def str=?
  (fn (_ a b)
    (match
      ((= (%str-byte-len a) (%str-byte-len b))
        (eq? 0 (%mem-cmp (%str->ptr a) (%str->ptr b) (%str-byte-len a))))
      (#t #f))))

; number->str: (number->str n [radix]) -> string
(def %n2s/ /)
(def %n2s% %)
; Digits accumulate in the NEGATIVE domain: negating a positive n is always
; safe, while (- 0 n) on the most-negative fixnum wraps back to itself (the
; old positive-domain recursion never terminated on it).  C division
; truncates toward zero, so for n <= 0 the remainder is 0..-(radix-1) and
; negating THAT is safe.  Digits prepend least-significant-first into one
; byte list, packed with a single bytes->str -- not list->str: digits are
; ASCII BYTES, and the utf8-aware list->str (x/type/str-utf8) shadows the
; byte-packer post-boot -- this must stay the raw pack either way.
; C subtraction, fetched once: the digit loop runs per digit of every
; number the printer renders, and the tower's arithmetic wrappers cost
; ~92 objects per op vs ~5 for the raw instruction.  eq? (value-word
; compare) replaces = for the zero test -- same answer on ints, C-cheap.
(def %n2s-int- (prim-ref (lit int) (lit -)))
; The digit table, hoisted: re-binding it per call was pure preamble.
(def %n2s-digits "0123456789abcdefghijklmnopqrstuvwxyz")
(def %n2s-loop
  (fn (self n radix acc)
    (do
      (def %q (%n2s/ n radix))
      (def %acc (pair (%str-byte-ref %n2s-digits (%n2s-int- 0 (%n2s% n radix))) acc))
      (match
        ((eq? %q 0) %acc)
        (#t (self %q radix %acc))))))
(def %n2s
  (fn (_ n radix)
    (match
      ((< n 0) (%str-append "-" (bytes->str (%n2s-loop n radix ()))))
      (#t (bytes->str (%n2s-loop (%n2s-int- 0 n) radix ()))))))
; Fixed-arity front for the printer's unary base-10 calls (the common
; case): skips the variadic rest-spine heap copy and the radix match.
(def number->str
  (fn (_ n . rest)
    (match
      ((eq? rest ()) (%n2s n 10))
      (#t (%n2s n (first rest))))))

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
        (let ((%0 (%char->integer #\0)))
          (def %digit
            (fn (_ ch)
              (def c (%char->integer ch))
              (match
                ((match ((not (< c %0)) (not (< (+ %0 9) c))) (#t #f))
                  (- c %0))
                ((match ((not (< c (%char->integer #\a)))
                         (not (< (+ (%char->integer #\a) 25) c))) (#t #f))
                  (+ 10 (- c (%char->integer #\a))))
                ((match ((not (< c (%char->integer #\A)))
                         (not (< (+ (%char->integer #\A) 25) c))) (#t #f))
                  (+ 10 (- c (%char->integer #\A))))
                (#t ()))))
          (def c0 (%char->integer (%str-byte-ref s 0)))
          (def neg (= c0 (%char->integer #\-)))
          (def start
            (match
              (neg 1)
              ((= c0 (%char->integer #\+)) 1)
              (#t 0)))
          (match
            ((= start len) ())
            (#t
              (let ((%parse
                      (fn (self i acc)
                        (match
                          ((= i len) acc)
                          (#t
                            (let ((d (%digit (%str-byte-ref s i))))
                              (match
                                ((eq? d ()) ())
                                ((< d radix) (self (+ i 1) (+ (* acc radix) d)))
                                (#t ()))))))))
                (let ((result (%parse start 0)))
                  (match
                    ((eq? result ()) ())
                    (neg (- 0 result))
                    (#t result)))))))))))
