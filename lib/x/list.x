; list.x -- List operations
(import x/logic)

; Convert any iterable to a list. Lists/nil pass through unchanged.
; Note: iter-based path may not work for all types yet
(def as-list
  (fn (_ x)
    (if (or (null? x) (pair? x)) x
      (let ((it (iter x)))
        (def %go (fn (_ )
          (let ((v (it)))
            (if (null? v) () (pair v (%go))))))
        (%go)))))

(note "Folds")

(doc (def fold
  (fn (_ (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (let ((lst (as-list lst)))
      (if (null? lst)
        init
        (fold f (f init (first lst)) (rest lst))))))
  (returns ANY "Final accumulated value")
  (example "(fold + 0 '(1 2 3))" "6")
  "Fold a function over a list from the left.")

(doc (def reduce
  (fn (_ (param f CALLABLE "Binary function")
       (param lst LIST "Non-empty list or iterable"))
    (let ((lst (as-list lst))) (fold f (first lst) (rest lst)))))
  "Fold without an initial value; uses the first element.")

(doc (def scan
  (fn (_ (param f CALLABLE "Binary function")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (if (null? lst)
        (list init)
        (pair init (scan f (f init (first lst)) (rest lst)))))))
  "Like fold, but returns a list of all intermediate values.")

(note "Basics")

(doc (def length
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (+ acc 1)) 0 lst)))
  "Return the number of elements.")

(doc (def nth
  (fn (_ (param n INT "Zero-based index")
       (param lst LIST "List"))
    (if (= n 0) (first lst) (nth (- n 1) (rest lst)))))
  "Return the element at index n (zero-based).")

(doc (def last
  (fn (_ (param lst LIST "Non-empty list"))
    (if (null? (rest lst)) (first lst) (last (rest lst)))))
  "Return the last element of a list.")

(doc (def init
  (fn (_ (param lst LIST "Non-empty list"))
    (if (null? (rest lst))
      ()
      (pair (first lst) (init (rest lst))))))
  "Return all elements except the last.")

(def %append2
  (fn (_ a b)
    (if (null? a) b (pair (first a) (%append2 (rest a) b)))))

(doc (def append (fn (_ . args) (fold %append2 () args)))
  "Concatenate zero or more lists.")

(doc (def prepend
  (fn (_ (param x ANY "Element to prepend")
       (param lst LIST "List"))
    (pair x lst)))
  "Add an element to the front of a list.")

(doc (def reverse
  (fn (_ (param lst LIST "List or iterable"))
    (fold (fn (_ acc x) (pair x acc)) () lst)))
  "Reverse a list.")

