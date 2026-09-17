; engine-contract.x -- the library half of the engine-contract gate.
;
; tools/check/engine-contract.sh runs this, then judges the candidate engine
; itself.  The split follows the gate's own two questions.  What the library
; needs is a property of committed text, read here as forms: the vocabulary's
; partition of the reference ISA, its profiles, the rows of requires.x derived
; from lib/ and apps/, and the parameter values constraints.x binds.  Whether a
; particular engine satisfies that stays in shell, because the question is
; asked of engines that may not run x at all, and such an engine still has to
; be refused by name.
;
; Usage:
;   sh x.sh --no-pin -q -f tools/check/engine-contract.x -- FEAT ISA REQ CONS FILE...
;
; FEAT is tools/contract/features.x, ISA the reference engine's isa.x, REQ
; tools/contract/requires.x, CONS tools/contract/constraints.x, and each FILE a
; source that requires.x is derived from.  When REQ or CONS does not exist, the
; checks that read it are skipped.
;
; Output is sections on stdout, each opened by a line `@@NAME`, in this order:
;
;   notes       the findings of checks 1 to 6, as the gate prints them
;   decl-atoms  the capabilities of the profile requires.x declares, with the
;               profiles it names expanded, one per line
;   cons-notes  the findings about the values constraints.x binds
;   pvals       NAME VALUE... for each parameter that lists its values
;   counts      CAPABILITIES ISA-ROWS PROFILES
;   end         empty; a run that stops early does not print it
;
; The checks, numbered as the gate numbers them:
;
;   1. total     every ISA row lands in a capability group, by its tag or by
;                explicit membership
;   2. disjoint  no coordinate is listed by two groups, or listed by one while
;                its tag is claimed whole
;   3. grounded  every coordinate a group lists is an ISA row
;   4. closed    every atom a profile names is a capability or an earlier
;                profile
;   5. separate  no profile names a parameter
;   6. derived   requires.x holds exactly the rows derived from the sources, and
;                its declared profile covers every capability they reach
;
; Names are compared as whole strings, and lists are sorted by byte order.
;
; The derivation reads forms, not text.  A (prim-ref NS METHOD) site counts
; wherever it is a form -- nested inside another call, or spread across lines
; -- and never when it is only words in a comment or a string; the quoted
; spelling 'ns 'method reads as the same (lit ...) form.  A `syscall` call is a
; form whose head is `syscall`, not the characters "(syscall " anywhere.
;
; A source holding a vector literal makes the reader take the vector's elements
; from the program's own input (tools/README.md).  The run form is the last form
; in this file, so that read finds the end of the input and no form of the
; program is consumed.

(import x/sys/posix)
(import x/sys/file)
(import x/codec/xon)
(import x/tool/contract)

(Contract alloc-guard!)

