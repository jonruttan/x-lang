; codec/pdf.x -- Pdf: a PDF file's objects, streams and pages.
;
; A PDF is numbered objects, a cross-reference that says where each one is,
; and a trailer that names the first of them.  (Pdf open) reads the
; cross-reference -- tables and cross-reference streams, each section's
; /Prev followed to the one before it -- and after that an object is read
; when it is asked for, from its offset or out of the object stream that
; holds it, and kept.
;
; An object is read as:
;
;   an integer                an integer
;   a real                    (real TEXT), the number as it is written
;   true, false, null         #t, #f, nil
;   a name                    (name TEXT), its #XX escapes decoded
;   a string                  (string BUF LENGTH), its escapes decoded; the
;                             bytes may hold NULs, so LENGTH says how many
;   an array                  (array OBJECT...)
;   a dictionary              (dict (KEY . OBJECT)...), KEY the name's text
;   an indirect reference     (ref NUMBER GENERATION)
;   a stream                  (stream ENTRIES START LENGTH): its dictionary's
;                             entries, and where its bytes are in the file
;   any other word            (op TEXT): a content stream's operator
;
; (Pdf data) answers a stream's bytes with its filters undone: FlateDecode
; with the PNG predictors, ASCIIHexDecode and ASCII85Decode.  Not yet here:
; LZWDecode, the TIFF predictor, the image filters, encrypted files (open
; refuses one), and the repair of a file whose cross-reference is damaged.
;
; The syntax is read by a Lexer (x/reader/lexer) over a span of the file, so
; the bytes of a string or a comment cost what compiled states cost; a
; string's escapes are decoded from the token.  A malformed file raises a
; label 'value naming what was wrong.

(module x/codec/pdf)
(import x/type/class)
(import x/core/list)
(import x/type/vector)
(import x/reader/lexer)
(import x/codec/bytes)
(import x/codec/inflate)

(import x/core/doors char->int int& int* int+ int- int->ptr int/ int< int<< int= int>> int| mem-copy obj-make obj-ref obj-set! ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-byte-ref str-byte-sub str-make type-of)

