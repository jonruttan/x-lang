; tui/style.x -- a terminal cell's style as one integer, and its SGR.
;
; A style is an integer: the attributes in bits 0-5 (bold 1, dim 2, italic
; 4, underline 8, reverse 16, strike 32), the foreground colour plus one in
; bits 8-16 and the background's in bits 17-25, 0 for the terminal's own.
; A colour is 0-255: 0-7 the ANSI colours, 8-15 their bright forms, the
; rest the 256-colour cube and greys.  0 is the plain style.

(module x/tui/style)
(import x/type/class)

(def %st-and (prim-ref (lit int) (lit &)))
(def %st-or (prim-ref (lit int) (lit |)))
(def %st-shr (prim-ref (lit int) (lit >>)))
(def %st-shl (prim-ref (lit int) (lit <<)))
(def %st< (prim-ref (lit int) (lit <)))
(def %st+ (prim-ref (lit int) (lit +)))
(def %st-cvt (prim-ref (lit convert) (lit to)))
(def %st-string (Type named STRING))
(def %st-num (fn (_ n) (%st-cvt n %st-string 10)))

(def %st-attrs
  (list (pair (lit bold) 1) (pair (lit dim) 2) (pair (lit italic) 4)
        (pair (lit underline) 8) (pair (lit reverse) 16) (pair (lit strike) 32)))
; The SGR parameter of each attribute bit, in bit order.
(def %st-codes (list "1" "2" "3" "4" "7" "9"))
(def %st-bit
  (fn (self name l)
    (match ((eq? l ()) (Err raise (lit value) "Style: no such attribute" name))
           ((eq? (first (first l)) name) (rest (first l)))
           (#t (self name (rest l))))))
(def %st-colour
  (fn (_ c)
    (match ((eq? c ()) 0)
           ((match ((%st< c 0) #t) ((%st< 255 c) #t) (#t #f))
             (Err raise (lit value) "Style: a colour is 0 to 255" c))
           (#t (%st+ c 1)))))
; The SGR parameters for colour field F (colour plus one, 0 for none): BASE
; for 0-7, BRIGHT for 8-15, EXTENDED;5;N past them.
(def %st-colour-codes
  (fn (_ f base bright extended out)
    (match ((= f 0) out)
           ((%st< f 9) (pair (%st-num (%st+ base (%st+ f -1))) out))
           ((%st< f 17) (pair (%st-num (%st+ bright (%st+ f -9))) out))
           (#t (pair (%str-concat (list extended ";5;" (%st-num (%st+ f -1)))) out)))))
(def %st-attr-codes
  (fn (self bits codes out)
    (match ((eq? codes ()) out)
           ((= (%st-and bits 1) 1) (self (%st-shr bits 1) (rest codes) (pair (first codes) out)))
           (#t (self (%st-shr bits 1) (rest codes) out)))))
; Each parameter after a ;, then the m.
(def %st-join
  (fn (self ps)
    (match ((eq? ps ()) (list "m")) (#t (pair ";" (pair (first ps) (self (rest ps))))))))
; The SGR sequence that sets S from the plain style.
(def style-sgr
  (fn (_ s)
    (def ps (%reverse
              (%st-colour-codes (%st-and (%st-shr s 17) 511) 40 100 "48"
                (%st-colour-codes (%st-and (%st-shr s 8) 511) 30 90 "38"
                  (%st-attr-codes (%st-and s 63) %st-codes ())))))
    (%str-concat (pair "\x1b[0" (%st-join ps)))))

(def-class Style ()
  (doc "Terminal styles as integers: attributes and colours packed in one word, and the SGR escape that sets one."
    (example "(Style sgr (Style make '(bold underline) 4 ()))" "\"\\x1b[0;1;4;34m\"")
    (see make) (see sgr))
  (static
    (method make (self (param attrs LIST "Attribute names: bold, dim, italic, underline, reverse, strike")
                       (param fg ANY "Foreground colour 0-255, or nil for the terminal's")
                       (param bg ANY "Background colour 0-255, or nil for the terminal's"))
      (doc "A style with ATTRS set and the colours FG and BG."
        (returns INTEGER "The style")
        (example "(Style make '(italic) () ())" "4")
        (example "(Style make () 1 ())" "512"))
      (%st-or (%st-or (%fold (fn (_ acc a) (%st-or acc (%st-bit a %st-attrs))) 0 attrs)
                      (%st-shl (%st-colour fg) 8))
              (%st-shl (%st-colour bg) 17)))
    (method with (self (param style INTEGER "A style") (param attrs LIST "Attribute names to add"))
      (doc "STYLE with ATTRS set as well."
        (returns INTEGER "The style")
        (example "(Style with (Style make '(bold) () ()) '(reverse))" "17"))
      (%st-or style (self make attrs () ())))
    (method has? (self (param style INTEGER "A style") (param attr SYMBOL "An attribute name"))
      (doc "Whether STYLE has the attribute ATTR."
        (returns BOOL "#t or #f")
        (example "(Style has? 9 'underline)" "#t"))
      (not (= (%st-and style (%st-bit attr %st-attrs)) 0)))
    (method fg (self (param style INTEGER "A style"))
      (doc "STYLE's foreground colour, or nil for the terminal's."
        (returns ANY "0-255 or nil")
        (example "(Style fg (Style make () 12 ()))" "12"))
      ((fn (_ f) (match ((= f 0) ()) (#t (- f 1)))) (%st-and (%st-shr style 8) 511)))
    (method bg (self (param style INTEGER "A style"))
      (doc "STYLE's background colour, or nil for the terminal's."
        (returns ANY "0-255 or nil")
        (example "(Style bg (Style make () () 200))" "200"))
      ((fn (_ f) (match ((= f 0) ()) (#t (- f 1)))) (%st-and (%st-shr style 17) 511)))
    (method sgr (self (param style INTEGER "A style"))
      (doc "The escape sequence that sets STYLE: it resets first, so it does not depend on the style before it."
        (returns STRING "ESC [ 0 ; ... m")
        (example "(Style sgr 0)" "\"\\x1b[0m\"")
        (example "(Style sgr (Style make '(dim) 9 200))" "\"\\x1b[0;2;91;48;5;200m\""))
      (style-sgr style))))

(provide x/tui/style Style style-sgr)
