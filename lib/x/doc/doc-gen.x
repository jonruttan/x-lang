; doc-gen.x -- Markdown documentation generator library
;
; Extracts (doc ...) and (note ...) forms from token trees
; and emits Markdown. Works with tokens from make-base + %token-read-string.
(import x/core/list)
(import x/doc/emit)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

(import x/type/str)
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %integer->char (prim-ref 'int '->char))


; --- Predicates (cross-base: use str=? not eq?) ---

(doc (def %doc-sym-is?
  (fn (_ sym name)
    (when (symbol? sym) (str=? (symbol->str sym) name))))
  (param sym ANY "Value to test")
  (param name STRING "Expected symbol name")
  (returns BOOL "True if sym is a symbol with the given name")
  "Test if a value is a symbol matching a name string (cross-base safe).")

(def %docgen-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "doc"))))
(def %doc-note-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "note"))))
(def %doc-def-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "def"))))
(def %doc-set-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "set!"))))
(def %doc-param-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "param"))))
(def %doc-provide-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "provide"))))

; --- Extraction helpers ---

; %doc-find-last-string comes from doc.x (same package, loads first);
; this file used to carry an identical copy (#227/#231 hoist).

(def %doc-extract-params
  (fn (self ps acc)
    (if (null? ps) (%reverse acc)
      (if (not (pair? ps))
        (if (%doc-param-form? ps) (%reverse (pair ps acc)) (%reverse acc))
        (if (%doc-param-form? (first ps))
          (self (rest ps) (pair (first ps) acc))
          (self (rest ps) acc))))))

(def %doc-extract-meta-type
  (fn (self forms tag acc)
    (if (null? forms) (%reverse acc)
      (if (pair? (first forms))
        (if (%doc-sym-is? (first (first forms)) tag)
          (self (rest forms) tag (pair (first forms) acc))
          (self (rest forms) tag acc))
        (self (rest forms) tag acc)))))

; --- Main doc form extraction ---

(doc (def %doc-extract
  (fn (_ form)
    (def %second (first (rest form)))
    (def %meta (rest (rest form)))
    (if (or (%doc-def-form? %second) (%doc-set-form? %second))
      (let ()  ; scoped: def in tail position would leak to global
        (def %name (first (rest %second)))
        (def %value (unless (null? (rest (rest %second)))
                      (first (rest (rest %second)))))
        (def %desc (%doc-find-last-string %meta))
        (def %fn-params
          (when (pair? %value)
            (when (%doc-sym-is? (first %value) "fn")
              (%doc-extract-params (first (rest %value)) ()))))
        (def %returns (%doc-extract-meta-type %meta "returns" ()))
        (def %examples (%doc-extract-meta-type %meta "example" ()))
        (def %sees (%doc-extract-meta-type %meta "see" ()))
        (def %notes (%doc-extract-meta-type %meta "note" ()))
        (list %name %desc %fn-params %returns %examples %sees %notes))
      (if (%doc-provide-form? %second)
        (let () (def %name (first (rest %second)))
            (def %desc (%doc-find-last-string %meta))
            (list %name %desc
              (%doc-extract-meta-type %meta "param" ())
              (%doc-extract-meta-type %meta "returns" ())
              (%doc-extract-meta-type %meta "example" ())
              (%doc-extract-meta-type %meta "see" ())
              (%doc-extract-meta-type %meta "note" ())))
        (let () (def %desc (%doc-find-last-string %meta))
            (list %second %desc
              (%doc-extract-meta-type %meta "param" ())
              (%doc-extract-meta-type %meta "returns" ())
              (%doc-extract-meta-type %meta "example" ())
              (%doc-extract-meta-type %meta "see" ())
              (%doc-extract-meta-type %meta "note" ())))))))
  (param form LIST "A (doc ...) token form")
  (returns LIST "(name desc params returns examples sees notes)")
  "Extract structured metadata from a (doc ...) form.")

; --- Output, through an emitter ------------------------------------------
; The walk below never writes Markdown -- it calls an EMITTER, a class value
; threaded through every walker (see x/doc/emit).  The helpers here convert
; token forms into the plain data the protocol takes: strings, string lists,
; and (name type desc) triples, so an emitter never has to know what a
; spliced variadic tail or a three-element (param ...) means.

(doc (def %doc-emit-entry
  (fn (_ em info)
    (def %name (List ref 0 info))
    (def %desc (List ref 1 info))
    (def %params (List ref 2 info))
    (def %returns (List ref 3 info))
    (def %examples (List ref 4 info))
    (def %sees (List ref 5 info))
    (def %notes (List ref 6 info))
    (when (symbol? %name) (em alias (DocEmit as-str %name)))
    (em entry-head (DocEmit as-str %name))
    (unless (str=? %desc "") (em text %desc))
    (%for-each (fn (_ n) (em note (DocEmit as-str (first (rest n))))) %notes)
    (unless (null? %params) (em params (DocEmit param-triples %params)))
    (unless (null? %returns)
      (let ((%ret (first %returns)))
        (em returns (DocEmit as-str (first (rest %ret))) (DocEmit returns-desc %ret))))
    (unless (null? %examples) (em examples (DocEmit example-pairs %examples)))
    (unless (null? %sees) (em see-also (DocEmit meta-strs %sees)))))
  (param em ANY "Emitter class (DocMd, DocMan)")
  (param info LIST "Extracted doc info from doc-extract")
  "Emit a single entry's documentation through an emitter.")

; One member declaration -> heading, optional description, the member note and
; its visibility tier.  Shared by the (doc NAME "...") arm and the bare-member
; arm, which differ only in where the description sits.
(def %doc-emit-member
  (fn (_ em name desc cname vis)
    (em alias (%str-build cname "-" name))
    (em entry-head name)
    (unless (str=? desc "") (em text desc))
    (em note (%str-build "Member: data carried by a " cname " instance."))
    (%for-each (fn (_ n) (em note (DocEmit as-str (first (rest n)))))
               (%doc-vis-note vis cname))))

; --- Lookup alist for retroactive docs ---

(doc (def %doc-build-lookup
  (fn (self tokens)
    (unless (null? tokens)
      (let ((tok (first tokens)))
        (if (%docgen-form? tok)
          (let ()
            (def %info (%doc-extract tok))
            (def %name (List ref 0 %info))
            (if (symbol? %name)
              (pair (pair (symbol->str %name) %info)
                    (self (rest tokens)))
              (self (rest tokens))))
          (self (rest tokens)))))))
  (param tokens LIST "Token list (e.g. from tokenizing doc-prims.x)")
  (returns LIST "Alist of (name-string . extracted-7-tuple) pairs")
  "Build a lookup alist from (doc ...) forms in a token stream.")

(doc (def %doc-lookup-alist
  (fn (_ alist name-str)
    (let ((hit (%assoc-str name-str alist)))
      (unless (null? hit) (rest hit)))))
  (param alist LIST "Alist from doc-build-lookup")
  (param name-str STRING "Function name as string")
  (returns LIST "Extracted 7-tuple, or () if not found")
  "Cross-base-safe lookup in a doc alist by name string.")

; --- Token tree walker ---

; --- Find the (doc (provide ...)) or (provide ...) form in tokens ---

(def %doc-find-provide
  (fn (self tokens)
    (unless (null? tokens)
      (let ((tok (first tokens)))
        (if (%docgen-form? tok)
          (let ((%second (first (rest tok))))
            (if (%doc-provide-form? %second)
              (%doc-extract tok)
              (self (rest tokens))))
          (if (%doc-provide-form? tok)
            (list (first (rest tok)) "" () () () () ())
            (self (rest tokens))))))))

; --- Emit body with prims alist fallback and deduplication ---


; --- def-class emission -----------------------------------------------------
; A class form is (def-class NAME parent-spec body...) where body items are a
; class-level (doc "desc" (note ...) (example ...)), bare members, (interface
; ...), (static (method ...) ...), and instance (method ...) forms.  Method
; docs ride INSIDE the method: (method NAME (self sig...) (doc ...) body...).
; All symbol comparison is by string (per-base interning; see %doc-splice-dos).

(def %doc-defclass-form? (fn (_ tok)
  (when (pair? tok) (%doc-sym-is? (first tok) "def-class"))))

; One signature element's display name: (param N T "d") -> N, bare symbol -> it.
(def %doc-param-name
  (fn (_ p)
    (match
      ((%doc-param-form? p) (symbol->str (first (rest p))))
      ((symbol? p) (symbol->str p))
      (#t "_"))))

; Render the sig after self as " a b . rest".  A dotted (param ...) tail reads
; SPLICED -- (self . (param args T "d")) tokenizes as (self param args T "d")
; -- so a remaining tail that is itself a param form is one variadic param.
(def %doc-sig-str
  (fn (self ps)
    (match
      ((null? ps) "")
      ((symbol? ps) (%str-build " . " (symbol->str ps)))
      ((%doc-param-form? ps) (%str-build " . " (symbol->str (first (rest ps)))))
      ((pair? ps) (%str-build " " (%doc-param-name (first ps)) (self (rest ps))))
      (#t ""))))

; Collect (param ...) forms from a sig for the Parameters section, treating a
; spliced variadic tail (see %doc-sig-str) as one param form.
(def %doc-sig-params
  (fn (self ps acc)
    (match
      ((null? ps) (%reverse acc))
      ((symbol? ps) (%reverse acc))
      ((%doc-param-form? ps) (%reverse (pair ps acc)))
      ((not (pair? ps)) (%reverse acc))
      ((%doc-param-form? (first ps)) (self (rest ps) (pair (first ps) acc)))
      (#t (self (rest ps) acc)))))

; Emit one (method ...) form as a doc entry.  static? picks the heading shape:
; (Class m a b) for statics, (m a b) + an instance note for instance methods.
; vis is "" for an undeclared (public) entry, or "private"/"protected" when
; the entry came out of a visibility block.  Documented, not hidden: (help ...)
; lists private members too, and a reader needs to know a name exists before
; they can be told they may not call it.
; The tier, in the words docs/object-system.md uses for it: private is this
; class's own methods, protected is any method on the chain in either
; direction.
(def %doc-vis-note
  (fn (_ vis cname)
    (match
      ((str=? vis "private")
        (list (list 'note (%str-build "Private: reachable from " cname "'s own methods only."))))
      ((str=? vis "protected")
        (list (list 'note (%str-build "Protected: reachable from methods anywhere on " cname "'s chain."))))
      (#t ()))))

(def %doc-emit-method
  (fn (_ em m cname static? vis)
    (def %mname (symbol->str (first (rest m))))
    (def %sig (first (rest (rest m))))
    (def %args (rest %sig))                          ; strip the self slot
    (def %mbody (rest (rest (rest m))))
    (def %docf (when (pair? %mbody)
                 (when (%docgen-form? (first %mbody)) (first %mbody))))
    (def %meta (unless (null? %docf) (rest %docf)))
    (def %head
      (if static?
        (%str-build "(" cname " " %mname (%doc-sig-str %args) ")")
        (%str-build "(" %mname (%doc-sig-str %args) ")")))
    (def %notes (%doc-extract-meta-type %meta "note" ()))
    ; The alias is built from the STRUCTURED name, not %head: a lookup name
    ; has to be typeable, and %head is a rendered signature.
    (em alias (%str-build cname "-" %mname))
    ; params ride the SIGNATURE; a bare-variadic sig (self . opt) documents
    ; its option via (param ...) in the doc meta instead -- fall back to it.
    (def %sig-params (%doc-sig-params %args ()))
    (%doc-emit-entry em
      (list %head
            (if (null? %docf) "" (%doc-find-last-string %meta))
            (if (null? %sig-params)
              (%doc-extract-meta-type %meta "param" ())
              %sig-params)
            (%doc-extract-meta-type %meta "returns" ())
            (%doc-extract-meta-type %meta "example" ())
            (%doc-extract-meta-type %meta "see" ())
            (%append
              (if static? %notes
                (%append %notes
                  (list (list 'note
                    (%str-build "Instance method: called on a " cname " instance.")))))
              (%doc-vis-note vis cname))))))

; The class-level doc form: (doc "description" (note ...) (example ...)).
(def %doc-emit-class-doc
  (fn (_ em f)
    (def %meta (rest (rest f)))
    (when (str? (first (rest f)))
      (do (em text (first (rest f)))
          (%for-each
            (fn (_ n) (em note (DocEmit as-str (first (rest n)))))
            (%doc-extract-meta-type %meta "note" ()))))))

(def %doc-walk-class-body
  (fn (self em body cname static? vis)
    (match
      ((not (pair? body)) ())
      (#t
        ; A bare symbol IS a member declaration -- (private balance ...)
        ; declares `balance` with no default -- so it is normalised to the
        ; (name) shape and flows through the member arm below.  Left alone it
        ; hit the not-a-pair arm and vanished, the same silence this walker
        ; keeps having to be taught out of.
        (do (let ((f (if (symbol? (first body)) (list (first body)) (first body))))
              (match
                ((not (pair? f)) ())
                ((%doc-sym-is? (first f) "method") (%doc-emit-method em f cname static? vis))
                ((%doc-sym-is? (first f) "static") (self em (rest f) cname #t vis))
                ; (private ...) / (protected ...) splice their tail into the
                ; class body -- lib/x/type/class.x explodes them exactly so --
                ; and hold bare member names, member declarations and methods.
                ; They nest inside (static ...) as well, so the static flag
                ; rides through unchanged.
                ((%doc-sym-is? (first f) "private")
                  (self em (rest f) cname static? "private"))
                ((%doc-sym-is? (first f) "protected")
                  (self em (rest f) cname static? "protected"))
                ; (interface a b c) -- the operations a type must supply
                ; to satisfy the protocol; part of the class's contract, so
                ; it belongs on the page.
                ((%doc-sym-is? (first f) "interface")
                  (em interface-line (%map (fn (_ n) (symbol->str n)) (rest f))))
                ; A doc form is the CLASS's own when its first argument is a
                ; string, and a MEMBER's when it is that member's name --
                ; which is the only thing telling them apart, and why members
                ; reached the page as nothing at all: %doc-emit-class-doc
                ; guards on str? and returns quietly for anything else, so
                ; (doc raw "...") fell into that guard and vanished.
                ((%docgen-form? f)
                  (if (str? (first (rest f)))
                    (%doc-emit-class-doc em f)
                    (%doc-emit-member em
                      (symbol->str (first (rest f)))
                      (if (str? (first (rest (rest f)))) (first (rest (rest f))) "")
                      cname vis)))
                ; ANYTHING ELSE IS A MEMBER.  A class body declares members
                ; as (name), (name default) or (name default "description")
                ; -- the head is the MEMBER'S OWN NAME, so class-body heads
                ; are an open set no list can enumerate, and an arm that
                ; dropped them dropped every member in the library: Ansi's
                ; colours, Random's kind/state/fd, all of it, while the page
                ; still looked finished.
                ;
                ; Treating the unknown as a member also converts the old
                ; silence into something VISIBLE.  When the object-model v2
                ; (private ...) and (protected ...) blocks land, they will
                ; render as a nonsense member named "private" rather than
                ; vanishing -- wrong, but wrong where someone can see it.
                (#t
                  (when (symbol? (first f))
                    ; pair? FIRST: first/rest are unchecked, so (first ())
                    ; is undefined behaviour, and a member with no
                    ; description -- (state 2463534242), (fd ()) -- has
                    ; exactly that empty tail.  It segfaulted the generator
                    ; outright.
                    ; BOTH steps guarded, not just the first: for a bare
                    ; member (ledger) the tail is (rest ()), and rest is as
                    ; unchecked as first.  Guarding only the (first tail)
                    ; still segfaulted -- the same trap, one level further in.
                    (%doc-emit-member em
                      (symbol->str (first f))
                      (let ((tail (if (pair? (rest f)) (rest (rest f)) ())))
                        (if (pair? tail)
                          (if (str? (first tail)) (first tail) "")
                          ""))
                      cname vis)))))
            (self em (rest body) cname static? vis))))))

(def %doc-emit-class
  (fn (_ em form)
    (def %cname (symbol->str (first (rest form))))
    (def %parent (first (rest (rest form))))
    (em class-head %cname
      (if (pair? %parent)
        (if (%doc-sym-is? (first %parent) "extends")
          (symbol->str (first (rest %parent)))
          "")
        ""))
    (%doc-walk-class-body em (rest (rest (rest form))) %cname #f "")))

(def %doc-walk-body-with-prims
  (fn (self em tokens prims-alist seen)
    (unless (null? tokens)
      (let ()
        (def %tok (first tokens))
        (def %rest (rest tokens))
        (if (%docgen-form? %tok)
          (if (%doc-provide-form? (first (rest %tok)))
            (self em %rest prims-alist seen)
            (let ()
              (def %info (%doc-extract %tok))
              (def %name-str (symbol->str (List ref 0 %info)))
              (if (%member-str? %name-str seen)
                (self em %rest prims-alist seen)
                (do (%doc-emit-entry em %info)
                    (self em %rest prims-alist (pair %name-str seen))))))
        (if (%doc-note-form? %tok)
          (do (unless (null? (rest %tok))
                (em section (DocEmit as-str (first (rest %tok)))))
              (self em %rest prims-alist seen))
        (if (%doc-defclass-form? %tok)
          (do (%doc-emit-class em %tok)
              (self em %rest prims-alist seen))
        (if (or (%doc-def-form? %tok) (%doc-set-form? %tok))
          (let ()
            (def %dname (first (rest %tok)))
            (def %dname-str (symbol->str %dname))
            (if (str=? (Str8 sub 0 1 %dname-str) "%")
              (self em %rest prims-alist seen)
              (if (%member-str? %dname-str seen)
                (self em %rest prims-alist seen)
                (let ()
                  (def %prims-entry (%doc-lookup-alist prims-alist %dname-str))
                  (if (not (null? %prims-entry))
                    (%doc-emit-entry em %prims-entry)
                    (em entry-head (DocEmit as-str %dname)))
                  (self em %rest prims-alist (pair %dname-str seen))))))
          (self em %rest prims-alist seen)))))))))

; --- Page header emission ---

(def %doc-emit-page-header
  (fn (_ em tokens)
    (def %provide (%doc-find-provide tokens))
    (unless (null? %provide)
      (let ()
        (def %mod-name (symbol->str (List ref 0 %provide)))
        ; Back navigation — count slashes to determine depth
        (def %depth
          (%fold (fn (_ acc ch) (if (= ch (%integer->char 47)) (+ acc 1) acc))
            0 (Str ->list %mod-name)))
        (em page-header %mod-name (List ref 1 %provide)
            (DocEmit meta-strs (List ref 6 %provide)) %depth)))))

; --- Public walkers ---

; Splice top-level (do ...) bodies into the token stream: a file whose whole
; body rides one do form (x-core.x) otherwise hides every doc/provide from
; the walker and produces an empty page.
(def %doc-splice-dos
  (fn (self tokens)
    (match
      ((null? tokens) ())
      ; string compare, not eq?: tokens come from a FRESH base (doc.x), and
      ; symbol interning is per-base, so 'do here is a different atom
      ((if (pair? (first tokens)) (%doc-sym-is? (first (first tokens)) "do") #f)
        (%append (self (rest (first tokens))) (self (rest tokens))))
      (#t (pair (first tokens) (self (rest tokens)))))))

(doc (def %doc-walk-with-prims
  (fn (_ tokens prims-alist em)
    (def %spliced (%doc-splice-dos tokens))
    (%doc-emit-page-header em %spliced)
    ; Build local doc lookup from standalone (doc name ...) forms in source,
    ; then merge with prims-alist so bare defs find their docs
    (def %local-alist (%doc-build-lookup %spliced))
    (def %merged (%append %local-alist prims-alist))
    (%doc-walk-body-with-prims em %spliced %merged ())))
  (param tokens LIST "Source file token list")
  (param prims-alist LIST "Alist from doc-build-lookup (or () for none)")
  (param em ANY "Emitter class (DocMd, DocMan)")
  "Walk source tokens, using prims-alist as fallback docs for bare defs.")

(doc (def %doc-walk
  (fn (_ tokens em)
    (%doc-walk-with-prims tokens () em)))
  (param tokens LIST "Token list from %token-read-string")
  (param em ANY "Emitter class (DocMd, DocMan)")
  "Walk a token tree, emitting all documentation through an emitter.")

(doc (provide x/doc/doc-gen)
  "Documentation generator from x-lang source tokens; output format rides an emitter (x/doc/emit).")
