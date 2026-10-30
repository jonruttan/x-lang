; highlight.x -- Highlight: x-lang source and REPL transcripts as HTML.
;
; The tokens and their classes are (Syntax x)'s, written by Syntax's HTML
; renderer: every byte kept, each classed token in a span whose class is
; Rouge's own (c1 comment, s string, sc character, m number, k keyword, kc
; constant, nc class, nv private, n name, p punctuation), so any Rouge or
; Pygments stylesheet, including the one the documentation site's theme
; ships, styles the output with no CSS of its own.  Lexical, so it renders
; fragments no parser would accept and the author's own layout byte for byte.
;
; What this file adds is the transcript: a REPL session ("> expr" and the
; value on the next line) and the reference's "expr => result" lines, which
; are not programs, with gp prompt, go output and o for the arrow.

(module x/tool/highlight)
(import x/type/str)
(import x/type/class)
(import x/tool/syntax)

(import x/core/doors char->int int+ int- str-byte-len str-byte-ref str-byte-sub)

(def %hl-escape (fn (_ s)
  (Str8 replace ">" "&gt;"
    (Str8 replace "<" "&lt;"
      (Str8 replace "&" "&amp;" s)))))

(def %hl-write-span (fn (_ cls text)
  (display "<span class=\"") (display cls) (display "\">")
  (display (%hl-escape text)) (display "</span>")))

(def %hl-write-source (fn (_ text)
  (let ((n (str-byte-len text)))
    (display (Syntax html text ((Syntax x) spans text) 0 n)))))

; --- Transcripts -------------------------------------------------------------

; The paren depth a line leaves open, counting the grammar's punct spans: a
; paren inside a string, a comment or a character literal opens nothing.
; This tells a transcript's continuation lines from its results: a REPL keeps
; reading while the expression is open.
(def %hl-depth (fn (_ s from d)
  ((fn (self sps d)
     (if (null? sps) d
       (let ((b (char->int (str-byte-ref s (first (first sps))))))
         (self (rest sps) (match ((= b 40) (int+ d 1)) ((= b 41) (int- d 1)) (#t d))))))
   (List filter (fn (_ sp) (eq? (first (rest (rest sp))) (lit punct)))
     ((Syntax x) spans s from (int- (str-byte-len s) from)))
   d)))

(def %hl-prompt? (fn (_ line) (Str8 starts? "> " line)))

; Two spellings, one idea: the generated reference writes "expr => result"
; from (example ...) forms, and docs/spec.md writes "42 -> 42" in its own
; normative notation.  Both split the same way, four bytes of arrow.
(def %hl-arrow-at (fn (_ line)
  (let ((fat (Str8 index-of " => " line)))
    (if (null? fat) (Str8 index-of " -> " line) fat))))

(def %hl-arrow-split (fn (_ line)
  (let ((at (%hl-arrow-at line)))
    (if (null? at) ()
      (pair (str-byte-sub line 0 at)
            (str-byte-sub line (int+ at 4) (int- (str-byte-len line) (int+ at 4))))))))

; Writes one line and returns the paren depth left open at its end, which the
; next line needs: at depth 0 a line is a result, and above it the session is
; still reading the same expression.
(def %hl-write-line (fn (_ line depth)
  (let ((n (str-byte-len line)))
    (let ((parts (%hl-arrow-split line)))
      (match
        ; "> expr": the prompt is Generic.Prompt, the rest is code.
        ((%hl-prompt? line)
          (do (%hl-write-span "gp" (str-byte-sub line 0 2))
              (%hl-write-source (str-byte-sub line 2 (int- n 2)))
              (%hl-depth line 2 0)))
        ; A continuation: the expression above has not closed, so this is
        ; more of it, not the value it returned.
        ((> depth 0)
          (do (%hl-write-source line)
              (%hl-depth line 0 depth)))
        ; "expr => result": both sides are code; only the arrow is not.
        ((not (null? parts))
          (do (%hl-write-source (first parts))
              (%hl-write-span "o" (str-byte-sub line (%hl-arrow-at line) 4))
              (%hl-write-source (rest parts))
              0))
        ; Anything else in a transcript is what the session printed back.
        ((str=? line "") 0)
        (#t (do (%hl-write-span "go" line) 0)))))))

(def %hl-write-lines (fn (self lines depth)
  (unless (null? lines)
    (let ((d (%hl-write-line (first lines) depth)))
      (do (unless (null? (rest lines)) (display "\n"))
          (self (rest lines) d))))))

(def %hl-write-transcript (fn (_ text)
  (%hl-write-lines (Str8 split "\n" text) 0)))

; --- Wrapping ----------------------------------------------------------------

; The container Rouge emits, so the theme's stylesheet finds what it expects.
(def %hl-open (fn (_)
  (display "<div class=\"highlight\"><pre class=\"highlight\"><code>")))

(def %hl-close (fn (_) (display "</code></pre></div>")))

; --- The Highlight class: the API -------------------------------------------

(def-class Highlight ()
  (doc "x-lang source and REPL transcripts as HTML, in Rouge's token classes, from the spans of (Syntax x)."
    (note "Emits Rouge/Pygments token classes, so an existing Rouge stylesheet renders the output. The keywords are lib/x/constructs.x's, read by x/tool/syntax.")
    (note "source and transcript WRITE their result, like x/tool/fmt's printers.")
    (example "(Highlight escape \"a<b\")" "\"a&lt;b\""))
  (static
    (method spans (self (param text STRING "Source text"))
      (doc "Write span markup for source text, WITHOUT the surrounding container."
        (returns ANY "nil (output via display)"))
      (%hl-write-source text))

    (method source (self (param text STRING "Source text"))
      (doc "Write x-lang source as a complete Rouge-style code block."
        (returns ANY "nil (output via display)"))
      (do (%hl-open) (%hl-write-source text) (%hl-close)))

    (method transcript (self (param text STRING "REPL transcript text"))
      (doc "Write a REPL transcript -- \"> expr\" prompts and \"expr => result\" lines -- as a complete code block."
        (returns ANY "nil (output via display)"))
      (do (%hl-open) (%hl-write-transcript text) (%hl-close)))

    (method escape (self (param text STRING "Text to escape"))
      (doc "HTML-escape &, < and > in text."
        (returns STRING "Escaped text"))
      (%hl-escape text))))

(doc (provide x/tool/highlight Highlight)
  (note "The tokens are (Syntax x)'s and the markup Syntax's HTML renderer's; the Highlight class adds the transcript lines and the container.")
  "x-lang source and REPL transcripts as HTML, in Rouge token classes.")
