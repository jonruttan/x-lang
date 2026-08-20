; dispatch-bench.x -- object-model dispatch micro-benchmarks (v2 arc).
; Run ONE AT A TIME via  ./x.sh -q -f benchmarks/dispatch-bench.x
; (single run; never inside a parallel suite). Times are CPU microseconds
; per call over N iterations -- coarse, for before/after comparison only.
(import x/sys/posix)

(def %bench-n 20000)
(def %clock (prim-ref (lit sys) (lit clock)))

(def %bench
  (fn (_ label f)
    (let ((t0 (%clock)))
      (let loop ((i 0))
        (if (< i %bench-n)
          (do (f) (loop (+ i 1)))
          ()))
      (let ((t1 (%clock)))
        (display label " " (/ (- t1 t0) %bench-n) " us/call\n")))))

(def-class BP () x (y 2)
  (method get (self) (self x))
  (method k (self) 5)
  (static
    (count 0)
    (method sget (self) 41)))
(def bp (new BP x 1))

; plain fn baseline
(def %plain (fn (_) 40))
(%bench "plain-fn      " (fn (_) (%plain)))
; instance method dispatch
(%bench "inst-method   " (fn (_) (bp get)))
(%bench "inst-const    " (fn (_) (bp k)))
; static method dispatch
(%bench "static-method " (fn (_) (BP sget)))
; instance field read / write
(%bench "field-read    " (fn (_) (bp x)))
(%bench "field-write   " (fn (_) (bp x 9)))
; static member read
(%bench "static-read   " (fn (_) (BP count)))
; hoisted direct call (the de-dispatch door)
(def %g (method-of BP (lit sget)))
(%bench "method-of-call" (fn (_) (%g BP)))

; Pin-shaped case: a class with 110 statics; call one registered EARLY (a
; back-of-table hit for a fresh table). Old dispatch walked the whole alist
; per call; the flat table promotes it to the front after the first hits.
(def %mk-method
  (fn (_ i)
    (list (lit method) (%str->symbol (%str-append "m" (%display-to-str i)))
      (lit (self)) i)))
(def %big-rows
  (fn (loop i acc)
    (if (< i 0) acc (loop (- i 1) (pair (%mk-method i) acc)))))
(eval! (pair (lit def-class) (pair (lit Big) (pair () (list (pair (lit static) (%big-rows 109 ())))))))
(%bench "big-back-hit  " (fn (_) (Big m109)))
