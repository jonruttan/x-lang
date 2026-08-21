; emit.x -- DocEmit: the documentation output protocol, and DocMd, its
; Markdown implementation.
;
; doc-gen walks source tokens and EXTRACTS structure; the walk used to
; `display` Markdown inline at 35 sites, which is why a second output
; format had nowhere to attach.  The walk now speaks to an emitter -- a
; CLASS value, passed as data -- and the format is whatever class the
; caller hands it: DocMd here, DocMan (roff) in emit-man.x.
;
; Emitters are stateless and their methods are all STATIC, so the emitter
; travels as the bare class (`(def em DocMd)`, then `(em note "...")`).
; No instances, no members, no per-call dispatch on instance state -- the
; walk threads one value through and nothing has to be constructed.
;
; The protocol takes PLAIN DATA, never raw token forms: strings, lists of
; strings, lists of (name type desc) triples.  Destructuring the (param
; ...) and (example ...) forms stays in doc-gen where the token shapes are
; already understood, so an emitter only has to know how to render -- the
; roff implementation never has to learn what a spliced variadic tail is.

(import x/type/class)
(import x/core/list)

(def-class DocEmit ()
  (doc "The documentation output protocol: the operations doc-gen's walk emits through. Subclass and supply all twelve to add an output format."
    (note "Every operation is a STATIC method, so the emitter is passed as the class value itself rather than an instance.")
    (note "Operations receive plain data -- strings and lists of strings -- never raw token forms; doc-gen owns the destructuring.")
    (see page-header) (see entry-head))
  (interface page-header section class-head interface-line entry-head
             alias text note params returns examples see-also)

  ; --- Adapters: token forms -> the plain data the protocol takes ---------
  ; These live WITH the protocol rather than in the walker because they are
  ; defined by what an emitter accepts, not by how the walk finds it.  Every
  ; implementation inherits them and none has to learn what a three-element
  ; (param ...) or a spliced variadic tail means.
  (static
    (method as-str (self (param v ANY "Any token value"))
      (doc "Stringify a token value the way the generator's interpolation does."
        (note "Entry heads are sometimes symbols (a bare def) and sometimes already strings (a rendered method signature); both must render unquoted.")
        (returns STRING "The value as display text"))
      $"{v}")

    (method meta-strs (self (param forms LIST "(note ...) or (see ...) forms"))
      (doc "Take the payload of each meta form, stringified."
        (returns LIST "String list"))
      (%map (fn (_ f) (self as-str (first (rest f)))) forms))

    (method param-triples (self (param ps LIST "(param NAME TYPE desc) forms"))
      (doc "Flatten parameter forms to (name type desc) string triples, each absent field empty."
        (note "The shapes are load-bearing and predate the protocol: a THIRD element that is a string is not a type at all -- it carries no type, and its description was never rendered either. Both rules are preserved rather than fixed, because the pages are a ratcheted artifact.")
        (returns LIST "List of three-element string lists"))
      (%map
        (fn (_ p)
          (let ((third (unless (null? (rest (rest p))) (first (rest (rest p)))))
                (fourth (if (null? (rest (rest p))) ()
                          (if (null? (rest (rest (rest p)))) ()
                            (first (rest (rest (rest p))))))))
            (list (self as-str (first (rest p)))
                  (if (null? third) "" (if (str? third) "" (self as-str third)))
                  (if (null? fourth) "" (if (str? fourth) fourth "")))))
        ps))

    (method example-pairs (self (param exs LIST "(example in out) forms"))
      (doc "Flatten example forms to (input output) string pairs."
        (returns LIST "List of two-element string lists"))
      (%map (fn (_ ex)
              (list (self as-str (first (rest ex)))
                    (self as-str (first (rest (rest ex))))))
            exs))

    (method returns-desc (self (param ret LIST "A (returns TYPE desc) form"))
      (doc "A return form's description, or empty -- a non-string third element is not a description."
        (returns STRING "The description text"))
      (if (null? (rest (rest ret))) ""
        (if (str? (first (rest (rest ret)))) (first (rest (rest ret))) "")))))

