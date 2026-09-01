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
          ; Drain via %i-empty?/%i-next like (Iter ->list): APPLYING the
          ; iter object never advances it -- (it) yields a singleton of
          ; the iterator -- so the old (it) loop spun forever on every
          ; non-pair input (C-stack crash; nothing in boot hit it).  And
          ; accumulate + %rev-onto (tail), so depth is bounded.  All the
          ; names here resolve at CALL time, like Iter above and the Err
          ; note at %map1-go.
          (def %go (fn (self acc)
            (if (%i-empty? it) (%rev-onto acc ())
              (self (pair (%i-next it) acc)))))
          (%go ()))))))
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

; Reverse-prepend: the tail-shape list builder (one trampolined self-call
; per element, no C frame growth).  Every walker below that used to grow
; the C stack -- one eval frame group per element, a segfault at ~16K
; elements -- now accumulates through this and reverses once (#333).
(def %rev-onto
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))

(def %append2
  (fn (_ a b)
    (%rev-onto (%rev-onto a ()) b)))

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
; Accumulate + %rev-onto, NOT (pair (f x) (self ...)): the recursion in
; argument position put one C eval frame group per element on the stack,
; so any 16K-element map segfaulted (Str8 upcase maps every byte).  The
; tail self-call trampolines; depth is bounded.
(def %map1-go
  (fn (self f lst acc)
    (match
      ((null? lst) (%rev-onto acc ()))
      ((not (pair? lst)) (Err raise (lit type) "map: improper list" ()))
      (#t (self f (rest lst) (pair (f (first lst)) acc))))))

(def %map1 (fn (_ f lst) (%map1-go f lst ())))

; Multi-list loop, inputs already normalized (the old recursion went
; back through the public entry, re-as-listing every tail per step).
; Tail-shape accumulate, like %map1-go.
(def %mapn-go
  (fn (self f lsts acc)
    (if (%any-null? lsts)
      (%rev-onto acc ())
      (self f (%map1 rest lsts)
        (pair (apply f (%map1 first lsts)) acc)))))

(doc (def %map
  (fn (_ (param f CALLABLE "Function to apply") . (param lsts LIST "One or more lists"))
    (let ((lsts (%map1 %as-list lsts)))
      (if (null? (rest lsts))
        (%map1 f (first lsts))
        (%mapn-go f lsts ())))))
  (returns LIST "New list")
  "Boot-layer map; the public face is (List map).")

; Already-normalized loop; see %fold-go.  Accumulate + %rev-onto, like
; %map1-go: the keep branch recursed in argument position -- one C eval
; frame group per kept element, a segfault at ~16K.
(def %filter-go
  (fn (self pred lst acc)
    (match
      ((null? lst) (%rev-onto acc ()))
      ((pred (first lst))
        (self pred (rest lst) (pair (first lst) acc)))
      (#t (self pred (rest lst) acc)))))

(doc (def %filter
  (fn (_ (param pred CALLABLE "Predicate function")
       (param lst LIST "List or iterable"))
    (%filter-go pred (%as-list lst) ())))
  (returns LIST "Filtered list")
  "Boot-layer filter; the public face is (List filter).")

(note "Search")

; The eq?/str=? split below is inherent, not stylistic: symbols intern
; PER-BASE, so two spellings of one name from different bases never eq?,
; while strings always compare by content.  The names encode the side so
; every call site picks one deliberately (#227).

(doc (def %memq?
  (fn (self (param x ANY "Value to look for (eq? comparison)")
       (param lst LIST "List to search"))
    (match
      ((null? lst) #f)
      ((eq? x (first lst)) #t)
      (#t (self x (rest lst))))))
  (returns BOOL "True if x occurs in lst under eq?")
  (note "Boot-layer eq? membership; the public face is (List includes?). Cross-base names need %member-str?.")
  "Boot-layer eq? membership test.")

(doc (def %member-str?
  (fn (self (param s STR "String to look for (str=? comparison)")
       (param lst LIST "List of strings"))
    (match
      ((null? lst) #f)
      ((str=? s (first lst)) #t)
      (#t (self s (rest lst))))))
  (returns BOOL "True if s occurs in lst under str=?")
  (note "The str=? side of the membership split; convert cross-base symbols to strings and use this.")
  "Boot-layer string membership test.")

(doc (def %find
  (fn (self (param pred CALLABLE "Predicate")
       (param lst LIST "List to search"))
    (match
      ((null? lst) ())
      ((pred (first lst)) (first lst))
      (#t (self pred (rest lst))))))
  (returns ANY "First element satisfying pred, or nil")
  (note "Boot-layer find-first; the public face is (List find). A nil result conflates a stored nil with a miss -- box at the call site when that matters (the %opt-cell pattern).")
  "Boot-layer find-first matching element.")

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
