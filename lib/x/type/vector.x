; vector.x -- Vector type with #() reader syntax
(import x/core/list)
; N+1 slot objects: slot 0 = length, slots 1..N = elements.

; Fill a vector's slots from a list (shared helper)
(def %vector-from-list
  (fn (_ type lst)
    (def len (length lst))
    (def v (make-obj type (+ len 1)))
    (obj-set! v 0 len)
    (def go (fn (_ l i)
      (if (not (null? l))
        (do (obj-set! v (+ i 1) (first l)) (go (rest l) (+ i 1))))))
    (go lst 0)
    v))

(def %vector-read ())

(def %vector
  (make-type
    "VECTOR"
    (list
      (pair
        (lit call)
        (fn (_ self . args)
          (def i (first args))
          (if (< i 0)
            (obj-ref self (+ (obj-ref self 0) i 1))
            (obj-ref self (+ i 1)))))
      (pair
        (lit write)
        (fn (_ self)
          (display "#(")
          (def len (obj-ref self 0))
          (def write-vec
            (fn (_ i sep)
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
        (fn (_ buffer score chr)
          (if (= chr (char->integer #\#))
            (fn (_ buffer score chr)
              (if (= chr (char->integer #\())
                (do (buffer-unread buffer) (score-set score 1 buffer))
                ()))
            ())))
      (pair (lit read) (fn (_ . args) (%vector-read (first args))))
      (pair
        (lit from)
        (list
          (pair
            (type-of (pair 1 ()))
            (fn (_ value) (%vector-from-list %vector value)))))
      (pair
        (lit to)
        (list
          (pair (type-of (pair 1 ()))
            (fn (_ self)
              (def len (obj-ref self 0))
              (def build
                (fn (_ i acc)
                  (if (< i 0) acc
                    (build (- i 1) (pair (obj-ref self (+ i 1)) acc)))))
              (build (- len 1) ())))))
      (pair
        (lit iter)
        (fn (_ self)
          (def len (obj-ref self 0))
          (def i 0)
          (fn (_ )
            (if (< i len)
              (let ((val (obj-ref self (+ i 1))))
                (set! i (+ i 1))
                val)
              ())))))))

(set! %vector-read (fn (_ . args) (%vector-from-list %vector (read))))

(note "Constructors")

(doc (def vector (fn (_ . args) (%vector-from-list %vector args)))
  (returns VECTOR "New vector containing the arguments")
  "Create a vector from the given arguments.")

(doc (def make-vector
  (fn (_ (param n INT "Number of elements")
       (param fill ANY "Value to fill each slot with"))
    (def v (make-obj %vector (+ n 1)))
    (obj-set! v 0 n)
    (def loop
      (fn (_ i)
        (if (<= i n)
          (do (obj-set! v i fill) (loop (+ i 1))))))
    (loop 1)
    v))
  (returns VECTOR "New vector of length n filled with fill")
  "Create a vector of length n, with every element set to fill.")

(note "Predicates")

(doc (def vector? (fn (_ (param x ANY "Value to test")) (type? x %vector)))
  (returns BOOL "True if x is a vector")
  "Test whether a value is a vector.")

(note "Access")

(doc (def vector-ref (fn (_ (param v VECTOR "Vector") (param i INT "Zero-based index")) (obj-ref v (+ i 1))))
  (returns ANY "Element at index i")
  "Return the element at index i of a vector.")

(doc (def vector-length (fn (_ (param v VECTOR "Vector")) (obj-ref v 0)))
  (returns INT "Number of elements")
  "Return the number of elements in a vector.")

(note "Conversion")

(doc (def vector->list (fn (_ (param v VECTOR "Vector to convert"))
  (def len (obj-ref v 0))
  (def build
    (fn (_ i acc)
      (if (< i 0) acc
        (build (- i 1) (pair (obj-ref v (+ i 1)) acc)))))
  (build (- len 1) ())))
  (returns LIST "List of the vector's elements")
  "Convert a vector to a list.")

(doc (def list->vector (fn (_ (param lst LIST "List to convert"))
  (%vector-from-list %vector lst)))
  (returns VECTOR "New vector containing the list's elements")
  "Convert a list to a vector.")

(doc (provide x/type/vector vector vector? vector-ref vector-length vector->list list->vector make-vector)
  (note "Literal syntax: #(1 2 3). Supports negative indexing.")
  (example "(vector-ref #(10 20 30) 1)" "20")
  "Fixed-size indexed vectors.")
