; list.x -- List operations (boot layer)
;
; THE TOP LEVEL IS SACRED (#108): the walkers here are %-private boot
; plumbing -- the PUBLIC face is the List class (lib/x/type/list.x).
; Round 1 (2026-07-21) retired the bare spellings fold/length/append/
; reverse/map/filter/for-each; boot-internal callers use the %-names.
(import x/core/logic)

(doc (def %as-list
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
  "Boot-layer plumbing: normalize any iterable to a list (%fold/%map/%filter self-normalize through it). The PUBLIC conversion surface is (List from-seq); this % helper is not provided.")

(note "Folds")

; The already-normalized loop: %as-list runs ONCE in the public entry.
; The old self-recursion re-entered through (let ((lst (%as-list lst))))
; on EVERY step -- ~575 objects per element, multiplied through the
; arithmetic wrappers into the system-wide allocation disease.
(def %fold-go
  (fn (self f acc lst)
    (if (null? lst) acc
      (self f (f acc (first lst)) (rest lst)))))

(doc (def %fold
  (fn (_ (param f CALLABLE "Binary function: (accumulator, element) -> new accumulator")
       (param init ANY "Initial accumulator value")
       (param lst LIST "List or iterable to fold over"))
    (%fold-go f init (%as-list lst))))
  (returns ANY "Final accumulated value")
  "Boot-layer fold; the public face is (List fold).")

(note "Basics")

(doc (def %length
  (fn (_ (param lst LIST "List or iterable"))
    (%fold (fn (_ acc _) (+ acc 1)) 0 lst)))
  "Boot-layer length; the public face is (List length).")

(def %append2
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))

(doc (def %append (fn (_ . args) (%fold %append2 () args)))
  "Boot-layer append; the public face is (List append).")

(doc (def %reverse
  (fn (_ (param lst LIST "List or iterable"))
    (%fold (fn (_ acc x) (pair x acc)) () lst)))
  "Boot-layer reverse; the public face is (List reverse).")

(note "Iteration")

(def %any-null?
  (fn (self lsts)
    (if (null? lsts)
      ()
      (if (null? (first lsts)) #t (self (rest lsts))))))

; first/rest are unchecked, so an improper tail walks off the end into UB.
; The Err lookup resolves at CALL time, long after err.x loads (x-core.x:221),
; and nothing in boot maps over an improper list -- so the guard is safe here
; even though this module loads at :113.
(def %map1
  (fn (self f lst)
    (match
      ((null? lst) ())
      ((not (pair? lst)) (Err raise (lit type) "map: improper list" ()))
      (#t (pair (f (first lst)) (self f (rest lst)))))))

; Multi-list loop, inputs already normalized (the old recursion went
; back through the public entry, re-as-listing every tail per step).
(def %mapn-go
  (fn (self f lsts)
    (if (%any-null? lsts)
      ()
      (pair
        (apply f (%map1 first lsts))
        (self f (%map1 rest lsts))))))

(doc (def %map
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 %as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (%mapn-go f lsts)))))
  (returns LIST "New list")
  "Boot-layer map; the public face is (List map).")

; Already-normalized loop; see %fold-go.
(def %filter-go
  (fn (self pred lst)
    (match
      ((null? lst) ())
      ((pred (first lst))
        (pair (first lst) (self pred (rest lst))))
      (#t (self pred (rest lst))))))

(doc (def %filter
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (%filter-go pred (%as-list lst))))
  (returns LIST "Filtered list")
  "Boot-layer filter; the public face is (List filter).")

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

(doc (def %for-each
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 %as-list lsts)))
      (if (null? (rest lsts))
        (%for-each1 f (first lsts))
        (%for-eachn-go f lsts)))))
  "Boot-layer for-each; the public face is (List for-each).")

; else and str-copy RETIRED by ruling (#108, 2026-07-22): cond/case match
; the SYMBOL else -- (lit else) -- so (else ...) clauses never needed the
; global; a string copy is (Str8 sub 0 (Str8 length s) s).

(doc (provide x/core/list)
  (note "Boot list layer: %-private walkers only (the top level is sacred, #108); the public list API is the List class.")
  (example "(List map (method-ref Num inc) '(1 2 3))" "(2 3 4)")
  "Boot-layer list plumbing; public list processing lives on the List class.")
