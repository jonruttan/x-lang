; sys/opts.x -- Opts: the command line, parsed once.
;
; EVERY BUNDLE WAS WRITING THIS.  x-grep's %grep-optarg and x-make's
; %mk-optarg are byte-identical apart from the error label, and
; x-coreutils grew nine parsers of its own -- one for clustered
; letters, one for attached values, one per applet for the operands.
; The cost was not the duplication.  It was that the CHECK and the
; READ drifted apart: x-coreutils' option guard admitted `-sm`, `-k2`
; and `-r`, and the applets behind it read whole tokens, the separated
; spelling only, and nothing at all -- three silent defects, each one
; a flag accepted and then ignored.
;
; So a caller declares its options ONCE, as two lists, and this parses
; against that declaration.  What the parser accepts is what the
; accessors read, because they are the same declaration.
;
;   (def spec-flags  (list "-r" "-n" "-u"))
;   (def spec-values (list "-k" "-t"))
;   (def o (Opts parse spec-flags spec-values argv))
;   (Opts on? o "-r")            ; was it given, in any spelling
;   (Opts value o "-k" "1")      ; its argument, or the default
;   (Opts operands o)            ; what was left
;   (Opts unknown o)             ; the first flag nobody declared
;
; THE HELP TEXT is the same declaration.  A command that prints usage
; declares its options as rows that carry their descriptions, and the
; rows are both what parse accepts and what usage prints:
;
;   (def d (Opts declare "cut" "[-s] [-d SEP] [FILE]..." "Print fields"
;            (list (Opts flag "-s" "Drop lines with no delimiter")
;                  (Opts arg "-d" "SEP" "Input field delimiter"))))
;   (Opts parse d argv)          ; as above, with the declaration
;   (Opts help? d argv)          ; --help first, and help not turned off
;   (Opts usage d)               ; busybox's layout, as a string
;
; THE SPELLINGS, all of which getopt(3) accepts and a hand-rolled
; reader usually does not: `-r`, the cluster `-rn`, the separated
; value `-k 2`, the attached value `-k2`, the value at the tail of a
; cluster `-nk2`, the long form `--name` and `--name=value`, and `--`
; ending the options.  A bare `-` is an operand (it means stdin), and
; so is a negative number, so `sort -5` reads as an operand rather
; than five unknown flags.

(module x/sys/opts)
(import x/type/class)
(import x/core/list)

