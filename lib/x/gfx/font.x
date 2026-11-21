; font.x -- Font: the printable ASCII characters as strokes.
;
; A glyph is drawn on a grid 4 wide.  Its baseline is 0, a capital's top 6,
; a small letter's 4, and a descender reaches -2.  A character takes 6 of
; the grid across, its 4 and 2 of space.
;
; A glyph is a list of strokes, a stroke a list of (X . Y) grid points to
; draw a line through.  A stroke of one point is a dot.  Every glyph is
; lines: nothing is filled, so a letter is as heavy as the line it is drawn
; with.
;
; The glyphs are kept as text, one a character from the space on.  Strokes
; are set apart by spaces and a point is two digits, its X and its Y; Y is
; written 2 more than it is, so that a descender needs no sign.
(module x/gfx/font)

(import x/core/doors char->int int& int+ int- int< str-byte-len str-byte-ref)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Font: " what) ())))

(def %glyphs
  (list
    ""                                     ; space
    "2824 22"                              ; !
    "1816 3836"                            ; "
    "1218 3238 0646 0444"                  ; #
    "473818070615354443321203 2822"        ; $
    "0248 17 33"                           ; %
    "4216172837360403122244"               ; &
    "2826"                                 ; '
    "38272332"                             ; (
    "18272312"                             ; )
    "2723 0644 0446"                       ; *
    "2723 0545"                            ; +
    "232211"                               ; ,
    "0545"                                 ; -
    "22"                                   ; .
    "0248"                                 ; /
    "183847433212030718 1337"              ; 0
    "172822 1232"                          ; 1
    "07183847460242"                       ; 2
    "07183847463525 354443321203"          ; 3
    "380444 3832"                          ; 4
    "480805354443321203"                   ; 5
    "38180703123243443505"                 ; 6
    "084822"                               ; 7
    "183847463515060718 1504031232434435"  ; 8
    "12324347381807061545"                 ; 9
    "25 22"                                ; :
    "25 232211"                            ; ;
    "470543"                               ; <
    "0646 0444"                            ; =
    "074503"                               ; >
    "07183847462524 22"                    ; ?
    "32120307183847443424263634"           ; @
    "0206284642 0545"                      ; A
    "02083847463505 3544433202"            ; B
    "4738180703123243"                     ; C
    "02082846442202"                       ; D
    "48080242 0535"                        ; E
    "480802 0535"                          ; F
    "47381807031232434525"                 ; G
    "0208 4248 0545"                       ; H
    "1838 2822 1232"                       ; I
    "4843321203"                           ; J
    "0208 480542"                          ; K
    "080242"                               ; L
    "0208254842"                           ; M
    "02084248"                             ; N
    "183847433212030718"                   ; O
    "02083847463505"                       ; P
    "183847433212030718 2441"              ; Q
    "02083847463505 2542"                  ; R
    "473818070615354443321203"             ; S
    "0848 2822"                            ; T
    "080312324348"                         ; U
    "082248"                               ; V
    "0812253248"                           ; W
    "0248 0842"                            ; X
    "082548 2522"                          ; Y
    "08480242"                             ; Z
    "38282232"                             ; [
    "0842"                                 ; \
    "18282212"                             ; ]
    "062846"                               ; ^
    "0141"                                 ; _
    "1827"                                 ; `
    "4642 4536160503123243"                ; a
    "0802 0516364543321203"                ; b
    "4536160503123243"                     ; c
    "4842 4536160503123243"                ; d
    "044445361605031242"                   ; e
    "48382722 0636"                        ; f
    "46413010 4536160503123243"            ; g
    "0802 0516364542"                      ; h
    "2622 28"                              ; i
    "36312010 38"                          ; j
    "0802 460442"                          ; k
    "18282232"                             ; l
    "0206 05162522 25364542"               ; m
    "0206 0516364542"                      ; n
    "163645433212030516"                   ; o
    "0600 0516364543321203"                ; p
    "4640 4536160503123243"                ; q
    "0206 05163645"                        ; r
    "45361605143443321203"                 ; s
    "28233242 0636"                        ; t
    "0603123243 4642"                      ; u
    "062246"                               ; v
    "0612243246"                           ; w
    "0246 0642"                            ; x
    "0603123243 46413010"                  ; y
    "06460242"                             ; z
    "38272615242332"                       ; {
    "2821"                                 ; |
    "18272635242312"                       ; }
    "04153445"))                           ; ~

(def %digit (fn (_ s i) (int- (int& (char->int (str-byte-ref s i)) 255) 48)))

; The strokes TEXT says, from byte I: a point every two digits, and a
; stroke ended by a space or the end.
(def %strokes
  (fn (_ text)
    (def n (str-byte-len text))
    ((fn (self i stroke out)
       (match
         ((int< i n)
           (if (int< (%digit text i) 0)
             (self (int+ i 1) () (pair (List reverse stroke) out))
             (self (int+ i 2) (pair (pair (%digit text i) (int- (%digit text (int+ i 1)) 2)) stroke) out)))
         ((null? stroke) (List reverse out))
         (#t (List reverse (pair (List reverse stroke) out)))))
     0 () ())))

(def-class Font ()
  (doc "The printable ASCII characters as strokes on a grid 4 wide: the baseline 0, a capital's top 6, a small letter's 4, a descender to -2, and a character 6 across with its space. A glyph is a list of strokes, a stroke a list of (X . Y) grid points; a stroke of one point is a dot."
    (example "(Font glyph 76)" "(((0 . 6) (0 . 0) (4 . 0)))")
    (see glyph))
  (static
    (method glyph (self (param code INTEGER "A character's code"))
      (doc "The strokes of the character: the space and any code outside 32 to 126 have none."
        (returns LIST "Strokes, each a list of (X . Y) grid points")
        (example "(Font glyph 76)" "(((0 . 6) (0 . 0) (4 . 0)))")
        (example "(Font glyph 105)" "(((2 . 4) (2 . 0)) ((2 . 6)))")
        (example "(null? (Font glyph 7))" "#t"))
      (if (if (int< code 32) #t (int< 126 code))
        ()
        (%strokes (List ref (int- code 32) %glyphs))))

    (method advance (self)
      (doc "How far one character is from the next, in grid units: a glyph's 4 and 2 of space."
        (returns INTEGER "6")
        (example "(Font advance)" "6"))
      6)

    (method cap (self)
      (doc "A capital's height above the baseline, in grid units."
        (returns INTEGER "6")
        (example "(Font cap)" "6"))
      6)))

(doc (provide x/gfx/font Font)
  "A stroke font: (Font glyph code) answers a printable ASCII character as lines on a small grid, for x/gfx/figure's labels."
  (example "(Font glyph 45)" "(((0 . 3) (4 . 3)))"))
