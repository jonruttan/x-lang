; string.x -- String utilities

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
