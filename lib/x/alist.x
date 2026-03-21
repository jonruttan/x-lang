; alist.x -- Association list operations
(import x/list)
;
; Alists: ((key1 . val1) (key2 . val2) ...)
; Keys compared with eq? (symbol pointer equality)

(def assoc-get
  (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (#t (assoc-get key (rest alist))))))

(def assoc-get-or
  (fn (d key alist)
    (def result (assoc-get key alist))
    (if (null? result) d result)))

(def assoc-has?
  (fn (key alist)
    (match
      ((null? alist) #f)
      ((eq? key (first (first alist))) #t)
      (#t (assoc-has? key (rest alist))))))

(def assoc-del
  (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (assoc-del key (rest alist)))
      (#t (pair (first alist) (assoc-del key (rest alist)))))))

(def assoc-put
  (fn (key val alist) (pair (pair key val) (assoc-del key alist))))

(def assoc-keys (fn (alist) (map first alist)))

(def assoc-vals (fn (alist) (map rest alist)))

(def assoc-map
  (fn (f alist)
    (map
      (fn (entry) (pair (first entry) (f (rest entry))))
      alist)))

(def assoc-filter (fn (pred alist) (filter pred alist)))

(def assoc-merge
  (fn (a b)
    (fold
      (fn (acc entry)
        (if (assoc-has? (first entry) acc) acc (pair entry acc)))
      a
      b)))

(def assoc-pick
  (fn (keys alist)
    (filter (fn (entry) (includes? (first entry) keys)) alist)))

(def assoc-omit
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
        (def transform (assoc-get (first entry) fns))
        (if (null? transform)
          entry
          (pair (first entry) (transform (rest entry)))))
      alist)))

(provide x/alist
  assoc-get assoc-get-or assoc-has? assoc-del assoc-put
  assoc-keys assoc-vals assoc-map assoc-filter assoc-merge
  assoc-pick assoc-omit from-pairs to-pairs evolve)
