; env.x -- Env: environments as values, read by name.
;
; An environment is one pair, (bindings . parent).  A frame's bindings are
; an alist of (name . value) cells and its parent is the environment it was
; made in; the root's bindings are a tree whose nodes are
; (entry . (left . right)) and its parent is nil (docs/engine-laws.md, law
; 10).  The engine makes them: a call makes a child of the closure's
; environment, an operative receives its caller's as a value, and (Fn env f)
; reads the one a closure was made in.  This class reads them by name.
;
; The cells are engine-built, so pair? answers #f for many of them; every
; walk here steps with first, rest and null? only, and what it answers is
; built from fresh pairs that the List and Assoc walkers accept.
;
; Not the process environment: Sys environ and Sys getenv read that.
(module x/type/env)

(import x/type/class)

(def-class Env ()
  (doc "Environments as values: one pair (bindings . parent), as (Env current), (Env root) and (Fn env f) answer. A frame's bindings are an alist of (name . value) and its parent the environment it was made in; the root's bindings are a tree and its parent nil. Not the process environment, which Sys environ and Sys getenv read."
    (example "(eval 'k ((fn (_ k) (Env current)) 7))" "7")
    (example "(Env has? (Env root) 'first)" "#t"))
  (static
    ; The bindings of one environment as a fresh alist.  A tree node,
    ; (entry . (left . right)), and an alist cell, (entry . next), look alike
    ; for as far as a walk can see, so the two are told apart by the
    ; environment, not its bindings: the root alone has no parent (law 10),
    ; and the root alone keeps a tree.  Both are copied: the engine's cells
    ; are not list pairs, and a caller holding the live alist could rebind a
    ; frame through set-rest!.
    (method %flatten (self e)
      (doc "The bindings of environment e as a fresh alist: a frame's copied, the root's tree walked in order.")
      (match
        ((null? (first e)) ())
        ((null? (rest e)) (Env %walk-tree (first e) ()))
        (#t (Env %copy-alist (first e) ()))))
    (method %copy-alist (self l acc)
      (doc "A fresh copy of an alist of (name . value) cells, in the same order.")
      (match
        ((null? l) (List reverse acc))
        (#t (Env %copy-alist (rest l)
              (pair (pair (first (first l)) (rest (first l))) acc)))))
    (method %walk-tree (self node acc)
      (doc "Every entry of a (entry . (left . right)) tree, as fresh pairs, onto acc.")
      (match
        ((null? node) acc)
        (#t
          (Env %walk-tree (first (rest node))
            (pair (pair (first (first node)) (rest (first node)))
                  (Env %walk-tree (rest (rest node)) acc))))))
    (method bindings (self (param e ANY "An environment"))
      (doc "The bindings of e's own frame, as a fresh alist of (name . value): a frame's in its own order, newest first; the root's tree flattened. The enclosing frames are not included -- (Env parent e) reaches them."
        (returns LIST "An alist of (name . value)")
        (example "(first (Env bindings ((fn (_ k) (Env current)) 7)))" "('k . 7)"))
      (Env %flatten e))
    (method names (self (param e ANY "An environment"))
      (doc "The names bound in e's own frame, in the order (Env bindings e) lists them."
        (returns LIST "Symbols")
        (example "(List includes? 'k (Env names ((fn (_ k) (Env current)) 7)))" "#t"))
      (List map (fn (_ entry) (first entry)) (Env bindings e)))
    (method parent (self (param e ANY "An environment"))
      (doc "The environment e was made in, or () for the root."
        (returns ANY "An environment, or ()")
        (example "(null? (Env parent (Env root)))" "#t"))
      (rest e))
    (method has? (self (param e ANY "An environment") (param name SYMBOL "A name"))
      (doc "Whether name resolves in e: in its own frame or any enclosing one, as lookup finds it. A name that is not a symbol raises a type error."
        (returns BOOL "#t when name is bound in e or an environment enclosing it")
        (example "(Env has? (Env root) 'first)" "#t")
        (example "(Env has? (Env root) 'no-such-name-zz)" "#f"))
      (if (symbol? name)
        (guard (_ #f) (do (eval name e) #t))
        (Err raise (lit type) "Env has?: a name is a symbol" name)))
    (method root (self)
      (doc "The root environment of the running base: where top-level forms bind, every frame's outermost parent, with the library's names in its tree and no parent of its own."
        (returns ANY "The root environment")
        (example "(null? (Env parent (Env root)))" "#t"))
      (%reflect-base-cell (lit env-root)))))

; (Env current) answers the environment the form is evaluated in.  It is an
; operative, installed over the class rather than declared in it: the class
; dispatcher evaluates a static method as a form in the caller's environment,
; so an operative stored as a method receives that environment, where a
; procedure would receive only its own frame.  (Block method! ...) installs
; its block forms the same way.
(Env def-static! (lit current) (op (self) e e))
(doc Env/current "The environment the form (Env current) is evaluated in: a frame inside a closure body, the root at the top level."
  (returns ANY "An environment")
  (example "(eval 'k ((fn (_ k) (Env current)) 7))" "7"))

(doc (provide x/type/env Env)
  (note "An environment is read by name: (Env bindings e), (Env names e), (Env parent e), (Env has? e 'name); (Env current) and (Env root) answer one.")
  (example "(Env has? (Env root) 'first)" "#t")
  "Env: environments as values -- one pair (bindings . parent) -- read by name.")