(def-class Opts ()
  (doc "The command line, parsed against a declaration: a list of flags that stand alone and a list that take an argument. Clusters, attached and separated values, --long, --long=value and -- are all understood, so a caller does not re-derive them. Answers a record the other methods read."
    (example "(Opts operands (Opts parse (list \"-r\") () (list \"-r\" \"f\")))" "(\"f\")")
    (example "(Opts on? (Opts parse (list \"-a\" \"-b\") () (list \"-ab\")) \"-b\")" "#t")
    (see parse) (see on?) (see value) (see operands) (see unknown))
  (static
    (method parse (self (param decl ANY "A declaration from (Opts declare), or the list of options that stand alone, as \"-r\" or \"--verbose\"")
                   . (param more LIST "After a declaration, the arguments; after a list of flags, the options that take an argument and then the arguments"))
      (doc "Parse argv against the declaration. Options may appear before or after operands (as getopt permutes); a caller whose operands can look like flags -- echo(1) -- wants parse-leading instead. The first undeclared option is remembered rather than raised, so the caller chooses the wording and the exit status. Given a declaration, a row's spellings are one option: whichever was given, on? and value answer for all of them."
        (returns ALIST "((on . LIST) (values . ALIST) (operands . LIST) (unknown . ANY))")
        (example "(Opts value (Opts parse () (list \"-k\") (list \"-k2\")) \"-k\")" "\"2\"")
        (example "(Opts unknown (Opts parse (list \"-a\") () (list \"-z\")))" "\"-z\"")
        (example "(Opts on? (Opts parse (Opts declare \"t\" \"\" () (list (Opts flag \"-q\" \"--quiet\" \"Quiet\"))) (list \"--quiet\")) \"-q\")" "#t"))
      (self %parse decl more #f))

    (method parse-leading (self (param decl ANY "A declaration, or the options that stand alone")
                           . (param more LIST "As for (Opts parse)"))
      (doc "Parse as (Opts parse) does, but STOP at the first operand: everything after it is an operand too, whatever it looks like. This is what echo(1) needs -- `echo hi -n` prints `hi -n` -- and what a guard checking only the leading tokens wants."
        (returns ALIST "((on . LIST) (values . ALIST) (operands . LIST) (unknown . ANY))")
        (example "(Opts operands (Opts parse-leading (list \"-n\") () (list \"hi\" \"-n\")))" "(\"hi\" \"-n\")"))
      (self %parse decl more #t))

    (method on? (self (param opts ALIST "A parsed command line")
                      (param flag STRING "The flag to ask about"))
      (doc "Was this flag given, in any spelling it has? True for a flag that stands alone AND for one that takes an argument -- the question is presence, not whether the flag takes an argument, and a caller that had to know which list a flag landed in would be re-deriving the declaration it already made."
        (returns BOOL "True when the flag was present")
        (example "(Opts on? (Opts parse (list \"-v\") () (list \"-v\")) \"-v\")" "#t")
        (example "(Opts on? (Opts parse () (list \"-m\") (list \"-m\" \"700\")) \"-m\")" "#t")
        (example "(Opts on? (Opts parse (list \"-v\") () ()) \"-v\")" "#f"))
      (if (self %member? flag (rest (Assoc entry (lit on) opts))) #t
        (not (null? (self values opts flag)))))

    (method value (self (param opts ALIST "A parsed command line")
                        (param flag STRING "The value-taking flag")
                   . (param default ANY "Answered when the flag was absent; nil when omitted"))
      (doc "The argument this flag carried -- the LAST one, when it was given more than once. Answers the default (or nil) when the flag was absent."
        (returns ANY "The argument, or the default")
        (example "(Opts value (Opts parse () (list \"-t\") (list \"-t\" \",\")) \"-t\")" "\",\"")
        (example "(Opts value (Opts parse () (list \"-w\") ()) \"-w\" \"6\")" "\"6\""))
      (let ((all (self values opts flag)))
        (if (null? all) (if (null? default) () (first default))
          (List last all))))

    (method values (self (param opts ALIST "A parsed command line")
                         (param flag STRING "The value-taking flag"))
      (doc "EVERY argument this flag carried, in the order given -- what `grep -e one -e two` needs. Empty when the flag was absent."
        (returns LIST "The arguments, in order")
        (example "(Opts values (Opts parse () (list \"-e\") (list \"-e\" \"a\" \"-e\" \"b\")) \"-e\")" "(\"a\" \"b\")"))
      (let go ((es (rest (Assoc entry (lit values) opts))) (acc ()))
        (if (null? es) (%reverse acc)
          (go (rest es)
              (if (str=? (first (first es)) flag)
                (pair (rest (first es)) acc) acc)))))

    (method operands (self (param opts ALIST "A parsed command line"))
      (doc "The arguments that were not options, nor an option's argument, in the order given."
        (returns LIST "The operands")
        (example "(Opts operands (Opts parse () (list \"-o\") (list \"-o\" \"out\" \"in\")))" "(\"in\")"))
      (rest (Assoc entry (lit operands) opts)))

    (method unknown (self (param opts ALIST "A parsed command line"))
      (doc "The first option the declaration did not name, or nil when every one was known. A caller refuses on this rather than letting an unread flag pass for a filename."
        (returns ANY "The offending token, or nil")
        (example "(Opts unknown (Opts parse (list \"-a\") () (list \"-az\")))" "\"-az\""))
      (rest (Assoc entry (lit unknown) opts)))

    ; --- the declaration --------------------------------------------------

    (method declare (self (param name STRING "The command's name, as the Usage: line prints it")
                          (param synopsis STRING "What follows the name on the Usage: line")
                          (param summary ANY "The text under the Usage: line, or nil")
                          (param rows LIST "The rows: (Opts flag ...), (Opts arg ...), (Opts hidden ...), (Opts text ...)")
                     . (param settings LIST "Pairs: (column . N) sets the description column, (help . #f) turns --help off, (banner . TEXT) leads the text"))
      (doc "A command's options and its help text as ONE declaration: parse reads the rows' spellings and usage prints the rows, so an option cannot be accepted and undocumented, nor documented and refused. The synopsis is written out rather than generated -- busybox's group and order their options by hand."
        (returns ALIST "The declaration parse, help? and usage read")
        (example "(Opts flags (Opts declare \"t\" \"\" () (list (Opts flag \"-a\" \"All\") (Opts arg \"-o\" \"FILE\" \"Out\"))))" "(\"-a\")")
        (see flag) (see arg) (see hidden) (see text) (see usage) (see help?))
      (list (pair (lit name) name)
            (pair (lit synopsis) synopsis)
            (pair (lit summary) summary)
            (pair (lit rows) rows)
            (pair (lit flags) (self %spellings rows (lit flag)))
            (pair (lit valued) (self %spellings rows (lit value)))
            (pair (lit settings) settings)))

    (method flag (self . (param words LIST "One or more spellings, then the description"))
      (doc "A row for an option that stands alone. Every spelling names the same option: (Opts flag \"-q\" \"--quiet\" \"Quiet\")."
        (returns LIST "The row")
        (example "(Opts usage (Opts declare \"t\" \"\" () (list (Opts flag \"-q\" \"--quiet\" \"Quiet\"))))" "\"Usage: t\\n\\n\\t-q,--quiet\\tQuiet\\n\""))
      (def r (%reverse words))
      (list (lit flag) (%reverse (rest r)) () (first r) #t))

    (method arg (self . (param words LIST "One or more spellings, the argument's name, then the description"))
      (doc "A row for an option that takes an argument: (Opts arg \"-o\" \"FILE\" \"Output to FILE\")."
        (returns LIST "The row")
        (example "(Opts valued (Opts declare \"t\" \"\" () (list (Opts arg \"-o\" \"FILE\" \"Out\"))))" "(\"-o\")"))
      (def r (%reverse words))
      (list (lit value) (%reverse (rest (rest r))) (first (rest r)) (first r) #t))

    (method hidden (self (param row LIST "A flag or value row"))
      (doc "The row, accepted by parse but left out of usage -- for spellings a command takes and does not advertise."
        (returns LIST "The row, unlisted"))
      (list (first row) (List ref 1 row) (List ref 2 row) (List ref 3 row) #f))

    (method text (self (param line STRING "A line of the help text, printed as written"))
      (doc "A row that is only text: a continuation line, a heading, or an option row laid out by hand. It declares nothing."
        (returns LIST "The row"))
      (list (lit text) () () line #t))

    (method name (self (param decl ALIST "A declaration"))
      (doc "The command's name." (returns STRING "The name"))
      (rest (Assoc entry (lit name) decl)))

    (method flags (self (param decl ALIST "A declaration"))
      (doc "Every spelling of every option that stands alone, hidden or not."
        (returns LIST "The spellings"))
      (rest (Assoc entry (lit flags) decl)))

    (method valued (self (param decl ALIST "A declaration"))
      (doc "Every spelling of every option that takes an argument, hidden or not."
        (returns LIST "The spellings"))
      (rest (Assoc entry (lit valued) decl)))

    (method help? (self (param decl ALIST "A declaration")
                        (param argv LIST "The arguments"))
      (doc "Is this a request for help: --help as the FIRST argument, and help not turned off? Busybox asks exactly this, before any option is parsed; test, true, false and echo turn it off, since POSIX gives --help no meaning there."
        (returns BOOL "True when the caller should print usage")
        (example "(Opts help? (Opts declare \"t\" \"\" () ()) (list \"--help\"))" "#t")
        (example "(Opts help? (Opts declare \"t\" \"\" () ()) (list \"-a\" \"--help\"))" "#f")
        (example "(Opts help? (Opts declare \"t\" \"\" () () (pair 'help #f)) (list \"--help\"))" "#f"))
      (if (null? argv) #f
        (if (str=? (first argv) "--help") (self %setting decl (lit help) #t) #f)))

    (method usage (self (param decl ALIST "A declaration"))
      (doc "The help text, laid out as busybox lays its out: the Usage: line, the summary, then a row per listed option -- a tab, the spellings and argument, and tabs out to the description column. The column is the first tab stop past the widest option unless (column . N) sets it. The caller chooses the stream and the status."
        (returns STRING "The text, ending in a newline")
        (example "(Opts usage (Opts declare \"t\" \"[-a] FILE\" \"Do it\" (list (Opts flag \"-a\" \"All\"))))" "\"Usage: t [-a] FILE\\n\\nDo it\\n\\n\\t-a\\tAll\\n\"")
        (example "(Opts usage (Opts declare \"t\" \"FILE\" ()  ()))" "\"Usage: t FILE\\n\""))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def syn (rest (Assoc entry (lit synopsis) decl)))
      (def summary (rest (Assoc entry (lit summary) decl)))
      (def banner (self %setting decl (lit banner) ()))
      (def shown (self %shown (rest (Assoc entry (lit rows) decl))))
      (def column (self %setting decl (lit column) (self %column shown)))
      (%str-concat
        (list (if (null? banner) "" (%str-concat (list banner "\n\n")))
              "Usage: " (self name decl)
              (match
                ((= (%blen syn) 0) "")
                ((= (%bref syn 0) 10) syn)
                (#t (%str-concat (list " " syn))))
              (if (if (null? summary) (null? shown) #f) ""
                (%str-concat
                  (list (if (null? summary) "" (%str-concat (list "\n\n" summary)))
                        (if (null? shown) ""
                          (%str-concat
                            (pair "\n"
                              (let go ((rs shown) (acc ()))
                                (if (null? rs) (%reverse acc)
                                  (go (rest rs)
                                      (pair (self %line (first rs) column) (pair "\n" acc)))))))))))
              "\n")))

    ; --- the rows ---------------------------------------------------------

    (method %setting (self (param decl ALIST "A declaration")
                           (param key SYMBOL "column, help or banner")
                           (param default ANY "Answered when it was not set"))
      (doc "A setting given to declare, or the default." (returns ANY "The setting"))
      (let ((e (Assoc entry key (rest (Assoc entry (lit settings) decl)))))
        (if (null? e) default (rest e))))

    (method %spellings (self (param rows LIST "Rows") (param label SYMBOL "flag or value"))
      (doc "Every spelling of the rows with this label, in order." (returns LIST "The spellings"))
      (let go ((rs rows) (acc ()))
        (if (null? rs) (%reverse acc)
          (go (rest rs)
              (if (eq? (first (first rs)) label)
                (%append2 (%reverse (List ref 1 (first rs))) acc) acc)))))

    (method %shown (self (param rows LIST "Rows"))
      (doc "The rows usage lists." (returns LIST "The rows not hidden"))
      (let go ((rs rows) (acc ()))
        (if (null? rs) (%reverse acc)
          (go (rest rs) (if (List ref 4 (first rs)) (pair (first rs) acc) acc)))))

    (method %left (self (param row LIST "A flag or value row"))
      (doc "A row's left column: its spellings joined by commas, and the argument's name."
        (returns STRING "The text"))
      (let go ((ss (List ref 1 row)) (acc ()))
        (if (null? ss)
          (%str-concat
            (%reverse (if (null? (List ref 2 row)) acc
                        (pair (List ref 2 row) (pair " " acc)))))
          (go (rest ss) (pair (first ss) (if (null? acc) acc (pair "," acc)))))))

    ; the left column starts at the first tab stop, 8, so the description
    ; column is the first stop past 8 plus the widest left
    (method %column (self (param rows LIST "The listed rows"))
      (doc "The first tab stop past the widest option." (returns INTEGER "The column"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (let go ((rs rows) (wide 0))
        (if (null? rs) (self %stop (+ 8 wide))
          (go (rest rs)
              (if (eq? (first (first rs)) (lit text)) wide
                (let ((w (%blen (self %left (first rs)))))
                  (if (> w wide) w wide)))))))

    (method %stop (self (param col INTEGER "A column"))
      (doc "The first tab stop past this column." (returns INTEGER "The stop"))
      (let go ((s 8)) (if (> s col) s (go (+ s 8)))))

    (method %line (self (param row LIST "A listed row") (param column INTEGER "The description column"))
      (doc "One row of the help text, without its newline."
        (returns STRING "The line"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (if (eq? (first row) (lit text)) (List ref 3 row)
        (let ((left (self %left row)))
          ; a tab at least, then tabs until the column is reached
          (let go ((c (self %stop (+ 8 (%blen left)))) (acc (list left "\t")))
            (if (>= c column)
              (%str-concat (%reverse (pair (List ref 3 row) (pair "\t" acc))))
              (go (self %stop c) (pair "\t" acc)))))))

    (method %parse (self (param decl ANY "A declaration, or the flags")
                         (param more LIST "argv, or the values and argv")
                         (param leading BOOL "Stop at the first operand?"))
      (doc "Parse either form; a declaration's rows widen each option to all its spellings."
        (returns ALIST "The parsed record"))
      (if (null? (rest more))
        (self %widen (self %walk (self flags decl) (self valued decl) (first more) leading)
              (rest (Assoc entry (lit rows) decl)))
        (self %walk decl (first more) (first (rest more)) leading)))

    (method %widen (self (param rec ALIST "A parsed record") (param rows LIST "The declaration's rows"))
      (doc "The record with every option given recorded under each of its row's spellings."
        (returns ALIST "The record"))
      (def spell (fn (_ s)
        (let go ((rs rows))
          (match
            ((null? rs) (list s))
            ((self %member? s (List ref 1 (first rs))) (List ref 1 (first rs)))
            (#t (go (rest rs)))))))
      (def on (let go ((l (rest (Assoc entry (lit on) rec))) (acc ()))
        (if (null? l) (%reverse acc) (go (rest l) (%append2 (spell (first l)) acc)))))
      (def vals (let go ((l (rest (Assoc entry (lit values) rec))) (acc ()))
        (if (null? l) (%reverse acc)
          (go (rest l)
              (let each ((ss (spell (first (first l)))) (acc acc))
                (if (null? ss) acc
                  (each (rest ss) (pair (pair (first ss) (rest (first l))) acc))))))))
      (list (pair (lit on) on)
            (pair (lit values) vals)
            (Assoc entry (lit operands) rec)
            (Assoc entry (lit unknown) rec)))

    ; --- the walk ---------------------------------------------------------

    (method %member? (self (param x STRING "Needle") (param xs LIST "Haystack"))
      (doc "Is this string in the list?" (returns BOOL "True when present"))
      (let go ((l xs))
        (if (null? l) #f (if (str=? (first l) x) #t (go (rest l))))))

    ; a token that could be an option: two or more characters, leading
    ; `-`, and not a negative number.  `-` alone is stdin, an operand.
    (method %option? (self (param tok STRING "A command-line token"))
      (doc "Could this token be an option?"
        (returns BOOL "True for -x, -xy, --long; false for -, -5 and plain words")
        (example "(Opts %option? \"-5\")" "#f"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (if (< (%blen tok) 2) #f
        (if (not (= (%bref tok 0) 45)) #f
          (let ((c (%bref tok 1)))
            (if (>= c 48) (not (<= c 57)) #t)))))

    (method %walk (self (param flags LIST "Standalone options")
                        (param values LIST "Value-taking options")
                        (param argv LIST "Arguments")
                        (param leading BOOL "Stop at the first operand?"))
      (doc "The parser proper: answers the record the accessors read."
        (returns ALIST "((on . LIST) (values . ALIST) (operands . LIST) (unknown . ANY))"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bsub (prim-ref (lit str) (lit byte-sub)))
      ; state rides the walk: seen flags, (flag . value) pairs, operands,
      ; and the first token nobody declared
      (let go ((as argv) (on ()) (vals ()) (ops ()) (bad ()) (done #f))
        (if (null? as)
          (list (pair (lit on) (%reverse on))
                (pair (lit values) (%reverse vals))
                (pair (lit operands) (%reverse ops))
                (pair (lit unknown) bad))
          (let ((a (first as)))
            (match
              ; `--` ends the options; everything after is an operand
              ((if done #t (str=? a "--"))
                (go (rest as) on vals
                    (if (str=? a "--") (if done (pair a ops) ops) (pair a ops))
                    bad #t))
              ((not (self %option? a))
                (go (rest as) on vals (pair a ops) bad leading))
              ; an exact value option: its argument is the next token
              ((self %member? a values)
                (if (null? (rest as))
                  (go () on vals ops (if (null? bad) a bad) done)
                  (go (rest (rest as)) on
                      (pair (pair a (first (rest as))) vals) ops bad done)))
              ((self %member? a flags) (go (rest as) (pair a on) vals ops bad done))
              ; --name=value
              ((self %long-value? a values)
                (let ((cut (self %long-split a)))
                  (go (rest as) on (pair cut vals) ops bad done)))
              (#t
                (let ((r (self %cluster a flags values (rest as))))
                  ; nil is the refusal; a cluster that sets only a VALUE
                  ; has an empty flag list and is not a refusal (-k2)
                  (if (null? r)
                    (go (rest as) on vals ops (if (null? bad) a bad) done)
                    (go (List ref 3 r)
                        (%append2 (first r) on)
                        (%append2 (List ref 1 r) vals)
                        ops bad done)))))))))

    (method %long-split (self (param tok STRING "A --name=value token"))
      (doc "Split --name=value into its pair." (returns PAIR "(--name . value)"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %bsub (prim-ref (lit str) (lit byte-sub)))
      (let go ((i 0))
        (if (>= i (%blen tok)) (pair tok "")
          (if (= (%bref tok i) 61)
            (pair (%bsub tok 0 i) (%bsub tok (+ i 1) (- (%blen tok) (+ i 1))))
            (go (+ i 1))))))

    (method %long-value? (self (param tok STRING "A token") (param values LIST "Value-taking options"))
      (doc "Is this --name=value for a declared value option?" (returns BOOL "True when it is"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (if (< (%blen tok) 3) #f
        (if (not (= (%bref tok 1) 45)) #f
          (self %member? (first (self %long-split tok)) values))))

    ; -rn, -k2, -nk2: each letter is a flag until one takes a value, and
    ; the REST of the token is that value (or the next token, when the
    ; letter ends it).  Answers (ON VALUES () REST) or (() () () ()).
    (method %cluster (self (param tok STRING "A clustered token")
                           (param flags LIST "Standalone options")
                           (param values LIST "Value-taking options")
                           (param more LIST "The arguments after this token"))
      (doc "Split a cluster into the options it names."
        (returns ANY "(ON VALUES () REST), or nil when a letter is undeclared"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %bsub (prim-ref (lit str) (lit byte-sub)))
      (def %dash (fn (_ c) (bytes->str (list 45 c))))
      (let go ((i 1) (on ()) (vals ()))
        (if (>= i (%blen tok)) (list (%reverse on) (%reverse vals) () more)
          (let ((name (%dash (%bref tok i))))
            (match
              ((self %member? name values)
                (let ((tail (%bsub tok (+ i 1) (- (%blen tok) (+ i 1)))))
                  (if (> (%blen tail) 0)
                    (list (%reverse on) (%reverse (pair (pair name tail) vals)) () more)
                    (if (null? more) ()
                      (list (%reverse on)
                            (%reverse (pair (pair name (first more)) vals))
                            () (rest more))))))
              ((self %member? name flags) (go (+ i 1) (pair name on) vals))
              (#t ()))))))))

(doc (provide x/sys/opts Opts)
  "Command-line parsing against a declaration of flags and valued options, on the Opts class.")
