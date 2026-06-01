; str/str.x -- Str: the 8-bit (byte) string class + full string suite
(import x/protocol/seq)

; Str treats a STRING as its raw bytes (8-bit chars, 0-255), with no encoding
; protocol. It provides the whole string suite (the methods x/type/string.x
; offers, minus the str- prefix) as static methods, so a string library is
; (Str append a b), (Str length s), (Str upcase s), and so on.
;
; The suite is written ONCE here, in two flavours:
;   - encoding-INDEPENDENT ops (append, join, repeat, contains?, starts?, ends?,
;     =?, <?, trim, ...) use the byte primitives directly. They are correct for
;     UTF-8 too: concatenation of valid sequences stays valid, substring search
;     is byte search, and UTF-8 byte order equals code-point order.
;   - encoding-SENSITIVE ops (make, reverse, upcase, downcase, pad-left, the
;     empty-separator split) route through SELF primitives (self length / ref /
;     ->list / ->str). Utf8 (a subclass) overrides only those primitives, so it
;     inherits this entire suite with correct code-point behaviour.

; Module-level helper: does sub occur in s at byte position pos?
(def %str-match-at?
  (fn (_ s sub pos)
    (def sub-len (str-length sub))
    (if (> (+ pos sub-len) (str-length s)) #f
      (str=? (substring s pos (+ pos sub-len)) sub))))

(def-class Str (extends Seq)
  (static
    ; --- cursor primitives (byte view) ---
    (method start (self v)     0)
    (method done? (self v cur) (>= cur (str-length v)))
    (method step  (self v cur) (pair (str-ref v cur) (+ cur 1)))

    ; --- indexing primitives: bytes are O(1) ---
    (method length (self v)   (str-length v))     ; overrides Seq's cursor walk
    (method ref    (self v i) (str-ref v i))

    ; encode: one byte element is its own low byte. Makes
    ; (Str ->str (Str ->list s)) an identity on the byte view.
    (method char->bytes (self el) (list (& (char->integer el) 255)))

    ; --- construction ---
    (method append (self . args) (fold str-append "" args))
    (method make   (self k . rest)
      (def ch (if (null? rest) (" " 0) (first rest)))
      (self ->str (repeat ch k)))

    ; --- predicates ---
    (method empty? (self s) (= (str-length s) 0))

    ; --- equality / ordering (byte order == code-point order for UTF-8) ---
    (method =? (self a b) (str=? a b))
    (method <? (self a b)
      (let go ((i 0))
        (cond
          ((= i (str-length a)) (< i (str-length b)))
          ((= i (str-length b)) #f)
          ((char<? (str-ref a i) (str-ref b i)) #t)
          ((char>? (str-ref a i) (str-ref b i)) #f)
          (#t (go (+ i 1))))))
    (method >?  (self a b) (self <? b a))
    (method <=? (self a b) (not (self >? a b)))
    (method >=? (self a b) (not (self <? a b)))

    ; --- case-insensitive comparison (built on downcase + the above) ---
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

    ; --- padding: pads to n ELEMENTS (bytes for Str, code points for Utf8) ---
    (method pad-left (self s n ch)
      (def len (self length s))
      (if (not (< len n)) s
        (str-append (self make (- n len) ch) s)))

    ; --- searching (byte-level; correct for UTF-8) ---
    (method contains? (self sub s)
      (def s-len (str-length s))
      (def sub-len (str-length sub))
      (def go (fn (loop i)
        (if (> (+ i sub-len) s-len) #f
          (if (%str-match-at? s sub i) #t (loop (+ i 1))))))
      (if (= sub-len 0) #t (go 0)))
    (method starts? (self pfx s) (%str-match-at? s pfx 0))
    (method ends?   (self sfx s)
      (def s-len (str-length s))
      (def sfx-len (str-length sfx))
      (if (> sfx-len s-len) #f (%str-match-at? s sfx (- s-len sfx-len))))

    ; --- transformation (code-point correct via self ->list / ->str) ---
    (method reverse  (self s) (self ->str (reverse (self ->list s))))
    (method upcase   (self s) (self ->str (map char-upcase   (self ->list s))))
    (method downcase (self s) (self ->str (map char-downcase (self ->list s))))

    ; --- trimming (whitespace is ASCII, so byte scanning is correct) ---
    (method trim-left (self s)
      (let go ((i 0))
        (if (= i (str-length s)) ""
          (if (char-whitespace? (str-ref s i))
            (go (+ i 1))
            (substring s i (str-length s))))))
    (method trim-right (self s)
      (let go ((i (- (str-length s) 1)))
        (if (< i 0) ""
          (if (char-whitespace? (str-ref s i))
            (go (- i 1))
            (substring s 0 (+ i 1))))))
    (method trim (self s) (self trim-left (self trim-right s)))

    ; --- splitting (empty sep -> per element, via self; else byte search) ---
    (method split (self sep s)
      (def sep-len (str-length sep))
      (def s-len (str-length s))
      (if (= sep-len 0)
        (map (fn (_ c) (self ->str (list c))) (self ->list s))
        (let go ((start 0) (i 0) (acc ()))
          (if (> (+ i sep-len) s-len)
            (reverse (pair (substring s start s-len) acc))
            (if (str=? (substring s i (+ i sep-len)) sep)
              (go (+ i sep-len) (+ i sep-len) (pair (substring s start i) acc))
              (go start (+ i 1) acc))))))))

(provide x/protocol/str/str Str)
