# Linux: a window on the Linux console
# @weight 2

No case touches a real device.  The framebuffer is a file the case
writes, with a directory holding the three numbers sysfs would; the
input directory is empty and the console's path is one that is not
there, so open takes neither.

## keys

### Linux's key numbers become SDL's keycodes: a letter, a digit, the arrows, escape

```x
(do (import x/sys/linux)
  (List map (fn (_ c) (Linux %keycode c)) (list 30 2 103 108 105 106 1 28 57 240)))
```
---
    (97 49 1073741906 1073741905 1073741904 1073741903 27 13 32 ())

### input events become Sdl's: shift held, a press, a repeat, a release; other kinds are passed over

```x
(do (import x/sys/linux)
  (import x/core/doors ptr-set! str->ptr str-make)
  (def sz (+ (* 2 %word-size) 8))
  (def buf (str-make (* 5 sz)))
  (def ev! (fn (_ i type code value)
             (do (ptr-set! (str->ptr buf) (+ (* i sz) (* 2 %word-size)) type 2)
                 (ptr-set! (str->ptr buf) (+ (* i sz) (* 2 %word-size) 2) code 2)
                 (ptr-set! (str->ptr buf) (+ (* i sz) (* 2 %word-size) 4) value 4))))
  (ev! 0 1 42 1)
  (ev! 1 1 30 1)
  (ev! 2 1 30 2)
  (ev! 3 0 0 0)
  (ev! 4 1 30 0)
  (def win (Vector make 15 ()))
  (Linux %set! win (lit mods) 0)
  (Linux %events! win buf (* 5 sz))
  (Linux %ref win (lit events)))
```
---
    (('key-down 1073742049 1 #f) ('key-down 97 1 #f) ('key-down 97 1 #t) ('key-up 97 1 #f))

## the picture's place

### whole multiples leave bars; fit keeps the shape and fills one way

```x
(do (import x/sys/linux)
  (def win (Vector make 15 ()))
  (Linux %set! win (lit sw) 1280)
  (Linux %set! win (lit sh) 800)
  (Linux %set! win (lit w) 640)
  (Linux %set! win (lit h) 360)
  (Linux %set! win (lit scaling) (lit whole))
  (def a (Linux place win))
  (Linux %set! win (lit w) 500)
  (Linux %set! win (lit h) 300)
  (def b (Linux place win))
  (Linux %set! win (lit scaling) (lit fit))
  (list a b (Linux place win)))
```
---
    ((0 40 1280 720) (140 100 1000 600) (0 16 1280 768))

## the screen

### a frame reaches the framebuffer scaled by two, blue and red swapped, in its place

```x
(do (import x/sys/linux)
  (import x/core/doors ptr-ref ptr-set! str->ptr)
  (def tmp (File temp "/tmp/x-linux-"))
  (File close (first tmp))
  (def dir (Str8 append (rest tmp) ".d"))
  (File mkdir dir)
  (File write-all (Str8 append dir "/virtual_size") "8,6\n")
  (File write-all (Str8 append dir "/bits_per_pixel") "32\n")
  (File write-all (Str8 append dir "/stride") "32\n")
  (File write-all (Str8 append dir "/fb") "")
  (File mkdir (Str8 append dir "/input"))
  (Linux devices! (Str8 append dir "/fb") dir (Str8 append dir "/input") (Str8 append dir "/pcm") (Str8 append dir "/no-console"))
  (def win (Linux open "spec" 4 2 1))
  (def buf (Linux canvas win))
  (ptr-set! (str->ptr buf) 0 10 1)
  (ptr-set! (str->ptr buf) 1 20 1)
  (ptr-set! (str->ptr buf) 2 30 1)
  (ptr-set! (str->ptr buf) 28 1 1)
  (ptr-set! (str->ptr buf) 29 2 1)
  (ptr-set! (str->ptr buf) 30 3 1)
  (Linux show! win buf)
  (def place (Linux place win))
  (def fb (File read-all (Str8 append dir "/fb")))
  (def px (fn (_ x y) (List map (fn (_ k) (ptr-ref (str->ptr fb) (+ (* y 32) (* x 4) k) 1)) (list 0 1 2 3))))
  (def seen (list place (px 0 1) (px 1 2) (px 2 1) (px 7 4) (px 6 3) (px 0 0) (px 7 5)))
  (Linux close win)
  seen)
```
---
    ((0 1 8 4) (30 20 10 255) (30 20 10 255) (0 0 0 255) (3 2 1 255) (3 2 1 255) (0 0 0 0) (0 0 0 0))

## the loops

### the compiled loops agree with the pure ones where there is a backend

```x
(do (import x/sys/linux)
  (Linux jit!))
```
---
    #t

### two streams mixed: each sample summed, clipped to 16 bits

```x
(do (import x/sys/linux)
  (import x/core/doors ptr-ref ptr-set! ptr->int str->ptr str-make)
  (def s16 (fn (_ vs)
             (def b (str-make (* 2 (List length vs))))
             ((fn (self i l) (unless (null? l) (do (ptr-set! (str->ptr b) (* 2 i) (first l) 2) (self (+ i 1) (rest l))))) 0 vs)
             b))
  (def acc (Sdl %zeroed (* 4 %word-size)))
  (def stream (fn (_ vs) (let ((s (Vector make 4 ()))) (do (Vector set! 1 (list (list (s16 vs) 0 (* 2 (List length vs)))) s) (Vector set! 2 (* 2 (List length vs)) s) (Vector set! 3 0 s) s))))
  (def a (stream (list 1000 -2000 30000 -30000)))
  (def b (stream (list 24 -48 30000 -30000)))
  (Linux %take! a (ptr->int (str->ptr acc)) 8 7)
  (Linux %take! b (ptr->int (str->ptr acc)) 6 7)
  (def out (str-make 8))
  ((eval (lit %k-out) (module x/sys/linux)) (ptr->int (str->ptr acc)) (ptr->int (str->ptr out)) 0 4)
  (list (List map (fn (_ i) (ptr-ref (str->ptr out) (* 2 i) 2)) (list 0 1 2 3))
        (Vector ref 2 a) (Vector ref 2 b) (Vector ref 3 a) (List length (Vector ref 1 b))))
```
---
    ((1024 63488 32767 35536) 0 2 7 1)
