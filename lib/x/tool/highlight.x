; highlight.x -- Highlight: lexical syntax highlighter for x-lang source.
;
; LEXICAL, and deliberately so. The formatter's token stream is parsed VALUES
; (x/tool/fmt re-prints from them), so highlighting through it would re-lay-out
; every example in the documentation instead of showing what its author wrote
; -- and a REPL transcript ("> (+ 1 2)" and the value it returned) is not a
; parseable program at all. A scanner preserves every byte and copes with both.
;
; Token classes are Rouge's own -- c1 comment, s string, sc character, m
; number, k keyword, kc constant, nc class, nv private, p punctuation, gp
; prompt, go output -- so any Rouge or Pygments stylesheet, including the one
; the documentation site's theme already ships, styles the output with no CSS
; of our own.
;
; The keyword set is NOT written here: it comes from the caller, which reads
; lib/x/constructs.x. A construct added there highlights without touching this
; file.
(import x/type/str)
(import x/type/class)

; HOT-PATH PRIMS, cached, and this file is nothing but hot path: a scanner
; touches every byte of every block it renders. The class doors cost a
; dispatch each (Str8 ref, Char =?) and the ambient arithmetic goes through
; the numeric tower, so the inner loop rides the same prims lib/x/boot/printer.x
; uses -- byte-ref returns a CHAR that IS its code point, so bytes compare with
; eq? against integer literals and never box.
(def %hl-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %hl-byte-len (prim-ref (lit str) (lit byte-len)))
(def %hl-byte-sub (prim-ref (lit str) (lit byte-sub)))
(def %hl-append (prim-ref (lit str) (lit append)))
(def %hl+ (prim-ref (lit int) (lit +)))
(def %hl- (prim-ref (lit int) (lit -)))

; --- HTML escaping -----------------------------------------------------------

; Bytes needing an entity: & < >
(def %hl-esc? (fn (_ b) (or (eq? b 38) (or (eq? b 60) (eq? b 62)))))

