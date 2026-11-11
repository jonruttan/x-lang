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
; Compiled code runs from a page this process mapped, and a state image
; cannot carry the page (docs/state-images.md, "Compiled code: put down
; before the write, picked up after the load").  So every entry is switched
; to its interpreted version before an image is written, and compiled again
; once one is loaded.  A compile through compile-asm is then a copy and a
; patch: the assembler's cache holds the code and its relocation records in
; the heap, and the image carries those (lib/x/tool/asm-cache.x).  This
; module adds one thunk to the image writer's
; transients, which switches every entry to interpreted, and each entry
; adds its own recache hook as it is made.  The hook is the entry's own so
; that it runs after the hooks of everything loaded before the entry: the
; compiler has its addresses back before the entry compiles, and an entry
; that reads an earlier one's compiled version finds the one just made.  An
; entry made on demand adds no hook: it stays interpreted after a load
; until its owner compiles it.
;
; (Compiled into-name) and (Compiled into-cell) make install functions for
; a binding and for a cell.  (Compiled into-object) installs into the
; function object itself, for a function the library binds once in many
; places, such as the doors of x/core/doors: every holder of the object
; calls whichever version is installed.  Any other place a function can be
; installed is a function of one value written where the place is known.
;
; The forms below keep to fn, if and match.  A lang bundle may give `do` a
; meaning of its own (boot/reflect.x, at %image-recache!), and this module
; is one a bundle imports.

(module x/tool/compiled)
(import x/type/class)

; Object identity, as boot/module.x has it: eq? compares the operand word,
; and two closures share theirs.
(import x/core/doors image-recache-hook! image-transient! io-display-to-str obj-same? obj-set!
  obj->ptr ptr-ref-word ptr-set-word!)
; A raise is kept as its text.  The engine raises one value and fills it
; again at the next raise, so the value itself would not keep.
; The doors to the image writer's transients and the loader's recache hooks
; (boot/reflect.x).

; A function object, closure or primitive, is a type word and two data
; words: the routine a call runs, and the state it runs on (a closure's
; parameters, body and environment; nil for a primitive).  The collector
; follows the state only while the type is a closure's.  (%compiled-words!
; TO FROM) writes FROM's three words into TO, all three read before any is
; written, and answers TO.
(def %compiled-type-off (* %obj-slot-type %word-size))
(def %compiled-call-off (* %obj-meta-len %word-size))
(def %compiled-state-off (* (+ %obj-meta-len 1) %word-size))
(def %compiled-words!
  (fn (_ to from)
    ((fn (_ p type call state)
       (ptr-set-word! p %compiled-call-off call)
       (ptr-set-word! p %compiled-state-off state)
       (ptr-set-word! p %compiled-type-off type)
       to)
     (obj->ptr to)
     (ptr-ref-word (obj->ptr from) %compiled-type-off)
     (ptr-ref-word (obj->ptr from) %compiled-call-off)
     (ptr-ref-word (obj->ptr from) %compiled-state-off))))

