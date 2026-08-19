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
      ; ONE catalog fetch per call (#333); it was one per matched branch.
      (let ((w (prim-ref (lit io) (lit write-to-str))))
        (match
          ((str? v) (w v))
          ((symbol? v) (symbol->str v))
          ((number? v) (w v))
          (#t (Err raise (lit type) "Xon emit: unsupported atom in form" v)))))
    ; A scratch base is the bare C ISA: the reader macros are armed on the
    ; BOOT base's string type (lit-reader.x), so a $"..." literal read into
    ; one SHATTERS at its first space -- and the trailing quote then opens a
    ; string that never closes, killing the file with "Unterminated input".
    ; Arm the SHARED analyser (one definition of where a literal ends, no
    ; second scanner to drift) with a KEEPING reader: a scratch base belongs
    ; to a tool that re-emits or inspects SOURCE, so the literal must survive
    ; as its own text.  lit-reader's EXPANDING reader would be exactly wrong
    ; here -- fmt would print (Str8 str ...) and destroy the sugar it was
    ; asked to format.  The token rides in a ('%interp "...") marker, the
    ; shape fmt already uses for comments; a bare string is indistinguishable
    ; from a real one, and converting to a symbol is not available -- the
    ; conversion catalog is off-limits inside x_token_read.
    ;
    ; Call ONCE per base, before its first read.  A handler slot is a LIST in
    ; every base; a fresh base's is STATIC-tagged, so it answers pair? with
    ; #f while walking like any other list (the #296 static-spine class).
    ; Prepending with pair handles both -- treating pair? #f as "a lone
    ; handler" and wrapping it makes the tokenizer apply a LIST as a handler,
    ; which bus-errors.
    (method arm-source! (self (param b ANY "A fresh base, before its first read"))
      (doc "Arm b to keep $\"...\" literals as ('%interp \"<source text>\") tokens."
        (returns ANY "nil")
        (note "For tools that read SOURCE into a scratch base (fmt, doc). The literal survives verbatim instead of shattering."))
      (let ((st (Xon %xon-find-type b "STRING")))
        (unless (null? st)
          (%type-push-analyse st (pair %interp-analyse (first (%type-analyse-cell st))))
          ; The tok prim is fetched ONCE here and closed over (#333):
          ; fetching it inside the callback paid a catalog walk per
          ; string token of every armed read.
          (%type-push-read st
            (pair (let ((%tokf (prim-ref (lit buf) (lit tok))))
                  (fn (_ buffer . rest)
                    (if (= (%buffer-last-char buffer) #\")
                      (let ((tok (%tokf buffer)))
                        (if (and (> (%str-length tok) 2) (= (%str-ref tok 0) #\$))
                          (list (lit %interp) tok)
                          ()))
                      ())))
                  (first (%type-read-cell st)))))))
    ; The base's type registry by NAME, through the contract-driven reflect
    ; door (tools/contract/base-paths.x), never a shape heuristic.
    (method %xon-find-type (self b name)
      ; The walk needs the RAW spine; a Base instance unwraps here.
      (let ((hit (%find (fn (_ e)
                          (str=? (%reflect-sym->str (%reflect-type-tree-name (rest e)))
                                 name))
                   (first (%reflect-step (Base raw-of b)
                            (%reflect-path (lit type-alist) %base-paths))))))
        (if (null? hit) () (rest hit))))
    (method parse (self (param s STR "xon text")
                       . (param base ANY "Optional base to intern into (default: the current base)"))
      (doc "Tokenize xon text into a list of forms."
        (returns LIST "The forms, in file order")
        (note "Symbols intern into the given base (fmt/doc read into fresh scratch bases); default is the caller's.")
        ; read-str drops a token left unterminated at end of buffer
        ; (#161); the appended space closes the final token.  This door
        ; exists so that workaround -- and its eventual removal -- lives
        ; in exactly one place.
        (example "(first (first (Xon parse \"(file \\\"a\\\" \\\"b\\\")\")))" "'file"))
      (Tok read-str (if (null? base) (%base) (first base))
                    (Str8 append s " ")))
    (method emit-form (self (param form LIST "One form"))
      (doc "Render one form as one xon line, newline-terminated, strings escaped."
        (returns STR "One line of xon text")
        (example "(Xon emit-form (list 'file \"a\" \"sha256:aa\"))" "\"(file \\\"a\\\" \\\"sha256:aa\\\")\\n\""))
      ; Pieces prepend, ONE concat (#333): the old right-recursive
      ; append chain re-copied every argument's tail per argument.
      (def %args
        (fn (self args acc)
          (match
            ((null? args) (%reverse (pair ")\n" acc)))
            ((not (pair? args)) (Err raise (lit type) "Xon emit: improper form tail" args))
            (#t (self (rest args)
                      (pair (Xon %xon-emit-atom (first args)) (pair " " acc)))))))
      (match
        ((not (pair? form)) (Err raise (lit type) "Xon emit: a form is a list" form))
        ((not (symbol? (first form))) (Err raise (lit type) "Xon emit: form head is a symbol" form))
        (#t (%str-concat
              (pair "(" (pair (symbol->str (first form)) (%args (rest form) ())))))))
    (method emit (self (param forms LIST "Forms to render"))
      (doc "Render forms as xon text, one per line."
        (returns STR "xon text"))
      ; One rendered piece per form, one concat (#333).
      (%str-concat (%map (fn (_ f) (Xon emit-form f)) forms)))
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
