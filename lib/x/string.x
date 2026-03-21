; string.x -- String utilities
(import x/char)
(import x/list)
(import x/derived)

(def string-empty? (fn (s) (= (string-length s) 0)))

(def string-join
  (fn (sep lst)
    (match
      ((null? lst) "")
      ((null? (rest lst)) (first lst))
      (#t
        (fold
          (fn (acc s) (string-append acc (string-append sep s)))
          (first lst)
          (rest lst))))))

(def string-repeat
  (fn (s n)
    (if (<= n 0)
      ""
      (string-append s (string-repeat s (- n 1))))))

(def string-contains?
  (fn (sub s)
    (def sub-len (string-length sub))
    (def s-len (string-length s))
    (def go
      (fn (i)
        (match
          ((> (+ i sub-len) s-len) #f)
          ((string=? (substring s i (+ i sub-len)) sub) #t)
          (#t (go (+ i 1))))))
    (if (= sub-len 0) #t (go 0))))

(def string-starts?
  (fn (pfx s)
    (def pfx-len (string-length pfx))
    (if (> pfx-len (string-length s))
      ()
      (string=? (substring s 0 pfx-len) pfx))))

(def string-ends?
  (fn (sfx s)
    (def sfx-len (string-length sfx))
    (def s-len (string-length s))
    (if (> sfx-len s-len)
      ()
      (string=? (substring s (- s-len sfx-len) s-len) sfx))))

(def string-reverse
  (fn (s)
    (def len (string-length s))
    (def go
      (fn (i acc)
        (if (< i 0)
          acc
          (go (- i 1) (string-append acc (substring s i (+ i 1)))))))
    (go (- len 1) "")))

; --- Conversion ---

(def string->list
  (fn (s)
    (let go ((i (- (string-length s) 1)) (acc ()))
      (if (< i 0) acc (go (- i 1) (pair (string-ref s i) acc))))))

; --- Case conversion ---

(def string-upcase
  (fn (s)
    (list->string (map char-upcase (string->list s)))))

(def string-downcase
  (fn (s)
    (list->string (map char-downcase (string->list s)))))

; --- Ordering ---

(def string<?
  (fn (a b)
    (let go ((i 0))
      (cond
        ((= i (string-length a)) (< i (string-length b)))
        ((= i (string-length b)) #f)
        ((char<? (string-ref a i) (string-ref b i)) #t)
        ((char>? (string-ref a i) (string-ref b i)) #f)
        (#t (go (+ i 1)))))))

(def string>? (fn (a b) (string<? b a)))
(def string<=? (fn (a b) (not (string>? a b))))
(def string>=? (fn (a b) (not (string<? a b))))

; --- Case-insensitive comparison ---

(def string-ci=?
  (fn (a b) (string=? (string-downcase a) (string-downcase b))))
(def string-ci<?
  (fn (a b) (string<? (string-downcase a) (string-downcase b))))
(def string-ci>?
  (fn (a b) (string>? (string-downcase a) (string-downcase b))))
(def string-ci<=?
  (fn (a b) (string<=? (string-downcase a) (string-downcase b))))
(def string-ci>=?
  (fn (a b) (string>=? (string-downcase a) (string-downcase b))))

; --- Trimming ---

(def string-trim-left
  (fn (s)
    (let go ((i 0))
      (if (= i (string-length s)) ""
        (if (char-whitespace? (string-ref s i))
          (go (+ i 1))
          (substring s i (string-length s)))))))

(def string-trim-right
  (fn (s)
    (let go ((i (- (string-length s) 1)))
      (if (< i 0) ""
        (if (char-whitespace? (string-ref s i))
          (go (- i 1))
          (substring s 0 (+ i 1)))))))

(def string-trim
  (fn (s) (string-trim-left (string-trim-right s))))

; --- Splitting ---

(def string-split
  (fn (sep s)
    (def sep-len (string-length sep))
    (def s-len (string-length s))
    (if (= sep-len 0) (map (fn (c) (list->string (list c))) (string->list s))
      (let go ((start 0) (i 0) (acc ()))
        (if (> (+ i sep-len) s-len)
          (reverse (pair (substring s start s-len) acc))
          (if (string=? (substring s i (+ i sep-len)) sep)
            (go (+ i sep-len) (+ i sep-len)
                (pair (substring s start i) acc))
            (go start (+ i 1) acc)))))))

(provide x/string
  string-empty? string-join string-repeat string-contains?
  string-starts? string-ends? string-reverse string->list
  string-upcase string-downcase
  string<? string>? string<=? string>=?
  string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
  string-trim-left string-trim-right string-trim string-split)