(def-class EngineContract ()
  (static
    (%cvt (prim-ref 'convert 'to))
    (%collect (prim-ref (lit heap) (lit collect)))
    ; Every file needs the core groups, so a row records only these: the ones
    ; a minimal engine may lack.
    (%above-core (list "isa/ffi-call" "isa/gc" "isa/sys" "isa/syscall"))

    ; --- text ---------------------------------------------------------------

    (method %text (self d) ((EngineContract %cvt) d %string))

    (method %texts (self data) (List map (fn (_ d) (EngineContract %text d)) data))

    (method %words (self words) (Str8 join " " words))

    (method %member? (self s l)
      (match
        ((null? l) #f)
        ((str=? s (first l)) #t)
        (#t (EngineContract %member? s (rest l)))))

    (method %any-member? (self ss l)
      (match
        ((null? ss) #f)
        ((EngineContract %member? (first ss) l) #t)
        (#t (EngineContract %any-member? (rest ss) l))))

    ; sorted by byte order, duplicates dropped
    (method %set (self strs) (Contract uniq (Contract sort strs)))

    ; each value that occurs more than once in a sorted list, once
    (method %repeated (self l)
      (let go ((l l) (acc ()))
        (match
          ((null? l) (List reverse acc))
          ((null? (rest l)) (List reverse acc))
          ((not (str=? (first l) (List second l))) (go (rest l) acc))
          ((if (pair? acc) (str=? (first acc) (first l)) #f) (go (rest l) acc))
          (#t (go (rest l) (pair (first l) acc))))))

    (method %section (self name lines)
      (do (display "@@") (display name) (newline)
          (List for-each (fn (_ l) (do (display l) (newline))) lines)))

    ; --- forms --------------------------------------------------------------

    (method %forms (self path) (Xon parse (File read-all path)))

    (method %at-least? (self l n)
      (match
        ((<= n 0) #t)
        ((pair? l) (EngineContract %at-least? (rest l) (- n 1)))
        (#t #f)))

    ; (def NAME (lit ROWS))
    (method %def? (self form)
      (if (EngineContract %at-least? form 3)
        (if (eq? (first form) (lit def)) (EngineContract %lit? (List third form)) #f)
        #f))

    (method %lit? (self x)
      (if (pair? x) (if (eq? (first x) (lit lit)) (pair? (rest x)) #f) #f))

    ; ROWS of the (def NAME (lit ROWS)) in FORMS, or nil when there is none
    (method %rows (self forms name)
      (match
        ((null? forms) ())
        ((if (EngineContract %def? (first forms)) (eq? (List second (first forms)) name) #f)
          (List second (List third (first forms))))
        (#t (EngineContract %rows (rest forms) name))))

    ; the rows of a table that are lists, as the text of their elements
    (method %text-rows (self rows)
      (List map (fn (_ r) (EngineContract %texts r)) (List filter (fn (_ r) (pair? r)) rows)))

    ; the rows of a table whose rows start with HEAD
    (method %headed (self rows head)
      (List filter (fn (_ r) (if (pair? r) (eq? (first r) head) #f)) rows))

    ; --- the ISA ------------------------------------------------------------

    ; (COORD . TAG) for every row, following the defs in file order
    (method %isa-pairs (self forms)
      (let ((go (fn (go fs acc)
                  (if (null? fs) (List reverse acc)
                    (go (rest fs) (EngineContract %isa-def (first fs) acc))))))
        (go forms ())))

    (method %isa-def (self form acc)
      (if (not (EngineContract %def? form)) acc
        (let ((name (List second form)) (rows (List second (List third form))))
          (match
            ((eq? name (lit %isa-catalog))
              (EngineContract %onto rows 3 acc
                (fn (_ r) (pair (Str8 append (EngineContract %text (first r)) "/"
                                             (EngineContract %text (List second r)))
                                (EngineContract %text (List third r))))))
            ((if (eq? name (lit %isa-bare)) #t (eq? name (lit %isa-keep)))
              (EngineContract %onto rows 2 acc
                (fn (_ r) (pair (EngineContract %text (first r)) (EngineContract %text (List second r))))))
            ; Values are part of the surface: x-release, x-version, args and
            ; the rest must be nameable by an atom, or no requires row could
            ; demand them, and x.sh depends on x-release.  A value row has no
            ; tag, so it enters with the sentinel `value`, which no capability
            ; claims whole, and check 1 then makes each one join a group
            ; explicitly.
            ((eq? name (lit %isa-values))
              (EngineContract %onto rows 1 acc
                (fn (_ r) (pair (EngineContract %text (first r)) "value"))))
            ; %isa-aliases name x-level aliases, which are not C rows
            (#t acc)))))

    ; F of each row with at least N elements, onto ACC (reversed)
    (method %onto (self rows n acc f)
      (match
        ((null? rows) acc)
        ((EngineContract %at-least? (first rows) n)
          (EngineContract %onto (rest rows) n (pair (f (first rows)) acc) f))
        (#t (EngineContract %onto (rest rows) n acc f))))

    ; --- checks 1 to 3: the partition ---------------------------------------

    ; A capability whose source is `rows` lists its members, and one whose
    ; source is `-` has none.  Any other source is a tag it claims whole.
    (method %claims-tag? (self src) (not (if (str=? src "rows") #t (str=? src "-"))))

    (method %tag-claims (self caps)
      (EngineContract %set
        (List map (fn (_ c) (rest c))
          (List filter (fn (_ c) (EngineContract %claims-tag? (rest c))) caps))))

    ; (COORD . GROUP) for every coordinate a group lists, in the order of the
    ; lines "COORD GROUP"
    (method %explicit (self rows)
      (List map (fn (_ line) (let ((w (Str8 split " " line))) (pair (first w) (List second w))))
        (Contract sort
          (let go ((rs rows) (acc ()))
            (if (null? rs) acc
              (go (rest rs)
                (List append
                  (List map (fn (_ c) (Str8 append c " " (first (first rs)))) (rest (first rs)))
                  acc)))))))

    ; (3) grounded
    (method %grounded (self explicit coords)
      (List map (fn (_ p) (Str8 append "  GROUNDED: " (rest p) " names " (first p)
                                       ", which is not an isa.x row"))
        (List filter (fn (_ p) (not (EngineContract %member? (first p) coords))) explicit)))

    ; (2) disjoint: a coordinate listed twice
    (method %listed-twice (self explicit)
      (let ((twice (EngineContract %repeated (Contract sort (List map (fn (_ p) (first p)) explicit)))))
        (if (null? twice) ()
          (list (Str8 append "  DISJOINT: coordinate claimed by two groups: " (Str8 join "\n" twice))))))

    ; (1) total
    (method %total (self isa claims explicit)
      (let ((listed (List map (fn (_ p) (first p)) explicit)))
        (List map (fn (_ p) (Str8 append "  TOTAL: " (first p) " (tag " (rest p)
                                         ") belongs to no capability group"))
          (List filter (fn (_ p) (not (if (EngineContract %member? (rest p) claims) #t
                                        (EngineContract %member? (first p) listed))))
            isa))))

    ; (2) disjoint: a coordinate listed while its tag is claimed whole
    (method %claimed-twice (self explicit isa claims)
      (let go ((ps explicit) (acc ()))
        (if (null? ps) (List reverse acc)
          (let ((tags (EngineContract %tags-of (first (first ps)) isa)))
            (go (rest ps)
              (if (EngineContract %any-member? tags claims)
                (pair (Str8 append "  DISJOINT: " (first (first ps)) " is claimed both by tag "
                                   (Str8 join "\n" tags) " and explicitly by " (rest (first ps)))
                      acc)
                acc))))))

    (method %tags-of (self coord isa)
      (List map (fn (_ p) (rest p)) (List filter (fn (_ p) (str=? coord (first p))) isa)))

    ; --- checks 4 and 5: profiles -------------------------------------------

    (method %profiles (self profs params atoms)
      (let go ((ps profs) (seen ()) (acc ()))
        (if (null? ps) (List reverse acc)
          (go (rest ps) (pair (first (first ps)) seen)
            (EngineContract %profile-notes (first (first ps)) (rest (first ps)) params atoms seen acc)))))

    ; NOTES onto ACC (reversed) for the atoms NAMES of profile NAME
    (method %profile-notes (self name names params atoms seen acc)
      (if (null? names) acc
        (EngineContract %profile-notes name (rest names) params atoms seen
          (let ((a (first names)))
            (match
              ((EngineContract %member? a params)
                (pair (Str8 append "  SEPARATE: profile " name " names the PARAMETER " a
                                   " -- parameters are values, not capabilities (see constraints.x)")
                      acc))
              ((EngineContract %member? a atoms) acc)
              ((EngineContract %member? a seen) acc)
              (#t (pair (Str8 append "  CLOSED: profile " name " names " a
                                     ", which is neither a capability nor an earlier profile")
                        acc)))))))

    ; --- check 6: requires.x ------------------------------------------------

    ; the capabilities profile NAME stands for, with the profiles it names
    ; expanded until none is left, sorted.  A profile already expanded adds
    ; nothing, so a profile that names itself still ends.
    (method %expand (self name profs)
      (let go ((todo (EngineContract %atoms-of name profs)) (done (list name)) (acc ()))
        (match
          ((null? todo) (EngineContract %set acc))
          ((EngineContract %member? (first todo) done) (go (rest todo) done acc))
          ((EngineContract %profile? (first todo) profs)
            (go (List append (EngineContract %atoms-of (first todo) profs) (rest todo))
                (pair (first todo) done) acc))
          (#t (go (rest todo) done (pair (first todo) acc))))))

    (method %atoms-of (self name profs)
      (let go ((ps profs) (acc ()))
        (match
          ((null? ps) acc)
          ((str=? name (first (first ps))) (go (rest ps) (List append acc (rest (first ps)))))
          (#t (go (rest ps) acc)))))

    (method %profile? (self name profs)
      (match
        ((null? profs) #f)
        ((str=? name (first (first profs))) #t)
        (#t (EngineContract %profile? name (rest profs)))))

    ; coordinate -> group, as a list of (COORD . GROUP).  A coordinate named in
    ; %feature-group-rows belongs to those groups; any other takes each
    ; capability that claims its tag whole.
    (method %groups-map (self isa caps explicit)
      (List append explicit
        (EngineContract %by-tag isa caps (List map (fn (_ p) (first p)) explicit))))

    (method %by-tag (self isa caps taken)
      (let ((go (fn (go is acc)
                  (match
                    ((null? is) acc)
                    ((EngineContract %member? (first (first is)) taken) (go (rest is) acc))
                    (#t (go (rest is) (EngineContract %owners-onto (first is) caps acc)))))))
        (go isa ())))

    (method %owners-onto (self coord-tag caps acc)
      (if (null? caps) acc
        (EngineContract %owners-onto coord-tag (rest caps)
          (let ((src (rest (first caps))))
            (if (if (str=? src (rest coord-tag)) (EngineContract %claims-tag? src) #f)
              (pair (pair (first coord-tag) (first (first caps))) acc)
              acc)))))

    ; (PATH CAP...) for every source that reaches a group above core, its
    ; capabilities sorted.
    ;
    ; The walk visits every cons cell of every file, so it runs as local
    ; closures calling themselves: a class-dispatched method per cell cost about
    ; a hundred times as much.  One pass finds both kinds of site, and the group
    ; map is cut to the above-core groups first, since no other group can reach
    ; a row.
    ;
    ; A list reached as an ELEMENT is a form and its head is looked at; the tail
    ; of a list is not a form, so (def syscall ...) is not a syscall call.
    ;
    ; Each file's forms are garbage once it is walked, and nothing collects on
    ; its own, so a sweep between files keeps the tree inside the allocation
    ; guard.
    (method %derive-all (self paths gmap)
      (let ((above (EngineContract %above-core))
            (cvt (EngineContract %cvt))
            (collect (EngineContract %collect)))
        (let ((member? (fn (member? s l)
                         (match
                           ((null? l) #f)
                           ((str=? s (first l)) #t)
                           (#t (member? s (rest l))))))
              (lit? (fn (_ x)
                      (if (pair? x) (if (eq? (first x) (lit lit)) (pair? (rest x)) #f) #f))))
          (let ((hot (List filter (fn (_ p) (member? (rest p) above)) gmap))
                ; (prim-ref (lit NS) (lit METHOD))
                (lits? (fn (_ x)
                         (match
                           ((not (pair? (rest x))) #f)
                           ((not (pair? (rest (rest x)))) #f)
                           (#t (if (lit? (first (rest x))) (lit? (first (rest (rest x)))) #f))))))
            (let ((onto (fn (onto coord ps acc)
                          (match
                            ((null? ps) acc)
                            ((str=? coord (first (first ps)))
                              (onto coord (rest ps) (pair (rest (first ps)) acc)))
                            (#t (onto coord (rest ps) acc))))))
              (let ((site (fn (_ x acc)
                            (match
                              ((eq? (first x) (lit syscall)) (pair "isa/syscall" acc))
                              ((if (eq? (first x) (lit prim-ref)) (lits? x) #f)
                                (onto (Str8 append
                                        (Str8 append (cvt (first (rest (first (rest x)))) %string) "/")
                                        (cvt (first (rest (first (rest (rest x))))) %string))
                                      hot acc))
                              (#t acc)))))
                ; FORM? says whether X was reached as an element (a form) or is
                ; a list whose elements are to be walked.
                (let ((walk (fn (walk x form? acc)
                              (match
                                ((not (pair? x)) acc)
                                (form? (walk x #f (site x acc)))
                                (#t (walk (rest x) #f (walk (first x) #t acc)))))))
                  (let ((go (fn (go ps acc)
                              (if (null? ps) acc
                                (let ((groups (EngineContract %set
                                                (walk (EngineContract %forms (first ps)) #f ()))))
                                  (do (collect)
                                      (go (rest ps)
                                        (if (null? groups) acc
                                          (pair (pair (first ps) groups) acc)))))))))
                    (go paths ())))))))))

    ; diff -u's view of two sorted lists, as the gate prints it: between one
    ; line the lists share and the next, the lines only in A marked -, then
    ; the lines only in B marked +
    (method %diff (self a b)
      (let go ((a a) (b b) (dels ()) (adds ()) (acc ()))
        (match
          ((if (null? a) (null? b) #f) (List reverse (EngineContract %flush dels adds acc)))
          ((null? a) (go a (rest b) dels (pair (first b) adds) acc))
          ((null? b) (go (rest a) b (pair (first a) dels) adds acc))
          ((str=? (first a) (first b))
            (go (rest a) (rest b) () () (EngineContract %flush dels adds acc)))
          ((Str8 <? (first a) (first b)) (go (rest a) b (pair (first a) dels) adds acc))
          (#t (go a (rest b) dels (pair (first b) adds) acc)))))

    ; the deletions then the additions onto ACC (reversed); DELS and ADDS
    ; arrive newest first
    (method %flush (self dels adds acc)
      (EngineContract %marked (List reverse adds) "    +"
        (EngineContract %marked (List reverse dels) "    -" acc)))

    (method %marked (self lines mark acc)
      (if (null? lines) acc
        (EngineContract %marked (rest lines) mark (pair (Str8 append mark (first lines)) acc))))

    ; (NOTES . DECLARED) for the requires.x at PATH: the findings of check 6,
    ; and the capabilities its declared profile stands for
    (method %requires (self path profs sources gmap)
      (let ((req (EngineContract %rows (EngineContract %forms path) (lit %requires)))
            (derived (EngineContract %derive-all sources gmap)))
        (let ((manifest (Contract sort
                          (List map (fn (_ r) (EngineContract %words (EngineContract %texts (rest r))))
                            (EngineContract %headed req (lit needs)))))
              (decls (List map (fn (_ r) (EngineContract %text (List second r)))
                       (List filter (fn (_ r) (EngineContract %at-least? r 2))
                         (EngineContract %headed req (lit profile)))))
              (reached (EngineContract %set
                         (let go ((rs derived) (acc ()))
                           (if (null? rs) acc (go (rest rs) (List append (rest (first rs)) acc)))))))
          (let ((declared (if (null? decls) () (EngineContract %expand (first decls) profs)))
                (diff (EngineContract %diff manifest
                        (Contract sort (List map (fn (_ r) (EngineContract %words r)) derived)))))
            (pair
              (List append
                ; The declared profile must cover every above-core capability
                ; the tree reaches.  Under-declaring is the unsafe direction:
                ; it would let a project pair with an engine that cannot load
                ; files the library uses.
                (if (null? decls) ()
                  (List map (fn (_ g) (Str8 append "  PROFILE: requires.x declares " (first decls)
                                                   ", which does not include " g
                                                   " -- but the tree reaches it"))
                    (List filter (fn (_ g) (not (EngineContract %member? g declared))) reached)))
                (if (null? diff) ()
                  (pair "  DERIVED: requires.x disagrees with the tree (-manifest +derived):" diff)))
              declared)))))

    ; --- the values constraints.x binds -------------------------------------

    ; (KEY VALUE...) for each (constraint "PATH" KEY = VALUE...)
    (method %bindings (self rows)
      (List map (fn (_ r) (EngineContract %texts (pair (List third r) (rest (rest (rest (rest r)))))))
        (List filter (fn (_ r) (if (EngineContract %at-least? r 5)
                                 (eq? (first (rest (rest (rest r)))) (lit =)) #f))
          (EngineContract %headed rows (lit constraint)))))

    (method %values (self bindings params)
      (let go ((bs bindings) (acc ()))
        (if (null? bs) (List reverse acc)
          (let ((key (first (first bs))) (value (EngineContract %words (rest (first bs)))))
            (go (rest bs)
              (if (EngineContract %legal? key value params) acc
                (pair "    vocabulary.  Add it to %feature-parameters or fix the row."
                  (pair (Str8 append "  PARAM-VALUE: constraints.x binds " key " = " value
                                     ", which is not in the")
                        acc))))))))

    ; A parameter that lists no values accepts any, and `unknown` is always
    ; legal: it says the build could not tell.
    (method %legal? (self key value params)
      (let ((row (List find (fn (_ r) (if (EngineContract %at-least? r 2) (str=? key (first r)) #f))
                   params)))
        (match
          ((null? row) #t)
          ((str=? value "unknown") #t)
          (#t (EngineContract %member? value (rest row))))))

    ; --- the run ------------------------------------------------------------

    (method %run (self args)
      (let ((feat (EngineContract %forms (first args)))
            (isa (EngineContract %isa-pairs (EngineContract %forms (List second args))))
            (req-path (List third args))
            (cons-path (first (rest (rest (rest args)))))
            (sources (rest (rest (rest (rest args))))))
        (let ((caps (List reverse
                      (EngineContract %onto (EngineContract %rows feat (lit %feature-capabilities)) 2 ()
                        (fn (_ r) (pair (EngineContract %text (first r)) (EngineContract %text (List second r)))))))
              (rows (EngineContract %text-rows (EngineContract %rows feat (lit %feature-group-rows))))
              (params (EngineContract %text-rows (EngineContract %rows feat (lit %feature-parameters))))
              (profs (EngineContract %text-rows (EngineContract %rows feat (lit %feature-profiles)))))
          (let ((explicit (EngineContract %explicit rows))
                (claims (EngineContract %tag-claims caps)))
            (let ((required (if (File exists? req-path)
                              (EngineContract %requires req-path profs sources
                                (EngineContract %groups-map isa caps explicit))
                              (pair () ()))))
              (do
                (EngineContract %section "notes"
                  (List append
                    (EngineContract %grounded explicit (List map (fn (_ p) (first p)) isa))
                    (EngineContract %listed-twice explicit)
                    (EngineContract %total isa claims explicit)
                    (EngineContract %claimed-twice explicit isa claims)
                    (EngineContract %profiles profs (List map (fn (_ r) (first r)) params)
                      (EngineContract %set (List map (fn (_ c) (first c)) caps)))
                    (first required)))
                (EngineContract %section "decl-atoms" (rest required))
                (EngineContract %section "cons-notes"
                  (if (File exists? cons-path)
                    (EngineContract %values
                      (EngineContract %bindings
                        (EngineContract %rows (EngineContract %forms cons-path) (lit %constraints)))
                      params)
                    ()))
                (EngineContract %section "pvals"
                  (List map (fn (_ r) (EngineContract %words r))
                    (List filter (fn (_ r) (EngineContract %at-least? r 2)) params)))
                (EngineContract %section "counts"
                  (list (EngineContract %words
                          (EngineContract %texts (list (List length caps) (List length isa)
                                                       (List length profs))))))
                (EngineContract %section "end" ())))))))))

(EngineContract %run (Contract argv))