(def %hl-esc-entity (fn (_ b)
  (match ((eq? b 38) "&amp;") ((eq? b 60) "&lt;") (#t "&gt;"))))

; Emit whole SAFE RUNS, not bytes -- the printer's pattern, and for its
; reason: the output door is an unbuffered write, so a per-byte emission
; costs a syscall per byte. Source that needs no entity at all (nearly all of
; it) leaves as one substring.
(def %hl-run-end (fn (self s i n)
  (match
    ((>= i n) i)
    ((%hl-esc? (%hl-byte-ref s i)) i)
    (#t (self s (%hl+ i 1) n)))))

(def %hl-esc-loop (fn (self s i n)
  (unless (>= i n)
    (match
      ((%hl-esc? (%hl-byte-ref s i))
        (do (display (%hl-esc-entity (%hl-byte-ref s i)))
            (self s (%hl+ i 1) n)))
      (#t (let ((e (%hl-run-end s (%hl+ i 1) n)))
            (do (display (%hl-byte-sub s i (%hl- e i)))
                (self s e n))))))))

(def %hl-display-escaped (fn (_ text)
  (%hl-esc-loop text 0 (%hl-byte-len text))))

; The string-returning form, for the class door that hands back a value.
(def %hl-escape (fn (_ s)
  (Str8 replace ">" "&gt;"
    (Str8 replace "<" "&lt;"
      (Str8 replace "&" "&amp;" s)))))

; --- Scanning primitives -----------------------------------------------------
;
; Every scanner takes (s i n) and returns the index one past what it found, so
; the driver advances by replacing i with the result. Byte constants, not
; character literals: ; 59, " 34, \ 92, # 35, $ 36, ( 40, ) 41, % 37, - 45,
; newline 10, space 32, tab 9, CR 13, 0-9 48-57, A-Z 65-90.

(def %hl-to-eol (fn (self s i n)
  (match
    ((>= i n) i)
    ((eq? (%hl-byte-ref s i) 10) i)
    (#t (self s (%hl+ i 1) n)))))

; Closing quote, honouring backslash escapes. An unterminated string runs to
; the end of the block rather than erroring: a doc snippet is often a
; fragment, and a highlighter that refuses to render half a line is worse than
; one that colours it optimistically.
(def %hl-string-end (fn (self s i n)
  (match
    ((>= i n) n)
    ((eq? (%hl-byte-ref s i) 92) (self s (%hl+ i 2) n))
    ((eq? (%hl-byte-ref s i) 34) (%hl+ i 1))
    (#t (self s (%hl+ i 1) n)))))

(def %hl-space? (fn (_ b)
  (or (eq? b 32) (or (eq? b 10) (or (eq? b 9) (eq? b 13))))))

(def %hl-delimiter? (fn (_ b)
  (or (%hl-space? b) (or (eq? b 40) (or (eq? b 41) (eq? b 59))))))

(def %hl-atom-end (fn (self s i n)
  (match
    ((>= i n) i)
    ((%hl-delimiter? (%hl-byte-ref s i)) i)
    (#t (self s (%hl+ i 1) n)))))

; --- Classifying an atom -----------------------------------------------------

(def %hl-digit? (fn (_ b) (and (>= b 48) (<= b 57))))

(def %hl-digits? (fn (self text i n)
  (match
    ((>= i n) #t)
    ((%hl-digit? (%hl-byte-ref text i)) (self text (%hl+ i 1) n))
    (#t #f))))

; A number is an optional sign then digits: "-" alone is the subtraction
; operator, not a number, so the sign only counts with a digit behind it.
(def %hl-number? (fn (_ text)
  (let ((n (%hl-byte-len text)))
    (match
      ((eq? n 0) #f)
      ((%hl-digit? (%hl-byte-ref text 0)) (%hl-digits? text 1 n))
      ((and (eq? (%hl-byte-ref text 0) 45) (> n 1))
        (and (%hl-digit? (%hl-byte-ref text 1)) (%hl-digits? text 2 n)))
      (#t #f)))))

(def %hl-member? (fn (self x xs)
  (match
    ((null? xs) #f)
    ((str=? x (first xs)) #t)
    (#t (self x (rest xs))))))

; Rouge's vocabulary, by what the name IS rather than where it sits: a scanner
; has no parse tree to ask about head position, and x-lang's own conventions
; carry the information anyway -- Capitalised names are classes (classes ARE
; namespaces here) and %-prefixed names are private.
(def %hl-atom-class (fn (_ text keywords)
  (let ((n (%hl-byte-len text)))
    (match
      ((eq? n 0) "n")
      ((%hl-member? text keywords) "k")
      ((str=? text "#t") "kc")
      ((str=? text "#f") "kc")
      ((str=? text "nil") "kc")
      ((%hl-number? text) "m")
      ((eq? (%hl-byte-ref text 0) 37) "nv")
      ((and (>= (%hl-byte-ref text 0) 65) (<= (%hl-byte-ref text 0) 90)) "nc")
      (#t "n")))))

; --- The scanner ------------------------------------------------------------

; The character-literal and interpolation branches look two or three bytes
; ahead, which lands past the end on a truncated fragment -- and a snippet in
; the documentation has every right to be truncated. Slicing past the end is
; an error, so every writer clamps.
(def %hl-clamp (fn (_ e n) (if (> e n) n e)))

(def %hl-write-span (fn (_ cls text)
  (do (display "<span class=\"") (display cls) (display "\">")
      (%hl-display-escaped text) (display "</span>"))))

; Each writer WRITES its token and returns where it stopped, the shape
; x/tool/fmt's printers use.
;
; MEASURED, twice, and the first answer was wrong. An early draft built one
; span string per token and joined thousands at the end; streaming replaced
; that and peak memory did NOT improve. The cost was never the strings -- it
; was the per-BYTE scanning going through CLASS DOORS (Str8 ref, Char =?) and
; the numeric tower ((+ i 1)). Riding the cached byte prims instead, the way
; lib/x/boot/printer.x does, cut resident memory about tenfold: 4KB of source
; peaks ~290MB above the boot baseline where it once wanted ~2.5GB, and a 13KB
; module no longer exhausts the machine. Streaming is kept for matching the
; formatter and for not holding a whole block's markup at once.
;
; Nothing is collected mid-run, so cost still accumulates across a process:
; a caller highlighting a whole corpus CHUNKS across processes (see the sweep).
(def %hl-write (fn (_ cls s i e n)
  (let ((end (%hl-clamp e n)))
    (do (%hl-write-span cls (%hl-byte-sub s i (%hl- end i))) end))))

(def %hl-write-atom (fn (_ s i e n keywords)
  (let ((end (%hl-clamp e n)))
    (let ((text (%hl-byte-sub s i (%hl- end i))))
      (do (%hl-write-span (%hl-atom-class text keywords) text) end)))))

; Whitespace carries no class but is still ESCAPED, like every other byte --
; the block is HTML now.
(def %hl-write-raw (fn (_ s i e n)
  (let ((end (%hl-clamp e n)))
    (do (%hl-display-escaped (%hl-byte-sub s i (%hl- end i))) end))))

(def %hl-write-token (fn (_ s i n keywords)
  (let ((c (%hl-byte-ref s i)))
    (match
      ; Comment: to end of line, the newline left for the next pass.
      ((eq? c 59) (%hl-write "c1" s i (%hl-to-eol s i n) n))
      ; String, and $"..." interpolation -- one class: the hole syntax is part
      ; of the literal, and colouring it apart would suggest it escapes the
      ; string, which it does not.
      ((eq? c 34) (%hl-write "s" s i (%hl-string-end s (%hl+ i 1) n) n))
      ((and (eq? c 36) (and (< (%hl+ i 1) n) (eq? (%hl-byte-ref s (%hl+ i 1)) 34)))
        (%hl-write "s" s i (%hl-string-end s (%hl+ i 2) n) n))
      ; Character literal: #\ and the one glyph after it, plus any word behind
      ; that, so #\newline stays one token and #\( does not lose its paren to
      ; the delimiter rule. The +3 is why the clamp exists.
      ((and (eq? c 35) (and (< (%hl+ i 1) n) (eq? (%hl-byte-ref s (%hl+ i 1)) 92)))
        (%hl-write "sc" s i (%hl-atom-end s (%hl-clamp (%hl+ i 3) n) n) n))
      ((or (eq? c 40) (eq? c 41)) (%hl-write "p" s i (%hl+ i 1) n))
      ((%hl-space? c) (%hl-write-raw s i (%hl+ i 1) n))
      (#t (%hl-write-atom s i (%hl-atom-end s (%hl+ i 1) n) n keywords))))))

; THE GUARD. A branch that returned its own start index would recurse without
; consuming, and the process would grow until the kernel killed it. Whether
; any branch can still do that is not something to trust to review:
; non-advancement is a loud error at the one place that can detect it.
(def %hl-scan (fn (self s i n keywords)
  (unless (>= i n)
    (let ((e (%hl-write-token s i n keywords)))
      (if (<= e i)
        (Err raise 'value "highlight: scanner did not advance" ())
        (self s e n keywords))))))

(def %hl-write-source (fn (_ text keywords)
  (%hl-scan text 0 (%hl-byte-len text) keywords)))

; --- Transcripts -------------------------------------------------------------
;
; Two shapes, both common in the documentation and neither a program: the
; tutorial's REPL sessions ("> expr" and the value on the next line) and the
; generated reference's "(expr) => result" from (example ...) forms.

(def %hl-prompt? (fn (_ line) (Str8 starts? "> " line)))

; Two spellings, one idea: the generated reference writes "expr => result"
; from (example ...) forms, and docs/spec.md writes "42 -> 42" in its own
; normative notation. Both split the same way -- four bytes of arrow.
(def %hl-arrow-at (fn (_ line)
  (let ((fat (Str8 index-of " => " line)))
    (if (null? fat) (Str8 index-of " -> " line) fat))))

(def %hl-arrow-split (fn (_ line)
  (let ((at (%hl-arrow-at line)))
    (if (null? at) ()
      (pair (%hl-byte-sub line 0 at)
            (%hl-byte-sub line (%hl+ at 4) (%hl- (%hl-byte-len line) (%hl+ at 4))))))))

(def %hl-write-line (fn (_ line keywords)
  (let ((parts (%hl-arrow-split line)))
    (match
      ; "> expr" -- the prompt is Generic.Prompt, the rest is code.
      ((%hl-prompt? line)
        (do (%hl-write-span "gp" (%hl-byte-sub line 0 2))
            (%hl-write-source (%hl-byte-sub line 2 (%hl- (%hl-byte-len line) 2)) keywords)))
      ; "expr => result" -- both sides are code; only the arrow is not.
      ((not (null? parts))
        (do (%hl-write-source (first parts) keywords)
            (%hl-write-span "o" (%hl-byte-sub line (%hl-arrow-at line) 4))
            (%hl-write-source (rest parts) keywords)))
      ; Anything else in a transcript is what the session printed back.
      ((str=? line "") ())
      (#t (%hl-write-span "go" line))))))

(def %hl-write-lines (fn (self lines keywords)
  (unless (null? lines)
    (do (%hl-write-line (first lines) keywords)
        (unless (null? (rest lines)) (display "\n"))
        (self (rest lines) keywords)))))

(def %hl-write-transcript (fn (_ text keywords)
  (%hl-write-lines (Str8 split "\n" text) keywords)))

; --- Wrapping ----------------------------------------------------------------

; The container Rouge emits, so the theme's stylesheet finds what it expects.
(def %hl-open (fn (_)
  (display "<div class=\"highlight\"><pre class=\"highlight\"><code>")))

(def %hl-close (fn (_) (display "</code></pre></div>")))

; --- The Highlight class: the API -------------------------------------------

(def-class Highlight ()
  (doc "Lexical syntax highlighter for x-lang source and REPL transcripts."
    (note "Emits Rouge/Pygments token classes, so an existing Rouge stylesheet renders the output. The keyword set is supplied by the caller from lib/x/constructs.x -- this class hardcodes no part of the language's vocabulary.")
    (note "source and transcript WRITE their result, like x/tool/fmt's printers. The scanner rides cached byte prims rather than the class doors, which is what makes it affordable -- 4KB of source costs about 290MB of resident memory above the boot baseline. Nothing is collected mid-run, so a caller highlighting a whole corpus chunks its work across processes.")
    (example "(Highlight escape \"a<b\")" "\"a&lt;b\""))
  (static
    (method keywords (self (param constructs LIST "Construct declarations (from XEON)"))
      (doc "The construct names, as strings, for use as the keyword set."
        (returns LIST "Construct names as strings"))
      (List map (fn (_ entry) (Str8 str (first entry))) constructs))

    (method spans (self (param text STR "Source text")
                        (param keywords LIST "Keyword names as strings"))
      (doc "Write span markup for source text, WITHOUT the surrounding container."
        (returns ANY "nil (output via display)"))
      (%hl-write-source text keywords))

    (method source (self (param text STR "Source text")
                         (param keywords LIST "Keyword names as strings"))
      (doc "Write x-lang source as a complete Rouge-shaped code block."
        (returns ANY "nil (output via display)"))
      (do (%hl-open) (%hl-write-source text keywords) (%hl-close)))

    (method transcript (self (param text STR "REPL transcript text")
                             (param keywords LIST "Keyword names as strings"))
      (doc "Write a REPL transcript -- \"> expr\" prompts and \"expr => result\" lines -- as a complete code block."
        (returns ANY "nil (output via display)"))
      (do (%hl-open) (%hl-write-transcript text keywords) (%hl-close)))

    (method escape (self (param text STR "Text to escape"))
      (doc "HTML-escape &, < and > in text."
        (returns STR "Escaped text"))
      (%hl-escape text))))

(doc (provide x/tool/highlight Highlight)
  (note "Scanning is %-private; the Highlight class is the API. The scanner is lexical, so it renders fragments and transcripts that no parser would accept, and preserves the author's own layout byte for byte.")
  "Lexical syntax highlighter for x-lang, emitting Rouge token classes.")
