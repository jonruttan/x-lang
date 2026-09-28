; doc-annotations.x -- every doc annotation names a type.
;
; tools/check/doc-annotations.sh runs this.  An annotation is the T of a
; (param NAME T ...) or (returns T ...) doc form (docs/glossary.md,
; "annotation").  It is documentation and is never evaluated, so nothing else
; fails when one names nothing.
;
; Usage:
;   sh x.sh --no-pin -q -l xe -f tools/check/doc-annotations.x -- NAMES FILE...
;
; NAMES is tools/contract/doc-annotations.x and each FILE a source to read.
;
; A name is taken when it is one of:
;
;   a runtime type  one the platform running this holds: every type in the
;                   type-alist, and the two built-in types, ATOM and PAIR,
;                   which the alist does not hold.  The type label of a
;                   handle names the first and the type label of a runtime
;                   type the second.
;   a class         the NAME of a (def-class NAME ...) form in any FILE
;   a listed name   one NAMES lists
;
; A union, written A|B, is taken when each of its parts is.
;
; The run is xenon's: the numeric tower's types register when its modules
; load, and an annotation naming one is judged against a platform that has
; loaded them.  The classes are read from the source instead, since a class
; module is loaded only by the programs that import it.
;
; The sources are read as forms and never evaluated.  An annotation counts
; where it is a form, and where a dotted tail splices it into the list before
; it: (self . (param args LIST "d")) reads as (self param args LIST "d").
; Words in a comment or a string are not forms.
;
; Output, on stdout: one line for each annotation that names nothing,
;
;   doc-annotations: FILE:LINE: (param NAME T): PART is not a runtime type, a class or a listed name
;
; then the count.  LINE is each line of FILE that spells the form with single
; spaces, and is left out when none does.  With nothing to report, the one
; line `doc-annotations: ok (N annotations, M names)`.  Exit 1 when an
; annotation names nothing, when no annotation was found at all, or when the
; platform answered with no runtime types: a run that read nothing has
; checked nothing.
;
; A source holding a vector literal makes the reader take the vector's elements
; from the program's own input (tools/README.md).  The run form is the last form
; in this file, so that read finds the end of the input and no form of the
; program is consumed.

(import x/sys/posix)
(import x/sys/file)
(import x/sys/stream)
(import x/codec/xon)
(import x/tool/contract)

(Contract alloc-guard!)

