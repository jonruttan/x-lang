; type/annotation.x -- Annotation: does a value satisfy an annotation?
;
; An annotation is the type a (param NAME T ...) or (returns T ...) doc form
; states (docs/glossary.md).  (Annotation ? v T) answers whether v is one of
; the values T names, so a checker has one definition to ask.
;
; T is a name or names joined by |, and v satisfies T when it satisfies any
; one of them.  A name is tested in this order:
;
;   ANY       every value
;   NIL       nil
;   LIST      nil, or a pair
;   ALIST     as LIST: the elements are not looked at
;   PAIR      a pair
;   ATOM      a value that is not a pair
;   NUMBER    what number? answers for, so the numeric modules that are
;             loaded decide it
;   CALLABLE  a value whose type has a call handler
;   TYPE      a runtime type's handle
;   any other the name of v's runtime type, or the name of a class v is an
;             instance of, the class's descendants included
;
; nil satisfies ANY, NIL, LIST and ALIST and nothing else: a parameter that
; may be nil says so, as STRING|NIL.  A name that is neither a runtime type's
; nor a loaded class's is satisfied by no value.
;
; Two kinds of value carry a type the registry does not hold: a pair the
; engine built, such as a row of the type alist, and a type's handle.  They
; are told by their type label before a type's name is asked for, since a
; name can be asked only of a registered type.
;
; Zero top-level %-globals (new-file budget 0).

(module x/type/annotation)
(import x/type/class)
(import x/type/type)
(import x/type/env)

(def-class Annotation ()
  (doc "The test of a value against an annotation, the type a (param NAME T ...) or (returns T ...) doc form states: (Annotation ? v T). T is a name or names joined by |. nil satisfies only ANY, NIL, LIST and ALIST."
    (example "(Annotation ? \"a\" 'STRING)" "#t")
    (example "(Annotation ? () 'STRING)" "#f")
    (example "(Annotation ? () 'STRING|NIL)" "#t"))

  (static
    (method ? (self (param v ANY "The value")
                    (param t SYMBOL|STRING "The annotation as a doc form writes it: a name, or names joined by |"))
      (doc "Whether v is a value the annotation t names: a value of the runtime type, an instance of the class or of a class descended from it, or a value of one of the listed names ANY, NIL, NUMBER, CALLABLE, ALIST and TYPE. v satisfies a union when it satisfies any part."
        (returns BOOL "#t when v satisfies t")
        (note "nil satisfies ANY, NIL, LIST and ALIST only. ALIST is tested as LIST is: the elements are not looked at.")
        (note "CALLABLE is a value whose type has a call handler, so a list, a string and a number satisfy it and nil, a symbol and a boolean do not.")
        (note "A name that is neither a runtime type's nor a loaded class's is satisfied by no value.")
        (example "(Annotation ? 7 'INTEGER)" "#t")
        (example "(Annotation ? \"7\" 'INTEGER)" "#f")
        (example "(Annotation ? \"7\" 'INTEGER|STRING)" "#t")
        (example "(Annotation ? () 'LIST)" "#t")
        (example "(Annotation ? 'first 'CALLABLE)" "#f")
        (example "(Annotation ? first \"CALLABLE\")" "#t")
        (example "(do (def-class AnnotationPet ()) (Annotation ? (new AnnotationPet) 'AnnotationPet))" "#t"))
      (self %any? v (Str8 split "|" (if (symbol? t) (symbol->str t) t))))

    (method %any? (self v parts)
      (match
        ((null? parts) #f)
        ((self %part? v (first parts)) #t)
        (#t (self %any? v (rest parts)))))

    ; The names that admit nil come first; below the nil test v is a value.
    (method %part? (self v p)
      (match
        ((str=? p "ANY") #t)
        ((str=? p "NIL") (null? v))
        ((str=? p "LIST") (if (null? v) #t (self %pair? v)))
        ((str=? p "ALIST") (if (null? v) #t (self %pair? v)))
        ((null? v) #f)
        ((str=? p "PAIR") (self %pair? v))
        ((str=? p "ATOM") (not (self %pair? v)))
        ((str=? p "NUMBER") (number? v))
        ((str=? p "CALLABLE") (self %callable? v))
        ((str=? p "TYPE") (self %handle? v))
        ((self %pair? v) #f)
        ((self %unregistered? v) #f)
        ((str=? p (Type name (Type of v))) #t)
        ((object? v) (self %instance? v p))
        (#t #f)))

    ; The type label of a value the engine builds outside the registry: of
    ; a type's handle for 'atom, of a runtime type for 'pair.  Both are read
    ; off the first row of the type alist.
    (method %built-in (self which)
      (let go ((l (Type alist)))
        (match
          ((null? l) ())
          ((null? (first l)) (go (rest l)))
          ((eq? which 'pair) (Type of (rest (first l))))
          (#t (Type of (first (first l)))))))

    (method %pair? (self v)
      (if (pair? v) #t (same? (Type of v) (self %built-in 'pair))))

    (method %unregistered? (self v)
      (same? (Type of v) (self %built-in 'atom)))

    (method %callable? (self v)
      (match
        ((self %pair? v) (pair? v))
        ((self %unregistered? v) #f)
        (#t (let ((ts (Type by-atom (Type of v))))
              (if (null? ts) #f (not (null? (Type call-top ts))))))))

    (method %handle? (self v)
      (let go ((l (Type alist)))
        (match
          ((null? l) #f)
          ((null? (first l)) (go (rest l)))
          ((same? (first (first l)) v) #t)
          (#t (go (rest l))))))

    ; The class p names is read from the root, where a class is bound.
    (method %instance? (self v p)
      (let ((cell (Env cell (Env root) (Str8 ->sym p))))
        (match
          ((null? cell) #f)
          ((class? (rest cell)) (instance-of? v (rest cell)))
          (#t #f))))))

(doc (provide x/type/annotation Annotation)
  (note "nil satisfies ANY, NIL, LIST and ALIST only; a parameter that may be nil is annotated with |NIL.")
  (example "(Annotation ? (list 1 2) 'VECTOR|LIST)" "#t")
  "The test of a value against a doc annotation, homed on the Annotation class.")
