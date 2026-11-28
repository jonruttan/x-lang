# Tui: styled-cell screen, Markdown page, windows, tabs and pictures
# @weight 1

## Width

### no C pointer is held until a text is measured, so a state image can carry the module

```x
(import x/tui/width)
(write (null? (eval (lit %wd-strspn) (module x/tui/width))))
```
---
    #t

### columns of code points and strings

Wide CJK and emoji take two columns, combining marks and controls none.

```x
(do (import x/tui/width)
  (list (Width char 65) (Width char 20013) (Width char 769) (Width char 10) (Width char 128512)
        (Width text "a中b") (Width text "café") (Width text "")))
```
---
    (1 2 0 0 2 4 4 0)

## Style

### attributes and colours packed, and the SGR that sets them

```x
(do (import x/tui/style)
  (list (Style sgr (Style make '(bold underline) 4 ())) (Style make '(italic) () ()) (Style make () 1 ())
        (Style with (Style make '(bold) () ()) '(reverse)) (Style has? 9 'underline) (Style fg (Style make () 12 ()))
        (Style bg (Style make () () 200)) (Style sgr 0) (Style sgr (Style make '(dim) 9 200)) (Style fg 0)))
```
---
    ("\x1b[0;1;4;34m" 4 512 17 #t 12 200 "\x1b[0m" "\x1b[0;2;91;48;5;200m" ())

## Screen

### the first render draws every row, later ones only the changed cells

A wide character over half of another blanks the half left behind; a row that ends blank is erased to its end.

```x
(do (import x/tui/screen) (import x/tui/style)
  (def s (Screen make 2 5))
  (Screen put s 0 0 "ab" (Style make '(bold) () ()))
  (def r1 (Screen render s))
  (def r2 (Screen render s))
  (Screen put s 1 2 "x中y" 0)
  (def r3 (Screen render s))
  (Screen put s 1 4 "z" 0)
  (def r4 (Screen render s))
  (Screen put s 1 1 "Q" 0)
  (list r1 r2 r3 r4 (Screen render s) (Screen row-text s 0) (Screen row-text s 1)
        (Screen put s 0 3 "中中" 0) (Screen row-text s 0)))
```
---
    ("\x1b[0m\x1b[H\x1b[2J\x1b[1;1H\x1b[0;1mab\x1b[0m\x1b[K\x1b[2;1H\x1b[K\x1b[0m\x1b[1;1H" "" "\x1b[2;3H\x1b[0mx中\x1b[0m\x1b[1;1H" "\x1b[2;4H\x1b[0m z\x1b[0m\x1b[1;1H" "\x1b[2;2H\x1b[0mQ\x1b[0m\x1b[1;1H" "ab   " " Qx z" 5 "ab 中")

### rows the terminal shows a row away are scrolled, not written

The rows moved up a row are deleted a line in a scroll region, and only the row they leave is written; moved down, a line is inserted.

```x
(do (import x/tui/screen)
  (def s (Screen make 6 3))
  (def rows! (fn (_ l) ((fn (go r l) (if (null? l) () (do (Screen put s r 0 (first l) 0) (go (+ r 1) (rest l))))) 0 l)))
  (rows! '("a" "b" "c" "d" "e" "f"))
  (Screen render s)
  (rows! '("b" "c" "d" "e" "f" "g"))
  (def up (Screen render s))
  (rows! '("x" "b" "c" "d" "e" "f"))
  (list up (Screen render s) (Screen render s) (Screen row-text s 0) (Screen row-text s 5)))
```
---
    ("\x1b[0m\x1b[1;6r\x1b[1;1H\x1b[1M\x1b[r\x1b[6;1Hg\x1b[0m\x1b[1;1H" "\x1b[0m\x1b[1;6r\x1b[1;1H\x1b[1L\x1b[r\x1b[1;1Hx\x1b[0m\x1b[1;1H" "" "x  " "f  ")

### a put at or past the right edge puts nothing and answers its column

On the last row, where the cells end, and on a row above a wide character the next row starts with: the cells and the next render are unchanged.

```x
(do (import x/tui/screen)
  (def s (Screen make 2 4))
  (Screen put s 0 0 "abcd" 0)
  (Screen put s 1 0 "中ab" 0)
  (Screen render s)
  (list (Screen put s 1 4 "x" 0) (Screen put s 1 9 "y" 0) (Screen put s 0 5 "z" 0) (Screen put s 1 -1 "w" 0)
        (Screen fill s 1 4 3 16) (Screen render s) (Screen row-text s 0) (Screen row-text s 1)))
```
---
    (4 9 5 -1 () "" "abcd" "中ab")

## Page

### Markdown laid out at a width: wrapping, quotes, lists, code, rules, links

```x
(do (import x/codec/markdown) (import x/tui/page)
  (def tui-doc "# Title here\n\nSome *emph* and **strong** text with `code` and a [link to x](/x \"t\") that wraps around.\n\n> quoted *line* that is long enough to wrap\n\n- one\n- two\n  1. sub\n  2. subtwo\n\n```\ncode\tblock\n```\n\n---\n\nAn ![alt](/i.png) and averyveryverylongwordthatmustbreak.")
  (def p (Page markdown (Markdown parse tui-doc) 24))
  (list (List map (fn (_ i) (Page line-text p i)) (List range 0 (Page count p)))
        (Page links p) (Page line p 2)))
```
---
    (("Title here" "" "Some emph and strong" "text with code and a" "link to x that wraps" "around." "" "│ quoted line that is" "│ long enough to wrap" "" "• one" "• two" "  1. sub" "  2. subtwo" "" "code    block" "" "────────────────────────" "" "An [alt] and" "averyveryverylongwordtha" "tmustbreak.") (("/x" "t" ((4 0 9))) ("/i.png" () ((19 3 5)))) (("Some" 0 ()) (" " 0 ()) ("emph" 4 ()) (" " 0 ()) ("and" 0 ()) (" " 0 ()) ("strong" 1 ())))

### a form's fields are drawn as lynx draws them, each in one piece, numbered with the links; a hidden field is not drawn; a button with an empty value is Submit

```x
(do (import x/codec/html) (import x/tui/page) (import x/tui/window)
  (def p (Page markdown (Html parse "<form action=/s><p>Name: <input name=n value=\"Ann Lee\"> <input type=password name=p value=abc><br><input type=checkbox name=c checked> yes <input type=radio name=r> no <select name=s><option value=1>One<option value=2 selected>Two</select> <input type=hidden name=h value=1><button name=b value=1>Go now</button> <a href=/u>u</a> <input type=submit value=\"\"></p></form>") 30))
  (def w (Window make "f" p))
  (list (List map (fn (_ i) (Page line-text p i)) (List range 0 (Page count p)))
        (List map (fn (_ l) (list (if (str? (first l)) (first l) (List ref 2 (first l))) (List ref 2 l))) (Page links p))
        (Window next-link w 5) (Window next-link w 5) (first (first (Window link w))) (Window prev-link w 5)))
```
---
    (("Name: Ann Lee_____________" "***_________________" "[X] yes ( ) no [Two] [Go now]" "u [Submit]") (("n" ((0 6 20))) ("p" ((1 0 20))) ("c" ((2 0 3))) ("r" ((2 8 3))) ("s" ((2 15 5))) ("b" ((2 21 8))) ("/u" ((3 0 1))) (() ((3 2 8)))) 0 1 'field 0)

### a table is a grid: its columns as wide as their widest cells when they fit, sharing the width when they do not, a rule under a header row, a column aligned, a link in a cell numbered in reading order

```x
(do (import x/codec/html) (import x/tui/page)
  (def b (Html parse "<table><caption>Cap</caption><thead><tr><th>Name<th align=right>Count</thead><tr><td>apples and pears<td>12<tr><td><a href=/x>x</a><td>3</table><p><a href=/y>y</a>"))
  (def lines (fn (_ p) (List map (fn (_ i) (Page line-text p i)) (List range 0 (Page count p)))))
  (list (lines (Page markdown b 30)) (lines (Page markdown b 14))
        (List map (fn (_ l) (list (first l) (List ref 2 l))) (Page links (Page markdown b 30)))))
```
---
    (("Cap" "" "Name             │ Count" "─────────────────┼──────" "apples and pears │    12" "x                │     3" "" "y") ("Cap" "" "Name   │ Count" "───────┼──────" "apples │    12" "and    │ " "pears  │ " "x      │     3" "" "y") (("/x" ((5 0 1))) ("/y" ((7 0 1)))))

### plain text keeps its spaces and expands tabs

```x
(do (import x/tui/page)
  (def p (Page text "a  b\tc\n\nd" 20))
  (list (Page count p) (Page line-text p 0) (Page line-text p 1) (Page line-text p 2)))
```
---
    (3 "a  b    c" "" "d")

### a page of many thousand lines is laid out, text or blocks: no walk over its lines waits a call a line

```x
(do (import x/tui/page)
  (def t (Page text (Str8 join "" (List map (fn (_ i) (Str8 append (%number->str i) "\n")) (List range 0 12000))) 80))
  (def m (Page markdown (List map (fn (_ i) (list 'paragraph (list (%number->str i)))) (List range 0 6000)) 80))
  (list (Page count t) (Page line-text t 11999) (Page count m) (Page line-text m 11998)))
```
---
    (12000 "11999" 11999 "5999")

## Window and Tabs

### links selected in turn scroll into view; the bar lists the tabs

```x
(do (import x/codec/markdown) (import x/tui/page) (import x/tui/window) (import x/tui/tabs) (import x/tui/screen)
  (def p (Page markdown (Markdown parse "[a](/a)\n\nb\n\nc\n\nd [e](/e)\n\nf\n\ng [h](/h)") 20))
  (def w (Window make "Doc" p))
  (def t (Tabs make))
  (Tabs add t w)
  (Tabs add t (Window make "Second tab" (Page text "plain\ttext" 20)))
  (def s (Screen make 4 20))
  (def moves (list (Tabs prev t) (Window next-link w 3) (Window next-link w 3) (Window top w)
                   (Window next-link w 3) (Window top w) (Window next-link w 3) (first (Window link w))
                   (Window prev-link w 3) (Window scroll w -9 3) (Window scroll w 99 3)))
  (Tabs draw t s 0 4)
  (list moves (List map (fn (_ r) (Screen row-text s r)) (list 0 1 2 3))
        (Screen style-at s 0 1) (Screen style-at s 0 12) (Tabs close t 0) (Tabs count t) (Window title (Tabs current t))))
```
---
    ((0 0 1 4 2 8 () "/h" 1 0 8) (" 1 Doc     2 Second " "f                   " "                    " "g h                 ") 1 16 0 1 "Second tab")

### a link that takes no place on the page is passed over, on a page of a few hundred lines

An empty link, and a link whose only text is an image's (the image's link
takes the place), have no spans: next-link and prev-link pass them over,
select of one selects none, and the page lays out, scrolls and draws.

```x
(do (import x/codec/markdown) (import x/tui/page) (import x/tui/window) (import x/tui/screen) (import x/tui/style)
  (def tui-long (Str8 join "\n\n"
    (pair "[![logo](/logo.png)](/home)"
          (List map (fn (_ n) (Str8 append "[](/e" (%number->str n) ") para " (%number->str n)
                                           " [l" (%number->str n) "](/l" (%number->str n) ")"))
                    (List range 1 160)))))
  (def p (Page markdown (Markdown parse tui-long) 30))
  (def w (Window make "Long" p))
  (def s (Screen make 5 30))
  (def moves (list (Window next-link w 5) (Window next-link w 5) (Window prev-link w 5) (Window prev-link w 5)
                   (Window selected w) (Window select w 0 5) (Window selected w) (Window select w 999 5)
                   (Window select w 319 5) (Window top w) (Window next-link w 5) (Window prev-link w 5)
                   (Window top w) (Window go w 0 5) (Window select w () 5) (Window prev-link w 5)))
  (Window draw w s 0 5)
  (list (Page count p) (List length (Page links p)) (List ref 0 (Page links p)) moves
        (List map (fn (_ r) (Str8 trim-right (Screen row-text s r))) (list 0 1 2 3 4))
        (Style has? (Screen style-at s 4 0) 'reverse) (Style has? (Screen style-at s 4 7) 'reverse)))
```
---
    (319 320 ("/home" () ()) (1 3 1 () 1 () () () 319 314 () 317 314 0 () 5) ("[logo]" "" "para 1 l1" "" "para 2 l2") #f #t)

## Panes

### a screen pasted on another is clipped at its edges, a wide character cut by either blanked

```x
(do (import x/tui/screen)
  (def s (Screen make 3 6))
  (Screen put s 0 0 "中中中" 0)
  (Screen put s 1 0 "abcdef" 0)
  (def p (Screen make 2 4))
  (Screen put p 0 0 "xy" 0)
  (Screen put p 1 0 "z中w" 0)
  (Screen paste s 0 1 p)
  (def q (Screen make 1 4))
  (Screen put q 0 0 "ab中" 0)
  (Screen paste s 2 3 q)
  (Screen paste s 5 0 q) (Screen paste s 0 9 q) (Screen paste s 0 -1 q)
  (list (Screen row-text s 0) (Screen row-text s 1) (Screen row-text s 2)))
```
---
    (" xy   " "az中wf" "   ab ")

### a side takes the width it wants up to a quarter of the columns, none under 8; the focus goes only to a shown pane

```x
(do (import x/tui/panes)
  (def p (Panes make))
  (def a (Panes columns p 80))
  (Panes toggle! p 'left) (Panes show! p 'right #t) (Panes width! p 'right 12)
  (def b (Panes columns p 80))
  (def c (Panes columns p 30))
  (def f (list (Panes focus-next! p) (Panes focus-next! p) (Panes focus-next! p) (Panes focus-next! p)))
  (Panes show! p 'right #f)
  (list a b c f (Panes focus p) (Panes focus! p 'right) (Panes focus! p 'left) (Panes columns p 80)))
```
---
    ((('main 0 80)) (('left 0 19) ('main 20 47) ('right 68 12)) (('main 0 30)) ('right 'left 'main 'right) 'main 'main 'left (('left 0 19) ('main 20 60)))

### each pane is drawn on a screen of its own, kept while its size is, with a bar beside it bold when its side has the focus

```x
(do (import x/tui/panes) (import x/tui/screen)
  (def s (Screen make 3 40))
  (def p (Panes make))
  (Panes show! p 'left #t) (Panes show! p 'right #t) (Panes width! p 'left 8)
  (Panes focus! p 'right)
  (Panes draw p s 1 2
    (fn (_ pane sub) (Screen put sub 0 0 (match ((eq? pane 'left) "left side") ((eq? pane 'main) "main") (#t "right")) 0)))
  (def first-draw (List map (fn (_ r) (Screen row-text s r)) (list 0 1 2)))
  (def bars (list (Screen style-at s 1 8) (Screen style-at s 1 30)))
  (Panes draw p s 1 2 (fn (_ pane sub) ()))
  (def kept (Screen row-text s 1))
  (Panes width! p 'left 10)
  (Panes draw p s 1 2 (fn (_ pane sub) ()))
  (list first-draw bars kept (Screen row-text s 1)))
```
---
    (("                                        " "left sid│main                 │right    " "        │                     │         ") (0 1) "left sid│main                 │right    " "         │                    │right    ")

## Picture

### an image is fitted to the cells it is given, its shape kept, never grown

A cell is two pixels tall, so ROWS cells hold twice ROWS pixels.

```x
(do (import x/tui/picture)
  (list (Picture fit 640 480 80 24) (Picture fit 16 16 80 24) (Picture fit 100 10 20 24) (Picture fit 10 100 80 5)))
```
---
    ((64 48) (16 16) (20 2) (1 10))

### a cell is the pixel above in the foreground and the pixel below in the background; a transparent one is the terminal's

Red over blue, green over nothing, nothing over yellow, nothing over nothing:
an upper half block, an upper alone, a lower alone, a space.  The colours
are set again only where they change.

```x
(do (import x/tui/picture) (import x/codec/bytes)
  (def px (Bytes of-list (list 255 0 0 255  0 255 0 255  0 0 0 0  0 0 0 0
                               0 0 255 255  0 0 0 0  255 255 0 255  0 0 0 0)))
  (Picture lines (list 4 2 (first px)) 80 24 'rgb))
```
---
    ("\x1b[0;38;2;255;0;0;48;2;0;0;255m▀\x1b[0;38;2;0;255;0m▀\x1b[0;38;2;255;255;0m▄\x1b[0m \x1b[0m")

### a shrunk image averages the pixels each one covers

Red and blue side by side drawn one pixel wide: their average.

```x
(do (import x/tui/picture) (import x/codec/bytes)
  (Picture lines (list 2 1 (first (Bytes of-list (list 255 0 0 255 0 0 255 255)))) 1 1 'rgb))
```
---
    ("\x1b[0;38;2;127;0;127m▀\x1b[0m")

### the 256-colour palette: the nearest of the cube's colours and the greys

Pure red is the cube's 196; a mid grey is the grey ramp's 244, nearer than
the cube's grey.

```x
(do (import x/tui/picture) (import x/codec/bytes)
  (Picture lines (list 1 2 (first (Bytes of-list (list 255 0 0 255 128 128 128 255)))) 4 4 'indexed))
```
---
    ("\x1b[0;38;5;196;48;5;244m▀\x1b[0m")
