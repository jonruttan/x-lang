; sys/opts.x -- Opts: the command line, parsed once.
;
; EVERY BUNDLE WAS WRITING THIS.  x-grep's %grep-optarg and x-make's
; %mk-optarg are byte-identical apart from the error tag, and
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
; THE SPELLINGS, all of which getopt(3) accepts and a hand-rolled
; reader usually does not: `-r`, the cluster `-rn`, the separated
; value `-k 2`, the attached value `-k2`, the value at the tail of a
; cluster `-nk2`, the long form `--name` and `--name=value`, and `--`
; ending the options.  A bare `-` is an operand (it means stdin), and
; so is a negative number, so `sort -5` reads as an operand rather
; than five unknown flags.

(import x/type/class)
(import x/core/list)

(def-class Opts ()
  (doc "The command line, parsed against a declaration: a list of flags that stand alone and a list that take an argument. Clusters, attached and separated values, --long, --long=value and -- are all understood, so a caller does not re-derive them. Answers a record the other methods read."
    (example "(Opts operands (Opts parse (list \"-r\") () (list \"-r\" \"f\")))" "(\"f\")")
    (example "(Opts on? (Opts parse (list \"-a\" \"-b\") () (list \"-ab\")) \"-b\")" "#t")
    (see parse) (see on?) (see value) (see operands) (see unknown))
  (static
    (method parse (self (param flags LIST "Options that stand alone, as \"-r\" or \"--verbose\"")
                        (param values LIST "Options that take an argument")
                        (param argv LIST "The arguments to parse"))
      (doc "Parse argv against the declaration. Options may appear before or after operands (as getopt permutes); a caller whose operands can look like flags -- echo(1) -- wants parse-leading instead. The first undeclared option is remembered rather than raised, so the caller chooses the wording and the exit status."
        (returns ALIST "((on . LIST) (values . ALIST) (operands . LIST) (unknown . ANY))")
        (example "(Opts value (Opts parse () (list \"-k\") (list \"-k2\")) \"-k\")" "\"2\"")
        (example "(Opts unknown (Opts parse (list \"-a\") () (list \"-z\")))" "\"-z\""))
      (self %walk flags values argv #f))

    (method parse-leading (self (param flags LIST "Options that stand alone")
                                (param values LIST "Options that take an argument")
                                (param argv LIST "The arguments to parse"))
      (doc "Parse as (Opts parse) does, but STOP at the first operand: everything after it is an operand too, whatever it looks like. This is what echo(1) needs -- `echo hi -n` prints `hi -n` -- and what a guard checking only the leading tokens wants."
        (returns ALIST "((on . LIST) (values . ALIST) (operands . LIST) (unknown . ANY))")
        (example "(Opts operands (Opts parse-leading (list \"-n\") () (list \"hi\" \"-n\")))" "(\"hi\" \"-n\")"))
      (self %walk flags values argv #t))

    (method on? (self (param opts ALIST "A parsed command line")
                      (param flag STRING "The flag to ask about"))
      (doc "Was this flag given, in any spelling it has?"
        (returns BOOL "True when the flag was present")
        (example "(Opts on? (Opts parse (list \"-v\") () (list \"-v\")) \"-v\")" "#t")
        (example "(Opts on? (Opts parse (list \"-v\") () ()) \"-v\")" "#f"))
      (self %member? flag (rest (Assoc entry (lit on) opts))))

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
