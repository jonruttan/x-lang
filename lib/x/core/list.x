; list.x -- List operations
(import x/core/logic)

(doc (def as-list
  (fn (_ x)
    (if (or (null? x) (pair? x)) x
      (let ((it (Iter new x)))
        (def %go (fn (self )
          (let ((v (it)))
            (if (null? v) () (pair v (self))))))
        (%go)))))
  (param x ANY "A list, nil, or iterable (e.g. vector)")
  (returns LIST "The input as a proper list")
  "Convert any iterable to a list. Lists and nil pass through unchanged.")

(note "Folds")

(doc (def fold
  (fn (self (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (let ((lst (as-list lst)))
      (if (null? lst)
        init
        (self f (f init (first lst)) (rest lst))))))
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

(doc (def map
  (fn (self (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (if (%any-null? lsts)
          ()
          (pair
            (apply f (%map1 first lsts))
            (apply self f (%map1 rest lsts))))))))
  (returns LIST "New list")
  "Apply a function to each element. Supports multiple lists.")

(doc (def filter
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst))
          (pair (first lst) (self pred (rest lst))))
        (#t (self pred (rest lst)))))))
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

(doc (def for-each
  (fn (self (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (if (not (%any-null? lsts))
          (do
            (apply f (%map1 first lsts))
            (apply self f (%map1 rest lsts))))))))
  "Apply a function to each element for side effects.")

(note "Predicates")

(note "Combinators")

(doc (def sum (fn (_ (param lst LIST "List of numbers")) (fold + 0 lst)))
  (returns INT "Sum")
  "Sum all elements of a list.")

(note "Search")

(doc (def find
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst)) (first lst))
        (#t (self pred (rest lst)))))))
  "Return the first element satisfying a predicate, or nil.")

(doc (def count
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (if (pred x) (+ acc 1) acc)) 0 lst)))
  (returns INT "Count of matching elements")
  "Count elements satisfying a predicate.")

(note "Slicing")

(doc (def take
  (fn (self (param n INT "Number of elements")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      ()
      (pair (first lst) (self (- n 1) (rest lst))))))
  "Take the first n elements of a list.")

(doc (def drop
  (fn (self (param n INT "Number of elements to skip")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      lst
      (self (- n 1) (rest lst)))))
  "Drop the first n elements of a list.")

(note "Generators")

(note "Transformation")

(doc (def sort
  (fn (self (param cmp CALLABLE "Comparison: (a b) -> #t if a comes first")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
    (def merge
      (fn (self a b)
        (match
          ((null? a) b)
          ((null? b) a)
          ((cmp (first a) (first b))
            (pair (first a) (self (rest a) b)))
          (#t (pair (first b) (self a (rest b)))))))
    (def split
      (fn (self xs a b)
        (match
          ((null? xs) (list a b))
          ((null? (rest xs)) (list (pair (first xs) a) b))
          (#t
            (self
              (rest (rest xs))
              (pair (first xs) a)
              (pair (first (rest xs)) b))))))
    (if (or (null? lst) (null? (rest lst)))
      lst
      (let ((halves (split lst () ())))
        (merge
          (self cmp (first halves))
          (self cmp (first (rest halves)))))))))
  "Merge sort a list using a comparison function.")

(note "Type predicate")

(note "Membership")

(doc (def member
  (fn (self (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (equal? x (first lst)) lst
        (self x (rest lst))))))
  "Find first occurrence by equality (equal?). Returns the tail from match, or #f.")

(note "Association")

(doc (def assoc
  (fn (self (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (equal? key (first (first alist))) (first alist)
        (self key (rest alist))))))
  "Look up a key in an alist by equality (equal?).")

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
  sum
  count
  take drop
  
  sort
  
  member assoc
  else str-copy)
  (note "Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.")
  (example "(map inc '(1 2 3))" "(2 3 4)")
  "List processing: map, filter, fold, sort, and 60+ functions.")

(doc (def as-list
  (fn (_ x)
    (if (or (null? x) (pair? x)) x
      (let ((it (Iter new x)))
        (def %go (fn (self )
          (let ((v (it)))
            (if (null? v) () (pair v (self))))))
        (%go)))))
  (param x ANY "A list, nil, or iterable (e.g. vector)")
  (returns LIST "The input as a proper list")
  "Convert any iterable to a list. Lists and nil pass through unchanged.")

(note "Folds")

(doc (def fold
  (fn (self (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (let ((lst (as-list lst)))
      (if (null? lst)
        init
        (self f (f init (first lst)) (rest lst))))))
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

(doc (def map
  (fn (self (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (if (%any-null? lsts)
          ()
          (pair
            (apply f (%map1 first lsts))
            (apply self f (%map1 rest lsts))))))))
  (returns LIST "New list")
  "Apply a function to each element. Supports multiple lists.")

(doc (def filter
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst))
          (pair (first lst) (self pred (rest lst))))
        (#t (self pred (rest lst)))))))
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

(doc (def for-each
  (fn (self (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (if (not (%any-null? lsts))
          (do
            (apply f (%map1 first lsts))
            (apply self f (%map1 rest lsts))))))))
  "Apply a function to each element for side effects.")

(note "Predicates")

(note "Combinators")

(doc (def sum (fn (_ (param lst LIST "List of numbers")) (fold + 0 lst)))
  (returns INT "Sum")
  "Sum all elements of a list.")

(note "Search")

(doc (def find
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst)) (first lst))
        (#t (self pred (rest lst)))))))
  "Return the first element satisfying a predicate, or nil.")

(doc (def count
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (if (pred x) (+ acc 1) acc)) 0 lst)))
  (returns INT "Count of matching elements")
  "Count elements satisfying a predicate.")

(note "Slicing")

(doc (def take
  (fn (self (param n INT "Number of elements")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      ()
      (pair (first lst) (self (- n 1) (rest lst))))))
  "Take the first n elements of a list.")

(doc (def drop
  (fn (self (param n INT "Number of elements to skip")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      lst
      (self (- n 1) (rest lst)))))
  "Drop the first n elements of a list.")

(note "Generators")

(note "Transformation")

(doc (def sort
  (fn (self (param cmp CALLABLE "Comparison: (a b) -> #t if a comes first")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
    (def merge
      (fn (self a b)
        (match
          ((null? a) b)
          ((null? b) a)
          ((cmp (first a) (first b))
            (pair (first a) (self (rest a) b)))
          (#t (pair (first b) (self a (rest b)))))))
    (def split
      (fn (self xs a b)
        (match
          ((null? xs) (list a b))
          ((null? (rest xs)) (list (pair (first xs) a) b))
          (#t
            (self
              (rest (rest xs))
              (pair (first xs) a)
              (pair (first (rest xs)) b))))))
    (if (or (null? lst) (null? (rest lst)))
      lst
      (let ((halves (split lst () ())))
        (merge
          (self cmp (first halves))
          (self cmp (first (rest halves)))))))))
  "Merge sort a list using a comparison function.")

(note "Type predicate")

(note "Membership")

(doc (def member
  (fn (self (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (equal? x (first lst)) lst
        (self x (rest lst))))))
  "Find first occurrence by equality (equal?). Returns the tail from match, or #f.")

(note "Association")

(doc (def assoc
  (fn (self (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (equal? key (first (first alist))) (first alist)
        (self key (rest alist))))))
  "Look up a key in an alist by equality (equal?).")

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
  sum
  find count
  take drop
  
  sort
  
  member assoc
  else str-copy)
  (note "Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.")
  (example "(map inc '(1 2 3))" "(2 3 4)")
  "List processing: map, filter, fold, sort, and 60+ functions.")
