# PdfText: a PDF's text as a document
# @weight 2

(PdfText runs) answers the runs a page's content stream shows, (PdfText
parse) the headings and paragraphs they spell.  The files are built by the
cases; a font with no /Widths gives every glyph half its size, so a run's
extent can be counted.

## runs

### a run a string: where it starts, its size, its extent, its text; TJ's numbers move the next run; a matrix scales

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pts-pad (fn (_ n) (Str8 pad-left 10 #\0 (Str8 str n))))
  (def %pts-file
    (fn (_ bodies extra)
      ((fn (self l n text rows)
         (match ((null? l)
                  (Str8 append text "xref\n0 " (Str8 str n) "\n0000000000 65535 f \n" rows
                               "trailer\n<</Size " (Str8 str n) " " extra ">>\nstartxref\n"
                               (Str8 str (Str8 length text)) "\n%%EOF\n"))
                (#t (self (rest l) (+ n 1)
                          (Str8 append text (Str8 str n) " 0 obj\n" (first l) "\nendobj\n")
                          (Str8 append rows (%pts-pad (Str8 length text)) " 00000 n \n")))))
       bodies 1 "%PDF-1.4\n" "")))
  (def %pts-stream (fn (_ entries data) (Str8 append "<<" entries "/Length " (Str8 str (Str8 length data)) ">>\nstream\n" data "\nendstream")))
  ; A one-page file: CONTENT its page's content, FONTS the font dictionary's entries, MORE objects from 5 on.
  (def %pts-page
    (fn (_ content fonts more)
      (%pts-file
        (List append
          (list "<</Type/Catalog/Pages 2 0 R>>"
                "<</Type/Pages/Kids[3 0 R]/Count 1>>"
                (Str8 append "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<<" fonts ">>>>>>")
                (%pts-stream "" content))
          more)
        "/Root 1 0 R/Info<</Title(A  title )>>")))
  (def %pts-plain "/F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica/Encoding/WinAnsiEncoding>>/F2<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold/Encoding/WinAnsiEncoding>>")
  (def %pts-runs (fn (_ text) ((fn (_ f) (PdfText runs f (first (Pdf pages f)))) (Pdf open text (Str8 length text)))))
  (%pts-runs (%pts-page "BT /F1 10 Tf 72 700 Td (Hello) Tj [(ab) -500 (c)] TJ 0 -12 Td (x) Tj ET q 2 0 0 2 10 20 cm BT /F2 6 Tf 1 0 0 1 5 5 Tm (yz) Tj ET Q" %pts-plain ())))
```
---
    ((72000 700000 10000 25000 "Hello" 0) (97000 700000 10000 10000 "ab" 0) (112000 700000 10000 5000 "c" 0) (72000 688000 10000 5000 "x" 0) (20000 30000 12000 12000 "yz" 1))

### the spacing parameters: character and word spacing, horizontal scaling, rise; ' and " start a line

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (%pts-runs (%pts-page "BT /F1 10 Tf 12 TL 100 500 Td 1 Tc (ab) Tj (c) Tj 0 Tc 2 Tw (a b) Tj (c) Tj 0 Tw 50 Tz (ab) Tj (c) Tj 100 Tz 3 Ts (r) Tj 0 Ts (n) ' 1 2 (m) \" T* (z) Tj ET" %pts-plain ())))
```
---
    ((100000 500000 10000 12000 "ab" 0) (112000 500000 10000 6000 "c" 0) (118000 500000 10000 17000 "a b" 0) (135000 500000 10000 5000 "c" 0) (140000 500000 10000 5000 "ab" 0) (145000 500000 10000 2500 "c" 0) (147500 503000 10000 5000 "r" 0) (100000 488000 10000 5000 "n" 0) (100000 476000 10000 7000 "m" 0) (100000 464000 10000 7000 "z" 0))

## characters

### /Differences names glyphs; a WinAnsi byte past ASCII; a ligature is its letters

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (List map (fn (_ r) (List ref 4 r))
    (%pts-runs (%pts-page "BT /F1 10 Tf 72 700 Td (a\\001\\002\\003b \\226 \\351) Tj ET"
                          "/F1<</Type/Font/Subtype/Type1/BaseFont/Times-Roman/Encoding<</BaseEncoding/WinAnsiEncoding/Differences[1/fi/eacute 3/Euro]>>>>" ()))))
```
---
    ("afié€b – é")

### a /ToUnicode map: bfchar, a bfrange from a start and from an array, two-byte codes, UTF-16 with a surrogate pair

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (List map (fn (_ r) (List ref 4 r))
    (%pts-runs
      (%pts-page "BT /F1 10 Tf 72 700 Td <000100020003000400050006> Tj <0007> Tj ET"
                 "/F1<</Type/Font/Subtype/Type0/BaseFont/Any/Encoding/Identity-H/DescendantFonts[<</Type/Font/Subtype/CIDFontType2/DW 600>>]/ToUnicode 5 0 R>>"
                 (list (%pts-stream "" "1 begincodespacerange <0000> <FFFF> endcodespacerange\n2 beginbfchar <0001> <0048> <0002> <00E9> endbfchar\n2 beginbfrange <0003> <0004> <0061> <0005> <0006> [<0058> <00660069>] endbfrange\n1 beginbfchar <0007> <D83DDE00> endbfchar"))))))
```
---
    ("HéabXfi" "😀")

