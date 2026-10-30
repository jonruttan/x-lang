# Tui: styled-cell screen, Markdown page, windows and tabs
# @weight 1

## Width

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

A wide character over half of another blanks the half left behind.

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
    ("\x1b[0m\x1b[H\x1b[2J\x1b[1;1H\x1b[0;1mab\x1b[0m   \x1b[2;1H     \x1b[0m\x1b[1;1H" "" "\x1b[2;3H\x1b[0mx中\x1b[0m\x1b[1;1H" "\x1b[2;4H\x1b[0m z\x1b[0m\x1b[1;1H" "\x1b[2;2H\x1b[0mQ\x1b[0m\x1b[1;1H" "ab   " " Qx z" 5 "ab 中")

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

### plain text keeps its spaces and expands tabs

```x
(do (import x/tui/page)
  (def p (Page text "a  b\tc\n\nd" 20))
  (list (Page count p) (Page line-text p 0) (Page line-text p 1) (Page line-text p 2)))
```
---
    (3 "a  b    c" "" "d")

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
