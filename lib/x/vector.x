; vector.x -- Vector type with #() reader syntax
(import x/list)
; N+1 slot objects: slot 0 = length, slots 1..N = elements.

(def %vector-read ())

(def %vector
  (make-type
    "VECTOR"
    (list
      (pair
        (lit call)
        (fn (self . args)
          (def i (first args))
          (if (< i 0)
            (obj-ref self (+ (obj-ref self 0) i 1))
            (obj-ref self (+ i 1)))))
      (pair
        (lit write)
        (fn (self)
          (display "#(")
          (def len (obj-ref self 0))
          (def write-vec
            (fn (i sep)
              (if (< i len)
                (do
                  (if sep (display " "))
                  (write (obj-ref self (+ i 1)))
                  (write-vec (+ i 1) #t)))))
          (write-vec 0 #f)
          (display ")")))
      (pair (lit first-chars) "#")
      (pair
        (lit analyse)
        (fn (buffer score chr)
          (if (= chr (char->integer #\#))
            (fn (buffer score chr)
              (if (= chr (char->integer #\())
                (do (buffer-unread buffer) (score-set score 1 buffer))
                ()))
            ())))
      (pair (lit read) (fn args (%vector-read (first args))))
      (pair
        (lit from)
        (list
          (pair
            (type-of (pair 1 ()))
            (fn (value)
              (def len (length value))
              (def v (make-obj %vector (+ len 1)))
              (obj-set! v 0 len)
              (def fill
                (fn (lst i)
                  (if (not (null? lst))
                    (do (obj-set! v (+ i 1) (first lst))
                      (fill (rest lst) (+ i 1))))))
              (fill value 0)
              v))))
      (pair
        (lit to)
        (list
          (pair (type-of (pair 1 ()))
            (fn (self)
              (def len (obj-ref self 0))
              (def build
                (fn (i acc)
                  (if (< i 0) acc
                    (build (- i 1) (pair (obj-ref self (+ i 1)) acc)))))
              (build (- len 1) ())))))
      (pair
        (lit iter)
        (fn (self)
          (def len (obj-ref self 0))
          (def i 0)
          (fn ()
            (if (< i len)
              (let ((val (obj-ref self (+ i 1))))
                (set! i (+ i 1))
                val)
              ())))))))

(set! %vector-read (fn args
  (def lst (read))
  (def len (length lst))
  (def v (make-obj %vector (+ len 1)))
  (obj-set! v 0 len)
  (def fill
    (fn (l i)
      (if (not (null? l))
        (do (obj-set! v (+ i 1) (first l))
          (fill (rest l) (+ i 1))))))
  (fill lst 0)
  v))

(def vector (fn args
  (def len (length args))
  (def v (make-obj %vector (+ len 1)))
  (obj-set! v 0 len)
  (def fill
    (fn (lst i)
      (if (not (null? lst))
        (do (obj-set! v (+ i 1) (first lst))
          (fill (rest lst) (+ i 1))))))
  (fill args 0)
  v))

(def vector? (fn (x) (type? x %vector)))

(def vector-ref (fn (v i) (obj-ref v (+ i 1))))

(def vector-length (fn (v) (obj-ref v 0)))

(def vector->list (fn (v)
  (def len (obj-ref v 0))
  (def build
    (fn (i acc)
      (if (< i 0) acc
        (build (- i 1) (pair (obj-ref v (+ i 1)) acc)))))
  (build (- len 1) ())))

(def list->vector (fn (lst)
  (def len (length lst))
  (def v (make-obj %vector (+ len 1)))
  (obj-set! v 0 len)
  (def fill
    (fn (l i)
      (if (not (null? l))
        (do (obj-set! v (+ i 1) (first l))
          (fill (rest l) (+ i 1))))))
  (fill lst 0)
  v))

(def make-vector
  (fn (n fill)
    (def v (make-obj %vector (+ n 1)))
    (obj-set! v 0 n)
    (def loop
      (fn (i)
        (if (<= i n)
          (do (obj-set! v i fill) (loop (+ i 1))))))
    (loop 1)
    v))

(provide x/vector vector vector? vector-ref vector-length vector->list list->vector make-vector)
