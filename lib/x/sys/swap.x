; swap.x -- Swap: a slow value set aside for a faster one, and put back
;
; The library is interpreted, and the fast form of a piece of it -- compiled
; code, most often -- is made once the slow form is in place and working.
; A site records one such replacement: the seat the value sits in, the slow
; value that belongs there (the twin), and the maker that makes the fast
; one.  The twin stays the reference: a maker that raises, or that answers
; the twin itself, leaves the twin seated, and the site says which.
;
; A made value is often this process's alone.  Native code sits in a page
; this process mapped, and a state image cannot carry it
; (docs/state-images.md, "Compiled code: put down before the write, picked
; up after the load").  So every site goes down before an image is written
; and comes up again once one is loaded: this module adds one thunk to the
; transients, which puts every site down, and each site adds its own recache
; hook as it is made.  The hook is the site's own so that it runs after the
; hooks of everything loaded before the site: a maker's compiler has its
; addresses back before the maker runs, and a maker that reads an earlier
; site's value finds the one just made.
;
; A seat is a function of one value that puts the value in place.  (Swap
; in-env) and (Swap in-cell) make the two seats the library has needed; any
; other place a value can be put is a function written where it is known.
;
; The forms below keep to fn, if and match.  A lang bundle may give `do` a
; meaning of its own (boot/reflect.x, at %image-recache!), and this module
; is one a bundle imports.

(module x/sys/swap)
(import x/type/class)

; Object identity, as boot/module.x has it: eq? compares the operand word,
; and two closures share theirs.
(def %swap-same? (prim-ref (lit obj) (lit same?)))
; A raise is kept as its text.  The engine raises one value and fills it
; again at the next raise, so the value itself would not keep.
(def %swap-text (prim-ref (lit io) (lit display-to-str)))
(def %swap-set! (prim-ref (lit obj) (lit set!)))
; The doors to the image writer's transients and the loader's recache hooks
; (boot/reflect.x).
(def %swap-transient! (prim-ref (lit image) (lit transient!)))
(def %swap-recache-hook! (prim-ref (lit image) (lit recache-hook!)))

(def-class Swap ()
  (doc "One replacement of a slow value by a faster one: the seat, the twin that belongs in it, and the maker of the fast value. (Swap site! ...) makes one and brings it up; (Swap report) lists them."
    (see site!) (see report))

  (doc name "What the report calls the site")
  (doc twin "The slow value, which the seat holds whenever the site is not up")
  (doc maker "(fn (_)) answering the fast value; a raise refuses, and answering the twin declines")
  (doc seat "(fn (_ value)) putting a value in place")
  (doc state "up, twin, refused or down; a site is brought up as it is made")
  (doc reason "The text of the raise that refused the site, or the empty string")
  (doc value "The made value while the site is up, and nil otherwise")

  (method %seat! (self v state reason)
    ((self seat) v)
    (self value (if (eq? state (lit up)) v ()))
    (self reason reason)
    (self state state)
    state)

  (method up! (self)
    (doc "Run the maker and seat what it makes. A maker that raises is refused: the twin is seated and the raise's text is kept as the reason. A maker that answers the twin has declined, and the state says so."
      (returns SYMBOL "The state the site is left in: up, twin or refused"))
    ; The answer is tagged, so that a maker answering nil is told from one
    ; that raised.
    ((fn (_ made)
       (if (first made)
         (self %seat! (rest made)
               (if (%swap-same? (rest made) (self twin)) (lit twin) (lit up))
               "")
         (self %seat! (self twin) (lit refused) (rest made))))
     (guard (e (pair #f (%swap-text e)))
       (pair #t ((self maker))))))

  (method down! (self)
    (doc "Seat the twin and let go of the made value, so that nothing the site holds is this process's alone."
      (returns SYMBOL "down"))
    (self %seat! (self twin) (lit down) ""))

  (static
    (doc all "Every site made, newest first")

    (method site! (self (param name SYMBOL "What the report calls the site")
                        (param twin ANY "The slow value, in its seat already")
                        (param maker CALLABLE "(fn (_)) answering the fast value; a raise refuses, and answering the twin declines")
                        (param seat CALLABLE "(fn (_ value)) putting a value in place; see in-env and in-cell"))
      (doc "Record a site and bring it up. The site goes down with every other before a state image is written, and comes up again after one is loaded, in the order the sites were made."
        (returns Swap "The site")
        (see in-env) (see in-cell) (see up!))
      ((fn (_ s)
         (s up!)
         (Swap all (pair s (Swap all)))
         ; After the maker has run: what it loaded has added its own hooks
         ; by now, and this one follows them.
         (%swap-recache-hook! (fn (_) (s up!)))
         s)
       (new Swap name name twin twin maker maker seat seat)))

    (method in-env (self (param name SYMBOL "The name to set")
                         (param env ANY "The environment the name is bound in"))
      (doc "A seat that is a name's binding: seating a value sets the name in that environment."
        (returns CALLABLE "(fn (_ value))"))
      (fn (_ v) (eval (list (lit set!) name (list (lit lit) v)) env)))

    (method in-cell (self (param cell PAIR "The pair whose first is the seat"))
      (doc "A seat that is the first of a pair, such as one cell of a type's handler list."
        (returns CALLABLE "(fn (_ value))"))
      (fn (_ v) (%swap-set! cell 0 v)))

    (method named (self (param name SYMBOL "A site's name"))
      (doc "The newest site of that name."
        (returns Swap "The site, or nil when no site has the name"))
      ((fn (loop l)
         (if (null? l)
           ()
           (if (eq? ((first l) name) name) (first l) (loop (rest l)))))
       (Swap all)))

    (method down! (self)
      (doc "Put every site down, newest first. The image writer does this before its walk."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ s) (s down!) (loop (rest l))) (first l))))
       (Swap all)))

    (method up! (self)
      (doc "Bring every site up, oldest first, so that a maker which reads an earlier site's value finds the one just made."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ s) (loop (rest l)) (s up!) ()) (first l))))
       (Swap all)))

    (method rows (self)
      (doc "The state of every site, oldest first."
        (returns LIST "One (name state reason) list for each site"))
      ((fn (loop l acc)
         (if (null? l)
           acc
           ((fn (_ s)
              (loop (rest l)
                    (pair (list (s name) (s state) (s reason)) acc)))
            (first l))))
       (Swap all) ()))

    (method report (self)
      (doc "Print the state of every site, oldest first: its name, its state, and the reason when it was refused."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ row)
              (display (first row) "\t" (first (rest row)))
              (if (eq? (first (rest row)) (lit refused))
                (display "\t" (first (rest (rest row))))
                ())
              (display "\n")
              (loop (rest l)))
            (first l))))
       (Swap rows)))))

; The writer runs this inside the child it images, before its walk.
(%swap-transient! (fn (_) (Swap down!)))

(doc (provide x/sys/swap Swap)
  "Sites: a slow value set aside for a faster one, put back before a state image is written and made again after one is loaded, with a report of which are up.")
