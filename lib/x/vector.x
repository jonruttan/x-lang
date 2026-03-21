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

(note "Constructors")

(doc (def vector (fn args
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
  (returns VECTOR "New vector containing the arguments")
  "Create a vector from the given arguments.")

(doc (def make-vector
  (fn ((param n INT "Number of elements")
       (param fill ANY "Value to fill each slot with"))
    (def v (make-obj %vector (+ n 1)))
    (obj-set! v 0 n)
    (def loop
      (fn (i)
        (if (<= i n)
          (do (obj-set! v i fill) (loop (+ i 1))))))
    (loop 1)
    v))
  (returns VECTOR "New vector of length n filled with fill")
  "Create a vector of length n, with every element set to fill.")

(note "Predicates")

(doc (def vector? (fn ((param x ANY "Value to test")) (type? x %vector)))
  (returns BOOL "True if x is a vector")
  "Test whether a value is a vector.")

(note "Access")

(doc (def vector-ref (fn ((param v VECTOR "Vector") (param i INT "Zero-based index")) (obj-ref v (+ i 1))))
  (returns ANY "Element at index i")
  "Return the element at index i of a vector.")

(doc (def vector-length (fn ((param v VECTOR "Vector")) (obj-ref v 0)))
  (returns INT "Number of elements")
  "Return the number of elements in a vector.")

(note "Conversion")

(doc (def vector->list (fn ((param v VECTOR "Vector to convert"))
  (def len (obj-ref v 0))
  (def build
    (fn (i acc)
      (if (< i 0) acc
        (build (- i 1) (pair (obj-ref v (+ i 1)) acc)))))
  (build (- len 1) ())))
  (returns LIST "List of the vector's elements")
  "Convert a vector to a list.")

(doc (def list->vector (fn ((param lst LIST "List to convert"))
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
  (returns VECTOR "New vector containing the list's elements")
  "Convert a list to a vector.")

(doc (provide x/vector vector vector? vector-ref vector-length vector->list list->vector make-vector)
  (note "Literal syntax: #(1 2 3). Supports negative indexing.")
  (example "(vector-ref #(10 20 30) 1)" "20")
  "Fixed-size indexed vectors.")
