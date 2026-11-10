; sys/sdl.x -- Sdl: a window, a pixel buffer shown in it, its events, and
; streams of sound, through the host's SDL3, loaded with dlopen.
;
; SDL3 is bound the way codec/zlib.x binds libz: dlopen, dlsym and ptr call
; from x/core/doors, no new C.  Every call here takes integers and pointers
; only, so the engine's ptr call carries all of them.
;
;   (Sdl load! path)            -> path; tried before the default names
;   (Sdl available?)            -> #t when libSDL3 opens
;   (Sdl hint! name value)      -> #t when SDL took the hint
;   (Sdl open title w h scale)  -> a window: a w x h RGBA picture shown at
;                                  scale, kept at whole multiples on resize
;   (Sdl scaling! win mode)     -> win; mode whole (whole multiples) or fit
;                                  (as large as fits, its shape kept)
;   (Sdl canvas win)            -> a zeroed RGBA buffer the window's size
;   (Sdl draw! win buf)         -> the buffer drawn, not yet presented
;   (Sdl present! win)          -> the drawn frame on screen
;   (Sdl show! win buf)         -> draw! then present!
;   (Sdl read-pixels win)       -> the drawn frame as an RGBA buffer
;   (Sdl poll)                  -> the next event, or nil
;   (Sdl poll win)              -> the same, the mouse in the picture's pixels
;   (Sdl post-key! code)        -> queues a key-down event, as a key press
;   (Sdl fullscreen! win on)    -> the window fullscreen on the desktop, or back,
;                                  and raised
;   (Sdl raise! win)            -> win, in front and given the keyboard
;   (Sdl buttons) (Sdl axes)    -> gamepad button and axis names
;   (Sdl mouse-buttons)         -> mouse button names
;   (Sdl close win)             -> releases the window and SDL
;   (Sdl error)                 -> SDL's last error message
;   (Sdl audio-open rate chans) -> a playing stream of signed 16-bit frames
;   (Sdl audio-put! s buf n)    -> n bytes of buf queued to play after the rest
;   (Sdl audio-queued s)        -> bytes queued and not yet played
;   (Sdl audio-clear! s)        -> the queue dropped, unplayed
;   (Sdl audio-close s)         -> the stream released
;
; Audio is pushed, never pulled: each stream is its own device stream, which
; SDL mixes with the others, and SDL's audio thread never calls into x.  A
; caller keeps a stream fed by asking audio-queued how far ahead it is.
; A buffer is a (str make) region of w*h*4 bytes, R G B A per pixel, rows
; top to bottom with no padding.  Events are lists: (key-down KEY MOD REPEAT),
; (key-up KEY MOD REPEAT), (pad-down BUTTON PAD), (pad-up BUTTON PAD),
; (pad-axis AXIS VALUE PAD), (pad-added PAD), (pad-removed PAD), (quit),
; (close), or (other TYPE).  KEY is SDL's keycode: the character's code for
; printable keys, (Sdl key 'up) and the other names in (Sdl keys) for the
; rest.  BUTTON and AXIS are names from (Sdl buttons) and (Sdl axes); PAD is
; SDL's joystick instance id.  open starts the gamepad subsystem with video,
; so pads connected at open arrive as pad-added, and poll opens each pad as
; it is added, which is what makes its buttons report.
;
; SDL's bool results are read from the low byte only, as both calling
; conventions leave the rest of the register undefined.

(module x/sys/sdl)
(import x/type/class)
(import x/core/list)
(import x/core/doors ffi-dlopen ffi-dlsym int->ptr int& int<< int= ptr->str ptr-call ptr-ref ptr-ref-word ptr-set! ptr-set-word! str->ptr str-make mem-copy)

(def-class Sdl ()
  (doc "A window that shows an RGBA pixel buffer, its keyboard and window events, and streams of sound, through the host's SDL3 loaded with dlopen."
    (note "SDL3 is looked for at the path given to load!, then as libSDL3.so.0, libSDL3.0.dylib, and under /opt/homebrew/lib and /usr/local/lib. A missing library raises a label 'io.")
    (example "(Sdl key (lit up))" "1073741906")
    (see open) (see show!) (see poll) (see available?))
  (static
    (%path-cell (pair () ()))
    (%init-video 32)
    (%init-gamepad 8192)
    (%init-audio 16)
    (%s16 32784)
    (%default-playback 4294967295)
    (%buttons (lit (south east west north back guide start left-stick right-stick
                    left-shoulder right-shoulder dpad-up dpad-down dpad-left dpad-right)))
    (%axes (lit (left-x left-y right-x right-y left-trigger right-trigger)))
    (%mouse-buttons (lit (left middle right x1 x2)))
    (%rgba32 376840196)
    (%streaming 1)
    (%integer-scale 4)
    (%letterbox 2)
    (%nearest 0)
    (%resizable 32)
    (%event-size 128)
    (%keys (lit ((up . 1073741906) (down . 1073741905) (left . 1073741904) (right . 1073741903)
            (escape . 27) (return . 13) (backspace . 8) (tab . 9) (space . 32))))

    (method keys (self)
      (doc "Keycodes by name for keys that are not printable characters."
        (returns LIST "((name . keycode) ...)")
        (example "(first (Sdl keys))" "('up . 1073741906)"))
      (Sdl %keys))

    (method %handle (self)
      (doc "The libSDL3 handle, or nil when no candidate opens."
        (returns POINTER|NIL "The dlopen handle")
        (sample "(Sdl %handle)" "the libSDL3 handle, or nil"))
      (let try ((names (List append (first (Sdl %path-cell))
                                    (list "libSDL3.so.0" "libSDL3.0.dylib"
                                          "/opt/homebrew/lib/libSDL3.0.dylib"
                                          "/usr/local/lib/libSDL3.0.dylib"))))
        (if (null? names) ()
          (let ((h (ffi-dlopen (first names) 1)))
            (if h h (try (rest names)))))))

    (method %sym (self (param name STRING "SDL function name"))
      (doc "The named SDL3 function; raises a label 'io when libSDL3 is not found."
        (returns POINTER "The function pointer")
        (sample "(Sdl %sym \"SDL_Init\")" "a function pointer"))
      (def h (Sdl %handle))
      (when (null? h)
        (Err raise (lit io) "Sdl: libSDL3 not found" (first (Sdl %path-cell))))
      (ffi-dlsym h name))

    (method %ok (self (param r INTEGER "A C bool result") (param what STRING "The call, for the message"))
      (doc "Raise a label 'io with SDL's error when a bool result is false."
        (returns ANY "nil")
        (sample "(Sdl %ok 1 \"init\")" "nil"))
      (when (= (& r 255) 0)
        (Err raise (lit io) (Str8 append "Sdl " what ": " (Sdl error)) r)))

    (method %made (self (param p INTEGER "A pointer result") (param what STRING "The call, for the message"))
      (doc "The pointer, or a label 'io with SDL's error when it is NULL."
        (returns INTEGER "The pointer, as an integer")
        (sample "(Sdl %made p \"window\")" "p"))
      (when (= p 0)
        (Err raise (lit io) (Str8 append "Sdl " what ": " (Sdl error)) ()))
      p)

    (method %zeroed (self (param n INTEGER "Byte count, a multiple of 8"))
      (doc "A (str make) region of n zero bytes."
        (returns STRING "The region")
        (sample "(Sdl %zeroed 128)" "a 128-byte region of zeros"))
      (def region (str-make n))
      (def p (str->ptr region))
      (let go ((i 0))
        (when (< i n)
          (do (ptr-set-word! p i 0) (go (+ i %word-size)))))
      region)

    (method load! (self (param path STRING "A libSDL3 file to try first"))
      (doc "Name the libSDL3 to load ahead of the default names, as a game shipping its own copy does."
        (returns STRING "The path")
        (example "(Sdl load! \"/nonexistent/libSDL3.dylib\")" "\"/nonexistent/libSDL3.dylib\""))
      (%set-first! (Sdl %path-cell) (list path))
      path)

    (method available? (self)
      (doc "Whether a libSDL3 can be opened."
        (returns BOOL "#t when one opens")
        (sample "(Sdl available?)" "#t on a host with SDL3"))
      (not (null? (Sdl %handle))))

    (method error (self)
      (doc "SDL's last error message."
        (returns STRING "The message, empty when there is none")
        (sample "(Sdl error)" "\"\""))
      (ptr->str (int->ptr (ptr-call (Sdl %sym "SDL_GetError")))))

    (method hint! (self (param name STRING "An SDL hint name, such as SDL_VIDEO_DRIVER")
                        (param value STRING "Its value"))
      (doc "Set an SDL hint; video and render driver hints take effect at the next open."
        (returns BOOL "#t when SDL took the hint")
        (sample "(Sdl hint! \"SDL_VIDEO_DRIVER\" \"offscreen\")" "#t"))
      (not (= (& (ptr-call (Sdl %sym "SDL_SetHint") name value) 255) 0)))

    (method open (self (param title STRING "Window title")
                       (param w INTEGER "Picture width in pixels")
                       (param h INTEGER "Picture height in pixels")
                       (param scale INTEGER "Initial window size, in multiples of the picture"))
      (doc "Start SDL's video and open a resizable window that shows a w x h RGBA picture, scaled by whole multiples with nearest-pixel sampling."
        (returns LIST "The window: (window renderer texture w h)")
        (sample "(Sdl open \"x\" 320 200 3)" "a 960 x 600 window"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_Init") (| (Sdl %init-video) (Sdl %init-gamepad))) "init")
      (def win (Sdl %made (ptr-call (Sdl %sym "SDL_CreateWindow") title (* w scale) (* h scale)
                                    (Sdl %resizable))
                          "window"))
      (def ren (Sdl %made (ptr-call (Sdl %sym "SDL_CreateRenderer") win ()) "renderer"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_SetRenderLogicalPresentation") ren w h (Sdl %integer-scale))
               "logical size")
      (def tex (Sdl %made (ptr-call (Sdl %sym "SDL_CreateTexture") ren (Sdl %rgba32) (Sdl %streaming) w h)
                          "texture"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_SetTextureScaleMode") tex (Sdl %nearest)) "scale mode")
      (list win ren tex w h))

    (method scaling! (self (param win LIST "A window from open")
                           (param mode SYMBOL "whole: whole multiples only; fit: as large as the window allows, its shape kept"))
      (doc "Set how the picture fills the window as it is resized: by whole multiples, every pixel the same size and bars round the rest, or as large as fits, the bars only on two sides and the pixels a little uneven."
        (returns LIST "The window")
        (sample "(Sdl scaling! win (lit fit))" "the picture fills the window's width or height"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_SetRenderLogicalPresentation") (List ref 1 win) (List ref 3 win) (List ref 4 win)
                         (match ((eq? mode (lit whole)) (Sdl %integer-scale))
                                ((eq? mode (lit fit)) (Sdl %letterbox))
                                (#t (Err raise (lit value) "Sdl scaling!: the mode is whole or fit" mode))))
               "logical size")
      win)

    (method canvas (self (param win LIST "A window from open"))
      (doc "A zeroed RGBA buffer the size of the window's picture: transparent black."
        (returns STRING "A region of w*h*4 bytes")
        (sample "(Sdl canvas win)" "a 256000-byte region for 320 x 200"))
      (Sdl %zeroed (* 4 (List ref 3 win) (List ref 4 win))))

    (method draw! (self (param win LIST "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Upload the buffer and draw it over the whole picture; nothing shows until present!."
        (returns LIST "The window")
        (sample "(Sdl draw! win (Sdl canvas win))" "win"))
      (def ren (List ref 1 win))
      (def tex (List ref 2 win))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_UpdateTexture") tex () (str->ptr buf) (* 4 (List ref 3 win)))
               "upload")
      (Sdl %ok (ptr-call (Sdl %sym "SDL_RenderClear") ren) "clear")
      (Sdl %ok (ptr-call (Sdl %sym "SDL_RenderTexture") ren tex () ()) "draw")
      win)

    (method present! (self (param win LIST "A window from open"))
      (doc "Put the drawn frame on screen."
        (returns LIST "The window")
        (sample "(Sdl present! win)" "win"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_RenderPresent") (List ref 1 win)) "present")
      win)

    (method show! (self (param win LIST "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Draw the buffer and present it."
        (returns LIST "The window")
        (sample "(Sdl show! win buf)" "win"))
      (Sdl draw! win buf)
      (Sdl present! win))

    (method read-pixels (self (param win LIST "A window from open"))
      (doc "The frame drawn since the last present, read back as an RGBA buffer; call it before present!."
        (returns STRING "A region of w*h*4 bytes")
        (sample "(Sdl read-pixels win)" "the drawn frame"))
      (def w (List ref 3 win))
      (def h (List ref 4 win))
      (def got (Sdl %made (ptr-call (Sdl %sym "SDL_RenderReadPixels") (List ref 1 win) ()) "read"))
      (def s (Sdl %made (ptr-call (Sdl %sym "SDL_ConvertSurface") got (Sdl %rgba32)) "convert"))
      (ptr-call (Sdl %sym "SDL_DestroySurface") got)
      (def sp (int->ptr s))
      (def pitch (ptr-ref sp 16 4))
      ; pixels follows the 4-byte pitch at 16, on the next word boundary
      (def pixels (ptr-ref-word sp (+ 16 %word-size)))
      (def out (str-make (* 4 w h)))
      (def op (str->ptr out))
      (let row ((y 0))
        (when (< y h)
          (do (mem-copy (int->ptr (+ (ptr->int op) (* y w 4)))
                        (int->ptr (+ pixels (* y pitch)))
                        (* w 4))
              (row (+ y 1)))))
      (ptr-call (Sdl %sym "SDL_DestroySurface") s)
      out)

    (method poll (self . (param win LIST "A window from open: the mouse's places in its picture's pixels"))
      (doc "The next queued event, or nil when the queue is empty."
        (note "A gamepad is opened when its pad-added arrives and closed at pad-removed; pads already connected at open arrive as pad-added too.")
        (note "The mouse's X Y are in the window's pixels, or in the picture's when the window is given, whole and toward zero; a place in the bars beside the picture lies outside it, below 0 or past its size.")
        (returns LIST|NIL "(key-down KEY MOD REPEAT), (key-up KEY MOD REPEAT), (mouse-down BUTTON X Y), (mouse-up BUTTON X Y), (mouse-motion X Y HELD), (pad-down BUTTON PAD), (pad-up BUTTON PAD), (pad-axis AXIS VALUE PAD), (pad-added PAD), (pad-removed PAD), (quit), (close) or (other TYPE)")
        (sample "(Sdl poll)" "(key-down 97 0 #f)")
        (sample "(Sdl poll win)" "(mouse-motion 120 64 (left))"))
      (def ev (Sdl %zeroed (Sdl %event-size)))
      (def p (str->ptr ev))
      (if (= (& (ptr-call (Sdl %sym "SDL_PollEvent") p) 255) 0) ()
        (let ((type (ptr-ref p 0 4)))
          (do (when (if (null? win) #f (if (< 1023 type) (< type 1027) #f))
                (ptr-call (Sdl %sym "SDL_ConvertEventToRenderCoordinates") (List ref 1 (first win)) p))
          (match
            ((= type 1024) (list (lit mouse-motion) (Sdl %f32-int (ptr-ref p 28 4)) (Sdl %f32-int (ptr-ref p 32 4))
                                 (Sdl %held (ptr-ref p 24 4))))
            ((= type 1025) (list (lit mouse-down) (Sdl %name (Sdl %mouse-buttons) (- (ptr-ref p 24 1) 1))
                                 (Sdl %f32-int (ptr-ref p 28 4)) (Sdl %f32-int (ptr-ref p 32 4))))
            ((= type 1026) (list (lit mouse-up) (Sdl %name (Sdl %mouse-buttons) (- (ptr-ref p 24 1) 1))
                                 (Sdl %f32-int (ptr-ref p 28 4)) (Sdl %f32-int (ptr-ref p 32 4))))
            ((= type 768) (list (lit key-down) (ptr-ref p 28 4) (ptr-ref p 32 2) (not (= (ptr-ref p 37 1) 0))))
            ((= type 769) (list (lit key-up) (ptr-ref p 28 4) (ptr-ref p 32 2) (not (= (ptr-ref p 37 1) 0))))
            ((= type 1616) (list (lit pad-axis) (Sdl %name (Sdl %axes) (ptr-ref p 20 1))
                                 (Sdl %sint16 (ptr-ref p 24 2)) (ptr-ref p 16 4)))
            ((= type 1617) (list (lit pad-down) (Sdl %name (Sdl %buttons) (ptr-ref p 20 1)) (ptr-ref p 16 4)))
            ((= type 1618) (list (lit pad-up) (Sdl %name (Sdl %buttons) (ptr-ref p 20 1)) (ptr-ref p 16 4)))
            ((= type 1619)
              (do (ptr-call (Sdl %sym "SDL_OpenGamepad") (ptr-ref p 16 4))
                  (list (lit pad-added) (ptr-ref p 16 4))))
            ((= type 1620)
              (let ((pad (ptr-call (Sdl %sym "SDL_GetGamepadFromID") (ptr-ref p 16 4))))
                (do (when (not (= pad 0)) (ptr-call (Sdl %sym "SDL_CloseGamepad") pad))
                    (list (lit pad-removed) (ptr-ref p 16 4)))))
            ((= type 256) (list (lit quit)))
            ((= type 528) (list (lit close)))
            (#t (list (lit other) type)))))))

    (method %name (self (param names LIST "Symbols in SDL's enum order") (param i INTEGER "An enum value"))
      (doc "The symbol for an SDL enum value, or the value itself past the named ones."
        (returns SYMBOL|INTEGER "The name, or i")
        (example "(Sdl %name (Sdl %buttons) 11)" "'dpad-up"))
      (if (< i (List length names)) (List ref i names) i))

    (method %sint16 (self (param u INTEGER "A 16-bit field read unsigned"))
      (doc "The field as a signed 16-bit value."
        (returns INTEGER "-32768 to 32767")
        (example "(Sdl %sint16 65535)" "-1"))
      (if (< u 32768) u (- u 65536)))

    (method %f32-int (self (param b INTEGER "A 32-bit IEEE float's bits, read as an integer"))
      (doc "The float as a whole number, toward zero; SDL gives the mouse's places as floats."
        (returns INTEGER "The whole part")
        (example "(Sdl %f32-int 1092616192)" "10")
        (example "(Sdl %f32-int 0xBF800000)" "-1"))
      (def e (& (>> b 23) 255))
      (def m (| (& b 8388607) 8388608))
      (def n (match ((< e 127) 0) ((< e 150) (>> m (- 150 e))) (#t (<< m (- e 150)))))
      ; the sign is bit 31, asked for by its place: a 4-byte word has no 2^31 to mask with
      (if (= (& (>> b 31) 1) 0) n (- 0 n)))

    (method %held (self (param state INTEGER "SDL's mouse button flags"))
      (doc "The mouse buttons held, by name, for the flags SDL gives with a motion."
        (returns LIST "Names from (Sdl mouse-buttons)")
        (example "(Sdl %held 5)" "('left 'right)"))
      (List flat-map (fn (_ i) (if (= 0 (& state (<< 1 i))) () (list (List ref i (Sdl %mouse-buttons))))) (List range 0 5)))

    (method mouse-buttons (self)
      (doc "Mouse button names in SDL's order, button 1 first."
        (returns LIST "(left middle right x1 x2)")
        (example "(List ref 2 (Sdl mouse-buttons))" "'right"))
      (Sdl %mouse-buttons))

    (method buttons (self)
      (doc "Gamepad button names in SDL's order; south is the bottom face button, Xbox A."
        (returns LIST "(south east west north ...)")
        (example "(List ref 0 (Sdl buttons))" "'south"))
      (Sdl %buttons))

    (method axes (self)
      (doc "Gamepad axis names in SDL's order; sticks run -32768 to 32767, triggers 0 to 32767."
        (returns LIST "(left-x left-y right-x right-y left-trigger right-trigger)")
        (example "(List ref 4 (Sdl axes))" "'left-trigger"))
      (Sdl %axes))

    (method fullscreen! (self (param win LIST "A window from open") (param on BOOL "#t for fullscreen, #f for a window"))
      (doc "Switch the window to the desktop's fullscreen or back; the picture keeps its whole-multiple scaling."
        (returns LIST "The window")
        (sample "(Sdl fullscreen! win #t)" "win"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_SetWindowFullscreen") (List ref 0 win) (if on 1 0)) "fullscreen")
      ; A Mac's fullscreen in place leaves the keyboard with the window
      ; that had it, the terminal the program started from.
      (Sdl raise! win))

    (method raise! (self (param win LIST "A window from open"))
      (doc "Bring the window to the front and give it the keyboard, as far as the system allows: it may refuse to take the keyboard from another program."
        (returns LIST "The window")
        (sample "(Sdl raise! win)" "win"))
      (ptr-call (Sdl %sym "SDL_RaiseWindow") (List ref 0 win))
      win)

    (method post-key! (self (param code INTEGER "An SDL keycode"))
      (doc "Queue a key-down event for code, as if it had been pressed: input for tests and replays."
        (returns BOOL "#t when SDL queued it")
        (sample "(Sdl post-key! (Sdl key (lit up)))" "#t"))
      (def ev (Sdl %zeroed (Sdl %event-size)))
      (def p (str->ptr ev))
      (ptr-set! p 0 768 4)
      (ptr-set! p 28 code 4)
      (ptr-set! p 36 1 1)
      (not (= (& (ptr-call (Sdl %sym "SDL_PushEvent") p) 255) 0)))

    (method key (self (param name SYMBOL "A key name from (Sdl keys)"))
      (doc "The keycode of a named key that is not a printable character."
        (returns INTEGER|NIL "The keycode, or nil for an unknown name")
        (example "(Sdl key (lit escape))" "27"))
      (def hit (List find (fn (_ e) (eq? (first e) name)) (Sdl keys)))
      (if (null? hit) () (rest hit)))

    (method audio-open (self (param rate INTEGER "Frames a second, such as 44100")
                             (param chans INTEGER "Channels a frame: 1 mono, 2 stereo, left first"))
      (doc "Start SDL's audio and open a stream to the default playback device that plays signed 16-bit little-endian frames, already running: what is put on it plays as soon as the device takes it. Each stream is mixed with every other one open."
        (note "With the hint SDL_AUDIO_DRIVER set to dummy, a stream opens and drains with no sound device, as a spec needs.")
        (returns INTEGER "The stream, an SDL_AudioStream pointer as an integer")
        (sample "(Sdl audio-open 44100 2)" "a stream"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_InitSubSystem") (Sdl %init-audio)) "audio init")
      (def spec (Sdl %zeroed 16))
      (def p (str->ptr spec))
      (ptr-set! p 0 (Sdl %s16) 4)
      (ptr-set! p 4 chans 4)
      (ptr-set! p 8 rate 4)
      (def s (Sdl %made (ptr-call (Sdl %sym "SDL_OpenAudioDeviceStream") (Sdl %default-playback) p () ())
                        "audio stream"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_ResumeAudioStreamDevice") s) "audio resume")
      s)

    (method audio-put! (self (param s INTEGER "A stream from audio-open")
                             (param buf STRING "A region of frames")
                             (param n INTEGER "Bytes of it to queue, from its start"))
      (doc "Queue the first n bytes of buf to play after what is already queued. SDL copies them: buf may be written again at once."
        (returns INTEGER "n")
        (sample "(Sdl audio-put! s buf 4096)" "4096"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_PutAudioStreamData") s (str->ptr buf) n) "audio put")
      n)

    (method audio-queued (self (param s INTEGER "A stream from audio-open"))
      (doc "Bytes queued on the stream and not yet taken by the device: how far ahead of the speaker the stream is."
        (returns INTEGER "A byte count, 0 when it has run dry")
        (sample "(Sdl audio-queued s)" "17640"))
      ; a C int: bit 31 is its sign on any word, and the bits above it are not its
      (def n (ptr-call (Sdl %sym "SDL_GetAudioStreamQueued") s))
      (if (int= 0 (int& n (int<< 1 31))) (int& n 2147483647)
        (Err raise (lit io) (Str8 append "Sdl audio-queued: " (Sdl error)) s)))

    (method audio-clear! (self (param s INTEGER "A stream from audio-open"))
      (doc "Drop everything queued on the stream, unplayed: the next put plays at once."
        (returns INTEGER "The stream")
        (sample "(Sdl audio-clear! s)" "s"))
      (Sdl %ok (ptr-call (Sdl %sym "SDL_ClearAudioStream") s) "audio clear")
      s)

    (method audio-close (self (param s INTEGER "A stream from audio-open"))
      (doc "Stop the stream and release it and its device; what was queued is dropped."
        (returns ANY "nil")
        (sample "(Sdl audio-close s)" "nil"))
      (ptr-call (Sdl %sym "SDL_DestroyAudioStream") s)
      ())

    (method close (self (param win LIST "A window from open"))
      (doc "Release the window's texture, renderer and window, and shut SDL down."
        (returns ANY "nil")
        (sample "(Sdl close win)" "nil"))
      (ptr-call (Sdl %sym "SDL_DestroyTexture") (List ref 2 win))
      (ptr-call (Sdl %sym "SDL_DestroyRenderer") (List ref 1 win))
      (ptr-call (Sdl %sym "SDL_DestroyWindow") (List ref 0 win))
      (ptr-call (Sdl %sym "SDL_Quit"))
      ())))

(doc (provide x/sys/sdl Sdl)
  (example "(Sdl key (lit escape))" "27")
  "A window that shows an RGBA pixel buffer, with keyboard and window events and streams of sound, through the host's SDL3 over the dlopen FFI.")