(def-class Compiled ()
  (doc "A function that has a compiled version: its interpreted version, the function that compiles it, and the function that installs either. (Compiled make ...) adds one to the list and compiles it; (Compiled report) prints the list."
    (see make) (see report)
    (example "((new Compiled name 'f interpreted first compile (fn (_) rest) install (fn (_ v) v)) compile!)" "'compiled"))

  (doc name "What the list calls the function"
    (example "((new Compiled name 'f interpreted first) name)" "'f"))
  (doc interpreted "The interpreted version, which is installed whenever the compiled one is not"
    (example "(eq? ((new Compiled name 'f interpreted first) interpreted) first)" "#t"))
  (doc compile "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines"
    (example "(eq? (((new Compiled name 'f interpreted first compile (fn (_) rest)) compile)) rest)" "#t"))
  (doc install "(fn (_ version)) installing a version where the function is called from"
    (example "(do (def cell (pair first ())) (def c (new Compiled name 'f interpreted first compile (fn (_) rest) install (Compiled into-cell cell))) (c compile!) (eq? (first cell) rest))" "#t"))
  (doc (state (lit interpreted)) "compiled, interpreted or failed"
    (example "((new Compiled name 'f interpreted first) state)" "'interpreted"))
  (doc (reason "") "The text of the raise that failed the compile, or the empty string"
    (example "(do (def c (new Compiled name 'f interpreted first compile (fn (_) (Err raise 'value \"no compiler here\" ())) install (fn (_ v) v))) (c compile!) (c reason))" "\"value: no compiler here\""))
  (doc compiled "The compiled version while it is installed, and nil otherwise"
    (example "(null? ((new Compiled name 'f interpreted first) compiled))" "#t"))

  (method %install! (self version state reason)
    ((self install) version)
    (self compiled (if (eq? state (lit compiled)) version ()))
    (self reason reason)
    (self state state)
    state)

  (method compile! (self)
    (doc "Compile the function and install the compiled version. A compile that raises has failed: the interpreted version is installed and the raise's text is kept as the reason. A compile that answers the interpreted version has declined, and the interpreted version is installed."
      (returns SYMBOL "The state the entry is left in: compiled, interpreted or failed")
      (example "((new Compiled name 'f interpreted first compile (fn (_) (Err raise 'value \"no compiler here\" ())) install (fn (_ v) v)) compile!)" "'failed")
      (example "((new Compiled name 'f interpreted first compile (fn (_) first) install (fn (_ v) v)) compile!)" "'interpreted"))
    ; The answer is labelled, so that a compile answering nil is told from one
    ; that raised.
    ((fn (_ made)
       (if (first made)
         (self %install! (rest made)
               (if (obj-same? (rest made) (self interpreted))
                 (lit interpreted)
                 (lit compiled))
               "")
         (self %install! (self interpreted) (lit failed) (rest made))))
     (guard (e (pair #f (io-display-to-str e)))
       (pair #t ((self compile))))))

  (method interpret! (self)
    (doc "Install the interpreted version and let go of the compiled one, so that nothing the entry holds is this process's alone."
      (returns SYMBOL "interpreted")
      (example "(do (def c (new Compiled name 'f interpreted first compile (fn (_) rest) install (fn (_ v) v))) (c compile!) (list (c interpret!) (c compiled)))" "('interpreted ())"))
    (self %install! (self interpreted) (lit interpreted) ""))

  (static
    (doc all "Every entry, newest first"
      (sample "(List map (fn (_ c) (c name)) (Compiled all))" "the names of the entries this process made, newest first, as ('or 'and 'null? 'obj-set! 'obj-ref)"))

    (method make (self (param name SYMBOL "What the list calls the function")
                       (param interpreted ANY "The interpreted version, installed already")
                       (param compile CALLABLE "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines")
                       (param install CALLABLE "(fn (_ version)) installing a version; see into-name and into-cell"))
      (doc "Add a function to the list and compile it. Every entry is switched to interpreted before a state image is written, and compiled again after one is loaded, in the order the entries were made."
        (returns Compiled "The entry")
        (see make-on-demand) (see into-name) (see into-cell)
        (sample "(Compiled make 'fib fib fib-compile (Compiled into-name 'fib env))" "with fib-compile answering the compiled version: fib compiled and its binding set to the compiled version, kept on the list and compiled again after an image loads"))
      ((fn (_ c)
         (c compile!)
         (Compiled all (pair c (Compiled all)))
         ; After the compile has run: what it loaded has added its own
         ; hooks by now, and this one follows them.
         (image-recache-hook! (fn (_) (c compile!)))
         c)
       (new Compiled name name interpreted interpreted
                     compile compile install install)))

    (method make-on-demand (self (param name SYMBOL "What the list calls the function")
                                 (param interpreted ANY "The interpreted version, installed already")
                                 (param compile CALLABLE "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines")
                                 (param install CALLABLE "(fn (_ version)) installing a version; see into-name and into-cell"))
      (doc "Add a function to the list and compile it, as make does, for a compile that is dear and not always wanted. The entry is switched to interpreted with every other before a state image is written, and stays interpreted after one is loaded until its owner sends it compile!."
        (returns Compiled "The entry")
        (see make) (see compile!)
        (sample "(Compiled make-on-demand 'fib fib fib-compile (Compiled into-name 'fib env))" "as make, but after an image loads fib stays interpreted until (Compiled named 'fib) is sent compile!"))
      ((fn (_ c)
         (c compile!)
         (Compiled all (pair c (Compiled all)))
         c)
       (new Compiled name name interpreted interpreted
                     compile compile install install)))

    (method into-name (self (param name SYMBOL "The name to set")
                            (param env ANY "The environment the name is bound in"))
      (doc "An install function for a name's binding: installing a version sets the name in that environment."
        (returns CALLABLE "(fn (_ version))")
        (example "(do (def f 1) ((op () env ((Compiled into-name 'f env) 2))) f)" "2"))
      (fn (_ v) (eval (list (lit set!) name (list (lit lit) v)) env)))

    (method into-cell (self (param cell PAIR "The pair whose first holds the function"))
      (doc "An install function for the first of a pair, such as one cell of a type's handler list."
        (returns CALLABLE "(fn (_ version))")
        (example "(do (def cell (pair 1 2)) ((Compiled into-cell cell) 5) (first cell))" "5"))
      (fn (_ v) (obj-set! cell 0 v)))

    (method into-object (self (param target CALLABLE "The function object to rewrite"))
      (doc "An install function for the function object itself: installing a version writes its type and its two data words into TARGET, so every holder of TARGET calls that version. TARGET keeps its flags and its identity."
        (returns CALLABLE "(fn (_ version))")
        (see in-place)
        (example "(do (def g (fn (_) 1)) ((Compiled into-object g) (fn (_) 2)) (g))" "2"))
      (fn (_ v) (%compiled-words! target v)))

    (method in-place (self (param name SYMBOL "What the list calls the function")
                           (param target CALLABLE "The function to compile where it stands")
                           (param compile CALLABLE "(fn (_)) answering the compiled version; a raise fails, and answering the interpreted version declines"))
      (doc "Add a function to the list as make does, installed into TARGET itself (into-object). The interpreted version is a new function object holding TARGET's two data words, which keeps TARGET's body alive while TARGET holds the compiled version."
        (returns Compiled "The entry")
        (see make) (see into-object)
        (sample "(Compiled in-place 'obj-ref obj-ref obj-ref-compile)" "with obj-ref-compile answering the compiled version: every holder of obj-ref now calls the compiled version"))
      (Compiled make name (%compiled-words! (fn (_ . a) a) target) compile
                (Compiled into-object target)))

    (method named (self (param name SYMBOL "An entry's name"))
      (doc "The newest entry of that name."
        (returns Compiled "The entry, or nil when no entry has the name")
        (example "(null? (Compiled named 'no-such-entry))" "#t"))
      ((fn (loop l)
         (if (null? l)
           ()
           (if (eq? ((first l) name) name) (first l) (loop (rest l)))))
       (Compiled all)))

    (method interpret-all! (self)
      (doc "Switch every entry to its interpreted version, newest first. The image writer does this before its walk."
        (returns NIL "nil")
        (sample "(Compiled interpret-all!)" "every function on the list runs interpreted"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ c) (c interpret!) (loop (rest l))) (first l))))
       (Compiled all)))

    (method compile-all! (self)
      (doc "Compile every entry, oldest first, so that an entry which reads an earlier one's compiled version finds the one just made."
        (returns NIL "nil")
        (sample "(Compiled compile-all!)" "every function on the list compiled again, as after an image loads"))
      ((fn (loop l)
         (if (null? l)
           ()
           ((fn (_ c) (loop (rest l)) (c compile!) ()) (first l))))
       (Compiled all)))

    (method list (self)
      (doc "The state of every entry, oldest first."
        (returns LIST "One (name state reason) list for each entry")
        (sample "(Compiled list)" "(('obj-ref 'compiled \"\") ('obj-set! 'compiled \"\") ...), one row for each entry this process made"))
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
        (returns NIL "nil")
        (sample "(Compiled report)" "a line for each entry, as obj-ref<TAB>compiled"))
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
(image-transient! (fn (_) (Compiled interpret-all!)))

(doc (provide x/tool/compiled Compiled)
  (example "((new Compiled name 'f interpreted first) state)" "'interpreted")
  "Functions that have a compiled version: switched to interpreted before a state image is written and compiled again after one is loaded, with a list of which are compiled.")