(def-class DocAnnotations ()
  (static
    ; A number, as the report writes it.
    (method %text (self d)
      ((prim-ref (lit convert) (lit to)) d (Type named STRING)))

    ; --- the names that are taken ------------------------------------------

    ; The name of every runtime type in the type-alist.  The alist and its
    ; entries are PAIRs, and pair? asks for the type the pair primitive
    ; builds, LIST, so the walk tests for nil.  The entries of the
    ; catalogue are fetched where they are used: two of them are closures,
    ; and a closure held as a static field is a method.
    (method %registered (self)
      (let ((type-name (prim-ref (lit type) (lit name))))
        (let go ((l ((prim-ref (lit type) (lit alist)))) (acc ()))
          (match
            ((null? l) acc)
            ((null? (first l)) (go (rest l) acc))
            (#t (go (rest l) (pair (type-name (first (first l))) acc)))))))

    ; The names of the two built-in types.  Each is the text of the object a
    ; type label points to: a handle's for the atom, a runtime type's for the
    ; pair.  A platform with no registered type has neither to ask.
    (method %built-in (self)
      (let ((l ((prim-ref (lit type) (lit alist))))
            (type-of (prim-ref (lit type) (lit of)))
            (text (prim-ref (lit sym) (lit ->str))))
        (match
          ((null? l) ())
          ((null? (first l)) ())
          (#t (list (text (type-of (first (first l))))
                    (text (type-of (rest (first l)))))))))

    ; The names NAMES lists: the first of each entry of its one form.
    (method %listed (self path)
      (let ((forms (Xon parse (File read-all path))))
        (let go ((rows (if (pair? forms) (first forms) ())) (acc ()))
          (match
            ((not (pair? rows)) acc)
            ((not (pair? (first rows))) (go (rest rows) acc))
            ((symbol? (first (first rows)))
              (go (rest rows) (pair (symbol->str (first (first rows))) acc)))
            (#t (go (rest rows) acc))))))

    ; --- the sources -------------------------------------------------------

    ; What PATHS hold, as (ANNOTATIONS . CLASSES).  An annotation is
    ; (T PATH NAME): T the annotation and NAME the parameter's name, each as
    ; the symbol the source spells, and NAME nil for a returns form.  A class
    ; is the symbol a def-class form names.
    ;
    ; Each file's forms are garbage once it is walked, and nothing collects
    ; on its own, so a sweep between files keeps the run inside the
    ; allocation guard.
    (method %sources (self paths)
      (let ((collect (prim-ref (lit heap) (lit collect))))
        ; X is a spine that starts NAME T: a parameter's name and its
        ; annotation, both symbols
        (let ((named? (fn (_ x)
                        (match
                          ((not (pair? x)) #f)
                          ((not (pair? (rest x))) #f)
                          ((not (symbol? (first x))) #f)
                          (#t (symbol? (first (rest x)))))))
              (add (fn (_ found t path name)
                     (pair (pair (list t path name) (first found)) (rest found)))))
          ; X was reached as an element, so it is a form: its head says what
          ; it is.
          (let ((form (fn (_ x path found)
                        (match
                          ((eq? (first x) (lit param))
                            (if (named? (rest x))
                              (add found (first (rest (rest x))) path (first (rest x)))
                              found))
                          ((eq? (first x) (lit returns))
                            (match
                              ((not (pair? (rest x))) found)
                              ((symbol? (first (rest x)))
                                (add found (first (rest x)) path ()))
                              (#t found)))
                          ((eq? (first x) (lit def-class))
                            (match
                              ((not (pair? (rest x))) found)
                              ((symbol? (first (rest x)))
                                (pair (first found) (pair (first (rest x)) (rest found))))
                              (#t found)))
                          (#t found))))
                ; X is a spine past its list's head.  A dotted tail that was
                ; a (param NAME T "d") form arrives here as its elements,
                ; the description last.
                (tail (fn (_ x path found)
                        (match
                          ((not (eq? (first x) (lit param))) found)
                          ((not (named? (rest x))) found)
                          ((not (pair? (rest (rest (rest x))))) found)
                          ((not (null? (rest (rest (rest (rest x)))))) found)
                          ((str? (first (rest (rest (rest x)))))
                            (add found (first (rest (rest x))) path (first (rest x))))
                          (#t found)))))
            ; FORM? says X was reached as an element.  HEAD? says X is a
            ; list's spine at its head, and not further on.
            (let ((walk (fn (walk x form? head? path found)
                          (match
                            ((not (pair? x)) found)
                            (form? (walk x #f #t path (form x path found)))
                            (#t (walk (rest x) #f #f path
                                  (walk (first x) #t #f path
                                    (if head? found (tail x path found)))))))))
              (let go ((ps paths) (found (pair () ())))
                (if (null? ps) found
                  (let ((next (walk (Xon parse (File read-all (first ps))) #f #t (first ps) found)))
                    (do (collect)
                        (go (rest ps) next))))))))))

    ; --- judging -----------------------------------------------------------

    (method %member? (self s l)
      (match
        ((null? l) #f)
        ((str=? s (first l)) #t)
        (#t (DocAnnotations %member? s (rest l)))))

    (method %seen? (self t seen)
      (match
        ((null? seen) #f)
        ((eq? t (first seen)) #t)
        (#t (DocAnnotations %seen? t (rest seen)))))

    ; The parts of the annotation TEXT that TAKEN does not hold.
    (method %untaken (self text taken)
      (List filter (fn (_ part) (not (DocAnnotations %member? part taken)))
        (if (Str8 includes? "|" text) (Str8 split "|" text) (list text))))

    (method %judged (self t taken bad)
      (let ((parts (DocAnnotations %untaken (symbol->str t) taken)))
        (if (null? parts) bad (pair (pair t parts) bad))))

    ; Each distinct annotation among ANNOTATIONS that has an untaken part, as
    ; (T . PARTS).  An annotation is judged once, however often it is used.
    (method %judge (self annotations taken)
      (let go ((as annotations) (seen ()) (bad ()))
        (match
          ((null? as) bad)
          ((DocAnnotations %seen? (first (first as)) seen) (go (rest as) seen bad))
          (#t (go (rest as) (pair (first (first as)) seen)
                (DocAnnotations %judged (first (first as)) taken bad))))))

    ; The untaken parts of T, or nil when it has none.
    (method %parts-of (self t bad)
      (match
        ((null? bad) ())
        ((eq? t (first (first bad))) (rest (first bad)))
        (#t (DocAnnotations %parts-of t (rest bad)))))

    ; --- the report --------------------------------------------------------

    ; The form as the report spells it, short of its closing parenthesis:
    ; "(param NAME T" or "(returns T".
    (method %opening (self a)
      (if (null? (List third a))
        (Str8 append "(returns " (symbol->str (first a)))
        (Str8 append "(param "
          (Str8 append (symbol->str (List third a))
            (Str8 append " " (symbol->str (first a)))))))

    ; The numbers of the lines of PATH that hold OPENING followed by a space
    ; or a closing parenthesis.
    (method %lines (self path opening)
      (let ((spaced (Str8 append opening " "))
            (closed (Str8 append opening ")")))
        (let go ((ls (Str8 split "\n" (File read-all path))) (n 1) (acc ()))
          (match
            ((null? ls) (List reverse acc))
            ((if (Str8 includes? spaced (first ls)) #t (Str8 includes? closed (first ls)))
              (go (rest ls) (+ n 1) (pair n acc)))
            (#t (go (rest ls) (+ n 1) acc))))))

    ; ":" and the line numbers, or "" when there are none.
    (method %numbers (self lines)
      (if (null? lines) ""
        (Str8 append ":"
          (Str8 join "," (List map (fn (_ n) (DocAnnotations %text n)) lines)))))

    (method %say (self a parts)
      (let ((opening (DocAnnotations %opening a)))
        (do (display
              (Str8 join ""
                (list "doc-annotations: " (List second a)
                      (DocAnnotations %numbers (DocAnnotations %lines (List second a) opening))
                      ": " opening "): " (Str8 join ", " parts)
                      (if (null? (rest parts)) " is" " are")
                      " not a runtime type, a class or a listed name")))
            (newline))))

    ; One line for each distinct form of each file that names nothing; the
    ; answer is how many annotations name nothing.
    (method %say-each (self annotations bad)
      (let go ((as (List reverse annotations)) (said ()) (n 0))
        (if (null? as) n
          (let ((a (first as)))
            (let ((parts (DocAnnotations %parts-of (first a) bad))
                  (key (Str8 append (List second a)
                         (Str8 append " " (DocAnnotations %opening a)))))
              (match
                ((null? parts) (go (rest as) said n))
                ((DocAnnotations %member? key said) (go (rest as) said (+ n 1)))
                (#t
                  (do (DocAnnotations %say a parts)
                      (go (rest as) (pair key said) (+ n 1))))))))))

    (method %stop (self text)
      (do (display (Str8 join "" (list "doc-annotations: FAIL (" text ")")))
          (newline)
          (Sys exit 1)))

    ; --- the run -----------------------------------------------------------

    (method %verdict (self annotations taken bad)
      (if (null? bad)
        (do (display
              (Str8 join ""
                (list "doc-annotations: ok ("
                      (DocAnnotations %text (List length annotations)) " annotations, "
                      (DocAnnotations %text (List length taken)) " names)")))
            (newline))
        (DocAnnotations %stop
          (DocAnnotations %count-text (DocAnnotations %say-each annotations bad)))))

    (method %count-text (self n)
      (if (= n 1) "1 annotation names nothing"
        (Str8 append (DocAnnotations %text n) " annotations name nothing")))

    (method %check (self names paths)
      (let ((types (List append (DocAnnotations %built-in) (DocAnnotations %registered)))
            (listed (DocAnnotations %listed names))
            (found (DocAnnotations %sources paths)))
        (let ((taken (List append types
                       (List append listed
                         (List map (fn (_ c) (symbol->str c)) (rest found))))))
          (match
            ((null? types)
              (DocAnnotations %stop "the platform answered with no runtime types"))
            ((null? (first found))
              (DocAnnotations %stop "no annotation was found in the files read"))
            (#t (DocAnnotations %verdict (first found) taken
                  (DocAnnotations %judge (first found) taken)))))))

    (method %run (self args)
      (if (if (pair? args) (pair? (rest args)) #f)
        (DocAnnotations %check (first args) (rest args))
        (do (Stream with-fd 2
              (fn (_)
                (display "Usage: x.sh --no-pin -q -l xe -f tools/check/doc-annotations.x -- NAMES FILE...\n")))
            (Sys exit 1))))))

(DocAnnotations %run (Contract argv))
