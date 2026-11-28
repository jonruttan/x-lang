# PdfWrite: a document as a PDF file
# @weight 2

(PdfWrite bytes) sets a document tree on pages and answers a PDF file.  The
cases read the file back with x/codec/pdf and x/codec/pdf-text: its
objects, where its runs are placed, and the document its text spells.

## the file

### a header, one page for an empty document, five fonts with their widths, the title

```x
(do (import x/codec/pdf-write) (import x/codec/pdf)
  (def %pws-open (fn (_ r) (Pdf open (first r) (List ref 2 r))))
  (def %pws-f (%pws-open (PdfWrite bytes () "A (title) – é")))
  (def %pws-fonts (Pdf lookup %pws-f (Pdf lookup %pws-f (first (Pdf pages %pws-f)) "Resources") "Font"))
  (list (Pdf version %pws-f) (List length (Pdf pages %pws-f))
        (List map (fn (_ k) (first (rest (Pdf lookup %pws-f (Pdf lookup %pws-f %pws-fonts k) "BaseFont")))) (list "F0" "F1" "F2" "F3" "F4"))
        (List take 4 (rest (Pdf lookup %pws-f (Pdf lookup %pws-f %pws-fonts "F1") "Widths")))
        (List ref 2 (Pdf lookup %pws-f (Pdf lookup %pws-f (Pdf trailer %pws-f) "Info") "Title"))))
```
---
    ("1.4" 1 ("Helvetica" "Helvetica-Bold" "Helvetica-Oblique" "Helvetica-BoldOblique" "Courier") (278 333 474 556) 13)

### a page's content: a line a text object, a font named when it changes, a space in the font before it

```x
(do (import x/codec/pdf-write) (import x/codec/pdf)
  (def %pws-content
    (fn (_ blocks)
      ((fn (_ f) ((fn (_ r) (Str8 sub 0 (List ref 2 r) (first r))) (Pdf data f (Pdf lookup f (first (Pdf pages f)) "Contents"))))
       (%pws-open (PdfWrite bytes blocks)))))
  (%pws-content (list (list (lit heading) 2 (list "Head"))
                      (list (lit paragraph) (list "a (b) " (list (lit strong) (list "c")) " d\\e " (list (lit emph) (list "f")) (list (lit code) "g"))))))
```
---
    "BT 72 704 Td /F1 16 Tf (Head) Tj ET\nBT 72 684.2 Td /F0 11 Tf (a \\(b\\) ) Tj /F1 11 Tf (c ) Tj /F0 11 Tf (d\\\\e ) Tj /F2 11 Tf (f) Tj /F4 11 Tf (g) Tj ET\n"

## setting

### a paragraph breaks at spaces to the page's width; a quote and a list item are set in, a marker before the item; a rule

```x
(do (import x/codec/pdf-write) (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pws-runs (fn (_ blocks) ((fn (_ f) (PdfText runs f (first (Pdf pages f)))) (%pws-open (PdfWrite bytes blocks)))))
  (def %pws-long "word word word word word word word word word word word word word word word word word word word word word word word")
  (list (List map (fn (_ r) (list (first r) (List ref 1 r) (List ref 3 r)))
          (%pws-runs (list (list (lit paragraph) (list %pws-long))
                           (list (lit block-quote) (list (list (lit paragraph) (list "quoted"))))
                           (list (lit list) #t 3 #t (list (list (list (lit paragraph) (list "item")))))
                           (list (lit list) #f () #f (list (list (list (lit paragraph) (list "loose"))))))))
        (%pws-content (list (list (lit thematic-break))))))
```
---
    (((72000 709000 454157) (72000 695000 158312) (90000 674000 33638) (72000 653000 9174) (90000 653000 20779) (72000 632000 3850) (90000 632000 26290)) "0.5 w 72 713 m 540 713 l S\n")

### a hard break ends a line; a code block keeps its lines, in Courier, a long one cut; a heading's size is its level's

```x
(do (import x/codec/pdf-write) (import x/codec/pdf) (import x/codec/pdf-text)
  (List map (fn (_ r) (list (first r) (List ref 1 r) (List ref 2 r) (List ref 4 r) (List ref 5 r)))
    (%pws-runs (list (list (lit heading) 1 (list "One"))
                     (list (lit heading) 3 (list "Three"))
                     (list (lit paragraph) (list "a" (list (lit hardbreak)) "b" (list (lit softbreak)) "c"))
                     (list (lit code-block) "" "x = 1\n  y\n")))))
```
---
    ((72000 700000 20000 "One" 1) (72000 668000 14000 "Three" 1) (72000 649300 11000 "a" 0) (72000 635300 11000 "b c" 0) (72000 616300 9000 "x = 1" 4) (72000 605300 9000 "  y" 4))

