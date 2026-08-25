; fmt.x -- x-lang comment-preserving formatter (entry script)
;
; A pure filter: format files to stdout.
;   sh x.sh --no-pin -q -f tools/dev/fmt.x -- [--lang LANG] FILE...
; ONE file streams bare (byte-exact: fmt-x writes it back verbatim).
; Several files stream behind "%%FMT-X-PAGE%% <source>" sentinel lines
; (#307, the doc.x batch pattern): one engine boot serves the chunk,
; and tools/dev/fmt-sweep.sh splits the pages back out.  Each file
; still gets a FRESH scratch base -- zero drift between files.
; In-place and check modes are launch glue in the sweep script: there
; is no stdin data channel under x.sh -f (the pipe carries the
; script), so inputs are read by path -- which also retires the old
; wrapper's awk string-escape hack.
;
; Data-driven: construct declarations (lib/x/constructs.x, plus the
; language-specific table when --lang or the file's path names one) tell
; the formatter how each form nests.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

(do
  (import x/tool/fmt)
  (import x/codec/xon)
  (import x/tool/contract)

  (Contract alloc-guard!)

  ; --- args: [--lang LANG] FILE... ---
  (def %argv (Contract argv))
  (def %lang
    (if (and (pair? %argv) (str=? (first %argv) "--lang"))
      (if (pair? (rest %argv)) (first (rest %argv)) ()) ()))
  (def %fmt-files
    (match
      ((null? %lang) %argv)
      (#t (rest (rest %argv)))))
  (when (null? %fmt-files)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/dev/fmt.x -- [--lang LANG] FILE...\n")
        (Sys exit 1)))
  (List for-each
    (fn (_ f)
      (unless (File exists? f)
        (do (%stderr (Str8 append "Error: " (Str8 append f " not found\n")))
            (Sys exit 1))))
    %fmt-files)

  ; Auto-detect language from the file path (the old wrapper's case table)
  (def %lang-of
    (fn (_ path)
      (match
        ((Str8 includes? "/lang/r5rs/" path) "r5rs")
        ((Str8 includes? "/lang/r7rs/" path) "r7rs")
        ((Str8 includes? "/lang/krn/" path) "krn")
        ((Str8 includes? "/lang/ash/" path) "ash")
        ((Str8 includes? "/lang/sweet/" path) "sweet")
        ((Str8 includes? "/lang/sl/" path) "sl")
        (#t ()))))
  ; --- Load construct declarations (parsed, not evaluated) ---
  (def %parse-one
    (fn (_ path) (first (Xon parse (File read-all path)))))
  (def %constructs (%parse-one "lib/x/constructs.x"))
  ; One built table per LANG, cached across the batch (a lib sweep is
  ; one lang -- nil -- so this is one build).  Key "" = no lang.
  (def %table-cache (pair () ()))
  (def %table-for
    (fn (_ lang)
      (def key (if (null? lang) "" lang))
      (def hit (%find (fn (_ e) (str=? key (first e)))
                      (first %table-cache)))
      (if (not (null? hit)) (rest hit)
        (let ((lc (if (null? lang) ()
                    (let ((p (Str8 append "lang/"
                               (Str8 append lang "/lib/constructs.x"))))
                      (if (File exists? p) (%parse-one p) ())))))
          (let ((table (Fmt build-table
                         (if (null? lc) %constructs
                           (%append %constructs lc)))))
            (do (%set-first! %table-cache
                  (pair (pair key table) (first %table-cache)))
                table))))))

  ; Reader that keeps the comment text as a token
  (def %fmt-comment-reader (fn (_ . args)
    (list '%comment (%buffer-token (first args)))))

  ; Find a type by NAME in a scratch base's registry (fresh string via
  ; the reflect walk), not by shape heuristics.
  (def %find-type (fn (_ entries name)
    (let ((hit (%find (fn (_ e)
                        (str=? (%reflect-sym->str (%reflect-type-name-atom (rest e)))
                               name))
                      entries)))
      (when (null? hit)
        (Err raise 'state (Str8 append "fmt: no such type in the fresh base's registry: " name) ()))
      (rest hit))))

  ; --- Boot-constrained set (#307) ---
  ;
  ; Files whose TEXT the boot reader consumes before lit-reader.x arms
  ; the quote family must spell the mechanism -- (lit x) -- because 'x
  ; does not exist for them yet; folding their spellings to sugar makes
  ; an unbootable tree.  The set derives MECHANICALLY from
  ; lib/x-core.x's include chain up to AND INCLUDING the reader files,
  ; plus the TRANSITIVE (import ...) pulls of those files (the syntax
  ; audit's rule: the boot-constrained set includes transitive mid-boot
  ; imports).  Everything later -- lib tail, dialects, apps, tools --
  ; gets the encouraged sugar (docs/syntax.md).
  ; Scanning parses with the RUNNING base, never a scratch one: symbols
  ; intern PER-BASE, so heads read in a foreign base would never be eq?
  ; to 'include / 'import here (the cross-base trap).
  ; The whole derivation lives in ONE closure (helpers before users
  ; inside it); %boot-file? is the only name the driver needs.
  (def %boot-file?
    ((fn (_)
       (def %parse-file (fn (_ path)
         (Xon parse (File read-all path))))
       (def %inc-head? (fn (_ h)
         (if (eq? h 'include) #t
           (if (eq? h 'include-once) #t (eq? h 'require-once)))))
       (def %import-head? (fn (_ h)
         (if (eq? h 'import) #t
           (if (eq? h 'import-once) #t
             (if (eq? h 'import-version) #t (eq? h 'import-version-once))))))
       ; Module symbol -> repo-relative lib path.
       (def %module->path (fn (_ sym)
         (Str8 append "lib/" (Str8 append (%cvt sym %string) ".x"))))
       ; Imports of one parsed file's top-level forms, as paths.
       (def %file-imports (fn (_ forms)
         (List filter (fn (_ p) (File exists? p))
           (List map (fn (_ f) (%module->path (first (rest f))))
             (List filter
               (fn (_ f)
                 (if (pair? f)
                   (if (%import-head? (first f))
                     (if (pair? (rest f)) (symbol? (first (rest f))) #f)
                     #f)
                   #f))
               forms)))))
       ; x-core's include chain, in order, cut after lit-reader.x.
       (def %boot-includes (fn (_ forms)
         (def go (fn (self fs acc)
           (if (null? fs) (%reverse acc)
             (let ((f (first fs)))
               (if (if (pair? f)
                     (if (%inc-head? (first f))
                       (if (pair? (rest f)) (str? (first (rest f))) #f)
                       #f)
                     #f)
                 (let ((p (first (rest f))))
                   (if (Str8 ends? "reader/lit-reader.x" p)
                     (%reverse (pair p acc))
                     (self (rest fs) (pair p acc))))
                 (self (rest fs) acc))))))
         (go forms ())))
       ; The full constrained set: seeds + transitive imports, a worklist.
       (def %seeds (pair "lib/x-core.x"
                     (%boot-includes (%parse-file "lib/x-core.x"))))
       (def %grow (fn (self work seen)
         (if (null? work) seen
           (let ((p (first work)))
             (if (not (null? (%find (fn (_ s) (str=? s p)) seen)))
               (self (rest work) seen)
               (self (%append (rest work)
                       (if (Str8 starts? "lib/" p)
                         (%file-imports (%parse-file p)) ()))
                     (pair p seen)))))))
       (def %the-set (%grow %seeds ()))
       ; A file is boot-constrained if a set entry is a SUFFIX of its
       ; path (absolute invocations still match their relative row).
       (fn (_ path)
         (not (null? (%find (fn (_ s)
                              (if (str=? s path) #t (Str8 ends? s path)))
                            %the-set)))))
     ()))

  ; --- Format ONE file: fresh base, patch COMMENT, tokenize, format ---
  ;
  ; A FRESH base PER FILE so the patch happens before the base's first
  ; read (the reader-macro boot-time-only rule) and no state drifts
  ; between batch files; tokenizing rides (tok read-str) with this base
  ; while the script itself keeps running on the booted one.
  ; Navigation is CONTRACT-DRIVEN (#39): the old hand-rolled walk
  ; hardcoded "type-struct has 7 elements, io is the 7th" and a
  ; shape-heuristic COMMENT probe -- both bit-rotted against the layout
  ; and segfaulted. Everything below rides engine/tools/contract/base-paths.x
  ; rows through the reflect/type doors, so a layout change moves these
  ; accessors automatically (or fails the check-base-paths gate loudly).
  (def %fmt-one
    (fn (_ file)
      ; The RAW base: this tool walks the spine directly (%reflect-step)
      ; and hands the base to tokenizer doors, so it holds the raw member.
      (def %fmt-base ((Base make) raw))
      ; The fresh base's type registry: descriptor row `type-alist`,
      ; walked FROM %fmt-base (reflect's own cell accessor is bound to
      ; the running base). Entries are (handle . type).
      (def %fmt-registry
        (first (%reflect-step %fmt-base (%reflect-path 'type-alist %base-paths))))
      ; Push the keeping reader through the blessed door (path-driven cell).
      (%type-push-read (%find-type %fmt-registry "COMMENT") %fmt-comment-reader)
      ; Same treatment for $"..." literals: keep them as their source
      ; text, so formatting cannot expand the sugar away -- see
      ; (Xon arm-source!).
      (Xon arm-source! %fmt-base)
      ; Arm the quote family (' ` , ,@) on the scratch base (#307): a
      ; BARE base tokenizes 'x as a quote-bearing symbol (stable only
      ; by accident) and '(1 2) as a bare ' symbol beside a list --
      ; which the printer then CORRUPTED to "' (1 2)".  The handlers
      ; are lit-reader/quasi-reader's own provided ones, chained onto
      ; the scratch base's current cells the way arm-source! chains.
      (def %type-push-analyse (prim-ref 'type 'push-analyse))
      (def %type-analyse-cell (prim-ref 'type 'analyse-cell))
      (def %type-read-cell (prim-ref 'type 'read-cell))
      (def %type-push-delimit (prim-ref 'type 'push-delimit))
      (def %sym-t (%find-type %fmt-registry "SYMBOL"))
      (%type-push-analyse %sym-t
        (pair %lit-analyse (pair %quasi-analyse (pair %unquote-analyse
          (first (%type-analyse-cell %sym-t))))))
      (%type-push-read %sym-t
        (pair %lit-read (pair %quasi-read (pair %unquote-read
          (first (%type-read-cell %sym-t))))))
      (%type-push-delimit %sym-t %macro-delimit)
      ; Boot-constrained files keep their (lit ...) spellings; everything
      ; else folds to the encouraged sugar.
      (Fmt fold-sugar! (not (%boot-file? file)))
      (def %the-lang (if (null? %lang) (%lang-of file) %lang))
      (def %tokens (Xon parse (File read-all file) %fmt-base))
      (Fmt tokens %tokens (%table-for %the-lang))))

  ; --- Drive: bare stream for ONE file, sentinel pages for several ---
  (if (null? (rest %fmt-files))
    (%fmt-one (first %fmt-files))
    (List for-each
      (fn (_ file)
        (do (display "%%FMT-X-PAGE%% ") (display file) (newline)
            (%fmt-one file)))
      %fmt-files)))
