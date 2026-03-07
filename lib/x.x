; # Computational Expressions in C
;
; ## x.x -- x Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(do (def x-lib-version "0.2.0")

  ; =========================================================
  ; Functional combinators (no dependencies)
  ; =========================================================
  (def identity (fn (x) x))
  (def const (fn (x) (fn (y) x)))
  (def compose (fn (f g) (fn (x) (f (g x)))))
  (def pipe (fn (f g) (fn (x) (g (f x)))))
  (def curry (fn (f x) (fn (y) (f x y))))
  (def flip (fn (f) (fn (a b) (f b a))))
  (def tap (fn (f) (fn (x) (f x) x)))

  ; =========================================================
  ; Math
  ; =========================================================
  (def inc (fn (n) (+ n 1)))
  (def dec (fn (n) (- n 1)))
  (def negate (fn (n) (- 0 n)))
  (def abs (fn (n) (if (< n 0) (- 0 n) n)))
  (def min (fn (a b) (if (< a b) a b)))
  (def max (fn (a b) (if (> a b) a b)))
  (def clamp (fn (lo hi n) (min hi (max lo n))))
  (def min-by (fn (f a b) (if (< (f a) (f b)) a b)))
  (def max-by (fn (f a b) (if (> (f a) (f b)) a b)))

  ; =========================================================
  ; Number predicates
  ; =========================================================
  (def zero? (fn (n) (= n 0)))
  (def positive? (fn (n) (> n 0)))
  (def negative? (fn (n) (< n 0)))
  (def even? (fn (n) (= (% n 2) 0)))
  (def odd? (fn (n) (not (= (% n 2) 0))))

  ; =========================================================
  ; Boolean / Logic
  ; =========================================================
  (def boolean? (fn (x) (or (eq? x t) (null? x))))
  (def default-to (fn (d x) (if (null? x) d x)))
  (def until (fn (pred f x) (if (pred x) x (until pred f (f x)))))
  (def equal? (fn (a b)
    (match
      ((and (number? a) (number? b)) (= a b))
      ((and (string? a) (string? b)) (string=? a b))
      (t (eq? a b)))))

  ; =========================================================
  ; List folds
  ; =========================================================
  (def fold (fn (f init lst)
    (if (null? lst) init
      (fold f (f init (first lst)) (rest lst)))))

  (def reduce (fn (f lst)
    (fold f (first lst) (rest lst))))

  (def scan (fn (f init lst)
    (if (null? lst) (list init)
      (pair init (scan f (f init (first lst)) (rest lst))))))

  ; =========================================================
  ; List basics
  ; =========================================================
  (def length (fn (lst)
    (fold (fn (acc x) (+ acc 1)) 0 lst)))

  (def nth (fn (n lst)
    (if (= n 0) (first lst) (nth (- n 1) (rest lst)))))

  (def last (fn (lst)
    (if (null? (rest lst)) (first lst) (last (rest lst)))))

  (def init (fn (lst)
    (if (null? (rest lst)) ()
      (pair (first lst) (init (rest lst))))))

  (def append (fn (a b)
    (if (null? a) b
      (pair (first a) (append (rest a) b)))))

  (def prepend (fn (x lst) (pair x lst)))

  (def reverse (fn (lst)
    (fold (fn (acc x) (pair x acc)) () lst)))

  (def flatten (fn (lst)
    (match
      ((null? lst) ())
      ((pair? (first lst))
        (append (flatten (first lst)) (flatten (rest lst))))
      (t (pair (first lst) (flatten (rest lst)))))))

  ; =========================================================
  ; List iteration
  ; =========================================================
  (def map (fn (f lst)
    (if (null? lst) ()
      (pair (f (first lst)) (map f (rest lst))))))

  (def filter (fn (pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst))
        (pair (first lst) (filter pred (rest lst))))
      (t (filter pred (rest lst))))))

  (def for-each (fn (f lst)
    (if (not (null? lst))
      (do (f (first lst)) (for-each f (rest lst))))))

  (def flat-map (fn (f lst)
    (if (null? lst) ()
      (append (f (first lst)) (flat-map f (rest lst))))))

  ; =========================================================
  ; List predicates (needed by combinators below)
  ; =========================================================
  (def any? (fn (pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst)) t)
      (t (any? pred (rest lst))))))

  (def every? (fn (pred lst)
    (match
      ((null? lst) t)
      ((not (pred (first lst))) ())
      (t (every? pred (rest lst))))))

  (def none? (fn (pred lst) (not (any? pred lst))))

  (def empty? (fn (lst) (null? lst)))

  ; =========================================================
  ; Combinators that depend on map/filter/append/any?/every?
  ; =========================================================
  (def complement (fn (pred) (fn args (not (apply pred args)))))
  (def partial (fn (f . bound) (fn args (apply f (append bound args)))))
  (def juxt (fn fns (fn args (map (fn (f) (apply f args)) fns))))
  (def both (fn (f g) (fn (x) (and (f x) (g x)))))
  (def either (fn (f g) (fn (x) (or (f x) (g x)))))
  (def all-pass (fn (preds) (fn (x) (every? (fn (p) (p x)) preds))))
  (def any-pass (fn (preds) (fn (x) (any? (fn (p) (p x)) preds))))
  (def reject (fn (pred lst) (filter (complement pred) lst)))
  (def concat (fn lsts (fold append () lsts)))
  (def sum (fn (lst) (fold + 0 lst)))
  (def product (fn (lst) (fold * 1 lst)))

  ; =========================================================
  ; List search
  ; =========================================================
  (def find (fn (pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst)) (first lst))
      (t (find pred (rest lst))))))

  (def find-index (fn (pred lst)
    (def go (fn (i lst)
      (match
        ((null? lst) (- 0 1))
        ((pred (first lst)) i)
        (t (go (+ i 1) (rest lst))))))
    (go 0 lst)))

  (def index-of (fn (x lst)
    (find-index (fn (el) (equal? el x)) lst)))

  (def includes? (fn (x lst)
    (match
      ((null? lst) ())
      ((equal? x (first lst)) t)
      (t (includes? x (rest lst))))))

  (def count (fn (pred lst)
    (fold (fn (acc x) (if (pred x) (+ acc 1) acc)) 0 lst)))

  ; =========================================================
  ; List slicing
  ; =========================================================
  (def take (fn (n lst)
    (if (or (<= n 0) (null? lst)) ()
      (pair (first lst) (take (- n 1) (rest lst))))))

  (def drop (fn (n lst)
    (if (or (<= n 0) (null? lst)) lst
      (drop (- n 1) (rest lst)))))

  (def take-while (fn (pred lst)
    (if (or (null? lst) (not (pred (first lst)))) ()
      (pair (first lst) (take-while pred (rest lst))))))

  (def drop-while (fn (pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst)) (drop-while pred (rest lst)))
      (t lst))))

  (def split-at (fn (n lst)
    (list (take n lst) (drop n lst))))

  (def slice (fn (start end lst)
    (take (- end start) (drop start lst))))

  ; =========================================================
  ; List generators
  ; =========================================================
  (def range (fn (start end)
    (if (>= start end) ()
      (pair start (range (+ start 1) end)))))

  (def repeat (fn (x n)
    (if (<= n 0) ()
      (pair x (repeat x (- n 1))))))

  (def times (fn (f n)
    (def go (fn (i)
      (if (>= i n) ()
        (pair (f i) (go (+ i 1))))))
    (go 0)))

  (def unfold (fn (pred f g seed)
    (if (pred seed) ()
      (pair (f seed) (unfold pred f g (g seed))))))

  (def iterate (fn (f n x)
    (if (<= n 0) ()
      (pair x (iterate f (- n 1) (f x))))))

  (def zip (fn (a b)
    (if (or (null? a) (null? b)) ()
      (pair (list (first a) (first b))
            (zip (rest a) (rest b))))))

  (def zip-with (fn (f a b)
    (if (or (null? a) (null? b)) ()
      (pair (f (first a) (first b))
            (zip-with f (rest a) (rest b))))))

  ; =========================================================
  ; List transformation
  ; =========================================================
  (def partition (fn (pred lst)
    (def go (fn (lst yes no)
      (match
        ((null? lst) (list (reverse yes) (reverse no)))
        ((pred (first lst))
          (go (rest lst) (pair (first lst) yes) no))
        (t (go (rest lst) yes (pair (first lst) no))))))
    (go lst () ())))

  (def group-by (fn (f lst)
    (def add-to-group (fn (alist key val)
      (match
        ((null? alist) (list (pair key (list val))))
        ((eq? (first (first alist)) key)
          (pair (pair key (append (rest (first alist)) (list val)))
                (rest alist)))
        (t (pair (first alist) (add-to-group (rest alist) key val))))))
    (fold (fn (acc x) (add-to-group acc (f x) x)) () lst)))

  (def sort (fn (cmp lst)
    (def merge (fn (a b)
      (match
        ((null? a) b)
        ((null? b) a)
        ((cmp (first a) (first b))
          (pair (first a) (merge (rest a) b)))
        (t (pair (first b) (merge a (rest b)))))))
    (def split (fn (lst a b)
      (match
        ((null? lst) (list a b))
        ((null? (rest lst)) (list (pair (first lst) a) b))
        (t (split (rest (rest lst))
                  (pair (first lst) a)
                  (pair (first (rest lst)) b))))))
    (if (or (null? lst) (null? (rest lst))) lst
      (let ((halves (split lst () ())))
        (merge (sort cmp (first halves))
               (sort cmp (first (rest halves))))))))

  (def sort-by (fn (f lst)
    (sort (fn (a b) (< (f a) (f b))) lst)))

  (def uniq (fn (lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (first lst) (first (rest lst))) (uniq (rest lst)))
      (t (pair (first lst) (uniq (rest lst)))))))

  (def uniq-by (fn (f lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      ((equal? (f (first lst)) (f (first (rest lst))))
        (uniq-by f (rest lst)))
      (t (pair (first lst) (uniq-by f (rest lst)))))))

  (def intersperse (fn (sep lst)
    (match
      ((null? lst) ())
      ((null? (rest lst)) lst)
      (t (pair (first lst)
               (pair sep (intersperse sep (rest lst))))))))

  (def transpose (fn (lsts)
    (if (or (null? lsts) (any? null? lsts)) ()
      (pair (map first lsts)
            (transpose (map rest lsts))))))

  (def update (fn (n val lst)
    (match
      ((null? lst) ())
      ((= n 0) (pair val (rest lst)))
      (t (pair (first lst) (update (- n 1) val (rest lst)))))))

  (def insert (fn (n val lst)
    (if (<= n 0) (pair val lst)
      (pair (first lst) (insert (- n 1) val (rest lst))))))

  (def remove (fn (start n lst)
    (match
      ((null? lst) ())
      ((> start 0)
        (pair (first lst) (remove (- start 1) n (rest lst))))
      ((> n 0) (remove 0 (- n 1) (rest lst)))
      (t lst))))

  (def adjust (fn (n f lst)
    (match
      ((null? lst) ())
      ((= n 0) (pair (f (first lst)) (rest lst)))
      (t (pair (first lst) (adjust (- n 1) f (rest lst)))))))

  ; =========================================================
  ; Association list operations
  ; =========================================================
  ; Alists: ((key1 . val1) (key2 . val2) ...)
  ; Keys compared with eq? (symbol pointer equality)

  (def aget (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (rest (first alist)))
      (t (aget key (rest alist))))))

  (def aget-or (fn (d key alist)
    (def result (aget key alist))
    (if (null? result) d result)))

  (def ahas? (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) t)
      (t (ahas? key (rest alist))))))

  (def adel (fn (key alist)
    (match
      ((null? alist) ())
      ((eq? key (first (first alist))) (adel key (rest alist)))
      (t (pair (first alist) (adel key (rest alist)))))))

  (def aset (fn (key val alist)
    (pair (pair key val) (adel key alist))))

  (def akeys (fn (alist) (map first alist)))

  (def avals (fn (alist) (map rest alist)))

  (def amap (fn (f alist)
    (map (fn (entry) (pair (first entry) (f (rest entry)))) alist)))

  (def afilter (fn (pred alist) (filter pred alist)))

  (def amerge (fn (a b)
    (fold (fn (acc entry)
      (if (ahas? (first entry) acc) acc
        (pair entry acc)))
      a b)))

  (def apick (fn (keys alist)
    (filter (fn (entry) (includes? (first entry) keys)) alist)))

  (def aomit (fn (keys alist)
    (filter (fn (entry) (not (includes? (first entry) keys))) alist)))

  (def from-pairs (fn (lst)
    (map (fn (p) (pair (first p) (first (rest p)))) lst)))

  (def to-pairs (fn (alist)
    (map (fn (entry) (list (first entry) (rest entry))) alist)))

  (def evolve (fn (fns alist)
    (map (fn (entry)
      (def transform (aget (first entry) fns))
      (if (null? transform) entry
        (pair (first entry) (transform (rest entry)))))
      alist)))

  ; =========================================================
  ; String utilities
  ; =========================================================
  (def string-empty? (fn (s) (= (string-length s) 0)))

  (def string-join (fn (sep lst)
    (match
      ((null? lst) "")
      ((null? (rest lst)) (first lst))
      (t (fold (fn (acc s) (string-append acc (string-append sep s)))
               (first lst) (rest lst))))))

  (def string-repeat (fn (s n)
    (if (<= n 0) ""
      (string-append s (string-repeat s (- n 1))))))

  (def string-contains? (fn (sub s)
    (def sub-len (string-length sub))
    (def s-len (string-length s))
    (def go (fn (i)
      (match
        ((> (+ i sub-len) s-len) ())
        ((string=? (substring s i (+ i sub-len)) sub) t)
        (t (go (+ i 1))))))
    (if (= sub-len 0) t (go 0))))

  (def string-starts? (fn (pfx s)
    (def pfx-len (string-length pfx))
    (if (> pfx-len (string-length s)) ()
      (string=? (substring s 0 pfx-len) pfx))))

  (def string-ends? (fn (sfx s)
    (def sfx-len (string-length sfx))
    (def s-len (string-length s))
    (if (> sfx-len s-len) ()
      (string=? (substring s (- s-len sfx-len) s-len) sfx))))

  (def string-reverse (fn (s)
    (def len (string-length s))
    (def go (fn (i acc)
      (if (< i 0) acc
        (go (- i 1) (string-append acc (string-ref s i))))))
    (go (- len 1) "")))

  ; =========================================================
  ; Vectors
  ; =========================================================
  (def %vector (make-type "VECTOR"
    (list
      (pair (lit call) (fn (self . args)
        ((first self) (first args))))
      (pair (lit write) (fn (self)
        (display "#(")
        (def write-vec (fn (lst sep)
          (if (not (null? lst))
            (do (if sep (display " "))
                (write (first lst))
                (write-vec (rest lst) t)))))
        (write-vec (first self) ())
        (display ")"))))))

  (def vector (fn args (make-instance %vector args)))
  (def vector? (fn (x) (type? x %vector)))
  (def vector-ref (fn (v i) (v i)))
  (def vector-length (fn (v)
    (fold (fn (acc x) (+ acc 1)) 0 (first v))))
  (def vector->list (fn (v) (first v)))
  (def list->vector (fn (lst) (make-instance %vector lst)))
  (def make-vector (fn (n fill)
    (def build (fn (i acc)
      (if (= i 0) acc (build (- i 1) (pair fill acc)))))
    (make-instance %vector (build n ()))))

  ()
)