## blocks

### a larger line is a heading; lines at the leading are one paragraph, a hyphenated word joined; a wider gap starts the next; a bold font is strong

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pts-doc
    (%pts-page "BT /F1 20 Tf 72 700 Td (Title) Tj ET BT /F1 10 Tf 72 670 Td (First line of the para-) Tj 0 -12 Td (graph goes on here and) Tj 0 -12 Td [(ends) -500 (now.)] TJ 0 -30 Td (A ) Tj /F2 10 Tf (bold) Tj /F1 10 Tf ( word.) Tj ET"
               %pts-plain ()))
  (PdfText parse %pts-doc (Str8 length %pts-doc)))
```
---
    (('heading 1 ("Title")) ('paragraph ("First line of the paragraph goes on here and" ('softbreak) "ends now.")) ('paragraph ("A " ('strong ("bold")) " word.")))

### a line whose first word would have fitted on the one before starts a paragraph; so does an indented line after two; two heading sizes are two levels

```x
(do (import x/codec/pdf) (import x/codec/pdf-text)
  (def %pts-two
    (%pts-page "BT /F1 24 Tf 72 740 Td (Big) Tj /F1 16 Tf 0 -30 Td (Small) Tj /F1 10 Tf 0 -30 Td (A full line of text that reaches the edge) Tj 0 -12 Td (short.) Tj 0 -12 Td (Next paragraph, also reaching the margin.) Tj 0 -12 Td (It continues to the right hand margin too) Tj 20 -12 Td (Indented start of a third, long line) Tj ET"
               %pts-plain ()))
  (PdfText parse %pts-two (Str8 length %pts-two)))
