# Term: decoding a keystroke
# @weight 1

`Term key` takes a function that yields the next byte rather than a
descriptor, which is the whole reason a terminal's key decoding can be tested
here at all: a spec hands it a list and never opens a tty.

Each case below builds such a reader over a byte list. Four kinds come
back: a STRING of literal text to insert, a SYMBOL naming a key, a (mouse ...)
list once mouse! has asked for the mouse, or nil when
the input ended.

## Literal text

### an ASCII byte is the character to insert

```x
(do (import x/repl/term)
    (Term key (fn (_) 65)))
```
---
    "A"

### a two-byte UTF-8 sequence arrives whole

```x
(do (import x/repl/term)
    (let ((bs (list 195 169)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    "é"

### a three-byte sequence arrives whole

```x
(do (import x/repl/term)
    (let ((bs (list 226 130 172)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    "€"

### end of input is nil

```x
(do (import x/repl/term)
    (null? (Term key (fn (_) ()))))
```
---
    #t

## Control bytes carry readline's names

```x
(do (import x/repl/term)
    (List map (fn (_ b) (Term key (fn (_) b)))
          (list 1 2 3 4 5 6 9 13 10 11 21 23 25 127)))
```
---
    ('home 'left 'interrupt 'eof 'end 'right 'complete 'enter 'enter 'kill-eol 'kill-bol 'kill-word 'yank 'backspace)

### ctrl-g, ctrl-r and ctrl-s are the search keys

```x
(do (import x/repl/term)
    (List map (fn (_ b) (Term key (fn (_) b))) (list 7 18 19)))
```
---
    ('abort 'search-back 'search-forward)

### an unbound control byte is dropped, not inserted

A byte with no binding must never reach the buffer: the redraw measures what
it holds, and an unprintable byte has no width.

```x
(do (import x/repl/term)
    (Term key (fn (_) 24)))
```
---
    'unbound

### ctrl-v is quoted-insert

The key after it is inserted as text, whatever it would have done; the loop
in x/repl/line reads that key.

```x
(do (import x/repl/term)
    (Term key (fn (_) 22)))
```
---
    'quoted-insert

## Escape sequences

### the CSI arrows

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 65) (list 27 91 66) (list 27 91 67) (list 27 91 68))))
```
---
    ('up 'down 'right 'left)

### SS3 arrows, which a terminal in application-cursor mode sends instead

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 79 65) (list 27 79 68) (list 27 79 72) (list 27 79 70))))
```
---
    ('up 'left 'home 'end)

### Home, End and Delete in both their spellings

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 72) (list 27 91 70)
            (list 27 91 49 126) (list 27 91 52 126) (list 27 91 51 126))))
```
---
    ('home 'end 'home 'end 'delete)

### Page Up and Page Down

`ESC [ 5 ~` and `ESC [ 6 ~`, with or without a modifier after the number.

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 53 126) (list 27 91 54 126) (list 27 91 53 59 53 126))))
```
---
    ('page-up 'page-down 'page-up)

### the function keys in the spellings terminals send them

F1 to F4 as SS3 (`ESC O P` to `S`) and, with a modifier, as CSI with a
final `P` to `S`; every function key as `ESC [ N ~`, whose numbers skip 16
and 22.  N is read whole: `15~` is F5, not the Home that `1~` is.

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 79 80) (list 27 79 83) (list 27 91 49 59 50 81)
            (list 27 91 49 53 126) (list 27 91 49 55 126) (list 27 91 50 52 126)
            (list 27 91 49 53 59 50 126) (list 27 91 49 126))))
```
---
    ('f1 'f4 'f2 'f5 'f6 'f12 'f5 'home)

### keypad digits from a keypad in application mode

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 79 112) (list 27 79 117) (list 27 79 121))))
```
---
    ('kp0 'kp5 'kp9)

### a ctrl-modified arrow is word motion

The modifier arrives as `;5` among the parameter bytes, which is why the
parameters are kept rather than dropped at the final byte.

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 91 49 59 53 67) (list 27 91 49 59 53 68))))
```
---
    ('word-right 'word-left)

### meta-b and meta-f are the same two motions

```x
(do (import x/repl/term)
    (List map
      (fn (_ bs) (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
      (list (list 27 98) (list 27 102) (list 27 127))))
```
---
    ('word-left 'word-right 'kill-word)

### an escape that goes nowhere is 'escape, not a stray insert

```x
(do (import x/repl/term)
    (let ((bs (list 27)))
      (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b))))))
```
---
    'escape

## The mouse, once mouse! asks for it

An SGR report, ESC [ < B ; X ; Y and M or m, comes back as a list:
(mouse ACTION BUTTON ROW COL MODS), the row and column from 0.

### a press, a drag and a release of the left button

```x
(do (import x/repl/term)
    (import x/core/doors char->int)
    (def key-of (fn (_ s) (let ((bs (List map (fn (_ i) (char->int (Str8 ref i s))) (List range 0 (Str8 length s)))))
                            (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))))
    (List map key-of (list "\x1b[<0;10;3M" "\x1b[<32;12;3M" "\x1b[<0;12;3m")))