(def %pdf-fail (fn (_ what) (Err raise (lit value) (Str8 append "Pdf: " what) ())))
; Raised by a read that ran out of tokens, and caught where more can be read.
(def %pdf-short (fn (_) (Err raise (lit value) "Pdf: an object ends early" (list (pair (lit short) #t)))))
(def %pdf-short?
  (fn (_ e)
    (match ((Err err? e)
             (match ((eq? (Err label e) (lit value))
                      ((fn (self d)
                         (match ((null? d) #f) ((eq? (first (first d)) (lit short)) #t) (#t (self (rest d)))))
                       (e data)))
                    (#t #f)))
           (#t #f))))

; --- the open file ----------------------------------------------------------
; A vector: the bytes and how many, the cross-reference's subsections newest
; first, the trailer's entries, the objects read so far by number, the object
; streams read so far, and the function that answers an object by number.
(def %pdf-vector (type-of (Vector make 0 ())))
(def %pdf-node
  (fn (_ n)
    (def v (obj-make %pdf-vector (int+ n 1)))
    (obj-set! v 0 n)
    ((fn (go k) (match ((int< 0 k) (do (obj-set! v k ()) (go (int+ k -1)))) (#t ()))) n)
    v))
(def %pdf-get (fn (_ v k) (obj-ref v (int+ k 1))))
(def %pdf-put! (fn (_ v k x) (obj-set! v (int+ k 1) x)))
(def %F-BUF 0)
(def %F-LEN 1)
(def %F-SECTIONS 2)
(def %F-TRAILER 3)
(def %F-CACHE 4)
(def %F-STREAMS 5)
(def %F-OBJECT 6)

; --- bytes ------------------------------------------------------------------
(def %pdf-u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %pdf-ptr (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))
(def %pdf-min (fn (_ a b) (match ((int< a b) a) (#t b))))
(def %pdf-white?
  (fn (_ c)
    (match ((int= c 32) #t) ((int= c 10) #t) ((int= c 13) #t) ((int= c 9) #t) ((int= c 0) #t)
           ((int= c 12) #t) (#t #f))))
(def %pdf-digit? (fn (_ c) (match ((int< c 48) #f) ((int< 57 c) #f) (#t #t))))
; A hexadecimal digit's value, or -1.
(def %pdf-hexval
  (fn (_ c)
    (match ((int< c 48) -1) ((int< c 58) (int- c 48)) ((int< c 65) -1) ((int< c 71) (int- c 55))
           ((int< c 97) -1) ((int< c 103) (int- c 87)) (#t -1))))
; I past the white space of P from I, before END.
(def %pdf-skip-white
  (fn (self p i end)
    (match ((int< i end) (match ((%pdf-white? (%pdf-u8 p i)) (self p (int+ i 1) end)) (#t i)))
           (#t i))))
; The unsigned decimal of P at I, before END: (VALUE . NEXT), or nil with no
; digit there.
(def %pdf-uint
  (fn (_ p i end)
    ((fn (self k n)
       (match ((match ((int< k end) (%pdf-digit? (%pdf-u8 p k))) (#t #f))
                (self (int+ k 1) (int+ (int* n 10) (int- (%pdf-u8 p k) 48))))
              ((int= k i) ())
              (#t (pair n k))))
     i 0)))
; Where NEEDLE first is in BUF from FROM, before END, or nil.
(def %pdf-find
  (fn (_ buf from end needle)
    (match ((int< from end)
             ((fn (_ at) (match ((null? at) ()) (#t (int+ from at))))
              (Bytes find (list buf from (int- end from)) needle)))
           (#t ()))))
; Where NEEDLE last is in BUF from FROM, before END, or nil.
(def %pdf-find-last
  (fn (_ buf from end needle)
    ((fn (self from last)
       ((fn (_ at) (match ((null? at) last) (#t (self (int+ at 1) at))))
        (%pdf-find buf from end needle)))
     from ())))
; Whether the bytes of the string WORD are in BUF at I, before END.
(def %pdf-at?
  (fn (_ buf i end word)
    ((fn (_ n)
       (match ((int< end (int+ i n)) #f)
              (#t (Bytes same? (list buf i n) (list word 0 n)))))
     (str-byte-len word))))
; A fresh buffer holding N bytes of the pointer P from START, a line end
; after them: what a Lexer reads to its last token.
(def %pdf-ended
  (fn (_ p start n)
    (def out (str-make (int+ n 2)))
    (def o (str->ptr out))
    (when (int< 0 n) (mem-copy o (%pdf-ptr p start) n))
    (ptr-set! o n 10 1)
    (ptr-set! o (int+ n 1) 0 1)
    out))

; --- tokens -----------------------------------------------------------------
; The regular characters: every byte but white space and the delimiters
; ( ) < > [ ] { } / and %.
(def %pdf-regular
  (list (pair 1 8) 11 (pair 14 31) (pair 33 36) 38 39 (pair 42 46) (pair 48 59) 61 (pair 63 90) 92
        (pair 94 122) 124 (pair 126 127) (pair 128 255) (pair -128 -1)))
(def %pdf-hex-class (list (pair 48 57) (pair 65 70) (pair 97 102) 0 9 10 12 13 32))
; The lexer, made on the first read and kept.
(def %pdf-lexer-cell (pair () ()))
(def %pdf-lexer
  (fn (_)
    (when (null? (first %pdf-lexer-cell))
      (%set-first! %pdf-lexer-cell
        (Lexer make
          (list (Lexer skip (list 0 9 10 12 13 32))
                (Lexer until () "%" "\n")
                (Lexer table (lit punct) (list "<<" ">>" "[" "]" "{" "}"))
                (Lexer pattern (lit hex) (list (list "<" 1 1) (list %pdf-hex-class 0 ()) (list ">" 1 1)))
                (Lexer nested (lit string) "(" (lit p) (list (list (lit p) 41 92 (list (pair "(" (lit p))))))
                (Lexer run (lit name) (list 47) %pdf-regular)
                (Lexer run (lit word) %pdf-regular %pdf-regular)
                (Lexer any (lit bad))))))
    (first %pdf-lexer-cell)))
; The tokens of LEN bytes of BUF from START, in a cell a read takes them from.
(def %pdf-lex (fn (_ buf start len) (pair ((%pdf-lexer) read-span buf start len) ())))

; The number a word spells: an integer, (real TEXT) for one written with a
; point, or nil for a word that is no number.
(def %pdf-number
  (fn (_ t)
    (def n (str-byte-len t))
    (def at (fn (_ i) (char->int (str-byte-ref t i))))
    (def sign (match ((int= n 0) 0) ((int= (at 0) 45) -1) ((int= (at 0) 43) 1) (#t 0)))
    ((fn (self i v points digits)
       (match ((int= i n)
                (match ((int= digits 0) ())
                       ((int= points 0) (match ((int= sign -1) (int- 0 v)) (#t v)))
                       (#t (list (lit real) t))))
              ((%pdf-digit? (at i)) (self (int+ i 1) (int+ (int* v 10) (int- (at i) 48)) points (int+ digits 1)))
              ((int= (at i) 46) (match ((int= points 0) (self (int+ i 1) v 1 digits)) (#t ())))
              (#t ())))
     (match ((int= sign 0) 0) (#t 1)) 0 0 0)))
; A name token's text without its solidus, each #XX the byte it names.
(def %pdf-name
  (fn (_ t)
    (def n (str-byte-len t))
    (match ((null? (Str8 index-of "#" t)) (str-byte-sub t 1 (int- n 1)))
           (#t (do
             (def p (str->ptr t))
             (def out (str-make n))
             (def o (str->ptr out))
             ((fn (self i k)
                (match ((int< i n)
                         ((fn (_ c hi lo)
                            (match ((match ((int= c 35) (match ((int< hi 0) #f) ((int< lo 0) #f) (#t #t))) (#t #f))
                                     (do (ptr-set! o k (int| (int<< hi 4) lo) 1) (self (int+ i 3) (int+ k 1))))
                                   (#t (do (ptr-set! o k c 1) (self (int+ i 1) (int+ k 1))))))
                          (%pdf-u8 p i) (%pdf-hexval (%pdf-u8 p (int+ i 1)))
                          (match ((int< (int+ i 2) n) (%pdf-hexval (%pdf-u8 p (int+ i 2)))) (#t -1))))
                       (#t (do (ptr-set! o k 0 1) out))))
              1 0))))))
; The index of the parenthesis that closes the literal string of P, from I
; inside it.
(def %pdf-string-end
  (fn (self p i depth)
    ((fn (_ c)
       (match ((int= c 92) (self p (int+ i 2) depth))
              ((int= c 40) (self p (int+ i 1) (int+ depth 1)))
              ((int= c 41) (match ((int= depth 0) i) (#t (self p (int+ i 1) (int- depth 1)))))
              (#t (self p (int+ i 1) depth))))
     (%pdf-u8 p i))))
(def %pdf-octal? (fn (_ c) (match ((int< c 48) #f) ((int< 55 c) #f) (#t #t))))
; The escape of P at I, the byte after its reverse solidus: (BYTE . NEXT),
; BYTE nil for a line end, which an escape removes.
(def %pdf-escape
  (fn (_ p i)
    ((fn (_ c)
       (match ((int= c 110) (pair 10 (int+ i 1)))
              ((int= c 114) (pair 13 (int+ i 1)))
              ((int= c 116) (pair 9 (int+ i 1)))
              ((int= c 98) (pair 8 (int+ i 1)))
              ((int= c 102) (pair 12 (int+ i 1)))
              ((int= c 10) (pair () (int+ i 1)))
              ((int= c 13) (pair () (match ((int= (%pdf-u8 p (int+ i 1)) 10) (int+ i 2)) (#t (int+ i 1)))))
              ((%pdf-octal? c)
                ((fn (self k v left)
                   (match ((match ((int< 0 left) (%pdf-octal? (%pdf-u8 p k))) (#t #f))
                            (self (int+ k 1) (int+ (int* v 8) (int- (%pdf-u8 p k) 48)) (int- left 1)))
                          (#t (pair (int& v 255) k))))
                 i 0 3))
              (#t (pair c (int+ i 1)))))
     (%pdf-u8 p i))))
; A literal string token as (string BUF LENGTH): its parentheses off, its
; escapes decoded, a line end of any kind one line feed.
(def %pdf-string
  (fn (_ t)
    (def p (str->ptr t))
    (def end (%pdf-string-end p 1 0))
    (def out (str-make (int+ end 1)))
    (def o (str->ptr out))
    (def n
      ((fn (self i k)
         (match ((int< i end)
                  ((fn (_ c)
                     (match ((int= c 92)
                              ((fn (_ e)
                                 (match ((null? (first e)) (self (rest e) k))
                                        (#t (do (ptr-set! o k (first e) 1) (self (rest e) (int+ k 1))))))
                               (%pdf-escape p (int+ i 1))))
                            ((int= c 13)
                              (do (ptr-set! o k 10 1)
                                  (self (match ((int= (%pdf-u8 p (int+ i 1)) 10) (int+ i 2)) (#t (int+ i 1))) (int+ k 1))))
                            (#t (do (ptr-set! o k c 1) (self (int+ i 1) (int+ k 1))))))
                   (%pdf-u8 p i)))
                (#t k)))
       1 0))
    (ptr-set! o n 0 1)
    (list (lit string) out n)))
; A hexadecimal string token as (string BUF LENGTH): two digits a byte, white
; space passed over, a last digit alone the high half of its byte.
(def %pdf-hex
  (fn (_ t)
    (def p (str->ptr t))
    ; A NUL is white space here, so the token's end is its >, not its length.
    (def end ((fn (self i) (match ((int= (%pdf-u8 p i) 62) i) (#t (self (int+ i 1))))) 1))
    (def out (str-make (int+ (int/ end 2) 1)))
    (def o (str->ptr out))
    (def n
      ((fn (self i k hi)
         (match ((int< i end)
                  ((fn (_ v)
                     (match ((int< v 0) (self (int+ i 1) k hi))
                            ((int< hi 0) (self (int+ i 1) k v))
                            (#t (do (ptr-set! o k (int| (int<< hi 4) v) 1) (self (int+ i 1) (int+ k 1) -1)))))
                   (%pdf-hexval (%pdf-u8 p i))))
                ((int< hi 0) k)
                (#t (do (ptr-set! o k (int<< hi 4) 1) (int+ k 1)))))
       1 0 -1))
    (ptr-set! o n 0 1)
    (list (lit string) out n)))

; --- objects ----------------------------------------------------------------
(def %pdf-tagged? (fn (_ x tag) (match ((pair? x) (eq? (first x) tag)) (#t #f))))
(def %pdf-is? (fn (_ t tag text) (match ((eq? (first t) tag) (str=? (first (rest t)) text)) (#t #f))))
; The next token of the cell TS, taken off it; short when there is none.
(def %pdf-next!
  (fn (_ ts)
    (match ((null? (first ts)) (%pdf-short))
           (#t ((fn (_ t) (%set-first! ts (rest (first ts))) t) (first (first ts)))))))
; The integer N, or the reference it starts when an integer and R follow it.
(def %pdf-ref-after
  (fn (_ ts n)
    ((fn (_ l)
       (match ((null? l) n)
              ((null? (rest l)) n)
              ((%pdf-is? (first (rest l)) (lit word) "R")
                ((fn (_ g)
                   (match ((number? g) (do (%set-first! ts (rest (rest l))) (list (lit ref) n g)))
                          (#t n)))
                 (match ((eq? (first (first l)) (lit word)) (%pdf-number (first (rest (first l))))) (#t ()))))
              (#t n)))
     (first ts))))
; The objects of TS up to the token that closes an array, in order.
(def %pdf-array
  (fn (self value ts acc)
    ((fn (_ l)
       (match ((null? l) (%pdf-short))
              ((%pdf-is? (first l) (lit punct) "]") (do (%set-first! ts (rest l)) (List reverse acc)))
              (#t (self value ts (pair (value ts) acc)))))
     (first ts))))
; The entries of TS up to the token that closes a dictionary, in order; an
; entry whose key is no name is dropped.
(def %pdf-entries
  (fn (self value ts acc)
    ((fn (_ l)
       (match ((null? l) (%pdf-short))
              ((%pdf-is? (first l) (lit punct) ">>") (do (%set-first! ts (rest l)) (List reverse acc)))
              (#t ((fn (_ k)
                     ((fn (_ v)
                        (self value ts (match ((%pdf-tagged? k (lit name)) (pair (pair (first (rest k)) v) acc)) (#t acc))))
                      (value ts)))
                   (value ts)))))
     (first ts))))
; The next object of TS.
(def %pdf-value
  (fn (self ts)
    ((fn (_ t)
       ((fn (_ tag text)
          (match
            ((eq? tag (lit word))
              ((fn (_ n)
                 (match ((null? n)
                          (match ((str=? text "true") #t) ((str=? text "false") #f) ((str=? text "null") ())
                                 (#t (list (lit op) text))))
                        ((number? n) (%pdf-ref-after ts n))
                        (#t n)))
               (%pdf-number text)))
            ((eq? tag (lit name)) (list (lit name) (%pdf-name text)))
            ((eq? tag (lit string)) (%pdf-string text))
            ((eq? tag (lit hex)) (%pdf-hex text))
            ((eq? tag (lit punct))
              (match ((str=? text "<<") (pair (lit dict) (%pdf-entries self ts ())))
                     ((str=? text "[") (pair (lit array) (%pdf-array self ts ())))
                     (#t (list (lit op) text))))
            (#t (list (lit op) text))))
        (first t) (first (rest t))))
     (%pdf-next! ts))))
; Every object of TS, in order.
(def %pdf-values
  (fn (self ts acc)
    (match ((null? (first ts)) (List reverse acc))
           (#t (self ts (pair (%pdf-value ts) acc))))))

; The value of KEY among the entries D, or nil.
(def %pdf-entry
  (fn (self d key)
    (match ((null? d) ())
           ((str=? (first (first d)) key) (rest (first d)))
           (#t (self (rest d) key)))))
; The entries of X, a dictionary or a stream; nil for anything else.
(def %pdf-entries-of
  (fn (_ x)
    (match ((%pdf-tagged? x (lit dict)) (rest x))
           ((%pdf-tagged? x (lit stream)) (first (rest x)))
           (#t ()))))
; X, or the object the reference X names.
(def %pdf-resolve
  (fn (_ f x)
    (match ((%pdf-tagged? x (lit ref)) ((%pdf-get f %F-OBJECT) f (first (rest x))))
           (#t x))))
; The value of KEY in X, a dictionary, a stream or a reference to one, itself
; resolved; nil when X has none.
(def %pdf-lookup (fn (_ f x key) (%pdf-resolve f (%pdf-entry (%pdf-entries-of (%pdf-resolve f x)) key))))

; --- an object at an offset -------------------------------------------------
; The length of the stream whose bytes start at START: what its entries D
; say when endstream follows that many bytes, else the bytes up to the first
; endstream, the line end before it not counted.
(def %pdf-stream-length
  (fn (_ f d start)
    (def buf (%pdf-get f %F-BUF))
    (def len (%pdf-get f %F-LEN))
    (def p (str->ptr buf))
    (def said (%pdf-resolve f (%pdf-entry d "Length")))
    (match ((match ((number? said)
                     (match ((int< said 0) #f)
                            ((int< len (int+ start said)) #f)
                            (#t (%pdf-at? buf (%pdf-skip-white p (int+ start said) len) len "endstream"))))
                   (#t #f))
             said)
           (#t ((fn (_ at)
                  (match ((null? at) (%pdf-fail "a stream has no endstream"))
                         (#t ((fn (_ e)
                                (int- (match ((match ((int< start e) (int= (%pdf-u8 p (int- e 1)) 13)) (#t #f)) (int- e 1)) (#t e))
                                      start))
                              (match ((match ((int< start at) (int= (%pdf-u8 p (int- at 1)) 10)) (#t #f)) (int- at 1)) (#t at))))))
                (%pdf-find buf start len "endstream"))))))
; The object the tokens TS spell after their NUMBER GENERATION obj: its
; value, or a stream when the word stream follows a dictionary.  STOP is
; where that word ends in the file.
(def %pdf-indirect
  (fn (_ f ts stop)
    (%pdf-next! ts)
    (%pdf-next! ts)
    (unless (%pdf-is? (%pdf-next! ts) (lit word) "obj") (%pdf-fail "no object where the cross-reference says one is"))
    (def v (%pdf-value ts))
    (match ((null? (first ts)) v)
           ((match ((%pdf-is? (first (first ts)) (lit word) "stream") (%pdf-tagged? v (lit dict))) (#t #f))
             (do
               (def p (str->ptr (%pdf-get f %F-BUF)))
               (def a (match ((int= (%pdf-u8 p stop) 13) (int+ stop 1)) (#t stop)))
               (def start (match ((int= (%pdf-u8 p a) 10) (int+ a 1)) (#t a)))
               (list (lit stream) (rest v) start (%pdf-stream-length f (rest v) start))))
           (#t v))))
; The object at OFF of the file F.  The tokens read run to the first endobj
; or stream after it; when the object is not whole by then -- the word was
; inside a string or a name -- they run to the next.
(def %pdf-object-at
  (fn (_ f off)
    (def buf (%pdf-get f %F-BUF))
    (def len (%pdf-get f %F-LEN))
    ((fn (self from)
       (def a (%pdf-find buf from len "endobj"))
       (def b (%pdf-find buf from len "stream"))
       (def stop
         (match ((null? a) (match ((null? b) len) (#t (int+ b 6))))
                ((null? b) (int+ a 6))
                ((int< b a) (int+ b 6))
                (#t (int+ a 6))))
       (def r
         (guard (e (match ((%pdf-short? e) (lit short)) (#t (error e))))
           (%pdf-indirect f (%pdf-lex buf off (int- (%pdf-min len (int+ stop 2)) off)) stop)))
       (match ((eq? r (lit short)) (match ((int< stop len) (self stop)) (#t (%pdf-fail "an object ends early"))))
              (#t r)))
     off)))

; --- filters ----------------------------------------------------------------
; Each takes and answers (BUF START LENGTH).
(def %pdf-ascii-hex
  (fn (_ r)
    (def p (str->ptr (first r)))
    (def end (int+ (first (rest r)) (first (rest (rest r)))))
    (def out (str-make (int+ (int/ (first (rest (rest r))) 2) 2)))
    (def o (str->ptr out))
    ((fn (self i k hi)
       ((fn (_ c)
          (match ((match ((int= c 62) #t) ((int< i end) #f) (#t #t))
                   (match ((int< hi 0) (list out 0 k))
                          (#t (do (ptr-set! o k (int<< hi 4) 1) (list out 0 (int+ k 1))))))
                 (#t ((fn (_ v)
                        (match ((int< v 0) (self (int+ i 1) k hi))
                               ((int< hi 0) (self (int+ i 1) k v))
                               (#t (do (ptr-set! o k (int| (int<< hi 4) v) 1) (self (int+ i 1) (int+ k 1) -1)))))
                      (%pdf-hexval c)))))
        (match ((int< i end) (%pdf-u8 p i)) (#t 62))))
     (first (rest r)) 0 -1)))
; ASCII85: five characters from ! to u are four bytes, most significant
; first; z is four zero bytes; a last group of N characters is N - 1 bytes.
(def %pdf-ascii-85
  (fn (_ r)
    (def p (str->ptr (first r)))
    (def end (int+ (first (rest r)) (first (rest (rest r)))))
    (def out (str-make (int+ (int* (first (rest (rest r))) 4) 8)))
    (def o (str->ptr out))
    ; The bytes of the group value V, COUNT of them, most significant first.
    (def put!
      (fn (_ k v count)
        (when (int< 0 count) (ptr-set! o k (int& (int>> v 24) 255) 1))
        (when (int< 1 count) (ptr-set! o (int+ k 1) (int& (int>> v 16) 255) 1))
        (when (int< 2 count) (ptr-set! o (int+ k 2) (int& (int>> v 8) 255) 1))
        (when (int< 3 count) (ptr-set! o (int+ k 3) (int& v 255) 1))
        (int+ k count)))
    ; A last group of N characters, padded with u to five.
    (def tail
      (fn (self v n have)
        (match ((int< have 5) (self (int+ (int* v 85) 84) n (int+ have 1)))
               (#t (pair v (int- n 1))))))
    ((fn (self i k v n)
       ((fn (_ c)
          (match ((int= c 126)
                   (match ((int< n 2) (list out 0 k))
                          (#t ((fn (_ t) (list out 0 (put! k (first t) (rest t)))) (tail v n n)))))
                 ((%pdf-white? c) (self (int+ i 1) k v n))
                 ((match ((int= c 122) (int= n 0)) (#t #f)) (self (int+ i 1) (put! k 0 4) 0 0))
                 ((match ((int< c 33) #t) ((int< 117 c) #t) (#t #f)) (%pdf-fail "a byte that is not ASCII85"))
                 ((int= n 4) (self (int+ i 1) (put! k (int+ (int* v 85) (int- c 33)) 4) 0 0))
                 (#t (self (int+ i 1) k (int+ (int* v 85) (int- c 33)) (int+ n 1)))))
        (match ((int< i end) (%pdf-u8 p i)) (#t 126))))
     (first (rest r)) 0 0 0)))
(def %pdf-or (fn (_ x default) (match ((number? x) x) (#t default))))
; The rows of R with their PNG predictors undone: each row a filter byte and
; then its bytes, per the parameters PARMS.
(def %pdf-predicted
  (fn (_ f r parms)
    (import x/codec/png)
    (def colors (%pdf-or (%pdf-lookup f parms "Colors") 1))
    (def bits (%pdf-or (%pdf-lookup f parms "BitsPerComponent") 8))
    (def columns (%pdf-or (%pdf-lookup f parms "Columns") 1))
    (def stride (int/ (int+ (int* (int* columns colors) bits) 7) 8))
    (def bpp ((fn (_ b) (match ((int< b 1) 1) (#t b))) (int/ (int* colors bits) 8)))
    (def rows (int/ (first (rest (rest r))) (int+ stride 1)))
    (Png unfilter (first r) (first (rest r)) rows stride bpp)
    (def out (str-make (int+ (int* rows stride) 1)))
    (def o (str->ptr out))
    (def p (str->ptr (first r)))
    ((fn (self y)
       (when (int< y rows)
         (mem-copy (%pdf-ptr o (int* y stride))
                   (%pdf-ptr p (int+ (int+ (first (rest r)) (int* y (int+ stride 1))) 1))
                   stride)
         (self (int+ y 1))))
     0)
    (list out 0 (int* rows stride))))
; R through the filter NAME with its parameters PARMS.
(def %pdf-filter
  (fn (_ f r name parms)
    (match
      ((match ((str=? name "FlateDecode") #t) ((str=? name "Fl") #t) (#t #f))
        ((fn (_ d predictor)
           (match ((int< predictor 2) (list (first d) 0 (first (rest d))))
                  ((int< predictor 10) (%pdf-fail "the TIFF predictor is not read"))
                  (#t (%pdf-predicted f (list (first d) 0 (first (rest d))) parms))))
         (Inflate zlib (first r) (first (rest r)) (first (rest (rest r))))
         (%pdf-or (%pdf-lookup f parms "Predictor") 1)))
      ((match ((str=? name "ASCIIHexDecode") #t) ((str=? name "AHx") #t) (#t #f)) (%pdf-ascii-hex r))
      ((match ((str=? name "ASCII85Decode") #t) ((str=? name "A85") #t) (#t #f)) (%pdf-ascii-85 r))
      (#t (%pdf-fail (Str8 append "the filter " name " is not read"))))))
; X as a list: an array's objects, nil for nil, anything else alone.
(def %pdf-listed
  (fn (_ x)
    (match ((null? x) ()) ((%pdf-tagged? x (lit array)) (rest x)) (#t (list x)))))
; The bytes of the stream S with its filters undone, in order: (BUF START
; LENGTH).
(def %pdf-decoded
  (fn (_ f s)
    (def d (first (rest s)))
    ((fn (self r names parms)
       (match ((null? names) r)
              (#t ((fn (_ name)
                     (self (%pdf-filter f r (match ((%pdf-tagged? name (lit name)) (first (rest name))) (#t ""))
                                        (match ((null? parms) ()) (#t (%pdf-resolve f (first parms)))))
                           (rest names)
                           (match ((null? parms) ()) (#t (rest parms)))))
                   (%pdf-resolve f (first names))))))
     (list (%pdf-get f %F-BUF) (first (rest (rest s))) (first (rest (rest (rest s)))))
     (%pdf-listed (%pdf-resolve f (%pdf-entry d "Filter")))
     (%pdf-listed (%pdf-resolve f (%pdf-entry d "DecodeParms"))))))

; --- the cross-reference ----------------------------------------------------
; A subsection is (table FIRST COUNT AT), COUNT entries of twenty bytes from
; AT of the file, or (stream FIRST COUNT BUF AT W1 W2 W3), entries of W1 + W2
; + W3 bytes from AT of BUF.  An entry read is (TYPE A B): 0 free; 1 at
; offset A; 2 the object B of the object stream A.
(def %pdf-field
  (fn (_ p at w)
    ((fn (self i v) (match ((int< i w) (self (int+ i 1) (int| (int<< v 8) (%pdf-u8 p (int+ at i))))) (#t v))) 0 0)))
(def %pdf-entry-of
  (fn (_ f sub n)
    (def k (int- n (first (rest sub))))
    (match
      ((eq? (first sub) (lit table))
        ((fn (_ p at)
           ((fn (_ offset)
              (match ((null? offset) (list 0 0 0))
                     ((int= (%pdf-u8 p (int+ at 17)) 110) (list 1 (first offset) 0))
                     (#t (list 0 0 0))))
            (%pdf-uint p at (int+ at 10))))
         (str->ptr (%pdf-get f %F-BUF)) (int+ (List ref 3 sub) (int* k 20))))
      (#t
        ((fn (_ p w1 w2 w3)
           ((fn (_ at)
              (list (match ((int= w1 0) 1) (#t (%pdf-field p at w1)))
                    (%pdf-field p (int+ at w1) w2)
                    (%pdf-field p (int+ (int+ at w1) w2) w3)))
            (int+ (List ref 4 sub) (int* k (int+ (int+ w1 w2) w3)))))
         (str->ptr (List ref 3 sub)) (List ref 5 sub) (List ref 6 sub) (List ref 7 sub))))))
; The entry for the object N: the first subsection that holds it says.
(def %pdf-where
  (fn (self f subs n)
    (match ((null? subs) ())
           ((match ((int< n (first (rest (first subs)))) #f)
                   (#t (int< n (int+ (first (rest (first subs))) (first (rest (rest (first subs))))))))
             (%pdf-entry-of f (first subs) n))
           (#t (self f (rest subs) n)))))

; The subsections of the table at AT, after its xref: (SUBSECTIONS . NEXT),
; NEXT where the word after them starts.
(def %pdf-table
  (fn (_ f at)
    (def p (str->ptr (%pdf-get f %F-BUF)))
    (def len (%pdf-get f %F-LEN))
    ((fn (self i acc)
       ((fn (_ a)
          (match ((null? a) (pair (List reverse acc) i))
                 (#t ((fn (_ b)
                        (match ((null? b) (%pdf-fail "a cross-reference subsection has no count"))
                               (#t ((fn (_ entries)
                                      (self (%pdf-skip-white p (int+ entries (int* (first b) 20)) len)
                                            (pair (list (lit table) (first a) (first b) entries) acc)))
                                    (%pdf-skip-white p (rest b) len)))))
                      (%pdf-uint p (%pdf-skip-white p (rest a) len) len)))))
        (%pdf-uint p i len)))
     (%pdf-skip-white p at len) ())))
; The subsections of the cross-reference stream S.
(def %pdf-stream-subs
  (fn (_ f s)
    (def d (first (rest s)))
    (def w (%pdf-listed (%pdf-resolve f (%pdf-entry d "W"))))
    (unless (int= (List length w) 3) (%pdf-fail "a cross-reference stream has no /W of three widths"))
    (def size (%pdf-or (%pdf-resolve f (%pdf-entry d "Size")) 0))
    (def index ((fn (_ x) (match ((null? x) (list 0 size)) (#t x))) (%pdf-listed (%pdf-resolve f (%pdf-entry d "Index")))))
    (def r (%pdf-decoded f s))
    (def width (int+ (int+ (first w) (first (rest w))) (first (rest (rest w)))))
    ((fn (self ix at acc)
       (match ((null? ix) (List reverse acc))
              ((null? (rest ix)) (List reverse acc))
              (#t (self (rest (rest ix)) (int+ at (int* (first (rest ix)) width))
                        (pair (list (lit stream) (first ix) (first (rest ix)) (first r) at
                                    (first w) (first (rest w)) (first (rest (rest w))))
                              acc)))))
     index (first (rest r)) ())))
; Read the cross-reference section at AT and those before it into F: its
; subsections after the ones already there, the newest's trailer kept.
(def %pdf-sections!
  (fn (self f at seen)
    (def buf (%pdf-get f %F-BUF))
    (def len (%pdf-get f %F-LEN))
    (def p (str->ptr buf))
    (def from (%pdf-skip-white p at len))
    (when (match ((int< at 0) #t) ((int< from len) #f) (#t #t)) (%pdf-fail "the cross-reference is past the end of the file"))
    (def table? (%pdf-at? buf from len "xref"))
    (def got
      (match (table?
               ((fn (_ t)
                  (unless (%pdf-at? buf (rest t) len "trailer") (%pdf-fail "a cross-reference table has no trailer"))
                  ((fn (_ stop)
                     (pair (first t)
                           (%pdf-entries-of
                             (%pdf-value (%pdf-lex buf (int+ (rest t) 7) (int- (%pdf-min len (int+ stop 1)) (int+ (rest t) 7)))))))
                   ((fn (_ s) (match ((null? s) len) (#t s))) (%pdf-find buf (rest t) len "startxref"))))
                (%pdf-table f (int+ from 4))))
             (#t ((fn (_ s)
                    (unless (%pdf-tagged? s (lit stream)) (%pdf-fail "no cross-reference where startxref says one is"))
                    (pair (%pdf-stream-subs f s) (first (rest s))))
                  (%pdf-object-at f from)))))
    (%pdf-put! f %F-SECTIONS (List append (%pdf-get f %F-SECTIONS) (first got)))
    (when (null? (%pdf-get f %F-TRAILER)) (%pdf-put! f %F-TRAILER (rest got)))
    (def more
      (fn (_ key)
        ((fn (_ prev)
           (when (match ((number? prev) (not (List includes? prev seen))) (#t #f))
             (self f prev (pair at seen))))
         (%pdf-entry (rest got) key))))
    (when table? (more "XRefStm"))
    (more "Prev")))

; --- objects by number ------------------------------------------------------
; The object stream NUMBER of F, read once: (BUF FIRST OFFSETS LENGTH), its
; bytes decoded, where its objects start, each one's offset from there in
; order, and how many bytes there are.
(def %pdf-object-stream
  (fn (_ f number)
    ((fn (_ held)
       (match ((null? held)
                (do
                  (def s ((%pdf-get f %F-OBJECT) f number))
                  (unless (%pdf-tagged? s (lit stream)) (%pdf-fail "an object stream is no stream"))
                  (def r (%pdf-decoded f s))
                  (def n (first (rest (rest r))))
                  (def buf (%pdf-ended (str->ptr (first r)) (first (rest r)) n))
                  (def start (%pdf-or (%pdf-resolve f (%pdf-entry (first (rest s)) "First")) 0))
                  (def offsets
                    ((fn (self l acc)
                       (match ((null? l) (List reverse acc))
                              ((null? (rest l)) (List reverse acc))
                              (#t (self (rest (rest l)) (pair (first (rest l)) acc)))))
                     (List take (int* 2 (%pdf-or (%pdf-resolve f (%pdf-entry (first (rest s)) "N")) 0))
                                (%pdf-values (%pdf-lex buf 0 (%pdf-min (int+ start 1) (int+ n 1))) ()))
                     ()))
                  (def made (list buf start offsets n))
                  (%pdf-put! f %F-STREAMS (pair (pair number made) (%pdf-get f %F-STREAMS)))
                  made))
              (#t (rest held))))
     (List find (fn (_ e) (int= (first e) number)) (%pdf-get f %F-STREAMS)))))
; The object K of the object stream NUMBER.
(def %pdf-packed
  (fn (_ f number k)
    (def os (%pdf-object-stream f number))
    (def offsets ((fn (self l i) (match ((null? l) ()) ((int= i 0) l) (#t (self (rest l) (int- i 1))))) (List ref 2 os) k))
    (match ((null? offsets) ())
           (#t ((fn (_ from to)
                  (%pdf-value (%pdf-lex (first os) from (int- to from))))
                (int+ (first (rest os)) (first offsets))
                ; A byte past the object ends its last token.
                (match ((null? (rest offsets)) (int+ (List ref 3 os) 1))
                       (#t (%pdf-min (int+ (List ref 3 os) 1) (int+ (int+ (first (rest os)) (first (rest offsets))) 1)))))))))
; The object N of F, nil for one the cross-reference does not hold; read
; once and kept.
(def %pdf-object
  (fn (_ f n)
    (def cache (%pdf-get f %F-CACHE))
    (match ((match ((number? n) (match ((int< n 0) #t) ((int< n (obj-ref cache 0)) #f) (#t #t))) (#t #t)) ())
           (#t ((fn (_ held)
                  (match ((null? held)
                           ((fn (_ e)
                              ((fn (_ v) (%pdf-put! cache n (list v)) v)
                               (match ((null? e) ())
                                      ((int= (first e) 1) (%pdf-object-at f (first (rest e))))
                                      ((int= (first e) 2) (%pdf-packed f (first (rest e)) (first (rest (rest e)))))
                                      (#t ()))))
                            (%pdf-where f (%pdf-get f %F-SECTIONS) n)))
                         (#t (first held))))
                (%pdf-get cache n))))))

; --- opening ----------------------------------------------------------------
(def %pdf-open
  (fn (_ s len)
    (def p (str->ptr s))
    (def head (%pdf-find s 0 (%pdf-min len 1024) "%PDF-"))
    (when (null? head) (%pdf-fail "no %PDF- header"))
    (def sx (%pdf-find-last s (match ((int< 2048 len) (int- len 2048)) (#t 0)) len "startxref"))
    (when (null? sx) (%pdf-fail "no startxref"))
    (def at (%pdf-uint p (%pdf-skip-white p (int+ sx 9) len) len))
    (when (null? at) (%pdf-fail "startxref names no offset"))
    (def f (%pdf-node 7))
    (%pdf-put! f %F-BUF s)
    (%pdf-put! f %F-LEN len)
    (%pdf-put! f %F-OBJECT %pdf-object)
    ; Reading a cross-reference stream reads objects, so there is a cache
    ; before the file's size is known; the one that holds every object
    ; replaces it.
    (%pdf-put! f %F-CACHE (%pdf-node 1))
    (%pdf-sections! f (first at) ())
    (def size
      ((fn (self subs most)
         (match ((null? subs) most)
                (#t ((fn (_ end) (self (rest subs) (match ((int< most end) end) (#t most))))
                     (int+ (first (rest (first subs))) (first (rest (rest (first subs)))))))))
       (%pdf-get f %F-SECTIONS) 1))
    (%pdf-put! f %F-CACHE (%pdf-node size))
    (unless (null? (%pdf-entry (%pdf-get f %F-TRAILER) "Encrypt")) (%pdf-fail "the file is encrypted"))
    f))
; The version a header says, "1.7" from %PDF-1.7.
(def %pdf-version
  (fn (_ f)
    (def s (%pdf-get f %F-BUF))
    (def len (%pdf-get f %F-LEN))
    (def p (str->ptr s))
    (def from (int+ (%pdf-find s 0 (%pdf-min len 1024) "%PDF-") 5))
    ((fn (self i)
       (match ((match ((int< i len) (match ((%pdf-digit? (%pdf-u8 p i)) #t) (#t (int= (%pdf-u8 p i) 46)))) (#t #f))
                (self (int+ i 1)))
              (#t (str-byte-sub s from (int- i from)))))
     from)))

; --- pages ------------------------------------------------------------------
; The attributes a page takes from the nodes above it when it has none.
(def %pdf-inherited (list "Resources" "MediaBox" "CropBox" "Rotate"))
; The entries D with each inherited attribute of UP it lacks added.
(def %pdf-inherit
  (fn (_ d up)
    ((fn (self keys d)
       (match ((null? keys) d)
              (#t ((fn (_ v)
                     (self (rest keys)
                           (match ((null? v) d) ((null? (%pdf-entry d (first keys))) (pair (pair (first keys) v) d)) (#t d))))
                   (%pdf-entry up (first keys))))))
     %pdf-inherited d)))
; The pages under the node X, in order, onto ACC reversed.  UP is the
; entries inherited so far; a tree deeper than DEPTH allows is a loop.
(def %pdf-pages
  (fn (self f x up depth acc)
    ((fn (_ d)
       (match ((null? d) acc)
              ((int< depth 1) (%pdf-fail "the page tree loops"))
              (#t ((fn (_ here kids)
                     (match ((null? kids) (pair (pair (lit dict) here) acc))
                            (#t ((fn (each ks acc)
                                   (match ((null? ks) acc)
                                          (#t (each (rest ks) (self f (first ks) here (int- depth 1) acc)))))
                                 (%pdf-listed kids) acc))))
                   (%pdf-inherit d up) (%pdf-resolve f (%pdf-entry d "Kids"))))))
     (%pdf-entries-of (%pdf-resolve f x)))))

(def-class Pdf ()
  (doc "A PDF file's objects, streams and pages. (Pdf open bytes length) reads the cross-reference; after it (Pdf object), (Pdf lookup) and (Pdf pages) answer objects, read when first asked for, and (Pdf data) a stream's bytes with its filters undone. An object is an integer, (real TEXT), #t, #f, nil, (name TEXT), (string BUF LENGTH), (array OBJECT...), (dict (KEY . OBJECT)...), (ref NUMBER GENERATION) or (stream ENTRIES START LENGTH)."
    (example "(Pdf read \"[1 -2.5 /A#20b (c\\\\)) <4142> true null 3 0 R] \" 0 45)" "(('array 1 ('real \"-2.5\") ('name \"A b\") ('string \"c)\" 2) ('string \"AB\" 2) #t () ('ref 3 0)))")
    (see open) (see pages) (see data) (see read))
  (static
    (method open (self (param s STRING "Bytes holding a PDF file")
                       . (param length INTEGER "How many bytes; default s's length to its first NUL"))
      (doc "Open a PDF: find its header and its startxref, and read every cross-reference section, tables and streams, the newest first. Give LENGTH for a file read whole: nearly every PDF holds a NUL. Raises a label 'value for a file with no header or cross-reference, and for an encrypted one."
        (returns OBJECT "The open file, for the other methods")
        (sample "(Pdf open bytes size)" "the file, its objects read as they are asked for"))
      (%pdf-open s (match ((null? length) (str-byte-len s)) (#t (first length)))))
    (method version (self (param f OBJECT "An open file"))
      (doc "The version the file's header says."
        (returns STRING "As \"1.7\"")
        (sample "(Pdf version f)" "\"1.4\" for a file that starts %PDF-1.4"))
      (%pdf-version f))
    (method trailer (self (param f OBJECT "An open file"))
      (doc "The newest trailer, as a dictionary: /Root, /Info, /Size, /ID."
        (returns LIST "(dict (KEY . OBJECT)...)")
        (sample "(Pdf lookup f (Pdf trailer f) \"Root\")" "the document catalogue"))
      (pair (lit dict) (%pdf-get f %F-TRAILER)))
    (method object (self (param f OBJECT "An open file") (param n INTEGER "An object's number"))
      (doc "The object numbered n, read from its offset or from the object stream that holds it, and kept. nil for a number the cross-reference has free or does not hold."
        (returns ANY "The object")
        (sample "(Pdf object f 1)" "the object 1 0 obj holds"))
      (%pdf-object f n))
    (method resolve (self (param f OBJECT "An open file") (param x ANY "An object"))
      (doc "x, or the object it names when it is a reference."
        (returns ANY "An object that is no reference")
        (sample "(Pdf resolve f (list 'ref 4 0))" "the object numbered 4"))
      (%pdf-resolve f x))
    (method lookup (self (param f OBJECT "An open file")
                         (param x ANY "A dictionary, a stream, or a reference to one")
                         (param key STRING "A key, the name's text"))
      (doc "The value of key in a dictionary or a stream's dictionary, both x and the value resolved. nil when x has no such key, or is neither."
        (returns ANY "The value, or nil")
        (sample "(Pdf lookup f page \"Contents\")" "a page's content stream"))
      (%pdf-lookup f x key))
    (method data (self (param f OBJECT "An open file") (param s LIST "A stream, (stream ENTRIES START LENGTH)"))
      (doc "A stream's bytes with its filters undone, in the order /Filter lists them: FlateDecode (with a PNG predictor when /DecodeParms names one), ASCIIHexDecode, ASCII85Decode. Raises a label 'value naming any other filter."
        (returns LIST "(BUF START LENGTH): the bytes, a line end after them")
        (sample "(Pdf data f (Pdf lookup f page \"Contents\"))" "a page's content, decompressed"))
      ((fn (_ r) (list (%pdf-ended (str->ptr (first r)) (first (rest r)) (first (rest (rest r)))) 0 (first (rest (rest r)))))
       (%pdf-decoded f s)))
    (method pages (self (param f OBJECT "An open file"))
      (doc "The file's pages in order, each a dictionary: the page tree from the catalogue's /Pages walked, and each page given the /Resources, /MediaBox, /CropBox and /Rotate of the nodes above it when it has none of its own."
        (returns LIST "((dict (KEY . OBJECT)...) ...)")
        (sample "(List length (Pdf pages f))" "how many pages the file has"))
      (List reverse
        (%pdf-pages f (%pdf-lookup f (%pdf-lookup f (pair (lit dict) (%pdf-get f %F-TRAILER)) "Root") "Pages") () 64 ())))
    (method read (self (param s STRING "Bytes holding PDF syntax, a delimiter after the last object")
                       (param start INTEGER "Where to read from")
                       (param length INTEGER "How many bytes"))
      (doc "The objects a span of bytes spells, in order: what a content stream is, its operators each (op TEXT) after their operands. The last token is read only when a byte follows it, as (Pdf data) leaves a line end."
        (returns LIST "The objects")
        (example "(Pdf read \"BT /F1 12 Tf (Hi) Tj ET \" 0 24)" "(('op \"BT\") ('name \"F1\") 12 ('op \"Tf\") ('string \"Hi\" 2) ('op \"Tj\") ('op \"ET\"))")
        (example "(Pdf read \"<</K [1 2] /L <</M (n)>>>> \" 0 27)" "(('dict (\"K\" 'array 1 2) (\"L\" 'dict (\"M\" 'string \"n\" 1))))"))
      (%pdf-values (%pdf-lex s start length) ()))))

(doc (provide x/codec/pdf Pdf)
  (example "(Pdf read \"/Type /Page \" 0 12)" "(('name \"Type\") ('name \"Page\"))")
  (note "Objects are plain lists, strings and integers, read when asked for. A string's bytes may hold NULs: its length is beside it.")
  "A PDF file's objects, streams and pages, homed on the Pdf class.")