```
---
    (('heading 1 ("Big")) ('heading 2 ("Small")) ('paragraph ("A full line of text that reaches the edge" ('softbreak) "short.")) ('paragraph ("Next paragraph, also reaching the margin." ('softbreak) "It continues to the right hand margin too")) ('paragraph ("Indented start of a third, long line")))

## lists

### items led by a bullet or by numbers are a list: the marker taken off, the first number kept, tight when a line apart

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (def %ptl-back (fn (_ blocks) ((fn (_ r) (PdfText parse (first r) (List ref 2 r))) (PdfWrite bytes blocks))))
  (def %ptl-item (fn (_ . inlines) (list (list (lit paragraph) inlines))))
  (def %ptl-doc
    (list (list (lit paragraph) (list "Before."))
          (list (lit list) #f () #t (list (%ptl-item "one") (%ptl-item "two " (list (lit strong) (list "bold")))))
          (list (lit list) #t 3 #t (list (%ptl-item "three") (%ptl-item "four")))
          (list (lit list) #f () #f (list (%ptl-item "loose") (%ptl-item "apart")))
          (list (lit paragraph) (list "After."))))
  (list (equal? (%ptl-back %ptl-doc) %ptl-doc) (%ptl-back %ptl-doc)))
```
---
    (#t (('paragraph ("Before.")) ('list #f () #t ((('paragraph ("one"))) (('paragraph ("two " ('strong ("bold"))))))) ('list #t 3 #t ((('paragraph ("three"))) (('paragraph ("four"))))) ('list #f () #f ((('paragraph ("loose"))) (('paragraph ("apart"))))) ('paragraph ("After."))))

### an item of several lines is one item, and a list of them stays apart item by item

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (def %ptl-long "word word word word word word word word word word word word word word word word word word word word word word word word")
  (List map
    (fn (_ b) (match ((eq? (first b) (lit list)) (list (List ref 1 b) (List ref 2 b) (List ref 3 b) (List length (List ref 4 b)))) (#t (first b))))
    (%ptl-back (list (list (lit list) #f () #t (list (%ptl-item %ptl-long) (%ptl-item %ptl-long) (%ptl-item "short")))
                     (list (lit list) #t 1 #t (list (%ptl-item %ptl-long) (%ptl-item %ptl-long)))))))
```
---
    ((#f () #t 3) (#t 1 #t 2))

### prose is not a list: a hyphen or a number that a wrapped line begins with, a year, a decimal, a marker with no space, a numbered heading

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (List map first
    (%ptl-back (list (list (lit paragraph) (list "word word word word word word word word word word word word word word word word word word word word wor - and on it goes, then 12. more words follow here"))
                     (list (lit paragraph) (list "1999. A year begins this."))
                     (list (lit paragraph) (list "1.5 times as many."))
                     (list (lit paragraph) (list "-dashed and *starred."))
                     (list (lit heading) 2 (list "1. Introduction"))
                     (list (lit paragraph) (list "- one hyphen item"))))))
```
---
    ('paragraph 'paragraph 'paragraph 'paragraph 'heading 'list)

### a list inside an item is read as items of the one list

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (%ptl-back (list (list (lit list) #f () #t
                     (list (list (list (lit paragraph) (list "outer")) (list (lit list) #f () #t (list (%ptl-item "inner"))))
                           (%ptl-item "next"))))))
```
---
    (('list #f () #f ((('paragraph ("outer"))) (('paragraph ("inner"))) (('paragraph ("next"))))))

## links

### a link written is read back: its destination, its text, the styles in it, the spaces beside it outside

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (def %ptk-back (fn (_ blocks) ((fn (_ r) (PdfText parse (first r) (List ref 2 r))) (PdfWrite bytes blocks))))
  (def %ptk-doc
    (list (list (lit paragraph)
            (list "See " (list (lit link) "https://example.com/a?b=1" () (list "the site")) " and "
                  (list (lit link) "/u (v)\\w" () (list "a " (list (lit strong) (list "bold")) " one")) "."))
          (list (lit paragraph) (list (list (lit link) "one" () (list "first")) " " (list (lit link) "two" () (list "second"))))
          (list (lit list) #f () #t (list (list (list (lit paragraph) (list "item " (list (lit link) "three" () (list "third")))))))))
  (list (equal? (%ptk-back %ptk-doc) %ptk-doc) (%ptk-back %ptk-doc)))
```
---
    (#t (('paragraph ("See " ('link "https://example.com/a?b=1" () ("the site")) " and " ('link "/u (v)\\w" () ("a " ('strong ("bold")) " one")) ".")) ('paragraph (('link "one" () ("first")) " " ('link "two" () ("second")))) ('list #f () #t ((('paragraph ("item " ('link "three" () ("third")))))))))

### a link over a line's end is one link; the links of a second page are their own

```x
(do (import x/codec/pdf-write) (import x/codec/pdf-text)
  (def %ptk-words "word word word word word word word word word word word word word word word word word")
  (def %ptk-para (fn (_ dest) (list (lit paragraph) (list "Then " (list (lit link) dest () (list %ptk-words " " %ptk-words)) " end."))))
  (def %ptk-links
    (fn (self inlines)
      (List flat-map
        (fn (_ x) (match ((str? x) ()) ((eq? (first x) (lit link)) (list (list (List ref 1 x) (List length (List ref 3 x))))) (#t ())))
        inlines)))
  (List map (fn (_ b) (%ptk-links (List ref 1 b)))
    (%ptk-back (List append (list (%ptk-para "first"))
                            (List map (fn (_ k) (list (lit paragraph) (list "filler"))) (List range 0 40))
                            (list (%ptk-para "second"))))))
```
---
    ((("first" 5)) () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () () (("second" 5)))

### the file: a page's /Annots, each a Link with its rectangle over the text and its URI; a page with no link has none

```x
(do (import x/codec/pdf-write) (import x/codec/pdf)
  (def %ptk-open (fn (_ r) (Pdf open (first r) (List ref 2 r))))
  (def %ptk-f (%ptk-open (PdfWrite bytes (list (list (lit paragraph) (list "A " (list (lit link) "https://x.test/" () (list "link")) " here."))))))
  (def %ptk-a (first (rest (Pdf lookup %ptk-f (first (Pdf pages %ptk-f)) "Annots"))))
  (list (List length (rest (Pdf lookup %ptk-f (first (Pdf pages %ptk-f)) "Annots")))
        (Pdf lookup %ptk-f %ptk-a "Subtype") (Pdf lookup %ptk-f %ptk-a "Rect")
        ((fn (_ u) (Str8 sub 0 (List ref 2 u) (List ref 1 u))) (Pdf lookup %ptk-f (Pdf lookup %ptk-f %ptk-a "A") "URI"))
        (null? (Pdf lookup (%ptk-open (PdfWrite bytes (list (list (lit paragraph) (list "none"))))) (first (Pdf pages (%ptk-open (PdfWrite bytes (list (list (lit paragraph) (list "none"))))))) "Annots"))))
```
---
    (1 ('name "Link") ('array ('real "82.395") ('real "706.8") ('real "98.895") ('real "717.8")) "https://x.test/" #t)

## title

### the /Info dictionary's /Title, trimmed

```x
(do (import x/codec/pdf-text)
  (PdfText title %pts-doc (Str8 length %pts-doc)))
```
---
    "A  title"

## the tree

### what parse answers is a sound document

```x
(do (import x/codec/pdf-text) (import x/codec/document)
  (list (Document check (PdfText parse %pts-doc (Str8 length %pts-doc)))
        (Document check (PdfText parse %pts-two (Str8 length %pts-two)))))
```
---
    (() ())