```
---
    (('mouse 'press 'left 2 9 ()) ('mouse 'drag 'left 2 11 ()) ('mouse 'release 'left 2 11 ()))

### the right and middle buttons, the wheel, a move with none held, and the modifiers

```x
(do (import x/repl/term)
    (import x/core/doors char->int)
    (def key-of (fn (_ s) (let ((bs (List map (fn (_ i) (char->int (Str8 ref i s))) (List range 0 (Str8 length s)))))
                            (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))))
    (List map key-of (list "\x1b[<2;1;1M" "\x1b[<1;1;1M" "\x1b[<64;5;6M" "\x1b[<65;5;6M" "\x1b[<35;7;8M" "\x1b[<28;1;1M")))
```
---
    (('mouse 'press 'right 0 0 ()) ('mouse 'press 'middle 0 0 ()) ('mouse 'wheel 'up 5 4 ()) ('mouse 'wheel 'down 5 4 ()) ('mouse 'move () 7 6 ()) ('mouse 'press 'left 0 0 ('shift 'alt 'ctrl)))

### a report cut short is no key

```x
(do (import x/repl/term)
    (def bs (list 27 91 60 48 59 49 77))
    (Term key (fn (_) (if (null? bs) () (let ((b (first bs))) (set! bs (rest bs)) b)))))
