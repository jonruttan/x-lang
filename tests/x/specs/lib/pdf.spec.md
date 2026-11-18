# Pdf: a PDF file's objects, streams and pages
# @weight 2

(Pdf read) answers the objects a span of bytes spells; (Pdf open) reads a
file's cross-reference, tables and streams, and (Pdf object), (Pdf lookup),
(Pdf pages) and (Pdf data) answer from it.  The files here are built by the
cases, so every offset in them is counted, not written by hand.

## syntax

### numbers: an integer, a sign, a real as it is written; a word that is no number is an operator

```x
(do (import x/codec/pdf)
  (def %pdf-spec-read (fn (_ s) (Pdf read (Str8 append s " ") 0 (+ (Str8 length s) 1))))
  (%pdf-spec-read "1 -2 +3 4.5 -.5 6. 1.2.3 0 R true false null"))
```
---
    (1 -2 3 ('real "4.5") ('real "-.5") ('real "6.") ('op "1.2.3") 0 ('op "R") #t #f ())

### strings: escapes, an octal byte, nested parentheses, a line continued; hexadecimal with white space and a last digit alone

```x
(do (import x/codec/pdf)
  (%pdf-spec-read "(a\\nb\\050c\\)) (nested (parens) kept) (line\\\ncontinued) () <48 65 6c6C6f> <7> <>"))
```
---
    (('string "a\nb(c)" 6) ('string "nested (parens) kept" 20) ('string "linecontinued" 13) ('string "" 0) ('string "Hello" 5) ('string "p" 1) ('string "" 0))

### a string's bytes past a NUL are kept, its length beside it

```x
(do (import x/codec/pdf) (import x/codec/bytes)
  (def %pdf-spec-nul (Pdf read (first (Bytes of-hex "2861006229203c3600363e20")) 0 12))
  (list (List map (fn (_ s) (List ref 2 s)) %pdf-spec-nul)
        (Bytes hex (list (List ref 1 (first %pdf-spec-nul)) 0 3))
        (Bytes hex (list (List ref 1 (List ref 1 %pdf-spec-nul)) 0 1))))
```
---
    ((3 1) "610062" "66")

### names: #XX is a byte, a solidus alone the empty name

```x
(do (import x/codec/pdf)
  (%pdf-spec-read "/Name /A#20B#2F /"))
```
---
    (('name "Name") ('name "A B/") ('name ""))

### arrays, dictionaries and references nest; a comment runs to its line's end

```x
(do (import x/codec/pdf)
  (%pdf-spec-read "<</A [1 2 0 R <</B null>>] /C true>> 3 0 R % a comment (\n[]<<>>"))
```
---
    (('dict ("A" 'array 1 ('ref 2 0) ('dict ("B"))) ("C" . #t)) ('ref 3 0) ('array) ('dict))

### a content stream: operands, then the operator

```x
(do (import x/codec/pdf)
  (%pdf-spec-read "q 1 0 0 1 72 720 cm BT /F1 12 Tf [(A) -120 (B)] TJ T* (C) ' ET Q"))
```
---
    (('op "q") 1 0 0 1 72 720 ('op "cm") ('op "BT") ('name "F1") 12 ('op "Tf") ('array ('string "A" 1) -120 ('string "B" 1)) ('op "TJ") ('op "T*") ('string "C" 1) ('op "'") ('op "ET") ('op "Q"))

## a file with a cross-reference table

### the header's version, the trailer, an object by number; a number the table has free or does not hold is nil

```x
(do (import x/codec/pdf)
  (def %pdf-spec-pad (fn (_ n) (Str8 pad-left 10 #\0 (Str8 str n))))
  (def %pdf-spec-file
    (fn (_ bodies extra)
      ((fn (self l n text rows)
         (match ((null? l)
                  (Str8 append text "xref\n0 " (Str8 str n) "\n0000000000 65535 f \n" rows
                               "trailer\n<</Size " (Str8 str n) " " extra ">>\nstartxref\n"
                               (Str8 str (Str8 length text)) "\n%%EOF\n"))
                (#t (self (rest l) (+ n 1)
                          (Str8 append text (Str8 str n) " 0 obj\n" (first l) "\nendobj\n")
                          (Str8 append rows (%pdf-spec-pad (Str8 length text)) " 00000 n \n")))))
       bodies 1 "%PDF-1.4\n" "")))
  (def %pdf-spec-open (fn (_ text) (Pdf open text (Str8 length text))))
  (def %pdf-spec-text (fn (_ r) (Str8 sub (List ref 1 r) (List ref 2 r) (first r))))
  (def %pdf-spec-plain
    (%pdf-spec-file
      (list "<</Type/Catalog/Pages 2 0 R>>"
            "<</Type/Pages/Kids[3 0 R 4 0 R]/Count 2/MediaBox[0 0 612 792]/Resources<</Font<<>>>>>>"
            "<</Type/Page/Parent 2 0 R/Contents 6 0 R>>"
            "<</Type/Pages/Parent 2 0 R/Kids[5 0 R]/Count 1/MediaBox[0 0 100 200]>>"
            "<</Type/Page/Parent 4 0 R/Rotate 90>>"
            "<</Length 7 0 R>>\nstream\nBT (Hi) Tj ET\nendstream"
            "13"
            "<</Length 99>>\r\nstream\r\nwrong length\r\nendstream"
            "<</Note (the word stream in a string)/Length 2>>\nstream\nok\nendstream")
      "/Root 1 0 R"))
  (def %pdf-spec-f (%pdf-spec-open %pdf-spec-plain))
  (list (Pdf version %pdf-spec-f) (Pdf trailer %pdf-spec-f) (Pdf object %pdf-spec-f 1) (Pdf object %pdf-spec-f 7)
        (Pdf object %pdf-spec-f 0) (Pdf object %pdf-spec-f 99)))
```
---
    ("1.4" ('dict ("Size" . 10) ("Root" 'ref 1 0)) ('dict ("Type" 'name "Catalog") ("Pages" 'ref 2 0)) 13 () ())

### lookup resolves the dictionary and the value; a key that is not there is nil

```x
(do (import x/codec/pdf)
  (list (Pdf lookup %pdf-spec-f (Pdf trailer %pdf-spec-f) "Root")
        (Pdf lookup %pdf-spec-f (list (lit ref) 6 0) "Length")
        (Pdf lookup %pdf-spec-f (list (lit ref) 1 0) "Nope")
        (Pdf lookup %pdf-spec-f 13 "Length")))
```
---
    (('dict ("Type" 'name "Catalog") ("Pages" 'ref 2 0)) 13 () ())

### pages in order through nested nodes, each with what the nodes above it give: the nearest MediaBox, Resources from two up; its own Rotate

```x
(do (import x/codec/pdf)
  (def %pdf-spec-pages (Pdf pages %pdf-spec-f))
  (List map
    (fn (_ p) (List map (fn (_ k) (Pdf lookup %pdf-spec-f p k)) (list "Type" "MediaBox" "Resources" "Rotate")))
    %pdf-spec-pages))
```
---
    ((('name "Page") ('array 0 0 612 792) ('dict ("Font" 'dict)) ()) (('name "Page") ('array 0 0 100 200) ('dict ("Font" 'dict)) 90))

### a stream's bytes: a length that is a reference; a wrong length, found by endstream; the word stream in the dictionary

```x
(do (import x/codec/pdf)
  (List map (fn (_ n) (%pdf-spec-text (Pdf data %pdf-spec-f (Pdf object %pdf-spec-f n)))) (list 6 8 9)))
```
---
    ("BT (Hi) Tj ET" "wrong length" "ok")

### a later section replaces an object, and /Prev reaches the rest

```x
(do (import x/codec/pdf)
  (def %pdf-spec-old (Str8 index-of "xref\n0 " %pdf-spec-plain))
  (def %pdf-spec-new (Str8 append %pdf-spec-plain "5 0 obj\n<</Type/Page/Parent 4 0 R/Rotate 180>>\nendobj\n"))
  (def %pdf-spec-g
    (%pdf-spec-open
      (Str8 append %pdf-spec-new "xref\n5 1\n" (%pdf-spec-pad (Str8 length %pdf-spec-plain)) " 00000 n \n"
                   "trailer\n<</Size 10/Root 1 0 R/Prev " (Str8 str %pdf-spec-old) ">>\nstartxref\n"
                   (Str8 str (Str8 length %pdf-spec-new)) "\n%%EOF\n")))
  (list (Pdf lookup %pdf-spec-g (list (lit ref) 5 0) "Rotate") (Pdf object %pdf-spec-g 7)
        (List length (Pdf pages %pdf-spec-g))))
```
---
    (180 13 2)

## filters

### ASCIIHexDecode, ASCII85Decode, FlateDecode after ASCIIHexDecode, and the PNG Up predictor

```x
(do (import x/codec/pdf) (import x/codec/deflate) (import x/codec/bytes)
  (def %pdf-spec-hexed
    (fn (_ s n) ((fn (_ c) (Bytes hex (list (first c) 0 (first (rest c))))) (Deflate zlib s 0 n))))
  (def %pdf-spec-stream (fn (_ entries data) (Str8 append "<<" entries "/Length " (Str8 str (Str8 length data)) ">>\nstream\n" data "\nendstream")))
  (def %pdf-spec-h
    (%pdf-spec-open
      (%pdf-spec-file
        (list (%pdf-spec-stream "/Filter/ASCIIHexDecode" "48 65 6C6c\n6F7>")
              (%pdf-spec-stream "/Filter/ASCII85Decode" "87cU RDZ~>")
              (%pdf-spec-stream "/Filter[/ASCIIHexDecode/FlateDecode]" (Str8 append (%pdf-spec-hexed "hello hello hello" 17) ">"))
              (%pdf-spec-stream "/Filter[/ASCIIHexDecode/FlateDecode]/DecodeParms[null<</Predictor 12/Columns 3>>]"
                                (Str8 append (%pdf-spec-hexed (first (Bytes of-hex "0261626302010101")) 8) ">"))
              (%pdf-spec-stream "/Filter/ASCII85Decode" "z!!~>")
              (%pdf-spec-stream "/Filter/DCTDecode" "x"))
        "/Root 1 0 R")))
  (list (List map (fn (_ n) (%pdf-spec-text (Pdf data %pdf-spec-h (Pdf object %pdf-spec-h n)))) (list 1 2 3 4))
        (Bytes hex (Pdf data %pdf-spec-h (Pdf object %pdf-spec-h 5)))
        (guard (e (e msg)) (Pdf data %pdf-spec-h (Pdf object %pdf-spec-h 6)))))
```
---
    (("Hellop" "Hello" "hello hello hello" "abcbcd") "0000000000" "Pdf: the filter DCTDecode is not read")

## a file with a cross-reference stream

### objects in an object stream, the cross-reference a stream of typed entries

```x
(do (import x/codec/pdf) (import x/codec/bytes) (import x/core/doors int/ int%)
  (def %pdf-spec-u16 (fn (_ n) (Bytes hex (Bytes of-list (list (int/ n 256) (int% n 256))))))
  (def %pdf-spec-a "<</Type/Pages/Kids[4 0 R]/Count 1>>")
  (def %pdf-spec-head (Str8 append "3 0 4 " (Str8 str (+ (Str8 length %pdf-spec-a) 1)) " "))
  (def %pdf-spec-packed (Str8 append %pdf-spec-head %pdf-spec-a " <</Type/Page/Parent 3 0 R/Rotate 270>>"))
  (def %pdf-spec-one "%PDF-1.5\n1 0 obj\n<</Type/Catalog/Pages 3 0 R>>\nendobj\n")
  (def %pdf-spec-two
    (Str8 append %pdf-spec-one "2 0 obj\n"
      (%pdf-spec-stream (Str8 append "/Type/ObjStm/N 2/First " (Str8 str (Str8 length %pdf-spec-head))) %pdf-spec-packed)
      "\nendobj\n"))
  (def %pdf-spec-rows
    (Str8 append "00000000" "01" (%pdf-spec-u16 9) "00" "01" (%pdf-spec-u16 (Str8 length %pdf-spec-one)) "00"
                 "02000200" "02000201" "01" (%pdf-spec-u16 (Str8 length %pdf-spec-two)) "00" ">"))
  (def %pdf-spec-x
    (%pdf-spec-open
      (Str8 append %pdf-spec-two "5 0 obj\n"
        (%pdf-spec-stream "/Type/XRef/Size 6/W[1 2 1]/Root 1 0 R/Filter/ASCIIHexDecode" %pdf-spec-rows)
        "\nendobj\nstartxref\n" (Str8 str (Str8 length %pdf-spec-two)) "\n%%EOF\n")))
  (list (Pdf version %pdf-spec-x) (Pdf object %pdf-spec-x 3) (Pdf object %pdf-spec-x 4)
        (List map (fn (_ p) (Pdf lookup %pdf-spec-x p "Rotate")) (Pdf pages %pdf-spec-x))
        (Pdf lookup %pdf-spec-x (Pdf trailer %pdf-spec-x) "Root")))
```
---
    ("1.5" ('dict ("Type" 'name "Pages") ("Kids" 'array ('ref 4 0)) ("Count" . 1)) ('dict ("Type" 'name "Page") ("Parent" 'ref 3 0) ("Rotate" . 270)) (270) ('dict ("Type" 'name "Catalog") ("Pages" 'ref 3 0)))

## refusals

### no header; no startxref; an encrypted file

```x
(do (import x/codec/pdf)
  (list (guard (e (e msg)) (Pdf open "hello" 5))
        (guard (e (e msg)) (Pdf open "%PDF-1.4\n" 9))
        (guard (e (e msg)) (%pdf-spec-open (%pdf-spec-file (list "<<>>") "/Root 1 0 R/Encrypt 1 0 R")))))
```
---
    ("Pdf: no %PDF- header" "Pdf: no startxref" "Pdf: the file is encrypted")
