; list.x -- List operations
(import x/logic)

; Convert any iterable to a list. Lists/nil pass through unchanged.
(def %as-list
  (fn (x)
    (if (or (null? x) (pair? x)) x
      (let ((it (iter x)))
        (def %go (fn ()
          (let ((v (it)))
            (if (null? v) () (pair v (%go))))))
        (%go)))))

(note "Folds")

(doc (def fold
  (fn ((param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (let ((lst (%as-list lst)))
      (if (null? lst)
        init
        (fold f (f init (first lst)) (rest lst))))))
  (returns ANY "Final accumulated value")
  (example "(fold + 0 '(1 2 3))" "6")
  "Fold a function over a list from the left.")

(doc (def reduce
  (fn ((param f CALLABLE "Binary function")
       (param lst LIST "Non-empty list or iterable"))
    (let ((lst (%as-list lst))) (fold f (first lst) (rest lst)))))
  "Fold without an initial value; uses the first element.")

(doc (def scan
  (fn ((param f CALLABLE "Binary function")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (if (null? lst)
        (list init)
        (pair init (scan f (f init (first lst)) (rest lst)))))))
  "Like fold, but returns a list of all intermediate values.")

(note "Basics")

(doc (def length
  (fn ((param lst LIST "List or iterable"))
    (fold (fn (acc x) (+ acc 1)) 0 lst)))
  "Return the number of elements.")

(doc (def nth
  (fn ((param n INT "Zero-based index")
       (param lst LIST "List"))
    (if (= n 0) (first lst) (nth (- n 1) (rest lst)))))
  "Return the element at index n (zero-based).")

(doc (def last
  (fn ((param lst LIST "Non-empty list"))
    (if (null? (rest lst)) (first lst) (last (rest lst)))))
  "Return the last element of a list.")

(doc (def init
  (fn ((param lst LIST "Non-empty list"))
    (if (null? (rest lst))
      ()
      (pair (first lst) (init (rest lst))))))
  "Return all elements except the last.")

(def %append2
  (fn (a b)
    (if (null? a) b (pair (first a) (%append2 (rest a) b)))))

(doc (def append (fn args (fold %append2 () args)))
  "Concatenate zero or more lists.")

(doc (def prepend
  (fn ((param x ANY "Element to prepend")
       (param lst LIST "List"))
    (pair x lst)))
  "Add an element to the front of a list.")

(doc (def reverse
  (fn ((param lst LIST "List or iterable"))
    (fold (fn (acc x) (pair x acc)) () lst)))
  "Reverse a list.")

(doc (def flatten
  (fn ((param lst LIST "Nested list"))
    (match
      ((null? lst) ())
      ((pair? (first lst))
        (%append2 (flatten (first lst)) (flatten (rest lst))))
      (#t (pair (first lst) (flatten (rest lst)))))))
  "Recursively flatten nested lists into a single list.")

(note "Iteration")

(def %any-null?
  (fn (lsts)
    (if (null? lsts)
      ()
      (if (null? (first lsts)) #t (%any-null? (rest lsts))))))

(def %map1
  (fn (f lst)
    (if (null? lst)
      ()
      (pair (f (first lst)) (%map1 f (rest lst))))))

(doc (def map
  (fn ((param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 %as-list lsts)))
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
  (fn ((param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst))
          (pair (first lst) (filter pred (rest lst))))
        (#t (filter pred (rest lst)))))))
  (returns LIST "Filtered list")
  "Return elements that satisfy a predicate.")

(def %for-each1
  (fn (f lst)
    (if (null? lst) ()
      (if (pair? lst)
        (do (f (first lst)) (%for-each1 f (rest lst)))
        (let ((it (iter lst)))
          (def %iter-loop
            (fn ()
              (let ((val (it)))
                (if (not (null? val))
                  (do (f val) (%iter-loop))))))
          (%iter-loop))))))

(doc (def for-each
  (fn ((param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 %as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (if (not (%any-null? lsts))
          (do
            (apply f (%map1 first lsts))
            (apply for-each f (%map1 rest lsts))))))))
  "Apply a function to each element for side effects.")

(doc (def flat-map
  (fn ((param f CALLABLE "Function returning a list")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (if (null? lst)
        ()
        (%append2 (f (first lst)) (flat-map f (rest lst)))))))
  "Map then flatten one level.")

(note "Predicates")

(doc (def any?
  (fn ((param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (match
        ((null? lst) #f)
        ((pred (first lst)) #t)
        (#t (any? pred (rest lst)))))))
  "Return #t if any element satisfies the predicate.")

(doc (def every?
  (fn ((param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (match
        ((null? lst) #t)
        ((not (pred (first lst))) #f)
        (#t (every? pred (rest lst)))))))
  "Return #t if all elements satisfy the predicate.")

(def none? (fn (pred lst) (not (any? pred lst))))

(def empty? (fn (lst) (null? lst)))

(note "Combinators")

(def complement
  (fn (pred) (fn args (not (apply pred args)))))

(def partial
  (fn (f . bound) (fn args (apply f (append bound args)))))

(def juxt
  (fn fns (fn args (map (fn (f) (apply f args)) fns))))

(def both (fn (f g) (fn (x) (and (f x) (g x)))))

(def either (fn (f g) (fn (x) (or (f x) (g x)))))

(def all-pass
  (fn (preds) (fn (x) (every? (fn (p) (p x)) preds))))

(def any-pass
  (fn (preds) (fn (x) (any? (fn (p) (p x)) preds))))

(def reject (fn (pred lst) (filter (complement pred) lst)))

(def concat (fn lsts (apply append lsts)))

(def sum (fn (lst) (fold + 0 lst)))

(def product (fn (lst) (fold * 1 lst)))

(note "Search")

(doc (def find
  (fn ((param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
      (match
        ((null? lst) ())
        ((pred (first lst)) (first lst))
        (#t (find pred (rest lst)))))))
  "Return the first element satisfying a predicate, or nil.")

(def find-index
  (fn (pred lst)
    (let ((lst (%as-list lst)))
      (def go
        (fn (i lst)
          (match
            ((null? lst) (- 0 1))
            ((pred (first lst)) i)
            (#t (go (+ i 1) (rest lst))))))
      (go 0 lst))))

(def index-of
  (fn (x lst) (find-index (fn (el) (equal? el x)) lst)))

(def includes?
  (fn (x lst)
    (let ((lst (%as-list lst)))
      (match
        ((null? lst) #f)
        ((equal? x (first lst)) #t)
        (#t (includes? x (rest lst)))))))

(def count
  (fn (pred lst)
    (fold (fn (acc x) (if (pred x) (+ acc 1) acc)) 0 lst)))

(note "Slicing")

(def take
  (fn (n lst)
    (if (or (<= n 0) (null? lst))
      ()
      (pair (first lst) (take (- n 1) (rest lst))))))

(def drop
  (fn (n lst)
    (if (or (<= n 0) (null? lst))
      lst
      (drop (- n 1) (rest lst)))))

(def take-while
  (fn (pred lst)
    (if (or (null? lst) (not (pred (first lst))))
      ()
      (pair (first lst) (take-while pred (rest lst))))))

(def drop-while
  (fn (pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst)) (drop-while pred (rest lst)))
      (#t lst))))

(def split-at
  (fn (n lst) (list (take n lst) (drop n lst))))

(def slice
  (fn (start end lst) (take (- end start) (drop start lst))))

(note "Generators")

(def range
  (fn (start end)
    (if (>= start end) () (pair start (range (+ start 1) end)))))

(def repeat
  (fn (x n) (if (<= n 0) () (pair x (repeat x (- n 1))))))

(def times
  (fn (f n)
    (def go
      (fn (i) (if (>= i n) () (pair (f i) (go (+ i 1))))))
    (go 0)))

(def unfold
  (fn (pred f g seed)
    (if (pred seed)
      ()
      (pair (f seed) (unfold pred f g (g seed))))))

(def iterate
  (fn (f n x)
    (if (<= n 0) () (pair x (iterate f (- n 1) (f x))))))

(def zip
  (fn (a b)
    (if (or (null? a) (null? b))
      ()
      (pair (list (first a) (first b)) (zip (rest a) (rest b))))))

(def zip-with
  (fn (f a b)
    (if (or (null? a) (null? b))
      ()
      (pair
        (f (first a) (first b))
        (zip-with f (rest a) (rest b))))))

(note "Transformation")

(doc (def partition
  (fn ((param pred CALLABLE "Predicate function")
       (param lst LIST "List"))
    (def go
      (fn (lst yes no)
        (match
          ((null? lst) (list (reverse yes) (reverse no)))
          ((pred (first lst))
            (go (rest lst) (pair (first lst) yes) no))
          (#t (go (rest lst) yes (pair (first lst) no))))))
    (go lst () ())))
  "Split a list into elements that match and don't match a predicate.")

(def group-by
  (fn (f lst)
    (def add-to-group
      (fn (alist key val)
        (match
          ((null? alist) (list (pair key (list val))))
          ((eq? (first (first alist)) key)
            (pair
              (pair key (append (rest (first alist)) (list val)))
              (rest alist)))
          (#t
            (pair (first alist) (add-to-group (rest alist) key val))))))
    (fold (fn (acc x) (add-to-group acc (f x) x)) () lst)))

(doc (def sort
  (fn ((param cmp CALLABLE "Comparison: (a b) -> #t if a comes first")
       (param lst LIST "List or iterable"))
    (let ((lst (%as-list lst)))
    (def merge
      (fn (a b)
        (match
          ((null? a) b)
          ((null? b) a)
          ((cmp (first a) (first b))
            (pair (first a) (merge (rest a) b)))
          (#t (pair (first b) (merge a (rest b)))))))
    (def split
      (fn (lst a b)
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


(def sort-by
  (fn (f lst) (sort (fn (a b) (< (f a) (f b))) lst)))

(def uniq
  (fn (lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (first lst) (first (rest lst))) (uniq (rest lst)))
      (#t (pair (first lst) (uniq (rest lst)))))))

(def uniq-by
  (fn (f lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (f (first lst)) (f (first (rest lst))))
        (uniq-by f (rest lst)))
      (#t (pair (first lst) (uniq-by f (rest lst)))))))

(def intersperse
  (fn (sep lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      (#t
        (pair (first lst) (pair sep (intersperse sep (rest lst))))))))

(def transpose
  (fn (lsts)
    (if (or (null? lsts) (any? null? lsts))
      ()
      (pair (map first lsts) (transpose (map rest lsts))))))

(def update
  (fn (n val lst)
    (match
      ((null? lst) ())
      ((= n 0) (pair val (rest lst)))
      (#t (pair (first lst) (update (- n 1) val (rest lst)))))))

(def insert
  (fn (n val lst)
    (if (<= n 0)
      (pair val lst)
      (pair (first lst) (insert (- n 1) val (rest lst))))))

(def remove
  (fn (start n lst)
    (match
      ((null? lst) ())
      ((> start 0)
        (pair (first lst) (remove (- start 1) n (rest lst))))
      ((> n 0) (remove 0 (- n 1) (rest lst)))
      (#t lst))))

(def adjust
  (fn (n f lst)
    (match
      ((null? lst) ())
      ((= n 0) (pair (f (first lst)) (rest lst)))
      (#t (pair (first lst) (adjust (- n 1) f (rest lst)))))))

(note "Type predicate")

(def list?
  (fn (x) (if (null? x) #t (if (pair? x) (list? (rest x)) #f))))

(note "Membership")

(def memq
  (fn (x lst)
    (if (null? lst) #f
      (if (eq? x (first lst)) lst
        (memq x (rest lst))))))

(def member
  (fn (x lst)
    (if (null? lst) #f
      (if (equal? x (first lst)) lst
        (member x (rest lst))))))

(note "Association")

(def assq
  (fn (key alist)
    (if (null? alist) #f
      (if (eq? key (first (first alist))) (first alist)
        (assq key (rest alist))))))

(def assoc
  (fn (key alist)
    (if (null? alist) #f
      (if (equal? key (first (first alist))) (first alist)
        (assoc key (rest alist))))))

(provide x/list
  fold reduce scan length nth last init append prepend reverse flatten
  map filter for-each flat-map any? every? none? empty?
  complement partial juxt both either all-pass any-pass reject concat sum product
  find find-index index-of includes? count
  take drop take-while drop-while split-at slice
  range repeat times unfold iterate zip zip-with
  partition group-by sort sort-by uniq uniq-by intersperse transpose
  update insert remove adjust
  list? memq member assq assoc)