```
---
    'unbound

### mouse! writes the modes on, and off

```x
(do (import x/repl/term)
    (def fds (Sys pipe))
    (def n (list (Term mouse! (rest fds) #t) (Term mouse! (rest fds) #f)))
    (def got (Sys fd-read (first fds) 64))
    (Sys close (first fds)) (Sys close (rest fds))
    (list n (str=? (bytes->str got) "\x1b[?1002h\x1b[?1006h\x1b[?1006l\x1b[?1002l")))
```
---
    ((16 16) #t)

## Capability, without a terminal

### a pipe is not a tty, so raw! declines and restore! of nil is a no-op

The two together are what let a caller bracket a read unconditionally and
fall back when there is nothing to bracket.

```x
(do (import x/repl/term)
    (list (Term tty? 0) (null? (Term raw! 0)) (Term restore! 0 ())))
```
---
    (#f #t #f)

### raw-with-signals! declines a pipe the same way

```x
(do (import x/repl/term)
    (null? (Term raw-with-signals! 0)))
```
---
    #t

### the signal keys are ISIG alone, set in c_lflag and nothing else moved

A fresh string is space-filled, so every byte but ISIG's reads 32 after.

```x
(do (import x/repl/term)
    (let ((s ((prim-ref (lit str) (lit make)) 64)))
      (let ((p ((prim-ref (lit str) (lit ->ptr)) s))
            (pref (prim-ref (lit ptr) (lit ref)))
            (at (if os-darwin? 24 12))
            (isig (if os-darwin? 128 1)))
        (Term %isig-on! p)
        (list (= (pref p at 4) (| 538976288 isig))
              (= (pref p 0 4) 538976288)
              (= (pref p (+ at 4) 4) 538976288)))))
```
---
    (#t #t #t)

### measure is nil where there is no window to measure

```x
(do (import x/repl/term)
    (null? (Term measure 0)))
```
---
    #t

### window always answers, falling back rather than failing

```x
(do (import x/repl/term)
    (let ((s (Term window 0))) (and (> (first s) 0) (> (rest s) 0))))
```
---
    #t

### where there is no window to measure, COLUMNS and LINES are the window

```x
(do (import x/repl/term)
    (Sys setenv "COLUMNS" "101")
    (Sys setenv "LINES" "33")
    (Term window 0))
```
---
    (101 . 33)

### a COLUMNS that is no positive number is passed over

```x
(do (import x/repl/term)
    (Sys setenv "COLUMNS" "wide")
    (Sys setenv "LINES" "0")
    (Term window 0))
```
---
    (80 . 24)

## Modes by name, on a pseudo-terminal

A pseudo-terminal's slave is a terminal no one is typing at, so its modes
are the system's defaults and can be set and read back.

### a new terminal's modes: canonical, echoing, signalling, ^C its interrupt

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def m (Term modes s))
    (def r (List map (fn (_ k) (Assoc get k m)) (list 'icanon 'echo 'isig 'vintr 'cs8 'cs7)))
    (File close s) (File close (first p))
    (list r (> (Assoc get 'ospeed m) 0)))
```
---
    ((#t #t #t 3 #t #f) #t)

### modes set by name read back, in order, a name this OS lacks passed over

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def ok (Term modes! s (list (pair 'echo #f) (pair 'icrnl #f) (pair 'vintr 7) (pair 'verase ())
                                 (pair 'opost #f) (pair 'ispeed 19200) (pair 'ospeed 19200) (pair 'no-such-mode #t))))
    (def m (Term modes s))
    (def r (List map (fn (_ k) (Assoc get k m)) (list 'echo 'icrnl 'icanon 'vintr 'verase 'opost 'ispeed 'ospeed)))
    (File close s) (File close (first p))
    (list ok r))
```
---
    (#t (#f #f #t 7 () #f 19200 19200))

### cs7 then cs8, as an 8-bit terminal's request may carry both, ends at 8

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (Term modes! s (list (pair 'cs7 #t) (pair 'cs8 #t)))
    (def m (Term modes s))
    (def r (list (Assoc get 'cs7 m) (Assoc get 'cs8 m)))
    (File close s) (File close (first p))
    r)
```
---
    (#f #t)

### busybox's modes beyond RFC 4254's set and read back: counts, a delay field, a top bit

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def ok (Term modes! s (list (pair 'icanon #f) (pair 'vmin 5) (pair 'vtime 2) (pair 'tab3 #t)
                                 (pair 'brkint #t) (pair 'echoprt #t) (pair 'noflsh #t))))
    (def m (Term modes s))
    (def r (List map (fn (_ k) (Assoc get k m)) (list 'vmin 'vtime 'tab0 'tab3 'brkint 'echoprt 'noflsh)))
    (File close s) (File close (first p))
    (list ok r))
```
---
    (#t (5 2 #f #t #t #t #t))

### a field holds one setting: tab3 then tab1 leaves tab1 alone

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (Term modes! s (list (pair 'tab3 #t) (pair 'tab1 #t) (pair 'tab2 #f)))
    (def m (Term modes s))
    (def r (List map (fn (_ k) (Assoc get k m)) (list 'tab0 'tab1 'tab2 'tab3)))
    (File close s) (File close (first p))
    r)
```
---
    (#f #t #f #f)

### settings edited by name, applied, and read again

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def st (Term settings s))
    (def r1 (list (Term setting! st 'echo #f) (Term setting! st 'vkill 11) (Term setting! st 'no-such-mode #t)))
    (def before (Term setting (Term settings s) 'echo))
    (def ok (Term apply! s st))
    (def again (Term settings s))
    (def r2 (list (Term setting again 'echo) (Term setting again 'vkill) (Term setting again 'no-such-mode)))
    (File close s) (File close (first p))
    (list r1 before ok r2))
```
---
    ((#t #t #f) #t #t (#f 11 ()))

### words: four flag words then nccs bytes, and words! takes them back

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def w (Term words (Term settings s)))
    (def st (Term settings s))
    (Term setting! st 'icanon #f)
    (def changed (Term words st))
    (def back (Term words! st w))
    (def short (Term words! st (list 1 2 3)))
    (def r (list (= (List length w) (+ 4 (Term nccs))) (eq? (List ref 3 w) (List ref 3 changed))
                 back short (= (List ref 3 (Term words st)) (List ref 3 w))))
    (File close s) (File close (first p))
    r)
```
---
    (#t #f #t #f #t)

### the control bytes tcgetattr does not write are 0, not a new string's spaces

Linux's TCGETS writes the kernel's 19 control characters; musl's termios
holds 32, and the 12 from the 20th on are left as settings found them.

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def w (Term words (Term settings s)))
    (def past (fn (self i) (if (>= i (Term nccs)) () (pair (List ref (+ 4 i) w) (self (+ i 1))))))
    (def r (null? (List find (fn (_ b) (not (= b 0))) (past 20))))
    (File close s) (File close (first p))
    r)
```
---
    #t

### settings of a pipe is nil, and apply! declines

```x
(do (import x/repl/term)
    (def fds (Sys pipe))
    (def r (list (Term settings (first fds)) (Term apply! (first fds) ((prim-ref 'str 'make) 128))))
    (Sys close (first fds)) (Sys close (rest fds))
    r)
```
---
    (() #f)

### window! sets the size measure then reads, nil keeping one side

```x
(do (import x/repl/term) (import x/sys/pty) (import x/sys/file)
    (def p (Pty open))
    (def s (File open (rest p) (list 'rdwr 'noctty)))
    (def a (Term window! s 100 30))
    (def m1 (Term measure s))
    (def b (Term window! s () 41))
    (def m2 (Term measure s))
    (File close s) (File close (first p))
    (list a m1 b m2))
```
---
    (#t (100 . 30) #t (100 . 41))

### window! on a pipe declines

```x
(do (import x/repl/term)
    (def fds (Sys pipe))
    (def r (Term window! (first fds) 80 24))
    (Sys close (first fds)) (Sys close (rest fds))
    r)
```
---
    #f

### a pipe has no modes: modes is nil and modes! declines

```x
(do (import x/repl/term)
    (def fds (Sys pipe))
    (def r (list (Term modes (first fds)) (Term modes! (first fds) (list (pair 'echo #f)))))
    (Sys close (first fds)) (Sys close (rest fds))
    r)
```
---
    (() #f)
