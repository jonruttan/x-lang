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

(doc (def reduce
  (fn (_ (param f CALLABLE "Binary function")
       (param lst LIST "Non-empty list or iterable"))
    (let ((lst (as-list lst))) (fold f (first lst) (rest lst)))))
  "Fold without an initial value; uses the first element.")

(note "Basics")

(doc (def length
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc _) (+ acc 1)) 0 lst)))
  "Return the number of elements.")

(doc (def nth
  (fn (self (param n INT "Zero-based index")
       (param lst LIST "List"))
    (if (= n 0) (first lst) (self (- n 1) (rest lst)))))
  "Return the element at index n (zero-based).")

(doc (def last
  (fn (self (param lst LIST "Non-empty list"))
    (if (null? (rest lst)) (first lst) (self (rest lst)))))
  "Return the last element of a list.")

(doc (def init
  (fn (self (param lst LIST "Non-empty list"))
    (if (null? (rest lst))
      ()
      (pair (first lst) (self (rest lst))))))
  "Return all elements except the last.")

(def %append2
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))

(doc (def append (fn (_ . args) (fold %append2 () args)))
  "Concatenate zero or more lists.")

(doc (def reverse
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (pair x acc)) () lst)))
  "Reverse a list.")

(doc (def flatten
  (fn (self (param lst LIST "Nested list"))
    (match
      ((null? lst) ())
      ((pair? (first lst))
        (%append2 (self (first lst)) (self (rest lst))))
      (#t (pair (first lst) (self (rest lst)))))))
  "Recursively flatten nested lists into a single list.")

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

(doc (def any?
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #f)
        ((pred (first lst)) #t)
        (#t (self pred (rest lst)))))))
  "Return #t if any element satisfies the predicate.")

(doc (def every?
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #t)
        ((not (pred (first lst))) #f)
        (#t (self pred (rest lst)))))))
  "Return #t if all elements satisfy the predicate.")

(doc (def none?
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (not (any? pred lst))))
  "Return #t if no element satisfies the predicate.")

(doc (def empty? (fn (_ (param lst LIST "List")) (null? lst)))
  "Return #t if the list is empty.")

(note "Combinators")

(doc (def complement
  (fn (_ (param pred CALLABLE "Predicate to negate"))
    (fn (_ . args) (not (apply pred args)))))
  (returns CALLABLE "Negated predicate")
  "Return a function that negates a predicate.")

(doc (def partial
  (fn (_ (param f CALLABLE "Function to partially apply") . (param bound ANY "Bound arguments"))
    (fn (_ . args) (apply f (append bound args)))))
  (returns CALLABLE "Partially applied function")
  "Partially apply a function with leading arguments.")

(doc (def juxt
  (fn (_ . fns) (fn (_ . args) (map (fn (_ f) (apply f args)) fns))))
  (returns CALLABLE "Juxtaposed function")
  "Create a function that applies multiple functions and collects results.")

(doc (def both
  (fn (_ (param f CALLABLE "First predicate")
       (param g CALLABLE "Second predicate"))
    (fn (_ x) (and (f x) (g x)))))
  (returns CALLABLE "Combined predicate")
  "Combine two predicates with AND.")

(doc (def either
  (fn (_ (param f CALLABLE "First predicate")
       (param g CALLABLE "Second predicate"))
    (fn (_ x) (or (f x) (g x)))))
  (returns CALLABLE "Combined predicate")
  "Combine two predicates with OR.")

(doc (def all-pass
  (fn (_ (param preds LIST "List of predicates"))
    (fn (_ x) (every? (fn (_ p) (p x)) preds))))
  (returns CALLABLE "Combined predicate")
  "Return a predicate that passes when all predicates pass.")

(doc (def any-pass
  (fn (_ (param preds LIST "List of predicates"))
    (fn (_ x) (any? (fn (_ p) (p x)) preds))))
  (returns CALLABLE "Combined predicate")
  "Return a predicate that passes when any predicate passes.")

(doc (def reject
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (filter (complement pred) lst)))
  (returns LIST "Filtered list")
  "Return elements that do NOT satisfy a predicate.")

(doc (def concat (fn (_ . lsts) (apply append lsts)))
  (returns LIST "Concatenated list")
  "Concatenate all argument lists into one.")

(doc (def sum (fn (_ (param lst LIST "List of numbers")) (fold + 0 lst)))
  (returns INT "Sum")
  "Sum all elements of a list.")

(doc (def product (fn (_ (param lst LIST "List of numbers")) (fold * 1 lst)))
  (returns INT "Product")
  "Multiply all elements of a list.")

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

(doc (def find-index
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (def go
        (fn (self i xs)
          (match
            ((null? xs) (- 0 1))
            ((pred (first xs)) i)
            (#t (self (+ i 1) (rest xs))))))
      (go 0 lst))))
  (returns INT "Index, or -1 if not found")
  "Return the index of the first element satisfying a predicate.")

(doc (def index-of
  (fn (_ (param x ANY "Value to find")
       (param lst LIST "List"))
    (find-index (fn (_ el) (equal? el x)) lst)))
  (returns INT "Index, or -1 if not found")
  "Return the index of the first occurrence of a value.")

(doc (def includes?
  (fn (self (param x ANY "Value to search for")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #f)
        ((equal? x (first lst)) #t)
        (#t (self x (rest lst)))))))
  (returns BOOLEAN "t if found")
  "Test if a list contains a value.")

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

(doc (def take-while
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (if (or (null? lst) (not (pred (first lst))))
      ()
      (pair (first lst) (self pred (rest lst))))))
  "Take elements from the front while predicate holds.")

(doc (def drop-while
  (fn (self (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((pred (first lst)) (self pred (rest lst)))
      (#t lst))))
  "Drop elements from the front while predicate holds.")

(doc (def split-at
  (fn (_ (param n INT "Split position")
       (param lst LIST "List"))
    (list (take n lst) (drop n lst))))
  (returns LIST "Pair of (taken dropped)")
  "Split a list at position n.")

(doc (def slice
  (fn (_ (param start INT "Start index (inclusive)")
       (param end INT "End index (exclusive)")
       (param lst LIST "List"))
    (take (- end start) (drop start lst))))
  "Extract a slice from start to end.")

(note "Generators")

(doc (def range
  (fn (self (param start INT "Start value (inclusive)")
       (param end INT "End value (exclusive)"))
    (if (>= start end) () (pair start (self (+ start 1) end)))))
  (returns LIST "List of integers")
  (example "(range 0 5)" "(0 1 2 3 4)")
  "Generate a list of integers from start to end.")

(doc (def repeat
  (fn (self (param x ANY "Value to repeat")
       (param n INT "Number of repetitions"))
    (if (<= n 0) () (pair x (self x (- n 1))))))
  (returns LIST "List of repeated values")
  "Create a list of n copies of a value.")

(doc (def times
  (fn (_ (param f CALLABLE "Function: index -> value")
       (param n INT "Number of iterations"))
    (def go
      (fn (self i) (if (>= i n) () (pair (f i) (self (+ i 1))))))
    (go 0)))
  (returns LIST "List of results")
  "Apply a function to each index 0..n-1, collecting results.")

(doc (def iterate
  (fn (self (param f CALLABLE "Step function")
       (param n INT "Number of iterations")
       (param x ANY "Initial value"))
    (if (<= n 0) () (pair x (self f (- n 1) (f x))))))
  (returns LIST "List of iterated values")
  "Generate n values by repeatedly applying f.")

(doc (def zip
  (fn (self (param a LIST "First list")
       (param b LIST "Second list"))
    (if (or (null? a) (null? b))
      ()
      (pair (list (first a) (first b)) (self (rest a) (rest b))))))
  (returns LIST "List of pairs")
  "Pair up corresponding elements from two lists.")

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

(doc (def uniq
  (fn (self (param lst LIST "Sorted list"))
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (first lst) (first (rest lst))) (self (rest lst)))
      (#t (pair (first lst) (self (rest lst)))))))
  "Remove consecutive duplicates from a sorted list.")

(doc (def intersperse
  (fn (self (param sep ANY "Separator element")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      (#t
        (pair (first lst) (pair sep (self sep (rest lst))))))))
  "Insert a separator between each element.")

(doc (def update
  (fn (self (param n INT "Index to update")
       (param val ANY "New value")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((= n 0) (pair val (rest lst)))
      (#t (pair (first lst) (self (- n 1) val (rest lst)))))))
  "Replace the element at index n.")

(doc (def insert
  (fn (self (param n INT "Insertion index")
       (param val ANY "Value to insert")
       (param lst LIST "List"))
    (if (<= n 0)
      (pair val lst)
      (pair (first lst) (self (- n 1) val (rest lst))))))
  "Insert a value at index n.")

(doc (def remove
  (fn (self (param start INT "Start index")
       (param n INT "Number of elements to remove")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((> start 0)
        (pair (first lst) (self (- start 1) n (rest lst))))
      ((> n 0) (self 0 (- n 1) (rest lst)))
      (#t lst))))
  "Remove n elements starting at index.")

(doc (def adjust
  (fn (self (param n INT "Index to adjust")
       (param f CALLABLE "Transformation function")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((= n 0) (pair (f (first lst)) (rest lst)))
      (#t (pair (first lst) (self (- n 1) f (rest lst)))))))
  "Apply a function to the element at index n.")

(note "Type predicate")

(doc (def list?
  (fn (self (param x ANY "Value to test"))
    (if (null? x) #t (if (pair? x) (self (rest x)) #f))))
  (returns BOOLEAN "t if proper list")
  "Test if a value is a proper list.")

(note "Membership")

(doc (def memq
  (fn (self (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (eq? x (first lst)) lst
        (self x (rest lst))))))
  "Find first occurrence by identity (eq?). Returns the tail from match, or #f.")

(doc (def member
  (fn (self (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (equal? x (first lst)) lst
        (self x (rest lst))))))
  "Find first occurrence by equality (equal?). Returns the tail from match, or #f.")

(note "Association")

(doc (def assq
  (fn (self (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (eq? key (first (first alist))) (first alist)
        (self key (rest alist))))))
  "Look up a key in an alist by identity (eq?).")

(doc (def assoc
  (fn (self (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (equal? key (first (first alist))) (first alist)
        (self key (rest alist))))))
  "Look up a key in an alist by equality (equal?).")

; --- Convenience aliases ---

(doc (def second (fn (_ x) (first (rest x))))
  (param x LIST "A list with at least two elements")
  (returns ANY "The second element")
  "Return the second element of a list.")

(doc (def third (fn (_ x) (first (rest (rest x)))))
  (param x LIST "A list with at least three elements")
  (returns ANY "The third element")
  "Return the third element of a list.")

(doc (def else #t)
  "Alias for #t, for use as the default clause in cond/case.")

; --- Compatibility aliases ---

(doc (def list-ref (fn (_ lst n) (nth n lst)))
  (param lst LIST "List to index")
  (param n INTEGER "Zero-based index")
  (returns ANY "The element at index n")
  "Return the nth element of a list (Scheme compatibility).")

(doc (def list-tail (fn (_ lst n) (drop n lst)))
  (param lst LIST "List to take tail of")
  (param n INTEGER "Number of elements to skip")
  (returns LIST "The remaining list after dropping n elements")
  "Return the tail of a list after n elements (Scheme compatibility).")

(doc (def str-copy (fn (_ s) (substring s 0 (str-length s))))
  (param s STRING "String to copy")
  (returns STRING "A copy of the string")
  "Return a copy of a string (Scheme compatibility).")

(doc (provide x/core/list
  as-list fold reduce length nth last init append reverse flatten
  map filter for-each any? every? none? empty?
  complement partial juxt both either all-pass any-pass reject concat sum product
  find find-index index-of includes? count
  take drop take-while drop-while split-at slice
  range repeat times iterate zip
  sort uniq intersperse
  update insert remove adjust
  list? memq member assq assoc
  second third else list-ref list-tail str-copy)
  (note "Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.")
  (example "(map inc '(1 2 3))" "(2 3 4)")
  "List processing: map, filter, fold, sort, and 60+ functions.")
