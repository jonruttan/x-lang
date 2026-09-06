; list.x -- List: the list/sequence operations as static methods.
;
; Transitional: the global functions in core/list.x still exist; call sites
; migrate to (List ...) and the globals are removed once nothing references them.
; This class loads AFTER object.x (it needs def-class); core/list.x loads before
; it (and the object system) as the low-level layer -- the %-helpers (%map1,
; %any-null?, %for-each1, %append2) stay there, shared by both.
;
; Recursion uses `recur` (a method's own self-reference); cross-calls to other
; list operations go through (List ...).

(import x/type/class)

; N5 (implicit conversion): count/index seats COERCE to INT through the
; conversion catalog. An already-INT arg costs one type-handle eq?
; (C-static atoms, pointer-stable; nil is typeless so it is checked
; first); anything else converts through %cvt, and only an UNCONVERTIBLE
; value errors. Coercion runs ONCE per public entry -- self-recursive
; walks move into inner `go` fns so the loop never re-probes. Explicit
; control: pre-convert yourself ((Convert to x %int)).
(def %list-type-of (prim-ref (lit type) (lit of)))
(def %list-int-type (%list-type-of 0))
(def %list-cvt (prim-ref (lit convert) (lit to)))
(def %list-int? (fn (_ n) (if (null? n) #f (eq? (%list-type-of n) %list-int-type))))
(def %list->int (fn (_ n what)
  (if (%list-int? n) n
    (let ((k (%list-cvt n %list-int-type)))
      (if (%list-int? k) k (error what))))))

(def-class List ()
  (static
    (method of (self . (param args ANY "Elements, in order"))
      (doc "Variadic literal: the arguments as a list -- (List of ...) is (list ...), homed on the class for the constructor-verb symmetry."
        (returns LIST "List of the arguments")
        (example "(List of 1 2 3)" "(1 2 3)"))
      args)
    ; --- Folds ---
    (method from-seq (self x)
      (doc "Build a list from any iterable -- the from-X conversion verb (Gen from-seq is its lazy twin; the boot layer normalizes through its private %as-list plumbing). Lists and nil pass through unchanged." (param x ANY "A list, nil, or iterable (e.g. vector)") (returns LIST "The input as a proper list"))
      (if (or (null? x) (pair? x)) x (Iter ->list (Iter new x))))
    (method iter (self (param lst LIST "List to iterate"))
      (doc "An iterator over the list's elements." (returns ITER "Iterator"))
      (Iter new lst))
    (method fold (self f init lst)
      (doc "Fold a function over a list from the left." (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator") (param init ANY "Initial accumulator value") (param lst LIST "List or iterable to fold over") (returns ANY "Final accumulated value") (example "(List fold + 0 '(1 2 3))" "6"))
      ; first/rest are unchecked C prims, so an improper tail walks off the end
      ; of the list into UB -- (pair 1 2) is ordinary data, not hostile input.
      ; Same discipline as `ref`'s walk below: the pair? guard makes the overrun
      ; an error rather than a crash. fold is the walker every other basic goes
      ; through (length, map, reverse, ...), so guarding here covers them all.
      ; The walk lives in an inner `go` so the loop never re-probes: `recur`
      ; would re-enter the method and re-run from-seq on the TAIL, which for an
      ; improper list is an atom -- and from-seq hands a non-list to Iter, which
      ; is where the crash actually was.
      (let ((lst (List from-seq lst)))
        (def go (fn (self acc xs)
          (match
            ((null? xs) acc)
            ((not (pair? xs)) (Err raise (lit type) "List fold: improper list" ()))
            (#t (self (f acc (first xs)) (rest xs))))))
        (go init lst)))
    (method reduce (self f lst)
      (doc "Fold without an initial value; uses the first element." (param f CALLABLE "Binary function") (param lst LIST "Non-empty list or iterable"))
      (let ((lst (List from-seq lst))) (List fold f (first lst) (rest lst))))
    (method scan (self f init lst)
      (doc "Like fold, but returns a list of all intermediate values." (param f CALLABLE "Binary function") (param init ANY "Initial accumulator value") (param lst LIST "List or iterable"))
      (def go (fn (self xs a acc)
        (if (null? xs) (%reverse (pair a acc))
          (self (rest xs) (f a (first xs)) (pair a acc)))))
      (go (List from-seq lst) init ()))
    (method fold-right (self f init lst)
      (doc "Fold from the right: elements combine last-to-first, callback (f acc element) like fold." (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator") (param init ANY "Initial accumulator value") (param lst LIST "List or iterable") (returns ANY "Final accumulated value") (example "(List fold-right (fn (_ acc x) (pair x acc)) () (list 1 2 3))" "(1 2 3)"))
      ; Right fold = left fold over the reversal; iterative (#336).
      (def go (fn (self xs a)
        (if (null? xs) a (self (rest xs) (f a (first xs))))))
      (go (%reverse (List from-seq lst)) init))
    ; --- Basics ---
    (method length (self lst)
      (doc "Return the number of elements." (param lst LIST "List or iterable"))
      (List fold (fn (_ acc _) (+ acc 1)) 0 lst))
    (method ref (self n lst)
      (doc "Return the element at index n (zero-based; negative counts from the end; coerced to INT); errors when n is unconvertible or out of range." (param n INT "Zero-based index (negative counts from the end)") (param lst LIST "List"))
      ; first/rest are unchecked C prims (UB on a non-pair -- segfaults on
      ; 32-bit); the pair? guard in the walk makes an overrun an error, not a
      ; crash. The entry coerces ONCE (a nil from a piped index-search miss is
      ; unconvertible and fails loudly here); only the negative case pays the
      ; length walk.
      (def i (%list->int n "List ref: index not convertible to INT"))
      (def go (fn (self j xs)
        (match
          ((not (pair? xs)) (Err raise (lit index) "List ref: index out of range" ()))
          ((= j 0) (first xs))
          (#t (self (- j 1) (rest xs))))))
      (if (< i 0)
        (let ((k (+ i (List length lst))))
          (if (< k 0) (Err raise (lit index) "List ref: index out of range" ()) (go k lst)))
        (go i lst)))
    (method last (self lst)
      (doc "Return the last element of a list." (param lst LIST "Non-empty list"))
      (if (null? (rest lst)) (first lst) (recur self (rest lst))))
    ; The rest of the #336 family (#300 caught the stragglers): every
    ; (pair x (recur ...)) walk below was NON-TAIL -- C-stack depth =
    ; list length, a segfault at ~10^4 elements (List range 10000 died
    ; in the stress lane).  All converted to accumulate-and-reverse or
    ; prefix-splice go loops; helpers defined BEFORE their users.
    (method init (self lst)
      (doc "Return all elements except the last." (param lst LIST "Non-empty list"))
      (def go (fn (self xs acc)
        (if (null? (rest xs)) (%reverse acc)
          (self (rest xs) (pair (first xs) acc)))))
      (go lst ()))
    (method append (self . args)
      (doc "Concatenate zero or more lists.")
      (List fold %append2 () args))
    (method prepend (self x lst)
      (doc "Add an element to the front of a list." (param x ANY "Element to prepend") (param lst LIST "List"))
      (pair x lst))
    (method reverse (self lst)
      (doc "Reverse a list." (param lst LIST "List or iterable"))
      (List fold (fn (_ acc x) (pair x acc)) () lst))
    (method flatten (self lst)
      (doc "Recursively flatten nested lists into a single list." (param lst LIST "Nested list"))
      ; Reverse-flatten onto acc: spine calls are tail; only structural
      ; NESTING recurses (depth = nesting, not length).
      (def go (fn (self x acc)
        (match
          ((null? x) acc)
          ((pair? (first x)) (self (rest x) (self (first x) acc)))
          (#t (self (rest x) (pair (first x) acc))))))
      (%reverse (go lst ())))
    ; --- Iteration ---
    (method map (self f . lsts)
      (doc "Apply a function to each element. Supports multiple lists." (param f CALLABLE "Function to apply") (param lsts LIST "One or more lists") (returns LIST "New list"))
      (let ((lsts (%map1 (fn (_ x) (List from-seq x)) lsts)))
        (if (null? (rest lsts))
          (%map1 f (first lsts))
          ((fn (self ls acc)
             (if (%any-null? ls) (%reverse acc)
               (self (%map1 rest ls) (pair (apply f (%map1 first ls)) acc))))
           lsts ()))))
    ; Inner go loops (#336), the fold precedent: `recur` re-entered the
    ; method and re-ran the from-seq normalization dispatch on EVERY
    ; tail; the accumulate-and-reverse shape also makes the walks
    ; iterative -- the old (pair x (recur ...)) bodies were non-tail
    ; and overflowed the C stack on ~10^5-element lists (the repeat
    ; segfault family, #333).
    (method filter (self pred lst)
      (doc "Return elements that satisfy a predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable") (returns LIST "Filtered list"))
      (def go (fn (self xs acc)
        (match
          ((null? xs) (%reverse acc))
          ((pred (first xs)) (self (rest xs) (pair (first xs) acc)))
          (#t (self (rest xs) acc)))))
      (go (List from-seq lst) ()))
    (method for-each (self f . lsts)
      (doc "Apply a function to each element for side effects." (param f CALLABLE "Function to apply") (param lsts LIST "One or more lists"))
      (let ((lsts (%map1 (fn (_ x) (List from-seq x)) lsts)))
        (if (null? (rest lsts))
          (%for-each1 f (first lsts))
          ((fn (self ls)
             (if (%any-null? ls) ()
               (do (apply f (%map1 first ls)) (self (%map1 rest ls)))))
           lsts))))
    (method flat-map (self f lst)
      (doc "Map then flatten one level." (param f CALLABLE "Function returning a list") (param lst LIST "List or iterable"))
      ; Helper first: a closure only sees sibling defs made BEFORE it.
      (def %rev-onto (fn (self l acc)
        (match ((null? l) acc) (#t (self (rest l) (pair (first l) acc))))))
      (def go (fn (self xs acc)
        (if (null? xs) (%reverse acc)
          (self (rest xs) (%rev-onto (f (first xs)) acc)))))
      (go (List from-seq lst) ()))
    ; --- Predicates ---
    (method any? (self pred lst)
      (doc "Return #t if any element satisfies the predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable"))
      (def go (fn (self xs)
        (match
          ((null? xs) #f)
          ((pred (first xs)) #t)
          (#t (self (rest xs))))))
      (go (List from-seq lst)))
    (method all? (self pred lst)
      (doc "Return #t if all elements satisfy the predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable"))
      (def go (fn (self xs)
        (match
          ((null? xs) #t)
          ((not (pred (first xs))) #f)
          (#t (self (rest xs))))))
      (go (List from-seq lst)))
    (method none? (self pred lst)
      (doc "Return #t if no element satisfies the predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable"))
      (not (List any? pred lst)))
    (method empty? (self lst)
      (doc "Return #t if the list is empty." (param lst LIST "List"))
      (null? lst))
    ; --- Combinators ---
    ; Function combinators (complement/partial/juxt/both/either/all-pass/
    ; any-pass) moved to the Fn class -- that is what Fn is for.
    (method reject (self pred lst)
      (doc "Return elements that do NOT satisfy a predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List") (returns LIST "Filtered list"))
      (List filter (Fn complement pred) lst))
    ; concat was byte-identical to append -- one name, one operation.
    (method min (self lst)
      (doc "The smallest element (by <); errors on an empty list." (param lst LIST "Non-empty list") (returns ANY "Smallest element") (example "(List min (list 3 1 2))" "1"))
      (if (null? lst) (Err raise (lit value) "List min: empty list" ())
        (List fold (fn (_ m x) (if (< x m) x m)) (first lst) (rest lst))))
    (method max (self lst)
      (doc "The largest element (by <); errors on an empty list." (param lst LIST "Non-empty list") (returns ANY "Largest element") (example "(List max (list 3 1 2))" "3"))
      (if (null? lst) (Err raise (lit value) "List max: empty list" ())
        (List fold (fn (_ m x) (if (< m x) x m)) (first lst) (rest lst))))
    (method sum (self lst)
      (doc "Sum all elements of a list." (param lst LIST "List of numbers") (returns INT "Sum"))
      (List fold + 0 lst))
    (method product (self lst)
      (doc "Multiply all elements of a list." (param lst LIST "List of numbers") (returns INT "Product"))
      (List fold * 1 lst))
    ; --- Search ---
    (method find (self pred lst)
      (doc "Return the first element satisfying a predicate, or nil." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable"))
      (def go (fn (self xs)
        (match
          ((null? xs) ())
          ((pred (first xs)) (first xs))
          (#t (self (rest xs))))))
      (go (List from-seq lst)))
    (method find-index (self pred lst)
      (doc "Return the index of the first element satisfying a predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable") (returns ANY "Zero-based index, or nil if not found"))
      (let ((lst (List from-seq lst)))
        (def go
          (fn (self i xs)
            (match
              ((null? xs) ())
              ((pred (first xs)) i)
              (#t (self (+ i 1) (rest xs))))))
        (go 0 lst)))
    (method index-of (self x lst)
      (doc "Return the index of the first occurrence of a value." (param x ANY "Value to find") (param lst LIST "List") (returns ANY "Zero-based index, or nil if not found"))
      (List find-index (fn (_ el) (equal? el x)) lst))
    (method includes? (self x lst)
      (doc "Test if a list contains a value." (param x ANY "Value to search for") (param lst LIST "List or iterable") (returns BOOL "t if found"))
      (def go (fn (self xs)
        (match
          ((null? xs) #f)
          ((equal? x (first xs)) #t)
          (#t (self (rest xs))))))
      (go (List from-seq lst)))
    (method count-if (self pred lst)
      (doc "Count elements satisfying a predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List or iterable") (returns INT "Count of matching elements"))
      (List fold (fn (_ acc x) (if (pred x) (+ acc 1) acc)) 0 lst))
    ; --- Slicing ---
    (method take (self n lst)
      (doc "Take the first n elements of a list (n coerced to INT)." (param n INT "Number of elements") (param lst LIST "List"))
      (def k (%list->int n "List take: count not convertible to INT"))
      (def go (fn (self j xs acc)
        ; Nested if, NOT and/or (#343): per element, operatives
        ; expand per evaluation.
        (if (if (<= j 0) #t (null? xs)) (%reverse acc)
          (self (- j 1) (rest xs) (pair (first xs) acc)))))
      (go k lst ()))
    (method chunk (self n lst)
      (doc "Split a list into successive n-element sublists; the last may be shorter." (param n INT "Chunk size (must be > 0)") (param lst LIST "List") (returns LIST "List of chunks") (example "(List chunk 2 (list 1 2 3 4 5))" "((1 2) (3 4) (5))"))
      (def k (%list->int n "List chunk: size not convertible to INT"))
      (def go (fn (self xs acc)
        (if (null? xs) (%reverse acc)
          (self (List drop k xs) (pair (List take k xs) acc)))))
      (if (<= k 0) (Err raise (lit value) "List chunk: size must be positive" ()) (go lst ())))
    (method drop (self n lst)
      (doc "Drop the first n elements of a list (n coerced to INT)." (param n INT "Number of elements to skip") (param lst LIST "List"))
      (def k (%list->int n "List drop: count not convertible to INT"))
      (def go (fn (self j xs)
        (if (if (<= j 0) #t (null? xs)) xs (self (- j 1) (rest xs)))))
      (go k lst))
    (method take-while (self pred lst)
      (doc "Take elements from the front while predicate holds." (param pred CALLABLE "Predicate function") (param lst LIST "List"))
      (def go (fn (self xs acc)
        (if (if (null? xs) #t (not (pred (first xs)))) (%reverse acc)
          (self (rest xs) (pair (first xs) acc)))))
      (go lst ()))
    (method drop-while (self pred lst)
      (doc "Drop elements from the front while predicate holds." (param pred CALLABLE "Predicate function") (param lst LIST "List"))
      (match
        ((null? lst) ())
        ((pred (first lst)) (recur self pred (rest lst)))
        (#t lst)))
    (method split-at (self n lst)
      (doc "Split a list at position n." (param n INT "Split position") (param lst LIST "List") (returns LIST "Pair of (taken dropped)"))
      (list (List take n lst) (List drop n lst)))
    (method slice (self start end lst)
      (doc "Extract a slice from start to end -- the slice convention: (start, end-exclusive)." (param start INT "Start index (inclusive)") (param end INT "End index (exclusive)") (param lst LIST "List"))
      (List take (- end start) (List drop start lst)))
    (method sub (self start n lst)
      (doc "Extract n elements from start -- the sub convention: (start, length); the counted twin of slice." (param start INT "Start index (inclusive)") (param n INT "Number of elements") (param lst LIST "List"))
      (List take n (List drop start lst)))
    ; --- Generators ---
    (method range (self start end)
      (doc "Generate a list of integers from start to end (both coerced to INT)." (param start INT "Start value (inclusive)") (param end INT "End value (exclusive)") (returns LIST "List of integers") (example "(List range 0 5)" "(0 1 2 3 4)"))
      (def a (%list->int start "List range: start not convertible to INT"))
      (def b (%list->int end "List range: end not convertible to INT"))
      (def go (fn (self i acc)
        (if (>= i b) (%reverse acc) (self (+ i 1) (pair i acc)))))
      (go a ()))
    (method repeat (self n x)
      (doc "Create a list of n copies of a value (n coerced to INT); count first, matching (Str8 repeat n s)." (param n INT "Number of repetitions") (param x ANY "Value to repeat") (returns LIST "List of repeated values"))
      (def k (%list->int n "List repeat: count not convertible to INT"))
      (def go (fn (self j acc)
        (if (<= j 0) acc (self (- j 1) (pair x acc)))))
      (go k ()))
    (method times (self n f)
      (doc "Apply a function to each index 0..n-1, collecting results (n coerced to INT). Count first, per the constructor-count rule (was (f n) before the V6 adjudication)." (param n INT "Number of iterations") (param f CALLABLE "Function: index -> value") (returns LIST "List of results"))
      (def k (%list->int n "List times: count not convertible to INT"))
      (def go (fn (self i acc)
        (if (>= i k) (%reverse acc) (self (+ i 1) (pair (f i) acc)))))
      (go 0 ()))
    (method unfold (self pred f g seed)
      (doc "Build a list by repeatedly applying step and value functions to a seed." (param pred CALLABLE "Stop predicate: seed -> boolean") (param f CALLABLE "Value function: seed -> element") (param g CALLABLE "Step function: seed -> next-seed") (param seed ANY "Initial seed value") (returns LIST "Generated list"))
      (def go (fn (self seed acc)
        (if (pred seed) (%reverse acc)
          (self (g seed) (pair (f seed) acc)))))
      (go seed ()))
    (method iterate (self f n x)
      (doc "Generate n values by repeatedly applying f (n coerced to INT)." (param f CALLABLE "Step function") (param n INT "Number of iterations") (param x ANY "Initial value") (returns LIST "List of iterated values"))
      (def k (%list->int n "List iterate: count not convertible to INT"))
      (def go (fn (self j v acc)
        (if (<= j 0) (%reverse acc) (self (- j 1) (f v) (pair v acc)))))
      (go k x ()))
    (method zip (self a b)
      (doc "Pair up corresponding elements from two lists as assocs -- the result is an alist, so it feeds Dict from-alist and the Assoc API directly." (param a LIST "First elements (keys)") (param b LIST "Second elements (values)") (returns LIST "Alist of (a . b) assocs") (example "(List zip (list 1 2) (list 7 8))" "((1 . 7) (2 . 8))"))
      (def go (fn (self a b acc)
        (if (if (null? a) #t (null? b)) (%reverse acc)
          (self (rest a) (rest b) (pair (pair (first a) (first b)) acc)))))
      (go a b ()))
    (method zip-with (self f a b)
      (doc "Combine corresponding elements from two lists using a function." (param f CALLABLE "Combining function") (param a LIST "First list") (param b LIST "Second list") (returns LIST "Combined list"))
      (def go (fn (self a b acc)
        (if (if (null? a) #t (null? b)) (%reverse acc)
          (self (rest a) (rest b) (pair (f (first a) (first b)) acc)))))
      (go a b ()))
    (method unzip (self alist)
      (doc "Invert zip: an alist of (a . b) assocs becomes a list of two lists." (param alist LIST "Alist of (a . b) assocs") (returns LIST "(firsts seconds)") (example "(List unzip (List zip (list 1 2) (list \"a\" \"b\")))" "((1 2) (\"a\" \"b\"))"))
      (list (List map first alist)
            (List map rest alist)))
    (method interleave (self a b)
      (doc "Alternate elements from two lists, stopping at the shorter." (param a LIST "First list") (param b LIST "Second list") (returns LIST "(a1 b1 a2 b2 ...)") (example "(List interleave (list 1 3) (list 2 4))" "(1 2 3 4)"))
      (def go (fn (self a b acc)
        (if (if (null? a) #t (null? b)) (%reverse acc)
          (self (rest a) (rest b) (pair (first b) (pair (first a) acc))))))
      (go a b ()))
    ; --- Transformation ---
    (method partition (self pred lst)
      (doc "Split a list into elements that match and don't match a predicate." (param pred CALLABLE "Predicate function") (param lst LIST "List"))
      (def go
        (fn (self xs yes no)
          (match
            ((null? xs) (list (List reverse yes) (List reverse no)))
            ((pred (first xs)) (self (rest xs) (pair (first xs) yes) no))
            (#t (self (rest xs) yes (pair (first xs) no))))))
      (go lst () ()))
    (method group-by (self f lst)
      (doc "Group list elements by a key function." (param f CALLABLE "Key function: element -> group key") (param lst LIST "List") (returns LIST "Alist of (key . elements), keys in first-seen order"))
      ; Prepend into each group (O(1)) and reverse once at the end -- the old
      ; per-element (List append group (list val)) was O(n^2) on skewed keys.
      (def add-to-group
        (fn (_ alist key val)
          (def %rev-onto (fn (self l tail)
            (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
          (def go (fn (self pre xs)
            (match
              ((null? xs) (%rev-onto pre (list (pair key (list val)))))
              ((eq? (first (first xs)) key)
                (%rev-onto pre
                  (pair (pair key (pair val (rest (first xs)))) (rest xs))))
              (#t (self (pair (first xs) pre) (rest xs))))))
          (go () alist)))
      (List map (fn (_ g) (pair (first g) (%reverse (rest g))))
        (List fold (fn (_ acc x) (add-to-group acc (f x) x)) () lst)))
    (method sort (self cmp lst)
      (doc "Stable merge sort using a comparison function: equal-key elements keep their input order." (param cmp CALLABLE "Comparison: (a b) -> #t if a comes strictly first") (param lst LIST "List or iterable"))
      (let ((lst (List from-seq lst)))
        ; STABILITY needs both halves of this: (a) split by taking the first
        ; half in order (the old alternate-cons split reversed and interleaved
        ; the halves), and (b) merge takes from the LEFT half unless the right
        ; element comes strictly first, so ties keep input order.
        ; Helpers first: a closure only sees sibling defs made BEFORE it.
        (def %rev-onto2 (fn (self l tail)
          (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
        (def %split (fn (self slow fast acc)
          (match
            ((null? fast) (pair (%reverse acc) slow))
            ((null? (rest fast)) (pair (%reverse acc) slow))
            (#t (self (rest slow) (rest (rest fast)) (pair (first slow) acc))))))
        (def merge
          ; Iterative merge (#336): the recursive body was non-tail
          ; (stack depth = output length) and the old split paid
          ; length/take/drop dispatches -- ~4 extra O(n) passes per
          ; level.  The split walks once, tortoise-and-hare.
          (fn (_ a b)
            (def go (fn (self a b acc)
              (match
                ((null? a) (%rev-onto2 acc b))
                ((null? b) (%rev-onto2 acc a))
                ((cmp (first b) (first a)) (self a (rest b) (pair (first b) acc)))
                (#t (self (rest a) b (pair (first a) acc))))))
            (go a b ())))
        (if (if (null? lst) #t (null? (rest lst))) lst
          (let ((halves (%split lst lst ())))
            (merge (recur self cmp (first halves))
                   (recur self cmp (rest halves)))))))
    (method sort-by (self f lst)
      (doc "Sort by a key function (ascending)." (param f CALLABLE "Key function: element -> comparable value") (param lst LIST "List"))
      (List sort (fn (_ a b) (< (f a) (f b))) lst))
    (method distinct (self lst)
      (doc "Remove ALL duplicates (equal?), keeping each element's first occurrence -- unlike uniq, no sorting needed." (param lst LIST "List") (returns LIST "lst without later duplicates") (example "(List distinct (list 1 2 1 3 2))" "(1 2 3)")
        (note "O(n^2) via equal?, so it works for every element type; hashable elements (symbols/strings/ints/chars) can dedupe O(n) through x/type/set instead."))
      (let go ((xs lst) (seen ()) (acc ()))
        (match
          ((null? xs) (%reverse acc))
          ((List includes? (first xs) seen) (go (rest xs) seen acc))
          (#t (go (rest xs) (pair (first xs) seen) (pair (first xs) acc))))))
    (method uniq (self lst)
      (doc "Remove consecutive duplicates from a sorted list." (param lst LIST "Sorted list"))
      (def go (fn (self xs acc)
        (match
          ((null? xs) (%reverse acc))
          ((null? (rest xs)) (%reverse (pair (first xs) acc)))
          ((equal? (first xs) (first (rest xs))) (self (rest xs) acc))
          (#t (self (rest xs) (pair (first xs) acc))))))
      (go lst ()))
    (method uniq-by (self f lst)
      (doc "Remove consecutive duplicates by key function." (param f CALLABLE "Key function") (param lst LIST "Sorted list"))
      (match
        ((null? lst) ())
        ((null? (rest lst)) lst)
        ; Drop the SECOND of a duplicate pair, not the first: de-duplication
        ; keeps the earliest element of each run (Unix uniq's reading, and the
        ; one the docs always claimed). Recurring on (rest lst) kept the LAST
        ; instead -- #73.
        (#t
          ((fn (self xs acc)
             (match
               ((null? xs) (%reverse acc))
               ((null? (rest xs)) (%reverse (pair (first xs) acc)))
               ((equal? (f (first xs)) (f (first (rest xs))))
                 (self (pair (first xs) (rest (rest xs))) acc))
               (#t (self (rest xs) (pair (first xs) acc)))))
           lst ()))))
    (method intersperse (self sep lst)
      (doc "Insert a separator between each element." (param sep ANY "Separator element") (param lst LIST "List"))
      (def go (fn (self xs acc)
        (if (null? (rest xs)) (%reverse (pair (first xs) acc))
          (self (rest xs) (pair sep (pair (first xs) acc))))))
      (match
        ((null? lst) ())
        ((null? (rest lst)) lst)
        (#t (go lst ()))))
    (method transpose (self lsts)
      (doc "Transpose rows and columns of a list of lists." (param lsts LIST "List of lists") (returns LIST "Transposed list of lists"))
      (def go (fn (self ls acc)
        (if (if (null? ls) #t (List any? null? ls)) (%reverse acc)
          (self (List map rest ls) (pair (List map first ls) acc)))))
      (go lsts ()))
    (method update (self n val lst)
      (doc "Replace the element at index n (coerced to INT)." (param n INT "Index to update") (param val ANY "New value") (param lst LIST "List"))
      (def k (%list->int n "List update: index not convertible to INT"))
      (def %rev-onto (fn (self l tail)
        (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
      (def go (fn (self j xs pre)
        (match
          ((null? xs) ())
          ((= j 0) (%rev-onto pre (pair val (rest xs))))
          (#t (self (- j 1) (rest xs) (pair (first xs) pre))))))
      (go k lst ()))
    (method insert (self n val lst)
      (doc "Insert a value at index n (coerced to INT; clamped: n<=0 prepends, n>=length appends)." (param n INT "Insertion index") (param val ANY "Value to insert") (param lst LIST "List"))
      (def k (%list->int n "List insert: index not convertible to INT"))
      (def %rev-onto (fn (self l tail)
        (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
      (def go (fn (self j xs pre)
        (match
          ((<= j 0) (%rev-onto pre (pair val xs)))
          ; past the end: clamp to append -- without this guard the recursion
          ; reaches (first ()) (unchecked car, UB)
          ((null? xs) (%rev-onto pre (pair val ())))
          (#t (self (- j 1) (rest xs) (pair (first xs) pre))))))
      (go k lst ()))
    (method remove (self start n lst)
      (doc "Remove n elements starting at index (both coerced to INT)." (param start INT "Start index") (param n INT "Number of elements to remove") (param lst LIST "List"))
      (def s0 (%list->int start "List remove: start not convertible to INT"))
      (def k (%list->int n "List remove: count not convertible to INT"))
      (def %rev-onto (fn (self l tail)
        (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
      (def go (fn (self i j xs pre)
        (match
          ((null? xs) ())
          ((> i 0) (self (- i 1) j (rest xs) (pair (first xs) pre)))
          ((> j 0) (self 0 (- j 1) (rest xs) pre))
          (#t (%rev-onto pre xs)))))
      (go s0 k lst ()))
    (method adjust (self n f lst)
      (doc "Apply a function to the element at index n (coerced to INT)." (param n INT "Index to adjust") (param f CALLABLE "Transformation function") (param lst LIST "List"))
      (def k (%list->int n "List adjust: index not convertible to INT"))
      (def %rev-onto (fn (self l tail)
        (match ((null? l) tail) (#t (self (rest l) (pair (first l) tail))))))
      (def go (fn (self j xs pre)
        (match
          ((null? xs) ())
          ((= j 0) (%rev-onto pre (pair (f (first xs)) (rest xs))))
          (#t (self (- j 1) (rest xs) (pair (first xs) pre))))))
      (go k lst ()))
    ; --- Type predicate / Membership / Association ---
    (method list? (self x)
      (doc "Test if a value is a proper list." (param x ANY "Value to test") (returns BOOL "t if proper list"))
      (if (null? x) #t (if (pair? x) (recur self (rest x)) #f)))
    (method second (self x)
      (doc "Return the second element of a list." (param x LIST "A list with at least two elements") (returns ANY "The second element"))
      (first (rest x)))
    (method third (self x)
      (doc "Return the third element of a list." (param x LIST "A list with at least three elements") (returns ANY "The third element"))
      (first (rest (rest x))))
    ; list-ref/list-tail (subject-first Scheme compat) moved to the x/rn
    ; dialect, where the R7RS-isms live -- the core class stays data-last.
    ))


; --- Block forms ------------------------------------------------------------
; (List map (x) (* x 10) xs) alongside (List map f xs); see x/type/block.x.
; Every selector here is subject-last, so the trailing count is 1 (the list)
; -- except fold, which carries init as well.
(import x/type/block)
(List for-each (fn (_ %lst-sel) (Block method! List %lst-sel))
  (list (lit map) (lit filter) (lit for-each) (lit find) (lit flat-map)
        (lit sort-by) (lit take-while) (lit any?) (lit all?)))
(Block method! List (lit fold) (lit fold) 2)
(Block method! List (lit sort) (lit binary) 1)
(Block method! List (lit reduce) (lit binary) 1)

(doc (provide x/type/list List)
  (note "The list/sequence operations as static methods; core/list.x keeps the low-level layer (fold/map/filter globals + %-helpers) it is built on.")
  (note "Element access is (List ref n lst) -- the adjudicated name; list-ref/list-tail are Scheme-compat wrappers.")
  (example "(List ref 1 (list 10 20 30))" "20")
  "List: the list/sequence API, homed on the List class.")
