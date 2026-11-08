# Sdl: a window, an RGBA buffer shown in it, and its events, through SDL3
# @weight 2

SDL3 loaded with dlopen, the way Zlib loads libz. Every case that opens a
window first selects SDL's dummy video driver and its software
renderer, so the spec runs with no display and reads back exactly the
pixels it drew. The host needs libSDL3 installed.

## the library

### libSDL3 opens

```x
(do (import x/sys/sdl)
  (Sdl available?))
```
---
    #t

### a named key answers its keycode; an unknown name answers nil

```x
(do (import x/sys/sdl)
  (list (Sdl key (lit escape)) (Sdl key (lit up)) (Sdl key (lit nowhere))))
```
---
    (27 1073741906 ())

## drawing

### a buffer drawn to an offscreen window reads back byte for byte

```x
(do (import x/sys/sdl) (import x/core/doors ptr-ref ptr-set! str->ptr)
  (Sdl hint! "SDL_VIDEO_DRIVER" "dummy")
  (Sdl hint! "SDL_RENDER_DRIVER" "software")
  (def win (Sdl open "spec" 4 2 1))
  (def buf (Sdl canvas win))
  (def p (str->ptr buf))
  ; pixel 0 opaque red, pixel 5 opaque green, the rest opaque blue
  (let go ((i 0))
    (when (< i 8)
      (do (ptr-set! p (* i 4) (if (= i 0) 255 0) 1)
          (ptr-set! p (+ 1 (* i 4)) (if (= i 5) 255 0) 1)
          (ptr-set! p (+ 2 (* i 4)) (if (or (= i 0) (= i 5)) 0 255) 1)
          (ptr-set! p (+ 3 (* i 4)) 255 1)
          (go (+ i 1)))))
  (Sdl draw! win buf)
  (def back (str->ptr (Sdl read-pixels win)))
  (Sdl present! win)
  (Sdl close win)
  (def px (fn (_ i) (list (ptr-ref back (* i 4) 1) (ptr-ref back (+ 1 (* i 4)) 1)
                          (ptr-ref back (+ 2 (* i 4)) 1) (ptr-ref back (+ 3 (* i 4)) 1))))
  (list (px 0) (px 1) (px 5) (px 7)))
```
---
    ((255 0 0 255) (0 0 255 255) (0 255 0 255) (0 0 255 255))

## events

### a posted key comes back from poll as key-down

```x
(do (import x/sys/sdl)
  (Sdl hint! "SDL_VIDEO_DRIVER" "dummy")
  (Sdl hint! "SDL_RENDER_DRIVER" "software")
  (def win (Sdl open "spec" 4 2 1))
  (Sdl post-key! (Sdl key (lit up)))
  (def got (let next ((e (Sdl poll)))
             (if (or (null? e) (eq? (first e) (lit key-down))) e (next (Sdl poll)))))
  (def empty (let drain ((e (Sdl poll))) (if (null? e) #t (drain (Sdl poll)))))
  (Sdl close win)
  (list got empty))
```
---
    (('key-down 1073741906 0 #f) #t)

### gamepad button and axis events come back from poll by name

SDL's event layout: type at 0, the pad's id at 16, the button or axis at
20, a button's down flag at 21, an axis's signed 16-bit value at 24.

```x
(do (import x/sys/sdl) (import x/core/doors ptr-call ptr-set! str->ptr str-make)
  (Sdl hint! "SDL_VIDEO_DRIVER" "dummy")
  (Sdl hint! "SDL_RENDER_DRIVER" "software")
  (def win (Sdl open "spec" 4 2 1))
  (def push (fn (_ type which index down value)
    (do (def ev (str-make 128))
        (def p (str->ptr ev))
        (let go ((i 0)) (when (< i 128) (do (ptr-set! p i 0 8) (go (+ i 8)))))
        (ptr-set! p 0 type 4)
        (ptr-set! p 16 which 4)
        (ptr-set! p 20 index 1)
        (ptr-set! p 21 down 1)
        (ptr-set! p 24 value 2)
        (ptr-call (Sdl %sym "SDL_PushEvent") p))))
  (push 1617 7 11 1 0)
  (push 1618 7 0 0 0)
  (push 1616 7 1 0 (- 65536 32768))
  (push 1616 7 5 0 32767)
  (def pad? (fn (_ e) (List find (fn (_ k) (eq? k (first e))) (lit (pad-down pad-up pad-axis)))))
  (def got (let next ((e (Sdl poll)) (acc ()))
             (if (null? e) (List reverse acc)
               (next (Sdl poll) (if (pad? e) (pair e acc) acc)))))
  (Sdl close win)
  got)
```
---
    (('pad-down 'dpad-up 7) ('pad-up 'south 7) ('pad-axis 'left-y -32768 7) ('pad-axis 'right-trigger 32767 7))

### fullscreen! answers the window, going there and back

```x
(do (import x/sys/sdl)
  (Sdl hint! "SDL_VIDEO_DRIVER" "dummy")
  (Sdl hint! "SDL_RENDER_DRIVER" "software")
  (def win (Sdl open "spec" 4 2 1))
  (def both (list (eq? (Sdl fullscreen! win #t) win) (eq? (Sdl fullscreen! win #f) win)))
  (Sdl close win)
  both)
```
---
    (#t #t)

## loading

### a path given to load! that does not open falls back to the default names

```x
(do (import x/sys/sdl)
  (Sdl load! "/nonexistent/libSDL3.dylib")
  (Sdl available?))
```
---
    #t