### a page that is full is followed by another

```x
(do (import x/codec/pdf-write) (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pws-many (%pws-open (PdfWrite bytes (List map (fn (_ n) (list (lit paragraph) (list (Str8 str n)))) (List range 0 70)))))
  (list (List length (Pdf pages %pws-many))
        (List map (fn (_ p) ((fn (_ rs) (list (List length rs) (List ref 4 (first rs)) (List ref 1 (first rs)) (List ref 1 (List last rs)))) (PdfText runs %pws-many p)))
                  (Pdf pages %pws-many))))
```
---
    (3 ((31 "0" 709000 79000) (31 "31" 709000 79000) (8 "62" 709000 562000)))

## tables

### a table is a grid: columns as wide as their widest cell, a cell aligned as its column, a header row bold with a heavier rule under it

```x
(do (import x/codec/pdf-write) (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pws-table (list (lit table) #t (list () (lit right)) (list (list (list "A") (list "Right")) (list (list "x") (list "10")) (list (list "yy") (list "5")))))
  (list (List map (fn (_ r) (list (first r) (List ref 1 r) (List ref 4 r) (List ref 5 r))) (%pws-runs (list %pws-table)))
        (List take 3 (Str8 split "\n" (%pws-content (list %pws-table))))))
```
---
    (((76000 708200 "A" 1) (95000 708200 "Right" 1) (76000 691200 "x" 0) (110873 691200 "10" 0) (76000 674200 "yy" 0) (116989 674200 "5" 0)) ("BT 76 708.2 Td /F1 11 Tf (A) Tj ET" "BT 95 708.2 Td /F1 11 Tf (Right) Tj ET" "0.5 w 72 720 m 127.105 720 l S"))

### a table too wide for the page shares its width, a long cell broken to its column; a row that does not fit begins the next page

```x
(do (import x/codec/pdf-write) (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pws-cell (Str8 join " " (List map (fn (_ n) "words") (List range 0 30))))
  (def %pws-wide (%pws-runs (list (list (lit table) #f () (list (list (list "n") (list %pws-cell) (list %pws-cell)))))))
  (def %pws-tall (%pws-open (PdfWrite bytes (list (list (lit table) #f () (List map (fn (_ n) (list (list (Str8 str n)))) (List range 0 50)))))))
  (list (List length %pws-wide)
        (List fold (fn (_ m r) (match ((int< m (int+ (first r) (List ref 3 r))) (int+ (first r) (List ref 3 r))) (#t m))) 0 %pws-wide)
        (List map (fn (_ p) ((fn (_ rs) (list (List length rs) (List ref 4 (first rs)))) (PdfText runs %pws-tall p))) (Pdf pages %pws-tall))))
```
---
    (11 508370 ((38 "0") (12 "38")))

## characters

### WinAnsi's characters are their bytes, a character outside it a question mark; a link is read back, an image is its alternative text, raw HTML nothing

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (def %pws-back (fn (_ blocks) ((fn (_ r) (PdfText parse (first r) (List ref 2 r))) (PdfWrite bytes blocks))))
  (%pws-back (list (list (lit paragraph) (list "café “q” – € • 日本 " (list (lit link) "/u" () (list "link")) " " (list (lit image) "/i" () (list "alt")) (list (lit html-inline) "<b>") "."))
                   (list (lit html-block) "<div>x</div>"))))
```
---
    (('paragraph ("café “q” – € • ?? " ('link "/u" () ("link")) " alt.")))

## read back

### Markdown written and read: headings by level, a paragraph's styles, and the tree is sound

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text) (import x/codec/markdown) (import x/codec/document)
  (def %pws-md (%pws-back (Markdown parse "# Title\n\nA paragraph with *emphasis*, **strong** text and `code`.\n\n## Section\n\nSecond paragraph.\n")))
  (list %pws-md (Document check %pws-md)))
```
---
    ((('heading 1 ("Title")) ('paragraph ("A paragraph with " ('emph ("emphasis")) ", " ('strong ("strong")) " text and " ('code "code") ".")) ('heading 2 ("Section")) ('paragraph ("Second paragraph."))) ())
