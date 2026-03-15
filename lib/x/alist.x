; alist.x -- Association list operations
;
; Alists: ((key1 . val1) (key2 . val2) ...)
; Keys compared with eq? (symbol pointer equality)

(def aget
  (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (aget key (rest alist))))))

(def aget-or
  (fn (d key alist)
    (def result (aget key alist))
    (if (null? result) d result)))

(def ahas?
  (fn (key alist)
    (match
      ((null? alist) #f)
      ((eq? key (first (first alist))) #t)
      (#t (ahas? key (rest alist))))))

(def adel
  (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (adel key (rest alist)))
      (#t (pair (first alist) (adel key (rest alist)))))))

(def aset
  (fn (key val alist) (pair (pair key val) (adel key alist))))

(def akeys (fn (alist) (map first alist)))

(def avals (fn (alist) (map rest alist)))

(def amap
  (fn (f alist)
    (map
      (fn (entry) (pair (first entry) (f (rest entry))))
      alist)))

(def afilter (fn (pred alist) (filter pred alist)))

(def amerge
  (fn (a b)
    (fold
      (fn (acc entry)
        (if (ahas? (first entry) acc) acc (pair entry acc)))
      a
      b)))

(def apick
  (fn (keys alist)
    (filter (fn (entry) (includes? (first entry) keys)) alist)))

(def aomit
  (fn (keys alist)
    (filter
      (fn (entry) (not (includes? (first entry) keys)))
      alist)))

(def from-pairs
  (fn (lst)
    (map (fn (p) (pair (first p) (first (rest p)))) lst)))

(def to-pairs
  (fn (alist)
    (map (fn (entry) (list (first entry) (rest entry))) alist)))

(def evolve
  (fn (fns alist)
    (map
      (fn (entry)
        (def transform (aget (first entry) fns))
        (if (null? transform)
          entry
          (pair (first entry) (transform (rest entry)))))
      alist)))
