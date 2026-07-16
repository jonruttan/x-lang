; list.x -- List operations
(import x/core/logic)

(doc (def as-list
  (fn (_ x)
    ; Nested if, NOT `or`: or is an expand-per-evaluation macro (~330
    ; objects each time), and this fast path runs inside every fold/map
    ; step in the system (the 2026-07-16 arithmetic-disease probes).
    (if (null? x) x
      (if (pair? x) x
        (let ((it (Iter new x)))
          (def %go (fn (self )
            (let ((v (it)))
              (if (null? v) () (pair v (self))))))
          (%go))))))
  (param x ANY "A list, nil, or iterable (e.g. vector)")
  (returns LIST "The input as a proper list")
  "Convert any iterable to a list. Lists and nil pass through unchanged.")

(note "Folds")

; The already-normalized loop: as-list runs ONCE in the public entry.
; The old self-recursion re-entered through (let ((lst (as-list lst))))
; on EVERY step -- ~575 objects per element, multiplied through the
; arithmetic wrappers into the system-wide allocation disease.
(def %fold-go
  (fn (self f acc lst)
    (if (null? lst) acc
      (self f (f acc (first lst)) (rest lst)))))

(doc (def fold
  (fn (_ (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (%fold-go f init (as-list lst))))
  (returns ANY "Final accumulated value")
  (example "(fold + 0 '(1 2 3))" "6")
  "Fold a function over a list from the left.")

(note "Basics")

(doc (def length
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc _) (+ acc 1)) 0 lst)))
  "Return the number of elements.")

(def %append2
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))

(doc (def append (fn (_ . args) (fold %append2 () args)))
  "Concatenate zero or more lists.")

(doc (def reverse
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (pair x acc)) () lst)))
  "Reverse a list.")

(note "Iteration")

(def %any-null?
  (fn (self lsts)
    (if (null? lsts)
      ()
      (if (null? (first lsts)) #t (self (rest lsts))))))

(def %map1
  (fn (self f lst)
    (if (null? lst)
      ()
      (pair (f (first lst)) (self f (rest lst))))))

; Multi-list loop, inputs already normalized (the old recursion went
; back through the public entry, re-as-listing every tail per step).
(def %mapn-go
  (fn (self f lsts)
    (if (%any-null? lsts)
      ()
      (pair
        (apply f (%map1 first lsts))
        (self f (%map1 rest lsts))))))

(doc (def map
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (%mapn-go f lsts)))))
  (returns LIST "New list")
  "Apply a function to each element. Supports multiple lists.")

; Already-normalized loop; see %fold-go.
(def %filter-go
  (fn (self pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst))
        (pair (first lst) (self pred (rest lst))))
      (#t (self pred (rest lst))))))

(doc (def filter
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (%filter-go pred (as-list lst))))
  (returns LIST "Filtered list")
  "Return elements that satisfy a predicate.")

(def %for-each1
  (fn (self f lst)
    (if (null? lst) ()
      (if (pair? lst)
        (do (f (first lst)) (self f (rest lst)))
        (let ((it (Iter new lst)))
          (def %iter-loop
            (fn (self )
              (let ((val (it)))
                (if (not (null? val))
                  (do (f val) (self))))))
          (%iter-loop))))))

; Multi-list loop, inputs already normalized; see %mapn-go.
(def %for-eachn-go
  (fn (self f lsts)
    (if (not (%any-null? lsts))
      (do
        (apply f (%map1 first lsts))
        (self f (%map1 rest lsts))))))

(doc (def for-each
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (%for-eachn-go f lsts)))))
  "Apply a function to each element for side effects.")

(note "Predicates")

(note "Combinators")

(note "Search")

(note "Slicing")

(note "Generators")

(note "Transformation")

(note "Type predicate")

(note "Membership")

(note "Association")

; --- Convenience aliases ---

(doc (def else #t)
  "Alias for #t, for use as the default clause in cond/case.")

; --- Compatibility aliases ---

(doc (def str-copy (fn (_ s) (substring s 0 (str-length s))))
  (param s STRING "String to copy")
  (returns STRING "A copy of the string")
  "Return a copy of a string (Scheme compatibility).")

(doc (provide x/core/list
  as-list fold length append reverse
  map filter for-each
  
  
  
  
  
  
  
  else str-copy)
  (note "Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.")
  (example "(map (method-ref Num inc) '(1 2 3))" "(2 3 4)")
  "List processing: map, filter, fold, sort, and 60+ functions.")
