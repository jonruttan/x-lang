; xon.x -- xon (x object notation) text codec
;
; xon is the on-disk form language of the pin manifests and lockfiles:
; s-expr forms, one per line, string arguments quoted.  Before this
; module every consumer re-derived the three layers by hand -- tokenize
; (with or without the end-of-buffer workaround), walk a closed
; vocabulary of heads, render forms back to text -- and the renderers
; disagreed with the reader about escaping (#224).  One codec, so each
; layer has a single definition (#230).
;
; The line shape is load-bearing OUTSIDE this module: x.sh and the
; release scripts extract forms with line-anchored sed/grep.  emit keeps
; their contract -- one form per line -- and makes it robust: a quote,
; backslash, or newline in a string argument is escaped, so it can no
; longer change the number of forms a reader sees or break the line.

(def-class Xon ()
  (doc "xon (x object notation) codec: read forms from text, walk a closed vocabulary, emit forms as lines."
    (note "One form per line on emit -- the contract the shell-side extractors (x.sh, release scripts) anchor on.")
    (note "String arguments escape through the printer's write path, so the reader always inverts the writer (#224).")
    (see read) (see emit) (see walk))
  (static
    ; write-to-str quotes and escapes strings, renders numbers bare --
    ; but renders symbols as 'sym, and xon heads/args are bare, so
    ; symbols go through symbol->str instead.
    (method %xon-emit-atom (self v)
      (match
        ((str? v) ((prim-ref (lit io) (lit write-to-str)) v))
        ((symbol? v) (symbol->str v))
        ((number? v) ((prim-ref (lit io) (lit write-to-str)) v))
        (#t (Err raise (lit type) "Xon emit: unsupported atom in form" v))))
    (method read (self (param s STR "xon text")
                       . (param base ANY "Optional base to intern into (default: the current base)"))
      (doc "Tokenize xon text into a list of forms."
        (returns LIST "The forms, in file order")
        (note "Symbols intern into the given base (fmt/doc read into fresh scratch bases); default is the caller's.")
        ; read-str drops a token left unterminated at end of buffer
        ; (#161); the appended space closes the final token.  This door
        ; exists so that workaround -- and its eventual removal -- lives
        ; in exactly one place.
        (example "(first (first (Xon read \"(file \\\"a\\\" \\\"b\\\")\")))" "'file"))
      (Tok read-str (if (null? base) (%base) (first base))
                    (Str8 append s " ")))
    (method emit-form (self (param form LIST "One form"))
      (doc "Render one form as one xon line, newline-terminated, strings escaped."
        (returns STR "One line of xon text")
        (example "(Xon emit-form (list 'file \"a\" \"sha256:aa\"))" "\"(file \\\"a\\\" \\\"sha256:aa\\\")\\n\""))
      (def %args
        (fn (self args)
          (match
            ((null? args) "")
            ((not (pair? args)) (Err raise (lit type) "Xon emit: improper form tail" args))
            (#t (Str8 append " "
                  (Str8 append (Xon %xon-emit-atom (first args))
                               (self (rest args))))))))
      (match
        ((not (pair? form)) (Err raise (lit type) "Xon emit: a form is a list" form))
        ((not (symbol? (first form))) (Err raise (lit type) "Xon emit: form head is a symbol" form))
        (#t (Str8 append "("
              (Str8 append (symbol->str (first form))
                (Str8 append (%args (rest form)) ")\n"))))))
    (method emit (self (param forms LIST "Forms to render"))
      (doc "Render forms as xon text, one per line."
        (returns STR "xon text"))
      (def %go
        (fn (self forms acc)
          (match
            ((null? forms) acc)
            (#t (self (rest forms) (Str8 append acc (Xon emit-form (first forms))))))))
      (%go forms ""))
    (method walk (self (param table LIST "Vocabulary: ((head . handler) ...) alist, eq?-keyed")
                      (param unknown CALLABLE "Handler for forms whose head is not in the table (and non-list forms)")
                      (param forms LIST "Forms to dispatch"))
      (doc "Dispatch each form to its head's handler; collect non-nil results in form order."
        (returns LIST "Non-nil handler results, in input order")
        (note "A handler returning nil contributes nothing -- effect-style vocabularies return nil throughout and ignore the result.")
        (note "eq? on heads is sound only when table symbols and forms were read in the SAME base (symbols intern per-base)."))
      (def %go
        (fn (self forms acc)
          (match
            ((null? forms) (%reverse acc))
            (#t
              (let ((form (first forms)))
                (let ((hit (if (pair? form) (%assq (first form) table) ())))
                  (let ((r (if (null? hit) (unknown form) ((rest hit) form))))
                    (self (rest forms) (if (null? r) acc (pair r acc))))))))))
      (%go forms ()))))

(doc (provide x/codec/xon Xon)
  (note "The consumers this replaces hand-rolled all three layers: pin.x's renderers/walkers (#224/#230), and the tool scripts' bare Tok read-str calls.")
  (note "Boot-included modules (repl/ansi.x) cannot import this codec mid-boot; they keep a local terminated-read with a comment.")
  "Xon: read, vocabulary-walk, and emit the xon form language.")
