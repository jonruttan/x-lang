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
; (glyphs.xon), so it is the same owl on every machine.  The project's NAME
; decides everything around it: sha256(name) seeds a bitwise function over a
; cell grid -- the field the owl sits on -- and the accent hue.  A project
; with a mascot, a logo colour or an idiom of its own wears it as a COSTUME:
; glyph rows around the owl, brand colours, a reference line in its language.
; A costume belongs to the PROJECT, not to this app -- each repository
; carries its own `bitwise.xon` and hands it over with (Bitwise costume-load!
; path); an unregistered name wears the plain owl.  Same name, same picture,
; forever.
;
; EVERY QUANTITY IS AN INTEGER.  Geometry is carried in micro-units (%U per
; user unit) and formatted with %fmt, half-up, so the picture is a function
; of the name alone and the browser twin (gallery/bitwise.js) computes the
; identical bytes with the same integer arithmetic.
;
; One class, one public global (tools/check/percent-globals.sh): every helper
; is a %-static on Bitwise, and the per-cell work stays inside one method's
; local loops -- a static dispatch per cell would be the whole budget.
(import x/type/class)
(import x/type/dict)
(import x/codec/xon)
(import x/codec/sha256)
(import x/codec/hex)
(import x/sys/file)

(def-class Bitwise ()
  (doc "The owl sigil, drawn for a project: (Bitwise render name fmt tagline kind uid) is an SVG whose field, colours and costume the name decides."
    (example "(first (Bitwise params \"x-lang\"))" "..."))
  (static
    ; where glyphs.xon lives: the entry arms it from
    ; %install-root, a spec from the repo root.  No literal here -- a runtime
    ; module may not know the tree's layout (tools/check/path-literals.sh).
    (%root-cell (pair () ()))
    ; the loaded glyphs, read on the first render, never at import: the
    ; linter imports this module as data with no root armed
    (%data-cell (pair () ()))
    ; the costumes projects have handed over, by name
    (%costumes-cell (pair () ()))
    (%U 1000000)
    (%ink "#161a22")
    (%paper "#f2f4f7")
    (%font "'Roboto Mono','Martian Mono',Menlo,'DejaVu Sans Mono',ui-monospace,monospace")
    (%sigil (list "., .," "{O,O}" "(   )" " \" \""))
    (%sigil-roles (list "ii ii" "ieifi" "iiiii" " i i "))
    (%ops (list "xor" "and" "or" "rings" "moire" "prod"))
    (%grids (list 16 20 24 32))

    (method root! (self (param path STRING "Directory holding glyphs.xon"))
      (doc "Arm the glyph root.  The entry does this from %install-root; a spec names apps/bitwise."
        (returns STRING "The path"))
      (%set-first! (Bitwise %root-cell) path)
      path)

    ; glyphs.xon is xon: forms the ordinary reader reads and no one
    ; evaluates -- (font ...), then one (glyph "CHAR" INDEX "PATH") per glyph.
    (method %data (self)
      (let ((d (first (Bitwise %data-cell))))
        (if (null? d)
          (let ((root (first (Bitwise %root-cell)))
                (nd (Dict make))
                (gmap (Dict make))
                (gix (Dict make)))
            (List for-each
              (fn (_ form)
                (let ((head (symbol->str (first form))))
                  (match
                    ((str=? head "font")
                     (do (nd set! 'upm (List ref 2 form))
                         (nd set! 'adv (List ref 3 form))
                         (nd set! 'asc (List ref 4 form))
                         (nd set! 'line (+ (- (List ref 4 form) (List ref 5 form)) (List ref 6 form)))))
                    ((str=? head "glyph")
                     (do (gix set! (List ref 1 form) (List ref 2 form))
                         (gmap set! (List ref 1 form) (List ref 3 form))))
                    (#t ()))))
              (Xon parse (File read-all (%path-join root "glyphs.xon"))))
            (nd set! 'gmap gmap)
            (nd set! 'gix gix)
            (%set-first! (Bitwise %data-cell) nd)
            nd)
          d)))

    ; ---------------------------------------------------------------- costumes

    (method %costumes (self)
      (let ((c (first (Bitwise %costumes-cell))))
        (if (null? c)
          (let ((d (Dict make))) (%set-first! (Bitwise %costumes-cell) d) d)
          c)))

    ; One (costume "NAME" (field ...) ...) form -> a name and its Dict.  The
    ; five list-valued fields keep their arguments; every other field is the
    ; one argument it carries.
    (method %costume-of (self form)
      (def lang (Dict make))
      (List for-each
        (fn (_ field)
          (let ((key (symbol->str (first field))) (vals (rest field)))
            (lang set! key
              (match
                ((str=? key "accent") vals)
                ((str=? key "secondary") vals)
                ((str=? key "eyes") vals)
                ((str=? key "rows") vals)
                ((str=? key "roles") vals)
                (#t (first vals))))))
        (rest (rest form)))
      (pair (List ref 1 form) lang))

    (method costume-load! (self (param path STRING "A project's bitwise.xon"))
      (doc "Register every (costume \"NAME\" ...) form in a project's own bitwise.xon, so a render of that name wears it.  A name with no costume registered wears the plain owl."
        (returns LIST "The names registered, in file order")
        (example "(Bitwise costume-load! \"bitwise.xon\")" "(\"x-lang\")"))
      (def out ())
      (List for-each
        (fn (_ form)
          (when (if (pair? form) (str=? (symbol->str (first form)) "costume") #f)
            (let ((nl (Bitwise %costume-of form)))
              ((Bitwise %costumes) set! (first nl) (rest nl))
              (set! out (pair (first nl) out)))))
        (Xon parse (File read-all path)))
      (%reverse out))

    (method %s (self v) (Io display-to-str v))
    (method %cat (self parts) (%str-concat parts))
    (method %esc (self t)
      (Str8 replace "\"" "&quot;"
        (Str8 replace ">" "&gt;" (Str8 replace "<" "&lt;" (Str8 replace "&" "&amp;" t)))))

    ; v micro-units -> "d.dd" with d decimals (0, 1, 2 or 4), rounded half-up.
    ; Hand-rolled: the library's pad-left costs milliseconds and this runs
    ; per glyph and per grid line.
    (method %fmt (self v d)
      (def s (fn (_ n) (Io display-to-str n)))
      (match
        ((= d 0) (s (/ (+ v 500000) 1000000)))
        ((= d 1)
         (let ((q (/ (+ v 50000) 100000)))
           (%str-concat (list (s (/ q 10)) "." (s (- q (* 10 (/ q 10))))))))
        ((= d 2)
         (let ((q (/ (+ v 5000) 10000)))
           (let ((f (- q (* 100 (/ q 100)))))
             (%str-concat (list (s (/ q 100)) (if (< f 10) ".0" ".") (s f))))))
        (#t
         (let ((q (/ (+ v 50) 100)))
           (let ((f (- q (* 10000 (/ q 10000)))))
             (%str-concat (list (s (/ q 10000))
                                (if (< f 10) ".000" (if (< f 100) ".00" (if (< f 1000) ".0" ".")))
                                (s f))))))))

    ; ---------------------------------------------------------------- seeding

    (method %digest (self name) (Hex decode-bytes (Sha256 hex name)))

    ; n x n booleans for parameter set p.  Each op maps a shifted cell
    ; coordinate pair to an integer; bit k of the result decides whether the
    ; cell is lit.  a, b are small odd multipliers, s a per-name salt.  Masked
    ; to 32 bits so the twin agrees.  The op is a local fn: per cell, no
    ; dispatch.
    (method %field (self p n)
      (def op (p get 'op))
      (def a (p get 'a))
      (def b (p get 'b))
      (def s (p get 'salt))
      (def k (p get 'bit))
      (def ox (p get 'ox))
      (def oy (p get 'oy))
      (def half (/ n 2))
      (def f
        (fn (_ x y)
          (match
            ((= op 0) (^ (^ (* x a) (* y b)) s))
            ((= op 1) (^ (& (* x a) (* y b)) s))
            ((= op 2) (^ (| (* x a) (* y b)) s))
            ((= op 3) (^ (+ (* (* x x) a) (* (* y y) b)) s))
            ((= op 4) (^ (^ (+ (* x a) (* y b)) (* x y)) s))
            (#t (^ (^ (* (* x y) a) (* (+ x y) b)) s)))))
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
                        (= 1 (& (>> (& (f x y) 4294967295) k) 1)))
                      racc))))
              acc)))))

    ; A field is asked for more than once per picture (the gate, the count,
    ; the ground); remember each grid size on the params.
    (method %field-of (self p n)
      (def key (%str-concat (list "field-" (Io display-to-str n))))
      (if (p has? key) (p get key)
        (let ((rows (self %field p n)))
          (p set! key rows)
          rows)))

    (method %lit (self rows)
      (let go ((rs rows) (n 0))
        (if (null? rs) n
          (go (rest rs)
              (+ n (let cnt ((cs (first rs)) (m 0))
                     (if (null? cs) m (cnt (rest cs) (if (first cs) (+ m 1) m)))))))))

    (method %formula (self op a b)
      (def sa (Io display-to-str a))
      (def sb (Io display-to-str b))
      (match
        ((= op 0) (%str-concat (list "(x*" sa ") ^ (y*" sb ")")))
        ((= op 1) (%str-concat (list "(x*" sa ") & (y*" sb ")")))
        ((= op 2) (%str-concat (list "(x*" sa ") | (y*" sb ")")))
        ((= op 3) (%str-concat (list "x*x*" sa " + y*y*" sb)))
        ((= op 4) (%str-concat (list "(x*" sa " + y*" sb ") ^ (x*y)")))
        (#t (%str-concat (list "(x*y*" sa ") ^ (x+y)*" sb)))))

    ; The lit fraction must read as a texture: sparse and dense are both
    ; fine (they are the variety); only under 18% or over 82% is rejected.
    (method %gate-ok? (self p)
      (def n (p get 'n))
      (def lit (self %lit (self %field-of p n)))
      (if (>= (* lit 100) (* 18 (* n n))) (<= (* lit 100) (* 82 (* n n))) #f))

    (method params (self (param name STRING "The project's name"))
      (doc "The traits sha256(name) settles: hue (tenths), operator, sampled bit, multipliers, offset, salt, grid; then the gate walk (bit, then op) until the field reads as a texture."
        (returns DICT "'name 'hue10 'op 'bit 'a 'b 'ox 'oy 'salt 'n 'lit 'opname 'formula")
        (example "((Bitwise params \"x-lang\") get 'formula)" "\"(x*11) ^ (y*15) >> 3 & 1\""))
      (def h (self %digest name))
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
      (p set! 'n (List ref (Num modulo (b 9) 4) (Bitwise %grids)))
      (let walk ((step 0))
        (if (< step 24)
          (unless (self %gate-ok? p)
            (p del! (%str-concat (list "field-" (Io display-to-str (p get 'n)))))
            (p set! 'bit (+ 1 (Num modulo (p get 'bit) 4)))
            (when (= (Num modulo step 4) 3)
              (p set! 'op (Num modulo (+ (p get 'op) 1) 6)))
            (walk (+ step 1)))))
      (p set! 'lit (self %lit (self %field-of p (p get 'n))))
      (p set! 'opname (List ref (p get 'op) (Bitwise %ops)))
      (p set! 'formula
        (%str-concat (list (self %formula (p get 'op) (p get 'a) (p get 'b)) " >> " (Io display-to-str (p get 'bit)) " & 1")))
      p)

    ; ---------------------------------------------------------------- colour

    (method %hue-str (self hue10)
      (%str-concat (list (Io display-to-str (/ hue10 10)) "." (Io display-to-str (Num modulo hue10 10)))))
    (method %hsl (self h s l)
      (%str-concat (list "hsl(" h "," (Io display-to-str s) "%," (Io display-to-str l) "%)")))
    (method %hsl3 (self t)
      (self %hsl (Io display-to-str (List ref 0 t)) (List ref 1 t) (List ref 2 t)))

    ; Colours: the hashed hue, unless the costume names its own.
    (method %palette (self p lang)
      (def hue (self %hue-str (p get 'hue10)))
      (def acc (if (lang has? "accent") (lang get "accent") #f))
      (def accent (if acc (self %hsl3 acc) (self %hsl hue 58 46)))
      (def pal (Dict make))
      (pal set! 'accent accent)
      (pal set! 'deep
        (if acc (self %hsl (Io display-to-str (List ref 0 acc)) (List ref 1 acc) (/ (* (List ref 2 acc) 65) 100))
          (self %hsl hue 55 30)))
      (pal set! 'eyes
        (if (lang has? "eyes") (List map (fn (_ e) (Bitwise %hsl3 e)) (lang get "eyes")) (list accent accent)))
      (pal set! 'secondary (if (lang has? "secondary") (self %hsl3 (lang get "secondary")) accent))
      pal)

    (method %colour (self pal role)
      (match
        ((str=? role "e") (List ref 0 (pal get 'eyes)))
        ((str=? role "f") (List ref 1 (pal get 'eyes)))
        ((str=? role "a") (pal get 'accent))
        ((str=? role "b") (pal get 'secondary))
        (#t (Bitwise %ink))))

    ; ---------------------------------------------------------------- the owl

    ; A row is bytes; the owl's glyphs are characters.  Split on UTF-8 leads.
    (method %glyph-list (self s)
      (def len (Str8 length s))
      (let go ((i 0) (acc ()))
        (if (>= i len) (%reverse acc)
          (let ((b (Char ->int (Str8 ref i s))))
            (let ((w (if (< b 128) 1 (if (< b 224) 2 (if (< b 240) 3 4)))))
              (go (+ i w) (pair (Str8 sub i w s) acc)))))))
    (method %chars (self s) (%length (self %glyph-list s)))
    ; The first n characters of s.
    (method %glyph-take (self s n)
      (%str-concat (let go ((gs (self %glyph-list s)) (i 0) (acc ()))
                     (if (if (null? gs) #t (>= i n)) (%reverse acc) (go (rest gs) (+ i 1) (pair (first gs) acc))))))
    ; Drop trailing bytes that are in chars.
    (method %rstrip (self s chars)
      (let go ((e (Str8 length s)))
        (if (= e 0) ""
          (if (Str8 includes? (Str8 sub (- e 1) 1 s) chars) (go (- e 1)) (Str8 sub 0 e s)))))
    (method %words (self t)
      (List filter (fn (_ w) (not (str=? w ""))) (Str8 split " " t)))

    ; (rows roles): the glyph rows and, per glyph, who colours it --
    ; i ink, e/f the two eyes, a accent, b the secondary colour.
    (method %costume (self lang)
      (list (List map (fn (_ r) (Bitwise %glyph-list r)) (if (lang has? "rows") (lang get "rows") (Bitwise %sigil)))
            (List map (fn (_ r) (Bitwise %glyph-list r)) (if (lang has? "roles") (lang get "roles") (Bitwise %sigil-roles)))))

    (method %cols (self rows)
      (let go ((rs rows) (m 0)) (if (null? rs) m (go (rest rs) (Num max m (%length (first rs)))))))

    ; The owl set from outlines.  (x-u, y-u) is the block's top-left and k
    ; the micro-units per font unit; glyph paths are declared once each, by
    ; index.  One dispatch per glyph for the coordinates, none per byte.
    (method %owl (self pal rows roles uid x-u y-u k)
      (def d (self %data))
      (def adv (d get 'adv))
      (def asc (d get 'asc))
      (def line (d get 'line))
      (def gix (d get 'gix))
      (def gmap (d get 'gmap))
      (def used ())
      (def groups (Dict make))
      (def ks (self %fmt k 4))
      (let rl ((rs rows) (ro roles) (row 0))
        (unless (null? rs)
          (let ((base (+ y-u (* (+ asc (* row line)) k))))
            (let cl ((cs (first rs)) (os (first ro)) (col 0))
              (unless (null? cs)
                (let ((ch (first cs)) (role (first os)))
                  (unless (str=? ch " ")
                    (unless (%member-str? ch used) (set! used (pair ch used)))
                    (groups set! role
                      (pair (%str-concat (list "<use href=\"#" uid "-" (Io display-to-str (gix get ch))
                                               "\" transform=\"translate(" (self %fmt (+ x-u (* (* col adv) k)) 2)
                                               "," (self %fmt base 2) ") scale(" ks ",-" ks ")\"/>"))
                            (groups get-or (list) role)))))
                (cl (rest cs) (rest os) (+ col 1)))))
          (rl (rest rs) (rest ro) (+ row 1))))
      (def defs
        (%str-concat (List map (fn (_ c) (%str-concat (list "<path id=\"" uid "-" (Io display-to-str (gix get c)) "\" d=\"" (gmap get c) "\"/>")))
                       (%reverse used))))
      (%str-concat
        (list "<defs>" defs "</defs>"
          (%str-concat (List map (fn (_ r)
                                   (if (groups has? r)
                                     (%str-concat (list "<g fill=\"" (Bitwise %colour pal r) "\">" (%str-concat (%reverse (groups get r))) "</g>"))
                                     ""))
                         (list "i" "e" "f" "a" "b"))))))

    ; The owl centred in the box at (x, y) of bw x bh user units.
    (method %owl-in (self pal lang uid x y bw bh)
      (def d (self %data))
      (def U (Bitwise %U))
      (def upm (d get 'upm))
      (def cr (self %costume lang))
      (def rows (first cr))
      (def roles (first (rest cr)))
      (def n (%length rows))
      (def cols (self %cols rows))
      (def size-u (Num min (/ (* bh (* upm U)) (* n (d get 'line)))
                           (/ (* bw (* upm U)) (* cols (d get 'adv)))))
      (def k (/ size-u upm))
      (def w-u (* (* cols (d get 'adv)) k))
      (def h-u (* (* n (d get 'line)) k))
      (self %owl pal rows roles uid
        (+ (* x U) (/ (- (* bw U) w-u) 2))
        (+ (* y U) (/ (- (* bh U) h-u) 2))
        k))

    ; The field: the name's bit function, one square per lit cell.
    ; Coordinates are formatted once per column and once per row.
    (method %bitfield (self p cols rows-n cell-u color opacity)
      (def rows (self %field-of p (Num max cols rows-n)))
      (def inset (/ (* cell-u 3) 10))
      (def ws (self %fmt (- cell-u (* 2 inset)) 1))
      (def coords
        (let go ((i 0) (acc ()))
          (if (>= i (Num max cols rows-n)) (%reverse acc)
            (go (+ i 1) (pair (Bitwise %fmt (+ (* i cell-u) inset) 1) acc)))))
      (def cells
        (let rl ((rs rows) (ys coords) (j 0) (acc ()))
          (if (>= j rows-n) acc
            (rl (rest rs) (rest ys) (+ j 1)
                (let cl ((cs (first rs)) (xs coords) (i 0) (acc acc))
                  (if (>= i cols) acc
                    (cl (rest cs) (rest xs) (+ i 1)
                        (if (first cs)
                          (pair (%str-concat (list "<rect x=\"" (first xs) "\" y=\"" (first ys)
                                                   "\" width=\"" ws "\" height=\"" ws "\"/>"))
                                acc)
                          acc))))))))
      (%str-concat (list "<g fill=\"" color "\" fill-opacity=\"" opacity "\">" (%str-concat (%reverse cells)) "</g>")))

    ; ---------------------------------------------------------------- formats

    (method %svg-open (self w h title)
      (%str-concat (list "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" (Io display-to-str w) "\" height=\"" (Io display-to-str h)
                         "\" viewBox=\"0 0 " (Io display-to-str w) " " (Io display-to-str h) "\" role=\"img\" aria-label=\"" (self %esc title) "\">")))

    (method %mark (self p pal lang uid)
      (def n (p get 'n))
      (%str-concat
        (list "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" width=\"512\" height=\"512\" role=\"img\" aria-label=\"Bitwise, "
              (self %esc (p get 'name)) "\">"
              (self %bitfield p n n (/ (* 100 (Bitwise %U)) n) (pal get 'accent) "0.22")
              (self %owl-in pal lang uid 6 8 88 84)
              "</svg>")))

    (method %avatar (self p pal lang uid)
      (%str-concat
        (list (self %svg-open 512 512 (%str-concat (list "Bitwise, " (p get 'name))))
              "<rect width=\"512\" height=\"512\" fill=\"" (Bitwise %paper) "\"/>"
              (self %bitfield p 16 16 (* 32 (Bitwise %U)) (pal get 'accent) "0.14")
              (self %owl-in pal lang uid 40 56 432 400)
              "</svg>")))

    ; Greedy wrap to width characters, at most four lines, an ellipsis if
    ; cut.  The current line's length rides along.
    (method %wrap (self text width)
      (def lines
        (let go ((ws (self %words text)) (cur "") (cur-n 0) (acc ()))
          (if (null? ws) (%reverse (if (= cur-n 0) acc (pair cur acc)))
            (let ((w (first ws)))
              (let ((wn (Bitwise %chars w)))
                (if (if (= cur-n 0) #f (> (+ cur-n (+ 1 wn)) width))
                  (go (rest ws) w wn (pair cur acc))
                  (go (rest ws) (if (= cur-n 0) w (%str-concat (list cur " " w))) (if (= cur-n 0) wn (+ cur-n (+ 1 wn))) acc)))))))
      (if (> (%length lines) 4)
        (list (List ref 0 lines) (List ref 1 lines) (List ref 2 lines)
              (%str-concat (list (self %rstrip (self %glyph-take (List ref 3 lines) (- width 1)) ",;: ") "\xe2\x80\xa6")))
        lines))

    (method %text (self x y size fill extra body)
      (%str-concat (list "<text x=\"" (Io display-to-str x) "\" y=\"" (Io display-to-str y) "\" font-family=\"" (Bitwise %font)
                         "\" font-size=\"" (Io display-to-str size) "\"" extra " fill=\"" fill "\">" (self %esc body) "</text>")))

    (method %banner (self p pal lang tagline kind uid)
      (def x 560)
      (def name (p get 'name))
      (def nlen (self %chars name))
      (def fs (if (<= nlen 10) 96 (if (<= nlen 14) 72 56)))
      (def tag-lines
        (let go ((ls (self %wrap tagline 42)) (y 356) (acc ()))
          (if (null? ls) (%reverse acc)
            (go (rest ls) (+ y 36) (pair (Bitwise %text x y 26 (Bitwise %ink) "" (first ls)) acc)))))
      (def colour
        (if (lang has? "logo") (lang get "logo")
          (%str-concat (list "hue " (Io display-to-str (/ (p get 'hue10) 10)) "&#176;"))))
      (%str-concat
        (list (self %svg-open 1280 640 (%str-concat (list name ", with Bitwise")))
              "<rect width=\"1280\" height=\"640\" fill=\"" (Bitwise %paper) "\"/>"
              (self %bitfield p 40 20 (* 32 (Bitwise %U)) (pal get 'accent) "0.09")
              (self %owl-in pal lang uid 60 90 440 460)
              (self %text x 200 20 (pal get 'deep) " letter-spacing=\"4\"" (Str8 upcase (if (str=? kind "") "an x project" kind)))
              (self %text x 300 fs (Bitwise %ink) " font-weight=\"700\"" name)
              (%str-concat tag-lines)
              (if (lang has? "reference")
                (self %text x 524 24 (pal get 'deep) " xml:space=\"preserve\"" (lang get "reference"))
                "")
              "<text x=\"" (Io display-to-str x) "\" y=\"580\" font-family=\"" (Bitwise %font) "\" font-size=\"15\" fill=\"" (pal get 'deep)
              "\">plumage  " (self %esc (p get 'formula)) "   " colour "</text>"
              "</svg>")))

    ; ---------------------------------------------------------------- entry

    (method %lang-of (self name)
      (def cs (self %costumes))
      (if (cs has? name) (cs get name) (Dict make)))

    (method render (self (param name STRING "The project's name")
                         (param fmt STRING "mark, avatar or banner")
                         (param tagline STRING "One sentence for the banner; may be empty")
                         (param kind STRING "The banner's eyebrow, e.g. \"a language on x-lang\"; empty for the default")
                         (param uid STRING "Prefix for the SVG ids, so several pictures can share a page"))
      (doc "Draw the project: (svg . params).  The owl is set from outlines, the field and hue from sha256(name), the costume from whatever (Bitwise costume-load! ...) registered for the name."
        (returns PAIR "The SVG text, then the params Dict with 'costume and 'reference added")
        (example "(Str8 sub 0 4 (first (Bitwise render \"x-lang\" \"mark\" \"\" \"\" \"o\")))" "\"<svg\""))
      (def p (self params name))
      (def lang (self %lang-of name))
      (def pal (self %palette p lang))
      (p set! 'costume (if (lang has? "mascot") (lang get "mascot") (if (lang has? "logo") (lang get "logo") "")))
      (p set! 'reference (if (lang has? "reference") (lang get "reference") ""))
      (pair
        (match
          ((str=? fmt "mark") (self %mark p pal lang uid))
          ((str=? fmt "avatar") (self %avatar p pal lang uid))
          ((str=? fmt "banner") (self %banner p pal lang tagline kind uid))
          (#t (Err raise 'value (%str-concat (list "bitwise: unknown format " fmt)) ())))
        p))

    (method diff (self (param a STRING "A rendering") (param b STRING "Another"))
      (doc "#t when the two renderings are the same bytes, else (differ-at OFFSET WINDOW-A WINDOW-B).  A native compare, then a binary search over prefixes -- a byte loop over a 60KB picture costs more in pure x than drawing it."
        (returns ANY "#t, or a list naming the first difference")
        (example "(Bitwise diff \"same\" \"same\")" "#t"))
      (if (str=? a b) #t
        (let ((n (Num min (Str8 length a) (Str8 length b))))
          (let go ((lo 0) (hi n))
            (if (>= lo hi)
              (list 'differ-at lo
                    (Str8 sub (Num max 0 (- lo 30)) (Num min 70 (- (Str8 length a) (Num max 0 (- lo 30)))) a)
                    (Str8 sub (Num max 0 (- lo 30)) (Num min 70 (- (Str8 length b) (Num max 0 (- lo 30)))) b))
              (let ((mid (/ (+ lo hi 1) 2)))
                (if (str=? (Str8 sub 0 mid a) (Str8 sub 0 mid b)) (go mid hi) (go lo (- mid 1)))))))))))

(provide bitwise/gen Bitwise)
