; vector.x -- Vector type with #() reader syntax

(def %vector-read ())

(def %vector (make-type "VECTOR"
  (list
    (pair (lit call) (fn (self . args)
      ((first self) (first args))))
    (pair (lit write) (fn (self)
      (display "#(")
      (def write-vec (fn (lst sep)
        (if (not (null? lst))
          (do (if sep (display " "))
              (write (first lst))
              (write-vec (rest lst) t)))))
      (write-vec (first self) ())
      (display ")")))
    (pair (lit analyse) (fn (buffer score chr)
      (if (= chr 35)
        (fn (buffer score chr)
          (if (= chr 40)
            (do (buffer-unread buffer) (score-set score 1 buffer %vector-read))
            ()))
        ()))))))

(set %vector-read (fn args
  (make-instance %vector (read))))

(def vector (fn args (make-instance %vector args)))
(def vector? (fn (x) (type? x %vector)))
(def vector-ref (fn (v i) (v i)))
(def vector-length (fn (v)
  (fold (fn (acc x) (+ acc 1)) 0 (first v))))
(def vector->list (fn (v) (first v)))
(def list->vector (fn (lst) (make-instance %vector lst)))
(def make-vector (fn (n fill)
  (def build (fn (i acc)
    (if (= i 0) acc (build (- i 1) (pair fill acc)))))
  (make-instance %vector (build n ()))))
