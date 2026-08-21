; emit-man.x -- DocMan: the roff (man page) implementation of DocEmit.
;
; One module page per source file, section 3x: the C reference already owns
; section 3 through Doxygen, and x-lang's library is a different namespace
; that should not collide with it -- or with any other project's man3.
;
; ALIASES.  A module page is not how anyone looks a name up; `man Str8-split`
; is.  DocEmit's `alias` operation carries the structured name of the entry
; about to be emitted, and this emitter writes it out as a
;
;   .\" X-ALIAS <name>
;
; comment line.  Roff ignores it (.\" is a comment), and tools/dev/man-sweep.sh
; harvests the lines to write one-line `.so` stub pages beside the real ones.
; The emitter stays a pure stdout filter that way -- it never has to know the
; output directory, the file names, or which aliases another page claimed.
;
; ESCAPING is not optional here.  x-lang identifiers are full of hyphens and
; backslashes reach roff as control characters, so every string that comes out
; of the walk goes through `esc` -- see its own note for the three rules.

(import x/type/class)
(import x/doc/emit)
(import x/core/list)
(import x/sys/posix)

(def-class DocMan (extends DocEmit)
  (doc "roff emitter: one man page per module, section 3x, plus .so alias stubs for every documented name."
    (note "Section 3x, not 3: Doxygen's C reference already occupies section 3, and the two namespaces should not collide.")
    (note "Alias names ride out as .\\\" X-ALIAS comment lines for the sweep to harvest; roff ignores them.")
    (see DocEmit) (see esc))
  (static
    (method esc (self (param s STRING "Text to escape"))
      (doc "Escape a string for roff."
        (note "Three rules: a backslash becomes \\e, a hyphen becomes \\- (roff renders a bare - as a typographic hyphen, which is wrong for an identifier and breaks copy-paste), and a leading . or ' is protected with \\& so roff does not read the line as a request.")
        (returns STRING "Text safe to emit in a man page"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %n (%blen s))
      (bytes->str
        (%reverse
          (let go ((i 0) (acc ()))
            (if (>= i %n) acc
              (let ((b (%c->i (%bref s i))))
                (go (+ i 1)
                  (match
                    ((= b 92) (pair 101 (pair 92 acc)))          ; \ -> \e
                    ((= b 45) (pair 45 (pair 92 acc)))           ; - -> \-
                    ((if (= i 0) (if (= b 46) #t (= b 39)) #f)   ; leading . or '
                      (pair b (pair 38 (pair 92 acc))))
                    (#t (pair b acc))))))))))

    ; A module name is a path; a man page name cannot be.  x/type/base
    ; becomes x-type-base, which is also what the alias stubs point at.
    (method page-name (self (param mod STRING "Module name, e.g. x/type/base"))
      (doc "Flatten a module path into its man page name."
        (returns STRING "The page name, e.g. x-type-base")
        (example "(DocMan page-name \"x/type/base\")" "\"x-type-base\""))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %n (%blen mod))
      (bytes->str
        (%reverse
          (let go ((i 0) (acc ()))
            (if (>= i %n) acc
              (let ((b (%c->i (%bref mod i))))
                (go (+ i 1) (pair (if (= b 47) 45 b) acc))))))))

    (method page-header (self (param mod STRING "Module name, e.g. x/type/base")
                              (param desc STRING "Module description, or \"\"")
                              (param notes LIST "Note strings")
                              (param depth INT "Directory depth -- unused; man pages have no relative links")
                              (param declared? BOOL "Whether the file declared (provide ...) -- unused; a man page needs a .TH either way"))
      (doc "Emit the .TH header, the NAME section man's apropos database reads, and DESCRIPTION."
        (note "Unlike Markdown, roff gets a header even for an undeclared file: without .TH the file is not a man page, and man renders it with no header at all. The title then comes from the source path."))
      ; The release rides the .TH date slot, which is where Doxygen puts it
      ; for the C reference too -- an installed page can then say which build
      ; it came from.  Read from the environment for the same reason doc-c
      ; does it that way: the Makefile owns X_RELEASE.
      (def %rel (let ((v (Sys getenv "X_RELEASE"))) (if (null? v) "" v)))
      (display $".TH \"{(self page-name mod)}\" \"3x\" \"{(self esc %rel)}\" \"x-lang\" \"x-lang library\"\n")
      ; NAME is what apropos indexes, so the dash separator only appears
      ; when there is something after it: lib/x/boot/* and the platform
      ; tables declare no module and have no description at all.
      (display ".SH NAME\n")
      (display (if (str=? desc "") $"{(self esc mod)}\n"
                 $"{(self esc mod)} \\- {(self esc desc)}\n"))
      ; No .PP after .SH: a paragraph macro straight after a section heading
      ; is redundant, and both groff and mandoc skip it with a warning.
      ; DESCRIPTION is skipped entirely when there is nothing to put in it,
      ; rather than left standing empty above the first entry.
      (unless (if (str=? desc "") (null? notes) #f)
        (do (display ".SH DESCRIPTION\n")
            (unless (str=? desc "") (display $"{(self esc desc)}\n"))
            (List for-each (fn (_ n) (self note n)) notes))))

    (method section (self (param title STRING "Section title"))
      (doc "Emit a top-level section heading.")
      (display $".SH \"{(self esc title)}\"\n"))

    (method class-head (self (param cname STRING "Class name")
                             (param parent STRING "Parent class name, or \"\""))
      (doc "Emit a class as its own section, naming the parent when it extends one.")
      (display $".SH \"CLASS {(self esc cname)}\"\n")
      (unless (str=? parent "")
        (display $".PP\nExtends \\fB{(self esc parent)}\\fP.\n")))

    (method interface-line (self (param names LIST "Operation name strings"))
      (doc "Emit the class's (interface ...) contract.")
      (display ".PP\n\\fBInterface:\\fP")
      (List for-each (fn (_ n) (display $" \\fB{(self esc n)}\\fP")) names)
      (newline))

    (method entry-head (self (param name STRING "Entry name or rendered signature"))
      (doc "Emit one entry as a subsection heading.")
      (display $".SS \"{(self esc name)}\"\n"))

    (method alias (self (param name STRING "Lookup name for the entry that follows"))
      (doc "Record a lookup name as a roff comment for the sweep to harvest into a .so stub."
        (note "Emitted UNESCAPED: this is a file name for the sweep, not display text."))
      (display $".\\\" X-ALIAS {name}\n"))

    (method text (self (param s STRING "Paragraph text"))
      (doc "Emit a description paragraph.")
      (display $".PP\n{(self esc s)}\n"))

    (method note (self (param s STRING "Note text"))
      (doc "Emit a note as an indented block, the roff answer to Markdown's blockquote.")
      (display $".RS 4\n.PP\n{(self esc s)}\n.RE\n"))

    (method params (self (param ps LIST "List of (name type desc) string triples"))
      (doc "Emit the parameter list as tagged paragraphs -- the shape man readers expect for arguments.")
      (display ".PP\n\\fBParameters:\\fP\n")
      (List for-each
        (fn (_ p)
          (display $".TP\n\\fB{(self esc (List ref 0 p))}\\fP")
          (unless (str=? (List ref 1 p) "")
            (display $" (\\fI{(self esc (List ref 1 p))}\\fP)"))
          (newline)
          (display (if (str=? (List ref 2 p) "") "\\&\n"
                     $"{(self esc (List ref 2 p))}\n")))
        ps))

    (method returns (self (param type STRING "Return type name")
                          (param desc STRING "Return description, or \"\""))
      (doc "Emit the return type and its description.")
      (display $".PP\n\\fBReturns:\\fP \\fI{(self esc type)}\\fP")
      (unless (str=? desc "") (display $" \\- {(self esc desc)}"))
      (newline))

    (method examples (self (param exs LIST "List of (input output) string pairs"))
      (doc "Emit the worked examples as a no-fill block, so the transcript keeps its own line breaks and spacing.")
      (display ".PP\n\\fBExamples:\\fP\n.RS 4\n.nf\n")
      (List for-each
        (fn (_ ex)
          (display $"{(self esc (List ref 0 ex))} => {(self esc (List ref 1 ex))}\n"))
        exs)
      (display ".fi\n.RE\n"))

    (method see-also (self (param names LIST "Referenced name strings"))
      (doc "Emit the cross-references.")
      (display ".PP\n\\fBSee also:\\fP")
      (List for-each (fn (_ s) (display $" \\fB{(self esc s)}\\fP")) names)
      (newline))))

(doc (provide x/doc/emit-man)
  "roff (man page) emitter for the documentation generator.")
