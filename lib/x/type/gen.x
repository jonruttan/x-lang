; gen.x -- Gen: lazy generators.
;
; A generator is an UNFOLD: a step function over a state.
;   (step state) -> (value . next-state)   -- a value was produced
;   (step state) -> ()                       -- exhausted
; Nothing is materialised until a consumer drives it.  Transformers (map,
; filter, take, ...) are lazy and return a new Gen in O(1); consumers (->list,
; fold, for-each, sum, ...) drive a generator to a result.
;
; Because a Gen is an object, the fluent ((g map f) filter p) form is just
; ordinary method dispatch -- no list is built between stages.
;
; Loads after object.x (def-class), list.x (reverse) and vector.x (Vector).

(import x/type/class)
(import x/type/list)
(import x/type/vector)
(import x/type/iter)

; The functional C iterator step, cached (hot: per element in from-seq gens):
; (%gen-i-step it) -> (value . next-iterator) | () -- exactly the Gen step
; contract with the iterator object as the state.
(def %gen-i-step (prim-ref (lit iter) (lit step)))

(def-class Gen ()
  (doc "A lazy generator: a step function over a state, producing values on demand."
    (note "Build with range / range-by / count-from / repeat / iterate / from-list / from-seq / of, or the `make` primitive.")
    (note "Transformers (%map filter take drop take-while drop-while enumerate zip zip-with scan) are lazy -- each returns a new Gen.")
    (note "Consumers (->list ->vector for-each fold reduce count sum product any? all? none? find ref first last min max empty?) drive it.")
    (note "count-from / repeat / iterate are INFINITE -- bound them with take / take-while before any consumer.")
    (example "(((Gen range 0 6) filter (fn (_ x) (< x 3))) ->list)" "(0 1 2)"))
  (step ()) (state ())

  ; ==========================================================================
  ; Constructors
  ; ==========================================================================
  (static
    (method make (self (param step CALLABLE "(step state) -> (value . next-state) | ()")
                       (param state ANY "Initial state"))
      (doc "A generator from a raw step function and an initial state -- the primitive the rest build on."
        (returns GEN "Generator"))
      ; (lit ...) not 'quote: gen.x loads before lit-reader installs the ' macro
      (new-from Gen (list (lit step) step (lit state) state)))

    (method range (self (param start INT "Start (inclusive)") (param stop INT "Stop (exclusive)"))
      (doc "Integers from start up to (not including) stop."
        (returns GEN "Generator") (example "((Gen range 0 4) ->list)" "(0 1 2 3)"))
      ; N5: count/index seats coerce to INT at construction (vector.x's
      ; %vec->int, which loads before us); the lazy steps then run pure INTs.
      (def a (%vec->int start "Gen range: start not convertible to INT"))
      (def b (%vec->int stop "Gen range: stop not convertible to INT"))
      (Gen make (fn (_ i) (if (< i b) (pair i (+ i 1)) ())) a))

    (method range-by (self (param start INT "Start") (param stop INT "Stop (exclusive)") (param by INT "Step, may be negative but not zero"))
      (doc "Integers from start toward stop, stepping by `by`."
        (returns GEN "Generator") (example "((Gen range-by 0 10 3) ->list)" "(0 3 6 9)"))
      ; a zero step would never advance i, so the generator would never terminate
      (def a (%vec->int start "Gen range-by: start not convertible to INT"))
      (def b (%vec->int stop "Gen range-by: stop not convertible to INT"))
      (def d (%vec->int by "Gen range-by: step not convertible to INT"))
      (if (= d 0) (Err raise (lit value) "Gen range-by: step must be non-zero" ())
        (Gen make (fn (_ i) (if (if (> d 0) (< i b) (> i b)) (pair i (+ i d)) ())) a)))

    (method count-from (self (param start INT "First value"))
      (doc "INFINITE: start, start+1, start+2, ...  Bound with take / take-while."
        (returns GEN "Infinite generator") (example "(((Gen count-from 1) take 3) ->list)" "(1 2 3)"))
      (Gen make (fn (_ i) (pair i (+ i 1)))
        (%vec->int start "Gen count-from: start not convertible to INT")))

    (method repeat (self (param x ANY "Value to repeat"))
      (doc "INFINITE: x, x, x, ...  Bound with take."
        (returns GEN "Infinite generator") (example "(((Gen repeat 7) take 3) ->list)" "(7 7 7)"))
      ; x rides the STATE, never a closure capture: the step runs after
      ; this activation's env frame is restored, so a captured x falls
      ; through to any global x (doctest census caught exactly that --
      ; (def x 42) earlier in the batch turned (Gen repeat 7) into 42s).
      (Gen make (fn (_ st) (pair st st)) x))

    (method iterate (self (param f CALLABLE "Successor function") (param x ANY "Seed"))
      (doc "INFINITE: x, (f x), (f (f x)), ...  Bound with take / take-while."
        (returns GEN "Infinite generator")
        (example "(((Gen iterate (fn (_ n) (* n 2)) 1) take 4) ->list)" "(1 2 4 8)"))
      (Gen make (fn (_ s) (pair s (f s))) x))

    (method from-seq (self (param v ANY "Iterable value: list, vector, string, or instance"))
      (doc "A generator over any iterable value, driven functionally by the C iterator steps: the state is an Iter, stepped without mutation."
        (returns GEN "Generator") (example "((Gen from-seq (Vector of 1 2 3)) ->list)" "(1 2 3)"))
      (Gen make %gen-i-step (Iter new v)))

    (method from-list (self (param lst LIST "Source list"))
      (doc "A generator over a list's elements."
        (returns GEN "Generator") (example "((Gen from-list (list 1 2 3)) ->list)" "(1 2 3)"))
      (Gen make (fn (_ l) (if (null? l) () (pair (first l) (rest l)))) lst))

    (method of (self . (param args ANY "Values"))
      (doc "A generator over the given values."
        (returns GEN "Generator") (example "((Gen of 1 2 3) ->list)" "(1 2 3)"))
      (Gen from-list args)))

  ; one step: (value . next-state), or () when exhausted
  (method %next (self) ((self step) (self state)))

  ; ==========================================================================
  ; Lazy transformers -- each returns a new Gen
  ; ==========================================================================
  (method map (self (param f CALLABLE "Applied to each value"))
    (doc "A generator that applies f to each value (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 4) map (fn (_ x) (* x x))) ->list)" "(0 1 4 9)"))
    (let ((src (self step)))
      (Gen make (fn (_ st) (let ((s (src st))) (if (null? s) () (pair (f (first s)) (rest s))))) (self state))))

  (method filter (self (param p CALLABLE "Predicate"))
    (doc "A generator of the values for which p holds (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 6) filter (fn (_ x) (< x 3))) ->list)" "(0 1 2)"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st) (let loop ((st st)) (let ((s (src st))) (if (null? s) () (if (p (first s)) s (loop (rest s)))))))
        (self state))))

  (method take (self (param n INT "How many"))
    (doc "A generator of at most the first n values (lazy)."
      (returns GEN "Generator") (example "(((Gen count-from 0) take 3) ->list)" "(0 1 2)"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st)
          (if (<= (first st) 0) ()
            (let ((s (src (rest st)))) (if (null? s) () (pair (first s) (pair (- (first st) 1) (rest s)))))))
        (pair (%vec->int n "Gen take: count not convertible to INT") (self state)))))

  (method drop (self (param n INT "How many to skip"))
    (doc "A generator that skips the first n values (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 5) drop 2) ->list)" "(2 3 4)"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st)
          (let loop ((d (first st)) (ss (rest st)))
            (let ((s (src ss)))
              (if (null? s) () (if (> d 0) (loop (- d 1) (rest s)) (pair (first s) (pair 0 (rest s))))))))
        (pair (%vec->int n "Gen drop: count not convertible to INT") (self state)))))

  (method take-while (self (param p CALLABLE "Predicate"))
    (doc "Values up to (not including) the first for which p fails (lazy)."
      (returns GEN "Generator") (example "(((Gen count-from 1) take-while (fn (_ x) (< x 4))) ->list)" "(1 2 3)"))
    (let ((src (self step)))
      (Gen make (fn (_ st) (let ((s (src st))) (if (null? s) () (if (p (first s)) s ())))) (self state))))

  (method drop-while (self (param p CALLABLE "Predicate"))
    (doc "Skip the leading run for which p holds, then yield the rest (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 6) drop-while (fn (_ x) (< x 3))) ->list)" "(3 4 5)"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st)
          (if (first st)
            (let loop ((ss (rest st)))
              (let ((s (src ss)))
                (if (null? s) () (if (p (first s)) (loop (rest s)) (pair (first s) (pair #f (rest s)))))))
            (let ((s (src (rest st)))) (if (null? s) () (pair (first s) (pair #f (rest s)))))))
        (pair #t (self state)))))

  (method enumerate (self)
    (doc "Pair each value with its 0-based index: (index . value) (lazy)."
      (returns GEN "Generator") (example "(((Gen of 10 20) enumerate) ->list)" "((0 . 10) (1 . 20))"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st) (let ((s (src (rest st)))) (if (null? s) () (pair (pair (first st) (first s)) (pair (+ (first st) 1) (rest s))))))
        (pair 0 (self state)))))

  (method zip-with (self (param f CALLABLE "Combiner (a b) -> c") (param other GEN "Other generator"))
    (doc "Combine corresponding values of two generators with f; stops at the shorter (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 3) zip-with (fn (_ a b) (+ a b)) (Gen range 10 13)) ->list)" "(10 12 14)"))
    (let ((sa (self step)) (sb (other step)))
      (Gen make
        (fn (_ st)
          (let ((a (sa (first st))) (b (sb (rest st))))
            (if (if (null? a) #t (null? b)) () (pair (f (first a) (first b)) (pair (rest a) (rest b))))))
        (pair (self state) (other state)))))

  (method zip (self (param other GEN "Other generator"))
    (doc "Pair corresponding values of two generators; stops at the shorter (lazy)."
      (returns GEN "Generator") (example "(((Gen range 0 2) zip (Gen of 10 20)) ->list)" "((0 . 10) (1 . 20))"))
    (self zip-with (fn (_ a b) (pair a b)) other))

  (method scan (self (param f CALLABLE "(acc value) -> acc") (param init ANY "Initial accumulator"))
    (doc "Running left-fold: emits init's successive updates (lazy)."
      (returns GEN "Generator") (example "(((Gen range 1 5) scan (fn (_ a x) (+ a x)) 0) ->list)" "(1 3 6 10)"))
    (let ((src (self step)))
      (Gen make
        (fn (_ st) (let ((s (src (rest st)))) (if (null? s) () (let ((acc (f (first st) (first s)))) (pair acc (pair acc (rest s)))))))
        (pair init (self state)))))

  ; ==========================================================================
  ; Eager consumers -- drive the generator
  ; ==========================================================================
  (method fold (self (param f CALLABLE "(acc value) -> acc") (param acc ANY "Initial accumulator"))
    (doc "Left-fold f over every value." (returns ANY "Final accumulator")
      (example "((Gen range 1 5) fold (fn (_ a x) (+ a x)) 0)" "10"))
    (let ((step (self step)))
      (let go ((st (self state)) (acc acc)) (let ((s (step st))) (if (null? s) acc (go (rest s) (f acc (first s))))))))

  (method for-each (self (param f CALLABLE "Applied for side effects"))
    (doc "Apply f to each value, in order." (returns GEN "self"))
    (let ((step (self step)))
      (let go ((st (self state))) (let ((s (step st))) (if (null? s) self (do (f (first s)) (go (rest s))))))))

  (method ->list (self)
    (doc "Materialise the generator as a list." (returns LIST "All the values"))
    (%reverse (self fold (fn (_ acc x) (pair x acc)) ())))

  (method ->vector (self)
    (doc "Materialise the generator as a vector." (returns VECTOR "All the values"))
    (Vector from-list (self ->list)))

  (method count (self)
    (doc "Count the values by consuming the generator (not for infinite ones). Deliberately `count`, not `length`: a lazy stream has no length property -- counting it is an action."
      (returns INT "Count"))
    (self fold (fn (_ n _) (+ n 1)) 0))

  (method sum (self) (doc "Sum of the values." (returns NUMBER "Sum")) (self fold (fn (_ a x) (+ a x)) 0))
  (method product (self) (doc "Product of the values." (returns NUMBER "Product")) (self fold (fn (_ a x) (* a x)) 1))

  (method empty? (self)
    (doc "Test whether the generator yields no values. Peeks one step -- a Gen is persistent, so nothing is consumed." (returns BOOL "#t when empty"))
    (null? (self %next)))

  (method reduce (self (param f CALLABLE "(acc value) -> acc"))
    (doc "Fold using the first value as the seed; errors on an empty generator (empty? is the presence door)." (returns ANY "Reduced value"))
    (let ((s (self %next))) (if (null? s) (Err raise (lit value) "Gen reduce: empty generator" ()) ((Gen make (self step) (rest s)) fold f (first s)))))

  (method any? (self (param p CALLABLE "Predicate"))
    (doc "t if p holds for any value; short-circuits." (returns BOOL "t/f"))
    (let ((step (self step)))
      (let go ((st (self state))) (let ((s (step st))) (if (null? s) #f (if (p (first s)) #t (go (rest s))))))))

  (method all? (self (param p CALLABLE "Predicate"))
    (doc "t if p holds for every value; short-circuits." (returns BOOL "t/f"))
    (let ((step (self step)))
      (let go ((st (self state))) (let ((s (step st))) (if (null? s) #t (if (p (first s)) (go (rest s)) #f))))))

  (method none? (self (param p CALLABLE "Predicate"))
    (doc "t if p holds for no value." (returns BOOL "t/f"))
    (not (self any? p)))

  (method find (self (param p CALLABLE "Predicate"))
    (doc "The first value satisfying p, or ()." (returns ANY "Value or nil"))
    (let ((step (self step)))
      (let go ((st (self state))) (let ((s (step st))) (if (null? s) () (if (p (first s)) (first s) (go (rest s))))))))

  (method ref (self (param n INT "0-based index"))
    (doc "The n-th value (0-based); errors when n is negative (a lazy stream has no end to count from) or past the last value." (returns ANY "Value at n"))
    (def k (%vec->int n "Gen ref: index not convertible to INT"))
    (if (< k 0) (Err raise (lit index) "Gen ref: index out of range" ())
      (let ((step (self step)))
        (let go ((st (self state)) (n k)) (let ((s (step st))) (if (null? s) (Err raise (lit index) "Gen ref: index out of range" ()) (if (<= n 0) (first s) (go (rest s) (- n 1)))))))))

  (method first (self)
    (doc "The first value; errors on an empty generator (empty? is the presence door)." (returns ANY "First value"))
    (let ((s (self %next))) (if (null? s) (Err raise (lit value) "Gen first: empty generator" ()) (first s))))

  (method last (self)
    (doc "The last value; errors on an empty generator (drives the whole generator)." (returns ANY "Last value"))
    (let ((s (self %next)))
      (if (null? s) (Err raise (lit value) "Gen last: empty generator" ())
        (let ((step (self step)))
          (let go ((st (rest s)) (lastv (first s))) (let ((s2 (step st))) (if (null? s2) lastv (go (rest s2) (first s2)))))))))

  (method min (self)
    (doc "The least value; errors on an empty generator (drives the whole generator)." (returns ANY "Least value"))
    (self reduce (fn (_ a x) (if (< x a) x a))))

  (method max (self)
    (doc "The greatest value; errors on an empty generator (drives the whole generator)." (returns ANY "Greatest value"))
    (self reduce (fn (_ a x) (if (< a x) x a)))))

(doc (provide x/type/gen Gen)
  (note "Lazy generators (unfold-based): build (range/iterate/repeat/from-list/of),")
  (note "transform lazily (map/filter/take/drop/zip/scan/...), drive eagerly")
  (note "(->list/fold/sum/find/...). Transformers return a Gen, so chaining never")
  (note "builds an intermediate list.")
  (example "(((Gen range 0 6) filter (fn (_ x) (< x 3))) ->list)" "(0 1 2)")
  "Lazy generators: produce-on-demand sequences with the usual functional toolbox.")
