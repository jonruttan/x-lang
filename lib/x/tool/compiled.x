; compiled.x -- Compiled: a function that has a compiled version, and the
; list of them
;
; The library is interpreted, and a function that matters for speed is
; compiled once its interpreted version is in place and working.  An entry
; here is one such function: its interpreted version, the function that
; compiles it, the function that installs either version where it is
; called from, and the compiled version once there is one.  The interpreted
; version stays the reference: when compiling raises, or answers the
; interpreted version itself, the interpreted one stays installed and the
; entry says which happened.
;
; Compiled code is machine code in a page this process mapped, and a state
; image cannot carry it (docs/state-images.md, "Compiled code: put down
; before the write, picked up after the load").  So every entry is switched
; to its interpreted version before an image is written, and compiled again
; once one is loaded.  This module adds one thunk to the image writer's
; transients, which switches every entry to interpreted, and each entry
; adds its own recache hook as it is made.  The hook is the entry's own so
; that it runs after the hooks of everything loaded before the entry: the
; compiler has its addresses back before the entry compiles, and an entry
; that reads an earlier one's compiled version finds the one just made.  An
; entry made on demand adds no hook: it stays interpreted after a load
; until its owner compiles it.
;
; (Compiled into-name) and (Compiled into-cell) make the two install
; functions the library has needed; any other place a function can be
; installed is a function of one value written where the place is known.
;
; The forms below keep to fn, if and match.  A lang bundle may give `do` a
; meaning of its own (boot/reflect.x, at %image-recache!), and this module
; is one a bundle imports.

(module x/tool/compiled)
(import x/type/class)

; Object identity, as boot/module.x has it: eq? compares the operand word,
; and two closures share theirs.
(def %compiled-same? (prim-ref (lit obj) (lit same?)))
; A raise is kept as its text.  The engine raises one value and fills it
; again at the next raise, so the value itself would not keep.
(def %compiled-text (prim-ref (lit io) (lit display-to-str)))
(def %compiled-set! (prim-ref (lit obj) (lit set!)))
; The doors to the image writer's transients and the loader's recache hooks
; (boot/reflect.x).
(def %compiled-transient! (prim-ref (lit image) (lit transient!)))
(def %compiled-recache-hook! (prim-ref (lit image) (lit recache-hook!)))

(def-class Compiled ()
  (doc "A function that has a compiled version: its interpreted version, the function that compiles it, and the function that installs either. (Compiled make ...) adds one to the list and compiles it; (Compiled report) prints the list."
    (see make) (see report))

  (doc name "What the list calls the function")
  (doc interpreted "The interpreted version, which is installed whenever the compiled one is not")
  (doc compile "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines")
  (doc install "(fn (_ version)) installing a version where the function is called from")
  (doc (state (lit interpreted)) "compiled, interpreted or failed")
  (doc (reason "") "The text of the raise that failed the compile, or the empty string")
  (doc compiled "The compiled version while it is installed, and nil otherwise")

  (method %install! (self version state reason)
    ((self install) version)
    (self compiled (if (eq? state (lit compiled)) version ()))
    (self reason reason)
    (self state state)
    state)

  (method compile! (self)
    (doc "Compile the function and install the compiled version. A compile that raises has failed: the interpreted version is installed and the raise's text is kept as the reason. A compile that answers the interpreted version has declined, and the interpreted version is installed."
      (returns SYMBOL "The state the entry is left in: compiled, interpreted or failed"))
    ; The answer is labelled, so that a compile answering nil is told from one
    ; that raised.
    ((fn (_ made)
       (if (first made)
         (self %install! (rest made)
               (if (%compiled-same? (rest made) (self interpreted))
                 (lit interpreted)
                 (lit compiled))
               "")
         (self %install! (self interpreted) (lit failed) (rest made))))
     (guard (e (pair #f (%compiled-text e)))
       (pair #t ((self compile))))))

  (method interpret! (self)
    (doc "Install the interpreted version and let go of the compiled one, so that nothing the entry holds is this process's alone."
      (returns SYMBOL "interpreted"))
    (self %install! (self interpreted) (lit interpreted) ""))

  (static
    (doc all "Every entry, newest first")

    (method make (self (param name SYMBOL "What the list calls the function")
                       (param interpreted ANY "The interpreted version, installed already")
                       (param compile CALLABLE "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines")
                       (param install CALLABLE "(fn (_ version)) installing a version; see into-name and into-cell"))
      (doc "Add a function to the list and compile it. Every entry is switched to interpreted before a state image is written, and compiled again after one is loaded, in the order the entries were made."
        (returns Compiled "The entry")
        (see make-on-demand) (see into-name) (see into-cell))
      ((fn (_ c)
         (c compile!)
         (Compiled all (pair c (Compiled all)))
         ; After the compile has run: what it loaded has added its own
         ; hooks by now, and this one follows them.
         (%compiled-recache-hook! (fn (_) (c compile!)))
         c)
       (new Compiled name name interpreted interpreted
                     compile compile install install)))

    (method make-on-demand (self (param name SYMBOL "What the list calls the function")
                                 (param interpreted ANY "The interpreted version, installed already")
                                 (param compile CALLABLE "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines")
                                 (param install CALLABLE "(fn (_ version)) installing a version; see into-name and into-cell"))
      (doc "Add a function to the list and compile it, as make does, for a compile that is dear and not always wanted. The entry is switched to interpreted with every other before a state image is written, and stays interpreted after one is loaded until its owner sends it compile!."
        (returns Compiled "The entry")
        (see make) (see compile!))
      ((fn (_ c)
         (c compile!)
         (Compiled all (pair c (Compiled all)))
         c)
       (new Compiled name name interpreted interpreted
                     compile compile install install)))

    (method into-name (self (param name SYMBOL "The name to set")
                            (param env ANY "The environment the name is bound in"))
      (doc "An install function for a name's binding: installing a version sets the name in that environment."
        (returns CALLABLE "(fn (_ version))"))
      (fn (_ v) (eval (list (lit set!) name (list (lit lit) v)) env)))

    (method into-cell (self (param cell PAIR "The pair whose first holds the function"))
      (doc "An install function for the first of a pair, such as one cell of a type's handler list."
        (returns CALLABLE "(fn (_ version))"))
      (fn (_ v) (%compiled-set! cell 0 v)))

    (method named (self (param name SYMBOL "An entry's name"))
      (doc "The newest entry of that name."
        (returns Compiled "The entry, or nil when no entry has the name"))
      ((fn (loop l)
         (if (null? l)
           ()
           (if (eq? ((first l) name) name) (first l) (loop (rest l)))))
       (Compiled all)))

    (method interpret-all! (self)
      (doc "Switch every entry to its interpreted version, newest first. The image writer does this before its walk."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ c) (c interpret!) (loop (rest l))) (first l))))
       (Compiled all)))

    (method compile-all! (self)
      (doc "Compile every entry, oldest first, so that an entry which reads an earlier one's compiled version finds the one just made."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ c) (loop (rest l)) (c compile!) ()) (first l))))
       (Compiled all)))

    (method list (self)
      (doc "The state of every entry, oldest first."
        (returns LIST "One (name state reason) list for each entry"))
      ((fn (loop l acc)
         (if (null? l)
           acc
           ((fn (_ c)
              (loop (rest l)
                    (pair (pair (c name) (pair (c state) (pair (c reason) ())))
                          acc)))
            (first l))))
       (Compiled all) ()))

    (method report (self)
      (doc "Print the list, oldest first: each function's name, its state, and the reason when its compile failed."
        (returns NIL "nil"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ row)
              (display (first row) "\t" (first (rest row)))
              (if (eq? (first (rest row)) (lit failed))
                (display "\t" (first (rest (rest row))))
                ())
              (display "\n")
              (loop (rest l)))
            (first l))))
       (Compiled list)))))

; The writer runs this inside the child it images, before its walk.
(%compiled-transient! (fn (_) (Compiled interpret-all!)))

(doc (provide x/tool/compiled Compiled)
  "Functions that have a compiled version: switched to interpreted before a state image is written and compiled again after one is loaded, with a list of which are compiled.")
