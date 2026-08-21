; highlight.x -- render x-lang code blocks in markdown as highlighted HTML
;
; A pure filter: markdown in, markdown out, with every ```x and ```x-repl
; fence replaced by the span markup x/tool/highlight emits.  Fences in any
; other language, and naked fences, pass through untouched -- the fence pass
; decided what each block holds, and this tool only believes it.
;
;   sh x.sh --no-pin -q -f tools/dev/highlight.x -- FILE...
;
; ONE file streams bare.  Several stream behind "%%HL-X-PAGE%% <source>"
; sentinel lines (the doc.x batch pattern), so one engine boot serves a
; chunk and tools/dev/highlight-sweep.sh splits the pages back out.
;
; COLLECTS BETWEEN BLOCKS.  Scanning allocates per token and the run would
; otherwise keep every intermediate alive to process exit, which is what made
; an early draft grow until the kernel killed it.  (heap collect) is safe
; here in a way it is not in doc.x: that tool holds a scratch BASE per file
; and cannot collect mid-batch (see tools/dev/doc-sweep.sh), while this one
; owns nothing but strings on the running base.

(do
  (import x/sys/posix)
  (import x/sys/file)
  (import x/tool/highlight)
  (import x/tool/contract)
  (import x/codec/xon)

  (Contract alloc-guard!)

  (def %hl-collect (prim-ref (lit heap) (lit collect)))

  (def %hl-files (Contract argv))
  (when (null? %hl-files)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/dev/highlight.x -- FILE...\n")
        (Sys exit 1)))

  ; The keyword set comes from the construct declarations, so a construct
  ; added there highlights without this tool changing.
  (def %hl-keywords
    (Highlight keywords (first (Xon parse (File read-all "lib/x/constructs.x")))))

  ; --- One file: walk lines, swapping tagged fences for their markup ---
  ;
  ; Line-oriented on purpose. A markdown file is not an s-expression, and the
  ; only structure this needs is which lines sit inside a fence it claimed.
  (def %hl-fence-tag
    (fn (_ line)
      (match
        ((str=? line "```x") "x")
        ((str=? line "```x-repl") "x-repl")
        (#t ()))))

  ; Collect a block's lines until the closing fence, returning
  ; (remaining-lines . block-text).  An unclosed fence takes the rest of the
  ; file rather than erroring: this is a filter, and a malformed page should
  ; still come out the other side.
  (def %hl-take-block
    (fn (self lines acc)
      (match
        ((null? lines) (pair () (Str8 join "\n" (List reverse acc))))
        ((Str8 starts? "```" (first lines))
          (pair (rest lines) (Str8 join "\n" (List reverse acc))))
        (#t (self (rest lines) (pair (first lines) acc))))))

  (def %hl-emit-block
    (fn (_ tag text)
      (if (str=? tag "x-repl")
        (Highlight transcript text %hl-keywords)
        (Highlight source text %hl-keywords))))

  ; Newlines are SEPARATORS here, not terminators, which is the difference
  ; between a filter and a filter that grows a file.  "a\nb\n" splits to
  ; ("a" "b" ""), and terminating each item appends a newline the source
  ; never had -- caught on glossary.md, a page with no x fences at all,
  ; which came back one byte longer.  Separating instead reproduces a
  ; newline-terminated file and an unterminated one alike.
  (def %hl-walk
    (fn (self lines first?)
      (unless (null? lines)
        (let ((tag (%hl-fence-tag (first lines))))
          (if (null? tag)
            (do (unless first? (newline))
                (display (first lines))
                (self (rest lines) #f))
            (let ((taken (%hl-take-block (rest lines) ())))
              (do (unless first? (newline))
                  (%hl-emit-block tag (rest taken))
                  ; One block's worth of scanning garbage, dropped before the
                  ; next: this is what keeps a long page flat instead of
                  ; climbing.
                  (%hl-collect)
                  (self (first taken) #f))))))))

  ; Returns whether the page it wrote ended with a newline, which is what
  ; the sentinel driver below needs to know to keep its markers on lines of
  ; their own without inventing a byte.
  (def %hl-one
    (fn (_ file)
      (let ((text (File read-all file)))
        (do (%hl-walk (Str8 split "\n" text) #t)
            (Str8 ends? "\n" text)))))

  ; --- Drive: bare stream for ONE file, sentinel pages for several ---
  (if (null? (rest %hl-files))
    (%hl-one (first %hl-files))
    (List for-each
      (fn (_ file)
        (do (display "%%HL-X-PAGE%% ") (display file) (newline)
            ; The next sentinel must start a line of its own -- but only add
            ; one when the page did not already end with a newline, or every
            ; page grows by a byte.
            (unless (%hl-one file) (newline))
            (%hl-collect)))
      %hl-files)))