(def-class DocMd (extends DocEmit)
  (doc "Markdown emitter: the reference pages under docs/ref/x, one .md per module."
    (note "Output is byte-for-byte what doc-gen emitted before the protocol existed; the sweep's pages are unchanged.")
    (see DocEmit))
  (static
    (method page-header (self (param mod STRING "Module name, e.g. x/type/base")
                              (param desc STRING "Module description, or \"\"")
                              (param notes LIST "Note strings")
                              (param depth INT "Directory depth, for the relative index link"))
      (doc "Emit the page header: the index back-link, the H1, the module description and its notes."
        (note "depth drives the ../ prefix on the index link; roff has no such link and ignores it."))
      (def %back
        (let go ((i depth) (acc ""))
          (if (< i 1) acc (go (- i 1) (Str8 append acc "../")))))
      (display $"[← Index]({%back}index.md)\n\n")
      (display $"# {mod}\n\n")
      (unless (str=? desc "") (display $"{desc}\n\n"))
      (List for-each (fn (_ n) (display $"> {n}\n\n")) notes))

    (method section (self (param title STRING "Section title"))
      (doc "Emit a section heading -- a (note \"...\") form at file top level.")
      (display $"## {title}\n\n"))

    (method class-head (self (param cname STRING "Class name")
                             (param parent STRING "Parent class name, or \"\""))
      (doc "Emit a class heading, and its parent when the class extends one.")
      (display $"## Class `{cname}`\n\n")
      (unless (str=? parent "") (display $"*Extends `{parent}`.*\n\n")))

    (method interface-line (self (param names LIST "Operation name strings"))
      (doc "Emit a class's (interface ...) contract -- the operations a subclass must supply.")
      (display "**Interface:** ")
      (List for-each (fn (_ n) (display $"`{n}` ")) names)
      (display "\n\n"))

    (method entry-head (self (param name STRING "Entry name or rendered signature"))
      (doc "Emit the heading for one documented entry: a def, a method, or a member.")
      (display $"### `{name}`\n\n"))

    (method alias (self (param name STRING "Lookup name for the entry that follows"))
      (doc "Record a lookup name for the next entry. Markdown has intra-page anchors already, so this is a no-op here; man output turns each one into a .so stub page."
        (note "Called with the STRUCTURED name -- Class-method, not the rendered signature -- because a lookup name has to be typeable."))
      ())

    (method text (self (param s STRING "Paragraph text"))
      (doc "Emit a description paragraph.")
      (display $"{s}\n\n"))

    (method note (self (param s STRING "Note text"))
      (doc "Emit one note -- a caveat or contract line attached to the entry above it.")
      (display $"> {s}\n\n"))

    (method params (self (param ps LIST "List of (name type desc) string triples"))
      (doc "Emit the parameter list. An empty type or description is omitted rather than rendered blank.")
      (display "**Parameters:**\n\n")
      (List for-each
        (fn (_ p)
          (display $"- **{(List ref 0 p)}**")
          (unless (str=? (List ref 1 p) "") (display $" : `{(List ref 1 p)}`"))
          (unless (str=? (List ref 2 p) "") (display $" — {(List ref 2 p)}"))
          (newline))
        ps)
      (newline))

    (method returns (self (param type STRING "Return type name")
                          (param desc STRING "Return description, or \"\""))
      (doc "Emit the return type and its description.")
      (display $"**Returns:** `{type}`")
      (unless (str=? desc "") (display $" — {desc}"))
      (newline) (newline))

    (method examples (self (param exs LIST "List of (input output) string pairs"))
      (doc "Emit the worked examples as an x-repl block."
        (note "The x-repl fence is what the doctest ratchet reads back; the pairs are (example INPUT OUTPUT) forms."))
      (display "**Examples:**\n\n" "```x-repl\n")
      (List for-each
        (fn (_ ex) (display $"{(List ref 0 ex)} => {(List ref 1 ex)}\n"))
        exs)
      (display "```\n\n"))

    (method see-also (self (param names LIST "Referenced name strings"))
      (doc "Emit the cross-references as intra-page anchors.")
      (display "**See also:** ")
      (List for-each (fn (_ s) (display $"[`{s}`](#{s}) ")) names)
      (newline) (newline))))

(doc (provide x/doc/emit)
  "The documentation output protocol (DocEmit) and its Markdown implementation (DocMd).")
