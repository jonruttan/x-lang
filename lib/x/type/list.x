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

(import x/type/object)

(def-class List ()
  (static
    ; --- Folds ---
    (method as-list (self x)
      (if (or (null? x) (pair? x)) x (Iter ->list (Iter new x))))
    (method fold (self f init lst)
      (let ((lst (List as-list lst)))
        (if (null? lst) init (recur self f (f init (first lst)) (rest lst)))))
    (method reduce (self f lst)
      (let ((lst (List as-list lst))) (List fold f (first lst) (rest lst))))
    (method scan (self f init lst)
      (let ((lst (List as-list lst)))
        (if (null? lst) (list init)
          (pair init (recur self f (f init (first lst)) (rest lst))))))
    ; --- Basics ---
    (method length (self lst) (List fold (fn (_ acc _) (+ acc 1)) 0 lst))
    (method nth (self n lst)
      (if (= n 0) (first lst) (recur self (- n 1) (rest lst))))
    (method last (self lst)
      (if (null? (rest lst)) (first lst) (recur self (rest lst))))
    (method init (self lst)
      (if (null? (rest lst)) () (pair (first lst) (recur self (rest lst)))))
    (method append (self . args) (List fold %append2 () args))
    (method prepend (self x lst) (pair x lst))
    (method reverse (self lst) (List fold (fn (_ acc x) (pair x acc)) () lst))
    (method flatten (self lst)
      (match
        ((null? lst) ())
        ((pair? (first lst)) (%append2 (recur self (first lst)) (recur self (rest lst))))
        (#t (pair (first lst) (recur self (rest lst))))))
    ; --- Iteration ---
    (method map (self f . lsts)
      (let ((lsts (%map1 (fn (_ x) (List as-list x)) lsts)))
        (if (null? (rest lsts))
          (%map1 f (first lsts))
          (if (%any-null? lsts) ()
            (pair (apply f (%map1 first lsts)) (apply recur self f (%map1 rest lsts)))))))
    (method filter (self pred lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) ())
          ((pred (first lst)) (pair (first lst) (recur self pred (rest lst))))
          (#t (recur self pred (rest lst))))))
    (method for-each (self f . lsts)
      (let ((lsts (%map1 (fn (_ x) (List as-list x)) lsts)))
        (if (null? (rest lsts))
          (%for-each1 f (first lsts))
          (if (not (%any-null? lsts))
            (do (apply f (%map1 first lsts)) (apply recur self f (%map1 rest lsts)))))))
    (method flat-map (self f lst)
      (let ((lst (List as-list lst)))
        (if (null? lst) () (%append2 (f (first lst)) (recur self f (rest lst))))))
    ; --- Predicates ---
    (method any? (self pred lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) #f)
          ((pred (first lst)) #t)
          (#t (recur self pred (rest lst))))))
    (method every? (self pred lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) #t)
          ((not (pred (first lst))) #f)
          (#t (recur self pred (rest lst))))))
    (method none? (self pred lst) (not (List any? pred lst)))
    (method empty? (self lst) (null? lst))
    ; --- Combinators ---
    (method complement (self pred) (fn (_ . args) (not (apply pred args))))
    (method partial (self f . bound) (fn (_ . args) (apply f (List append bound args))))
    (method juxt (self . fns) (fn (_ . args) (List map (fn (_ f) (apply f args)) fns)))
    (method both (self f g) (fn (_ x) (and (f x) (g x))))
    (method either (self f g) (fn (_ x) (or (f x) (g x))))
    (method all-pass (self preds) (fn (_ x) (List every? (fn (_ p) (p x)) preds)))
    (method any-pass (self preds) (fn (_ x) (List any? (fn (_ p) (p x)) preds)))
    (method reject (self pred lst) (List filter (List complement pred) lst))
    (method concat (self . lsts) (List fold %append2 () lsts))
    (method sum (self lst) (List fold + 0 lst))
    (method product (self lst) (List fold * 1 lst))
    ; --- Search ---
    (method find (self pred lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) ())
          ((pred (first lst)) (first lst))
          (#t (recur self pred (rest lst))))))
    (method find-index (self pred lst)
      (let ((lst (List as-list lst)))
        (def go
          (fn (self i xs)
            (match
              ((null? xs) (- 0 1))
              ((pred (first xs)) i)
              (#t (self (+ i 1) (rest xs))))))
        (go 0 lst)))
    (method index-of (self x lst)
      (List find-index (fn (_ el) (equal? el x)) lst))
    (method includes? (self x lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) #f)
          ((equal? x (first lst)) #t)
          (#t (recur self x (rest lst))))))
    (method count (self pred lst)
      (List fold (fn (_ acc x) (if (pred x) (+ acc 1) acc)) 0 lst))
    ; --- Slicing ---
    (method take (self n lst)
      (if (or (<= n 0) (null? lst)) ()
        (pair (first lst) (recur self (- n 1) (rest lst)))))
    (method drop (self n lst)
      (if (or (<= n 0) (null? lst)) lst (recur self (- n 1) (rest lst))))
    (method take-while (self pred lst)
      (if (or (null? lst) (not (pred (first lst)))) ()
        (pair (first lst) (recur self pred (rest lst)))))
    (method drop-while (self pred lst)
      (match
        ((null? lst) ())
        ((pred (first lst)) (recur self pred (rest lst)))
        (#t lst)))
    (method split-at (self n lst) (list (List take n lst) (List drop n lst)))
    (method slice (self start end lst)
      (List take (- end start) (List drop start lst)))
    ; --- Generators ---
    (method range (self start end)
      (if (>= start end) () (pair start (recur self (+ start 1) end))))
    (method repeat (self x n)
      (if (<= n 0) () (pair x (recur self x (- n 1)))))
    (method times (self f n)
      (def go (fn (self i) (if (>= i n) () (pair (f i) (self (+ i 1))))))
      (go 0))
    (method unfold (self pred f g seed)
      (if (pred seed) () (pair (f seed) (recur self pred f g (g seed)))))
    (method iterate (self f n x)
      (if (<= n 0) () (pair x (recur self f (- n 1) (f x)))))
    (method zip (self a b)
      (if (or (null? a) (null? b)) ()
        (pair (list (first a) (first b)) (recur self (rest a) (rest b)))))
    (method zip-with (self f a b)
      (if (or (null? a) (null? b)) ()
        (pair (f (first a) (first b)) (recur self f (rest a) (rest b)))))
    ; --- Transformation ---
    (method partition (self pred lst)
      (def go
        (fn (self xs yes no)
          (match
            ((null? xs) (list (List reverse yes) (List reverse no)))
            ((pred (first xs)) (self (rest xs) (pair (first xs) yes) no))
            (#t (self (rest xs) yes (pair (first xs) no))))))
      (go lst () ()))
    (method group-by (self f lst)
      (def add-to-group
        (fn (self alist key val)
          (match
            ((null? alist) (list (pair key (list val))))
            ((eq? (first (first alist)) key)
              (pair (pair key (List append (rest (first alist)) (list val))) (rest alist)))
            (#t (pair (first alist) (self (rest alist) key val))))))
      (List fold (fn (_ acc x) (add-to-group acc (f x) x)) () lst))
    (method sort (self cmp lst)
      (let ((lst (List as-list lst)))
        (def merge
          (fn (self a b)
            (match
              ((null? a) b)
              ((null? b) a)
              ((cmp (first a) (first b)) (pair (first a) (self (rest a) b)))
              (#t (pair (first b) (self a (rest b)))))))
        (def split
          (fn (self xs a b)
            (match
              ((null? xs) (list a b))
              ((null? (rest xs)) (list (pair (first xs) a) b))
              (#t (self (rest (rest xs)) (pair (first xs) a) (pair (first (rest xs)) b))))))
        (if (or (null? lst) (null? (rest lst))) lst
          (let ((halves (split lst () ())))
            (merge (recur self cmp (first halves)) (recur self cmp (first (rest halves))))))))
    (method sort-by (self f lst)
      (List sort (fn (_ a b) (< (f a) (f b))) lst))
    (method uniq (self lst)
      (match
        ((null? lst) ())
        ((null? (rest lst)) lst)
        ((equal? (first lst) (first (rest lst))) (recur self (rest lst)))
        (#t (pair (first lst) (recur self (rest lst))))))
    (method uniq-by (self f lst)
      (match
        ((null? lst) ())
        ((null? (rest lst)) lst)
        ((equal? (f (first lst)) (f (first (rest lst)))) (recur self f (rest lst)))
        (#t (pair (first lst) (recur self f (rest lst))))))
    (method intersperse (self sep lst)
      (match
        ((null? lst) ())
        ((null? (rest lst)) lst)
        (#t (pair (first lst) (pair sep (recur self sep (rest lst)))))))
    (method transpose (self lsts)
      (if (or (null? lsts) (List any? null? lsts)) ()
        (pair (List map first lsts) (recur self (List map rest lsts)))))
    (method update (self n val lst)
      (match
        ((null? lst) ())
        ((= n 0) (pair val (rest lst)))
        (#t (pair (first lst) (recur self (- n 1) val (rest lst))))))
    (method insert (self n val lst)
      (if (<= n 0) (pair val lst)
        (pair (first lst) (recur self (- n 1) val (rest lst)))))
    (method remove (self start n lst)
      (match
        ((null? lst) ())
        ((> start 0) (pair (first lst) (recur self (- start 1) n (rest lst))))
        ((> n 0) (recur self 0 (- n 1) (rest lst)))
        (#t lst)))
    (method adjust (self n f lst)
      (match
        ((null? lst) ())
        ((= n 0) (pair (f (first lst)) (rest lst)))
        (#t (pair (first lst) (recur self (- n 1) f (rest lst))))))
    ; --- Type predicate / Membership / Association ---
    (method list? (self x) (if (null? x) #t (if (pair? x) (recur self (rest x)) #f)))
    (method memq (self x lst)
      (if (null? lst) #f (if (eq? x (first lst)) lst (recur self x (rest lst)))))
    (method member (self x lst)
      (if (null? lst) #f (if (equal? x (first lst)) lst (recur self x (rest lst)))))
    (method assq (self key alist)
      (if (null? alist) #f
        (if (eq? key (first (first alist))) (first alist) (recur self key (rest alist)))))
    (method assoc (self key alist)
      (if (null? alist) #f
        (if (equal? key (first (first alist))) (first alist) (recur self key (rest alist)))))
    (method second (self x) (first (rest x)))
    (method third (self x) (first (rest (rest x))))
    (method list-ref (self lst n) (List nth n lst))
    (method list-tail (self lst n) (List drop n lst))))
