; str/str8.x -- Str8: the 8-bit (byte) string class + the full string suite
(import x/protocol/seq)

; Str8 treats a STRING as its raw bytes (8-bit chars, 0-255), with no encoding
; protocol. It provides the whole string suite (the methods x/type/string.x
; offers, minus the str- prefix) as static methods: (Str8 append a b),
; (Str8 index s i), (Str8 length s), (Str8 upcase s), ...
;
; Three string PROTOCOLS:
;   Str8     -- always 8-bit bytes (this class)
;   StrUTF8  -- always UTF-8 code points (subclass; overrides the primitives)
;   Str      -- the AMBIENT protocol (currently = Str8); see provide below
;
; The suite is written ONCE here, expressed entirely through SELF primitives:
;   (self length s)        -- element count
;   (self index s i)       -- i-th element (CHARACTER)
;   (self sub s start len)  -- substring of `len` elements from `start`
;   (self =? a b) (self ->list s) (self ->str l)
; so a subclass that overrides only those gets the whole suite in its own
; protocol. Str8's primitives bottom out in the str-byte-* C primitives, which
; are ALWAYS byte-level and IGNORE any handler pushed on the ambient string
; call -- so Str8 is allocation-light and safe to use inside readers/tokenizers
; that must not touch the ambient (s i).

(def-class Str8 (extends Seq)
  (static
    ; --- primitives (8-bit byte view; handler-immune via str-byte-*) ---
    (method length (self v)        (str-byte-len v))
    (method index  (self v i)      (str-byte-ref v i))
    (method sub    (self v st len) (str-byte-sub v st len))
    (method ref    (self v i)      (self index v i))  ; alias: ref = index

    ; cursor primitives (drive Seq's ->list/each/fold/count).
    ; The cursor is a BYTE offset for every subclass, so done? bounds against the
    ; raw byte length -- NOT (self length), which a code-point subclass overrides
    ; via count -> done?, an infinite recursion. start/done? are inherited
    ; unchanged by StrUTF8; only step advances differently.
    (method start (self v)     0)
    (method done? (self v cur) (>= cur (str-byte-len v)))
    (method step  (self v cur) (pair (self index v cur) (+ cur 1)))

    ; encode: one byte element is its own low byte. Makes
    ; (Str8 ->str (Str8 ->list s)) an identity on the byte view.
    (method char->bytes (self el) (list (& (char->integer el) 255)))

    ; --- equality (byte equality; correct code-point equality for UTF-8 too) ---
    (method =? (self a b)
      (if (= (self length a) (self length b))
        (let go ((i 0) (n (self length a)))
          (if (= i n) #t
            (if (= (char->integer (self index a i))
                   (char->integer (self index b i)))
              (go (+ i 1) n) #f)))
        #f))

    ; does sub occur in s at element position pos?
    (method match-at? (self s sub pos)
      (def sub-len (self length sub))
      (if (> (+ pos sub-len) (self length s)) #f
        (self =? (self sub s pos sub-len) sub)))

    ; --- construction ---
    (method append (self . args) (fold str-append "" args))
    (method make   (self k . rest)
      (def ch (if (null? rest) (" " 0) (first rest)))
      (self ->str (repeat ch k)))

    ; --- predicates ---
    (method empty? (self s) (= (self length s) 0))

    ; --- ordering (element order; byte order == code-point order for UTF-8) ---
    (method <? (self a b)
      (let go ((i 0) (la (self length a)) (lb (self length b)))
        (cond
          ((= i la) (< i lb))
          ((= i lb) #f)
          ((char<? (self index a i) (self index b i)) #t)
          ((char>? (self index a i) (self index b i)) #f)
          (#t (go (+ i 1) la lb)))))
    (method >?  (self a b) (self <? b a))
    (method <=? (self a b) (not (self >? a b)))
    (method >=? (self a b) (not (self <? a b)))

    ; --- case-insensitive comparison ---
    (method ci=?  (self a b) (self =?  (self downcase a) (self downcase b)))
    (method ci<?  (self a b) (self <?  (self downcase a) (self downcase b)))
    (method ci>?  (self a b) (self >?  (self downcase a) (self downcase b)))
    (method ci<=? (self a b) (self <=? (self downcase a) (self downcase b)))
    (method ci>=? (self a b) (self >=? (self downcase a) (self downcase b)))

    ; --- joining / repeating ---
    (method join (self sep lst)
      (match
        ((null? lst) "")
        ((null? (rest lst)) (first lst))
        (#t (fold (fn (_ acc s) (str-append acc (str-append sep s)))
                  (first lst) (rest lst)))))
    (method repeat (self s n)
      (if (<= n 0) "" (str-append s (self repeat s (- n 1)))))

    ; --- padding (to n ELEMENTS) ---
    (method pad-left (self s n ch)
      (def len (self length s))
      (if (not (< len n)) s
        (str-append (self make (- n len) ch) s)))

    ; --- searching ---
    (method contains? (self sub s)
      (def s-len (self length s))
      (def sub-len (self length sub))
      (def go (fn (loop i)
        (if (> (+ i sub-len) s-len) #f
          (if (self match-at? s sub i) #t (loop (+ i 1))))))
      (if (= sub-len 0) #t (go 0)))
    (method starts? (self pfx s) (self match-at? s pfx 0))
    (method ends?   (self sfx s)
      (def s-len (self length s))
      (def sfx-len (self length sfx))
      (if (> sfx-len s-len) #f (self match-at? s sfx (- s-len sfx-len))))

    ; --- transformation ---
    (method reverse  (self s) (self ->str (reverse (self ->list s))))
    (method upcase (self (param s STRING "String to convert"))
      (doc "Uppercase the ASCII letters of s; other characters pass through."
        (returns STRING "s with a-z mapped to A-Z")
        (example "(Str8 upcase \"café\")" "\"CAFé\""))
      (self ->str (map char-upcase (self ->list s))))
    (method downcase (self s) (self ->str (map char-downcase (self ->list s))))

    ; --- trimming (whitespace is ASCII; element scanning is correct) ---
    (method trim-left (self s)
      (let go ((i 0) (n (self length s)))
        (if (= i n) ""
          (if (char-whitespace? (self index s i))
            (go (+ i 1) n)
            (self sub s i (- n i))))))
    (method trim-right (self s)
      (let go ((i (- (self length s) 1)))
        (if (< i 0) ""
          (if (char-whitespace? (self index s i))
            (go (- i 1))
            (self sub s 0 (+ i 1))))))
    (method trim (self s) (self trim-left (self trim-right s)))

    ; --- splitting (empty sep -> per element; else element search) ---
    (method split (self sep s)
      (def sep-len (self length sep))
      (def s-len (self length s))
      (if (= sep-len 0)
        (map (fn (_ c) (self ->str (list c))) (self ->list s))
        (let go ((start 0) (i 0) (acc ()))
          (if (> (+ i sep-len) s-len)
            (reverse (pair (self sub s start (- s-len start)) acc))
            (if (self =? (self sub s i sep-len) sep)
              (go (+ i sep-len) (+ i sep-len)
                  (pair (self sub s start (- i start)) acc))
              (go start (+ i 1) acc))))))))

(provide x/protocol/str/str8 Str8)
