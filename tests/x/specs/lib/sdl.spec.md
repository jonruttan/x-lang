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

### scaling: fit and whole each answer the window; any other mode raises

```x
(do (import x/sys/sdl)
  (Sdl hint! "SDL_VIDEO_DRIVER" "dummy")
  (Sdl hint! "SDL_RENDER_DRIVER" "software")
  (def win (Sdl open "spec" 4 2 1))
  (def fit (eq? (Sdl scaling! win (lit fit)) win))
  (def whole (eq? (Sdl scaling! win (lit whole)) win))
  (def bad (guard (e (Err label e)) (Sdl scaling! win (lit stretch))))
  (Sdl close win)
  (list fit whole bad))
```
---
    (#t #t 'value)

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

## loading

### a path given to load! that does not open falls back to the default names

```x
(do (import x/sys/sdl)
  (Sdl load! "/nonexistent/libSDL3.dylib")
  (Sdl available?))
```
---
    #t