(doc (def flatten
  (fn (_ (param lst LIST "Nested list"))
    (match
      ((null? lst) ())
      ((pair? (first lst))
        (%append2 (flatten (first lst)) (flatten (rest lst))))
      (#t (pair (first lst) (flatten (rest lst)))))))
  "Recursively flatten nested lists into a single list.")

(note "Iteration")

(def %any-null?
  (fn (_ lsts)
    (if (null? lsts)
      ()
      (if (null? (first lsts)) #t (%any-null? (rest lsts))))))

(def %map1
  (fn (_ f lst)
    (if (null? lst)
      ()
      (pair (f (first lst)) (%map1 f (rest lst))))))

(doc (def map
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (if (%any-null? lsts)
          ()
          (pair
            (apply f (%map1 first lsts))
            (apply map f (%map1 rest lsts))))))))
  (returns LIST "New list")
  "Apply a function to each element. Supports multiple lists.")

(doc (def filter
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst))
          (pair (first lst) (filter pred (rest lst))))
        (#t (filter pred (rest lst)))))))
  (returns LIST "Filtered list")
  "Return elements that satisfy a predicate.")

(def %for-each1
  (fn (_ f lst)
    (if (null? lst) ()
      (if (pair? lst)
        (do (f (first lst)) (%for-each1 f (rest lst)))
        (let ((it (iter lst)))
          (def %iter-loop
            (fn (_ )
              (let ((val (it)))
                (if (not (null? val))
                  (do (f val) (%iter-loop))))))
          (%iter-loop))))))

(doc (def for-each
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (if (not (%any-null? lsts))
          (do
            (apply f (%map1 first lsts))
            (apply for-each f (%map1 rest lsts))))))))
  "Apply a function to each element for side effects.")

(doc (def flat-map
  (fn (_ (param f CALLABLE "Function returning a list")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (if (null? lst)
        ()
        (%append2 (f (first lst)) (flat-map f (rest lst)))))))
  "Map then flatten one level.")

(note "Predicates")

(doc (def any?
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #f)
        ((pred (first lst)) #t)
        (#t (any? pred (rest lst)))))))
  "Return #t if any element satisfies the predicate.")

(doc (def every?
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #t)
        ((not (pred (first lst))) #f)
        (#t (every? pred (rest lst)))))))
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
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst)) (first lst))
        (#t (find pred (rest lst)))))))
  "Return the first element satisfying a predicate, or nil.")

(doc (def find-index
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (def go
        (fn (_ i lst)
          (match
            ((null? lst) (- 0 1))
            ((pred (first lst)) i)
            (#t (go (+ i 1) (rest lst))))))
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
  (fn (_ (param x ANY "Value to search for")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
      (match
        ((null? lst) #f)
        ((equal? x (first lst)) #t)
        (#t (includes? x (rest lst)))))))
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
  (fn (_ (param n INT "Number of elements")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      ()
      (pair (first lst) (take (- n 1) (rest lst))))))
  "Take the first n elements of a list.")

(doc (def drop
  (fn (_ (param n INT "Number of elements to skip")
       (param lst LIST "List"))
    (if (or (<= n 0) (null? lst))
      lst
      (drop (- n 1) (rest lst)))))
  "Drop the first n elements of a list.")

(doc (def take-while
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (if (or (null? lst) (not (pred (first lst))))
      ()
      (pair (first lst) (take-while pred (rest lst))))))
  "Take elements from the front while predicate holds.")

(doc (def drop-while
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((pred (first lst)) (drop-while pred (rest lst)))
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
  (fn (_ (param start INT "Start value (inclusive)")
       (param end INT "End value (exclusive)"))
    (if (>= start end) () (pair start (range (+ start 1) end)))))
  (returns LIST "List of integers")
  (example "(range 0 5)" "(0 1 2 3 4)")
  "Generate a list of integers from start to end.")

(doc (def repeat
  (fn (_ (param x ANY "Value to repeat")
       (param n INT "Number of repetitions"))
    (if (<= n 0) () (pair x (repeat x (- n 1))))))
  (returns LIST "List of repeated values")
  "Create a list of n copies of a value.")

(doc (def times
  (fn (_ (param f CALLABLE "Function: index -> value")
       (param n INT "Number of iterations"))
    (def go
      (fn (_ i) (if (>= i n) () (pair (f i) (go (+ i 1))))))
    (go 0)))
  (returns LIST "List of results")
  "Apply a function to each index 0..n-1, collecting results.")

(doc (def unfold
  (fn (_ (param pred CALLABLE "Stop predicate: seed -> boolean")
       (param f CALLABLE "Value function: seed -> element")
       (param g CALLABLE "Step function: seed -> next-seed")
       (param seed ANY "Initial seed value"))
    (if (pred seed)
      ()
      (pair (f seed) (unfold pred f g (g seed))))))
  (returns LIST "Generated list")
  "Build a list by repeatedly applying step and value functions to a seed.")

(doc (def iterate
  (fn (_ (param f CALLABLE "Step function")
       (param n INT "Number of iterations")
       (param x ANY "Initial value"))
    (if (<= n 0) () (pair x (iterate f (- n 1) (f x))))))
  (returns LIST "List of iterated values")
  "Generate n values by repeatedly applying f.")

(doc (def zip
  (fn (_ (param a LIST "First list")
       (param b LIST "Second list"))
    (if (or (null? a) (null? b))
      ()
      (pair (list (first a) (first b)) (zip (rest a) (rest b))))))
  (returns LIST "List of pairs")
  "Pair up corresponding elements from two lists.")

(doc (def zip-with
  (fn (_ (param f CALLABLE "Combining function")
       (param a LIST "First list")
       (param b LIST "Second list"))
    (if (or (null? a) (null? b))
      ()
      (pair
        (f (first a) (first b))
        (zip-with f (rest a) (rest b))))))
  (returns LIST "Combined list")
  "Combine corresponding elements from two lists using a function.")

(note "Transformation")

(doc (def partition
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (def go
      (fn (_ lst yes no)
        (match
          ((null? lst) (list (reverse yes) (reverse no)))
          ((pred (first lst))
            (go (rest lst) (pair (first lst) yes) no))
          (#t (go (rest lst) yes (pair (first lst) no))))))
    (go lst () ())))
  "Split a list into elements that match and don't match a predicate.")

(doc (def group-by
  (fn (_ (param f CALLABLE "Key function: element -> group key")
       (param lst LIST "List"))
    (def add-to-group
      (fn (_ alist key val)
        (match
          ((null? alist) (list (pair key (list val))))
          ((eq? (first (first alist)) key)
            (pair
              (pair key (append (rest (first alist)) (list val)))
              (rest alist)))
          (#t
            (pair (first alist) (add-to-group (rest alist) key val))))))
    (fold (fn (_ acc x) (add-to-group acc (f x) x)) () lst)))
  (returns LIST "Alist of (key . elements)")
  "Group list elements by a key function.")

(doc (def sort
  (fn (_ (param cmp CALLABLE "Comparison: (a b) -> #t if a comes first")
       (param lst LIST "List or iterable"))
    (let ((lst (as-list lst)))
    (def merge
      (fn (_ a b)
        (match
          ((null? a) b)
          ((null? b) a)
          ((cmp (first a) (first b))
            (pair (first a) (merge (rest a) b)))
          (#t (pair (first b) (merge a (rest b)))))))
    (def split
      (fn (_ lst a b)
        (match
          ((null? lst) (list a b))
          ((null? (rest lst)) (list (pair (first lst) a) b))
          (#t
            (split
              (rest (rest lst))
              (pair (first lst) a)
              (pair (first (rest lst)) b))))))
    (if (or (null? lst) (null? (rest lst)))
      lst
      (let ((halves (split lst () ())))
        (merge
          (sort cmp (first halves))
          (sort cmp (first (rest halves)))))))))
  "Merge sort a list using a comparison function.")


(doc (def sort-by
  (fn (_ (param f CALLABLE "Key function: element -> comparable value")
       (param lst LIST "List"))
    (sort (fn (_ a b) (< (f a) (f b))) lst)))
  "Sort by a key function (ascending).")

(doc (def uniq
  (fn (_ (param lst LIST "Sorted list"))
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (first lst) (first (rest lst))) (uniq (rest lst)))
      (#t (pair (first lst) (uniq (rest lst)))))))
  "Remove consecutive duplicates from a sorted list.")

(doc (def uniq-by
  (fn (_ (param f CALLABLE "Key function")
       (param lst LIST "Sorted list"))
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (f (first lst)) (f (first (rest lst))))
        (uniq-by f (rest lst)))
      (#t (pair (first lst) (uniq-by f (rest lst)))))))
  "Remove consecutive duplicates by key function.")

(doc (def intersperse
  (fn (_ (param sep ANY "Separator element")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      (#t
        (pair (first lst) (pair sep (intersperse sep (rest lst))))))))
  "Insert a separator between each element.")

(doc (def transpose
  (fn (_ (param lsts LIST "List of lists"))
    (if (or (null? lsts) (any? null? lsts))
      ()
      (pair (map first lsts) (transpose (map rest lsts))))))
  (returns LIST "Transposed list of lists")
  "Transpose rows and columns of a list of lists.")

(doc (def update
  (fn (_ (param n INT "Index to update")
       (param val ANY "New value")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((= n 0) (pair val (rest lst)))
      (#t (pair (first lst) (update (- n 1) val (rest lst)))))))
  "Replace the element at index n.")

(doc (def insert
  (fn (_ (param n INT "Insertion index")
       (param val ANY "Value to insert")
       (param lst LIST "List"))
    (if (<= n 0)
      (pair val lst)
      (pair (first lst) (insert (- n 1) val (rest lst))))))
  "Insert a value at index n.")

(doc (def remove
  (fn (_ (param start INT "Start index")
       (param n INT "Number of elements to remove")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((> start 0)
        (pair (first lst) (remove (- start 1) n (rest lst))))
      ((> n 0) (remove 0 (- n 1) (rest lst)))
      (#t lst))))
  "Remove n elements starting at index.")

(doc (def adjust
  (fn (_ (param n INT "Index to adjust")
       (param f CALLABLE "Transformation function")
       (param lst LIST "List"))
    (match
      ((null? lst) ())
      ((= n 0) (pair (f (first lst)) (rest lst)))
      (#t (pair (first lst) (adjust (- n 1) f (rest lst)))))))
  "Apply a function to the element at index n.")

(note "Type predicate")

(doc (def list?
  (fn (_ (param x ANY "Value to test"))
    (if (null? x) #t (if (pair? x) (list? (rest x)) #f))))
  (returns BOOLEAN "t if proper list")
  "Test if a value is a proper list.")

(note "Membership")

(doc (def memq
  (fn (_ (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (eq? x (first lst)) lst
        (memq x (rest lst))))))
  "Find first occurrence by identity (eq?). Returns the tail from match, or #f.")

(doc (def member
  (fn (_ (param x ANY "Value to search for")
       (param lst LIST "List"))
    (if (null? lst) #f
      (if (equal? x (first lst)) lst
        (member x (rest lst))))))
  "Find first occurrence by equality (equal?). Returns the tail from match, or #f.")

(note "Association")

(doc (def assq
  (fn (_ (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (eq? key (first (first alist))) (first alist)
        (assq key (rest alist))))))
  "Look up a key in an alist by identity (eq?).")

(doc (def assoc
  (fn (_ (param key ANY "Key to search for")
       (param alist LIST "Association list"))
    (if (null? alist) #f
      (if (equal? key (first (first alist))) (first alist)
        (assoc key (rest alist))))))
  "Look up a key in an alist by equality (equal?).")

(doc (provide x/list
  as-list fold reduce scan length nth last init append prepend reverse flatten
  map filter for-each flat-map any? every? none? empty?
  complement partial juxt both either all-pass any-pass reject concat sum product
  find find-index index-of includes? count
  take drop take-while drop-while split-at slice
  range repeat times unfold iterate zip zip-with
  partition group-by sort sort-by uniq uniq-by intersperse transpose
  update insert remove adjust
  list? memq member assq assoc)
  (note "Accepts any iterable (lists, vectors, custom iterables). Ramda-inspired functional style.")
  (example "(map inc '(1 2 3))" "(2 3 4)")
  "List processing: map, filter, fold, sort, and 60+ functions.")
