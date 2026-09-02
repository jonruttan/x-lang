; # x-lang -- Bitwise
;
; ## apps/bitwise/gen.x -- the owl, in costume, over a field the name seeds
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; Bitwise is the owl stamped in every x source header, and this module keeps
; it exactly that: glyphs of Roboto Mono set from the font's own outlines
; (glyphs.json), so it is the same owl on every machine.  The project's NAME
; decides everything around it: sha256(name) seeds a bitwise function over a
; cell grid -- the field the owl sits on -- and the accent hue.  A project
; with a mascot, a logo colour or an idiom of its own wears it as a COSTUME
; from langs.json: glyph rows around the owl, brand colours, a reference
; line in its language.  Same name, same picture, forever.
;
; EVERY QUANTITY IS AN INTEGER.  Geometry is carried in micro-units (%bw-U
; per user unit) and formatted with %bw-fmt, half-up, so the picture is a
; function of the name alone and the browser twin (gallery/bitwise.js)
; computes the identical bytes with the same integer arithmetic.
(import x/codec/json)
(import x/codec/sha256)
(import x/codec/hex)
(import x/sys/file)

; The data lives beside this file, and %bitwise-root says where that is: the
; entry (run.x) arms it from %install-root, a spec from the repo root.  No
; literal here -- a runtime module may not know the tree's layout
; (tools/check/path-literals.sh) -- and no read at load time either: the
; linter imports this module as data, with no root armed.  The first render
; reads the two files and fills the metrics in.
; lint-known: %bitwise-root
(def %bw-glyphs #f)
(def %bw-langs #f)
(def %bw-upm 0)
(def %bw-adv 0)
(def %bw-asc 0)
(def %bw-line 0)
(def %bw-gmap #f)
(def %bw-gix #f)
(def %bw-load!
  (fn (_)
    (unless %bw-glyphs
      (set! %bw-glyphs (Json parse (File read-all (%path-join %bitwise-root "glyphs.json"))))
      (set! %bw-langs (Json parse (File read-all (%path-join %bitwise-root "langs.json"))))
      (set! %bw-upm (%bw-glyphs get "upm"))
      (set! %bw-adv (%bw-glyphs get "adv"))
      (set! %bw-asc (%bw-glyphs get "asc"))
      (set! %bw-line (+ (- (%bw-glyphs get "asc") (%bw-glyphs get "desc")) (%bw-glyphs get "gap")))
      (set! %bw-gmap (%bw-glyphs get "glyphs"))
      (set! %bw-gix (%bw-glyphs get "index")))))

(def %bw-U 1000000)
(def %bw-ink "#161a22")
(def %bw-paper "#f2f4f7")
(def %bw-font "'Roboto Mono','Martian Mono',Menlo,'DejaVu Sans Mono',ui-monospace,monospace")
(def %bw-sigil (list "., .," "{O,O}" "(   )" " \" \""))
(def %bw-sigil-roles (list "ii ii" "ieifi" "iiiii" " i i "))
(def %bw-ops (list "xor" "and" "or" "rings" "moire" "prod"))
(def %bw-grids (list 16 20 24 32))
(def %bw-pow10 (list 1 10 100 1000 10000 100000 1000000))

(def %bw-s (fn (_ v) (Io display-to-str v)))
(def %bw-cat (fn (_ parts) (%str-concat parts)))
(def %bw-esc
  (fn (_ t)
    (Str8 replace "\"" "&quot;"
      (Str8 replace ">" "&gt;" (Str8 replace "<" "&lt;" (Str8 replace "&" "&amp;" t))))))

; v micro-units -> "d.dd" with d decimals (0, 1, 2 or 4), rounded half-up.
; Hand-rolled: the library's pad-left costs milliseconds and this runs per
; glyph and per grid line.
(def %bw-fmt
  (fn (_ v d)
    (match
      ((= d 0) (%bw-s (/ (+ v 500000) 1000000)))
      ((= d 1)
       (let ((q (/ (+ v 50000) 100000)))
         (%bw-cat (list (%bw-s (/ q 10)) "." (%bw-s (- q (* 10 (/ q 10))))))))
      ((= d 2)
       (let ((q (/ (+ v 5000) 10000)))
         (let ((f (- q (* 100 (/ q 100)))))
           (%bw-cat (list (%bw-s (/ q 100)) (if (< f 10) ".0" ".") (%bw-s f))))))
      (#t
       (let ((q (/ (+ v 50) 100)))
         (let ((f (- q (* 10000 (/ q 10000)))))
           (%bw-cat (list (%bw-s (/ q 10000))
                          (if (< f 10) ".000" (if (< f 100) ".00" (if (< f 1000) ".0" ".")))
                          (%bw-s f)))))))))

; ---------------------------------------------------------------- seeding

(def %bw-digest (fn (_ name) (Hex decode-bytes (Sha256 hex name))))

; Each op maps a shifted cell coordinate pair to an integer; bit k of the
; result decides whether the cell is lit.  a, b are small odd multipliers,
; s a per-name salt.  Masked to 32 bits so the twin agrees.
(def %bw-op
  (fn (_ op x y a b s)
    (match
      ((= op 0) (^ (^ (* x a) (* y b)) s))
      ((= op 1) (^ (& (* x a) (* y b)) s))
      ((= op 2) (^ (| (* x a) (* y b)) s))
      ((= op 3) (^ (+ (* (* x x) a) (* (* y y) b)) s))
      ((= op 4) (^ (^ (+ (* x a) (* y b)) (* x y)) s))
      (#t (^ (^ (* (* x y) a) (* (+ x y) b)) s)))))

(def %bw-field
  (fn (_ p n)
    (def op (p get 'op))
    (def a (p get 'a))
    (def b (p get 'b))
    (def s (p get 'salt))
    (def k (p get 'bit))
    (def ox (p get 'ox))
    (def oy (p get 'oy))
    (def half (/ n 2))
    (let rows ((j 0) (acc ()))
      (if (>= j n) (%reverse acc)
        (rows (+ j 1)
          (pair
            (let cells ((i 0) (racc ()))
              (if (>= i n) (%reverse racc)
                (cells (+ i 1)
                  (pair
                    (let ((x (if (= op 3) (Num abs (- i half)) (+ i ox)))
                          (y (if (= op 3) (Num abs (- j half)) (+ j oy))))
                      (= 1 (& (>> (& (%bw-op op x y a b s) 4294967295) k) 1)))
                    racc))))
            acc))))))

; A field is asked for more than once per picture (the gate, the count, the
; ground); remember each grid size on the params.
(def %bw-field-of
  (fn (_ p n)
    (def key (%bw-cat (list "field-" (%bw-s n))))
    (if (p has? key) (p get key)
      (let ((rows (%bw-field p n)))
        (p set! key rows)
        rows))))

(def %bw-lit
  (fn (_ rows)
    (let go ((rs rows) (n 0))
      (if (null? rs) n
        (go (rest rs)
            (+ n (let cnt ((cs (first rs)) (m 0))
                   (if (null? cs) m (cnt (rest cs) (if (first cs) (+ m 1) m))))))))))

(def %bw-formula
  (fn (_ op a b)
    (def sa (%bw-s a))
    (def sb (%bw-s b))
    (match
      ((= op 0) (%bw-cat (list "(x*" sa ") ^ (y*" sb ")")))
      ((= op 1) (%bw-cat (list "(x*" sa ") & (y*" sb ")")))
      ((= op 2) (%bw-cat (list "(x*" sa ") | (y*" sb ")")))
      ((= op 3) (%bw-cat (list "x*x*" sa " + y*y*" sb)))
      ((= op 4) (%bw-cat (list "(x*" sa " + y*" sb ") ^ (x*y)")))
      (#t (%bw-cat (list "(x*y*" sa ") ^ (x+y)*" sb))))))

; The lit fraction must read as a texture: sparse and dense are both fine
; (they are the variety); only under 18% or over 82% is rejected.  Walk the
; bit, then the op.  Deterministic, so the same name lands on the same field.
(def %bw-gate-ok?
  (fn (_ p)
    (def n (p get 'n))
    (def lit (%bw-lit (%bw-field-of p n)))
    (if (>= (* lit 100) (* 18 (* n n))) (<= (* lit 100) (* 82 (* n n))) #f)))

(def %bw-params
  (fn (_ name)
    (def h (%bw-digest name))
    (def b (fn (_ i) (List ref i h)))
    (def p (Dict make))
    (p set! 'name name)
    ; hue to one decimal, as tenths: round((h0*256+h1) * 3600 / 65536), half-up
    (p set! 'hue10 (/ (+ (* (+ (* (b 0) 256) (b 1)) 7200) 65536) 131072))
    (p set! 'op (Num modulo (b 2) 6))
    (p set! 'bit (+ 1 (Num modulo (b 3) 4)))
    (p set! 'a (+ (* (& (b 4) 7) 2) 1))
    (p set! 'b (+ (* (& (b 5) 7) 2) 1))
    (p set! 'ox (& (b 6) 31))
    (p set! 'oy (& (b 7) 31))
    (p set! 'salt (b 8))
    (p set! 'n (List ref (Num modulo (b 9) 4) %bw-grids))
    (let walk ((step 0))
      (if (< step 24)
        (unless (%bw-gate-ok? p)
          (p del! (%bw-cat (list "field-" (%bw-s (p get 'n)))))
          (p set! 'bit (+ 1 (Num modulo (p get 'bit) 4)))
          (when (= (Num modulo step 4) 3)
            (p set! 'op (Num modulo (+ (p get 'op) 1) 6)))
          (walk (+ step 1)))))
    (p set! 'lit (%bw-lit (%bw-field-of p (p get 'n))))
    (p set! 'opname (List ref (p get 'op) %bw-ops))
    (p set! 'formula
      (%bw-cat (list (%bw-formula (p get 'op) (p get 'a) (p get 'b)) " >> " (%bw-s (p get 'bit)) " & 1")))
    p))

; ---------------------------------------------------------------- colour

(def %bw-hue-str
  (fn (_ hue10) (%bw-cat (list (%bw-s (/ hue10 10)) "." (%bw-s (Num modulo hue10 10))))))
(def %bw-hsl
  (fn (_ h s l) (%bw-cat (list "hsl(" h "," (%bw-s s) "%," (%bw-s l) "%)"))))
(def %bw-hsl3
  (fn (_ t) (%bw-hsl (%bw-s (List ref 0 t)) (List ref 1 t) (List ref 2 t))))

; Colours: the hashed hue, unless the costume names its own.
(def %bw-palette
  (fn (_ p lang)
    (def hue (%bw-hue-str (p get 'hue10)))
    (def acc (if (lang has? "accent") (lang get "accent") #f))
    (def accent (if acc (%bw-hsl3 acc) (%bw-hsl hue 58 46)))
    (def pal (Dict make))
    (pal set! 'accent accent)
    (pal set! 'deep
      (if acc (%bw-hsl (%bw-s (List ref 0 acc)) (List ref 1 acc) (/ (* (List ref 2 acc) 65) 100))
        (%bw-hsl hue 55 30)))
    (pal set! 'eyes
      (if (lang has? "eyes") (List map %bw-hsl3 (lang get "eyes")) (list accent accent)))
    (pal set! 'secondary (if (lang has? "secondary") (%bw-hsl3 (lang get "secondary")) accent))
    pal))

(def %bw-colour
  (fn (_ pal role)
    (match
      ((str=? role "e") (List ref 0 (pal get 'eyes)))
      ((str=? role "f") (List ref 1 (pal get 'eyes)))
      ((str=? role "a") (pal get 'accent))
      ((str=? role "b") (pal get 'secondary))
      (#t %bw-ink))))

; ---------------------------------------------------------------- the owl

; A row is bytes; the owl's glyphs are characters.  Split on UTF-8 leads.
(def %bw-glyph-list
  (fn (_ s)
    (def len (Str8 length s))
    (let go ((i 0) (acc ()))
      (if (>= i len) (%reverse acc)
        (let ((b (Char ->int (Str8 ref i s))))
          (let ((w (if (< b 128) 1 (if (< b 224) 2 (if (< b 240) 3 4)))))
            (go (+ i w) (pair (Str8 sub i w s) acc))))))))

; (rows roles): the glyph rows and, per glyph, who colours it --
; i ink, e/f the two eyes, a accent, b the secondary colour.
(def %bw-costume
  (fn (_ lang)
    (list (List map %bw-glyph-list (if (lang has? "rows") (lang get "rows") %bw-sigil))
          (List map %bw-glyph-list (if (lang has? "roles") (lang get "roles") %bw-sigil-roles)))))

(def %bw-cols
  (fn (_ rows)
    (let go ((rs rows) (m 0)) (if (null? rs) m (go (rest rs) (Num max m (%length (first rs))))))))

; The owl set from outlines.  (x-u, y-u) is the block's top-left and k the
; micro-units per font unit; glyph paths are declared once each, by index.
(def %bw-owl
  (fn (_ pal rows roles uid x-u y-u k)
    (def used ())
    (def groups (Dict make))
    (def ks (%bw-fmt k 4))
    (let rl ((rs rows) (ro roles) (row 0))
      (unless (null? rs)
        (let ((base (+ y-u (* (+ %bw-asc (* row %bw-line)) k))))
          (let cl ((cs (first rs)) (os (first ro)) (col 0))
            (unless (null? cs)
              (let ((ch (first cs)) (role (first os)))
                (unless (str=? ch " ")
                  (unless (%member-str? ch used) (set! used (pair ch used)))
                  (groups set! role
                    (pair (%bw-cat (list "<use href=\"#" uid "-" (%bw-s (%bw-gix get ch))
                                         "\" transform=\"translate(" (%bw-fmt (+ x-u (* (* col %bw-adv) k)) 2)
                                         "," (%bw-fmt base 2) ") scale(" ks ",-" ks ")\"/>"))
                          (groups get-or (list) role)))))
              (cl (rest cs) (rest os) (+ col 1)))))
        (rl (rest rs) (rest ro) (+ row 1))))
    (def defs
      (%bw-cat (List map (fn (_ c) (%bw-cat (list "<path id=\"" uid "-" (%bw-s (%bw-gix get c)) "\" d=\"" (%bw-gmap get c) "\"/>")))
                 (%reverse used))))
    (%bw-cat
      (list "<defs>" defs "</defs>"
        (%bw-cat (List map (fn (_ r)
                             (if (groups has? r)
                               (%bw-cat (list "<g fill=\"" (%bw-colour pal r) "\">" (%bw-cat (%reverse (groups get r))) "</g>"))
                               ""))
                   (list "i" "e" "f" "a" "b")))))))

; The owl centred in the box at (x, y) of bw x bh user units.
(def %bw-owl-in
  (fn (_ pal lang uid x y bw bh)
    (def cr (%bw-costume lang))
    (def rows (first cr))
    (def roles (first (rest cr)))
    (def n (%length rows))
    (def cols (%bw-cols rows))
    (def size-u (Num min (/ (* bh (* %bw-upm %bw-U)) (* n %bw-line))
                         (/ (* bw (* %bw-upm %bw-U)) (* cols %bw-adv))))
    (def k (/ size-u %bw-upm))
    (def w-u (* (* cols %bw-adv) k))
    (def h-u (* (* n %bw-line) k))
    (%bw-owl pal rows roles uid
      (+ (* x %bw-U) (/ (- (* bw %bw-U) w-u) 2))
      (+ (* y %bw-U) (/ (- (* bh %bw-U) h-u) 2))
      k)))

; The field: the name's bit function, one square per lit cell.  Coordinates
; are formatted once per column and once per row, not once per cell.
(def %bw-bitfield
  (fn (_ p cols rows-n cell-u color opacity)
    (def rows (%bw-field-of p (Num max cols rows-n)))
    (def inset (/ (* cell-u 3) 10))
    (def ws (%bw-fmt (- cell-u (* 2 inset)) 1))
    (def coords
      (let go ((i 0) (acc ()))
        (if (>= i (Num max cols rows-n)) (%reverse acc)
          (go (+ i 1) (pair (%bw-fmt (+ (* i cell-u) inset) 1) acc)))))
    (def cells
      (let rl ((rs rows) (ys coords) (j 0) (acc ()))
        (if (>= j rows-n) acc
          (rl (rest rs) (rest ys) (+ j 1)
              (let cl ((cs (first rs)) (xs coords) (i 0) (acc acc))
                (if (>= i cols) acc
                  (cl (rest cs) (rest xs) (+ i 1)
                      (if (first cs)
                        (pair (%bw-cat (list "<rect x=\"" (first xs) "\" y=\"" (first ys)
                                             "\" width=\"" ws "\" height=\"" ws "\"/>"))
                              acc)
                        acc))))))))
    (%bw-cat (list "<g fill=\"" color "\" fill-opacity=\"" opacity "\">" (%bw-cat (%reverse cells)) "</g>"))))

; ---------------------------------------------------------------- formats

(def %bw-svg-open
  (fn (_ w h title)
    (%bw-cat (list "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" (%bw-s w) "\" height=\"" (%bw-s h)
                   "\" viewBox=\"0 0 " (%bw-s w) " " (%bw-s h) "\" role=\"img\" aria-label=\"" (%bw-esc title) "\">"))))

(def %bw-fmt-mark
  (fn (_ p pal lang uid)
    (def n (p get 'n))
    (%bw-cat
      (list "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"512\" height=\"512\" role=\"img\" aria-label=\"Bitwise, "
            (%bw-esc (p get 'name)) "\">"
            (%bw-bitfield p n n (/ (* 100 %bw-U) n) (pal get 'accent) "0.22")
            (%bw-owl-in pal lang uid 6 8 88 84)
            "</svg>"))))

(def %bw-fmt-avatar
  (fn (_ p pal lang uid)
    (%bw-cat
      (list (%bw-svg-open 512 512 (%bw-cat (list "Bitwise, " (p get 'name))))
            "<rect width=\"512\" height=\"512\" fill=\"" %bw-paper "\"/>"
            (%bw-bitfield p 16 16 (* 32 %bw-U) (pal get 'accent) "0.14")
            (%bw-owl-in pal lang uid 40 56 432 400)
            "</svg>"))))

(def %bw-words
  (fn (_ t) (List filter (fn (_ w) (not (str=? w ""))) (Str8 split " " t))))
(def %bw-chars (fn (_ s) (%length (%bw-glyph-list s))))

; Greedy wrap to width characters, at most four lines, an ellipsis if cut.
; The current line's length rides along; re-measuring it per word cost
; a second on a long tagline.
(def %bw-wrap
  (fn (_ text width)
    (def lines
      (let go ((ws (%bw-words text)) (cur "") (cur-n 0) (acc ()))
        (if (null? ws) (%reverse (if (= cur-n 0) acc (pair cur acc)))
          (let ((w (first ws)))
            (let ((wn (%bw-chars w)))
              (if (if (= cur-n 0) #f (> (+ cur-n (+ 1 wn)) width))
                (go (rest ws) w wn (pair cur acc))
                (go (rest ws) (if (= cur-n 0) w (%bw-cat (list cur " " w))) (if (= cur-n 0) wn (+ cur-n (+ 1 wn))) acc)))))))
    (if (> (%length lines) 4)
      (list (List ref 0 lines) (List ref 1 lines) (List ref 2 lines)
            (%bw-cat (list (%bw-rstrip-chars (%bw-glyph-take (List ref 3 lines) (- width 1)) ",;: ") "\xe2\x80\xa6")))
      lines)))

; Drop trailing bytes that are in chars.
(def %bw-rstrip-chars
  (fn (_ s chars)
    (let go ((e (Str8 length s)))
      (if (= e 0) ""
        (if (Str8 includes? (Str8 sub (- e 1) 1 s) chars) (go (- e 1)) (Str8 sub 0 e s))))))

; The first n characters of s (UTF-8 aware).
(def %bw-glyph-take
  (fn (_ s n)
    (%bw-cat (let go ((gs (%bw-glyph-list s)) (i 0) (acc ()))
               (if (if (null? gs) #t (>= i n)) (%reverse acc) (go (rest gs) (+ i 1) (pair (first gs) acc)))))))

(def %bw-text
  (fn (_ x y size fill extra body)
    (%bw-cat (list "<text x=\"" (%bw-s x) "\" y=\"" (%bw-s y) "\" font-family=\"" %bw-font
                   "\" font-size=\"" (%bw-s size) "\"" extra " fill=\"" fill "\">" (%bw-esc body) "</text>"))))

(def %bw-fmt-banner
  (fn (_ p pal lang tagline kind uid)
    (def x 560)
    (def name (p get 'name))
    (def nlen (%bw-chars name))
    (def fs (if (<= nlen 10) 96 (if (<= nlen 14) 72 56)))
    (def tag-lines
      (let go ((ls (%bw-wrap tagline 42)) (y 356) (acc ()))
        (if (null? ls) (%reverse acc)
          (go (rest ls) (+ y 36) (pair (%bw-text x y 26 %bw-ink "" (first ls)) acc)))))
    (def colour
      (if (lang has? "logo") (lang get "logo")
        (%bw-cat (list "hue " (%bw-s (/ (p get 'hue10) 10)) "&#176;"))))
    (%bw-cat
      (list (%bw-svg-open 1280 640 (%bw-cat (list name ", with Bitwise")))
            "<rect width=\"1280\" height=\"640\" fill=\"" %bw-paper "\"/>"
            (%bw-bitfield p 40 20 (* 32 %bw-U) (pal get 'accent) "0.09")
            (%bw-owl-in pal lang uid 60 90 440 460)
            (%bw-text x 200 20 (pal get 'deep) " letter-spacing=\"4\"" (Str8 upcase (if (str=? kind "") "an x project" kind)))
            (%bw-text x 300 fs %bw-ink " font-weight=\"700\"" name)
            (%bw-cat tag-lines)
            (if (lang has? "reference")
              (%bw-text x 524 24 (pal get 'deep) " xml:space=\"preserve\"" (lang get "reference"))
              "")
            "<text x=\"" (%bw-s x) "\" y=\"580\" font-family=\"" %bw-font "\" font-size=\"15\" fill=\"" (pal get 'deep)
            "\">plumage  " (%bw-esc (p get 'formula)) "   " colour "</text>"
            "</svg>"))))

; ---------------------------------------------------------------- entry

(def %bw-lang-of
  (fn (_ name)
    (%bw-load!)
    (if (%bw-langs has? name) (%bw-langs get name) (Dict make))))

; (bitwise-render name fmt tagline kind uid) -> (svg . params)
(def bitwise-render
  (fn (_ name fmt tagline kind uid)
    (%bw-load!)
    (def p (%bw-params name))
    (def lang (%bw-lang-of name))
    (def pal (%bw-palette p lang))
    (p set! 'costume (if (lang has? "mascot") (lang get "mascot") (if (lang has? "logo") (lang get "logo") "")))
    (p set! 'reference (if (lang has? "reference") (lang get "reference") ""))
    (pair
      (match
        ((str=? fmt "mark") (%bw-fmt-mark p pal lang uid))
        ((str=? fmt "avatar") (%bw-fmt-avatar p pal lang uid))
        ((str=? fmt "banner") (%bw-fmt-banner p pal lang tagline kind uid))
        (#t (Err raise 'value (%bw-cat (list "bitwise: unknown format " fmt)) ())))
      p)))

(def bitwise-params %bw-params)

; (bitwise-diff a b): #t when the two renderings are the same bytes, else
; the offset of the first difference with a window of each around it.  The
; parity specs compare gen.x against the twin's checked-in renderings with
; this: a native compare, then a binary search over prefixes on a mismatch
; -- a byte loop over a 60KB picture costs more in pure x than drawing it.
(def bitwise-diff
  (fn (_ a b)
    (if (str=? a b) #t
      (let ((n (Num min (Str8 length a) (Str8 length b))))
        (let go ((lo 0) (hi n))
          (if (>= lo hi)
            (list 'differ-at lo
                  (Str8 sub (Num max 0 (- lo 30)) (Num min 70 (- (Str8 length a) (Num max 0 (- lo 30)))) a)
                  (Str8 sub (Num max 0 (- lo 30)) (Num min 70 (- (Str8 length b) (Num max 0 (- lo 30)))) b))
            (let ((mid (/ (+ lo hi 1) 2)))
              (if (str=? (Str8 sub 0 mid a) (Str8 sub 0 mid b)) (go mid hi) (go lo (- mid 1))))))))))

(provide bitwise/gen bitwise-render bitwise-params bitwise-diff
  %bw-load! %bw-lang-of %bw-palette %bw-costume %bw-glyph-list %bw-chars %bw-glyph-take
  %bw-rstrip-chars %bw-words %bw-hue-str %bw-s %bw-cat %bw-esc %bw-fmt %bw-digest %bw-field %bw-field-of)
