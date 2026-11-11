; sys/linux.x -- Linux: a window on the Linux console, answering Sdl's
; messages, so a program written to Sdl shows its picture and plays its
; sound on a machine with no SDL3 and no browser: a kernel and x alone.
;
; The picture goes to the framebuffer, /dev/fb0, scaled from the window's
; size to the screen's with nearest-pixel sampling, between black bars.
; Keys come from the kernel's input devices, /dev/input/event*, taken from
; the console while the window is open.  The sound goes to ALSA's first
; playback device, /dev/snd/pcmC0D0p, through its ioctls: every stream
; opened is mixed here into the one the device plays.  Nothing runs but x:
; the ioctls and the reads and writes are syscalls.
;
;   (Linux devices! fb sysfs input pcm console) -> fb; what the next open uses
;   (Linux available?)          -> #t when the framebuffer is there
;   (Linux open title w h scale) -> a window: a w x h RGBA picture
;   (Linux scaling! win mode)   -> win; whole or fit, as Sdl's
;   (Linux canvas win)          -> a zeroed RGBA buffer the window's size
;   (Linux draw! win buf)       -> the buffer kept as the frame, not yet shown
;   (Linux present! win)        -> the frame written to the screen
;   (Linux show! win buf)       -> draw! then present!
;   (Linux read-pixels win)     -> the frame drawn last
;   (Linux poll)                -> the next event, or nil
;   (Linux post-key! code)      -> queues a key-down event, as a key press
;   (Linux fullscreen! win on)  -> win; the screen is always the window's
;   (Linux key name) (Linux keys) (Linux buttons) (Linux axes) -> as Sdl's
;   (Linux close win)           -> the console given back, the devices closed
;   (Linux audio-open rate chans) -> a stream of signed 16-bit frames
;   (Linux audio-put! s buf n)  -> n bytes of buf queued after the rest
;   (Linux audio-queued s)      -> bytes queued and not yet played
;   (Linux audio-clear! s)      -> what is queued and not yet played dropped
;   (Linux audio-close s)       -> the stream released
;
; One window at a time, as SDL has one event queue: poll and the audio
; methods take no window.  Every call that touches the window or a stream
; first reads the input devices and feeds the sound device, without
; waiting, so a program that polls each frame keeps both moving.
;
; The console is put in graphics mode while the window is open, so the
; kernel draws no text or cursor over the picture, and each input device
; is grabbed, so keys reach the window and not the shell.  close gives both
; back; a program that ends without close leaves the console dark until
; another program sets it to text.
;
; The loops that touch every pixel or sample are three kernels, each
; written once below as an integer function over byte and word addresses:
; the pure-x version through x/tool/int-form, the compiled one from
; x/tool/int-form-jit, adopted only after it writes what the pure one
; writes.  They are built at open and at the first stream; in pure x a
; frame takes seconds.

(module x/sys/linux)
(import x/type/class)
(import x/core/list)
(import x/sys/posix)
(import x/sys/file)
(import x/sys/sdl)
(import x/tool/compiled)
(import x/tool/int-form int-form-pure)
(import x/platform/syscall file-modes syscall-id)
(import x/core/doors char->int int& int* int+ int- int/ int< int= int<< int>> int->ptr
  mem-copy ptr->int ptr-ref ptr-set! ptr-ref-word ptr-set-word! str->ptr str-make)

; --- The kernels, as forms -------------------------------------------------
;
; (%mem-byte-ref-at A I) is the byte at A + I; (%mem-ref-at A I) the word
; at A + I words.  A store answers the value stored.

; Pixels I to N of the screen's row at D, each the window's pixel at
; FX >> 16 along its row at S, FX stepping by STEP: red, green, blue and
; alpha become blue, green, red and an opaque fourth byte, the order of
; the framebuffer's 32-bit pixels.
(def %row-form
  (lit (fn (self s d i n fx step)
    (if (< i n)
      (do (%mem-byte-set-at! d (<< i 2) (%mem-byte-ref-at s (+ (<< (>> fx 16) 2) 2)))
          (%mem-byte-set-at! d (+ (<< i 2) 1) (%mem-byte-ref-at s (+ (<< (>> fx 16) 2) 1)))
          (%mem-byte-set-at! d (+ (<< i 2) 2) (%mem-byte-ref-at s (<< (>> fx 16) 2)))
          (%mem-byte-set-at! d (+ (<< i 2) 3) 255)
          (self s d (+ i 1) n (+ fx step) step))
      0))))

; Samples I to N of the signed 16-bit little-endian bytes at S added into
; the words at A.
(def %add-form
  (lit (fn (self s a i n)
    (if (< i n)
      (do (%mem-set-at! a i (+ (%mem-ref-at a i)
                               (- (+ (%mem-byte-ref-at s (<< i 1)) (<< (%mem-byte-ref-at s (+ (<< i 1) 1)) 8))
                                  (<< (>> (%mem-byte-ref-at s (+ (<< i 1) 1)) 7) 16))))
          (self s a (+ i 1) n))
      0))))

; Words I to N at A clipped to 16 bits and written to O as little-endian
; byte pairs; A is left zero for the next mix.
(def %out-form
  (lit (fn (self a o i n)
    (if (< i n)
      (do (%mem-set-at! a i (match ((< 32767 (%mem-ref-at a i)) 32767)
                                   ((< (%mem-ref-at a i) -32768) -32768)
                                   (#t (%mem-ref-at a i))))
          (%mem-byte-set-at! o (<< i 1) (& (%mem-ref-at a i) 255))
          (%mem-byte-set-at! o (+ (<< i 1) 1) (& (>> (%mem-ref-at a i) 8) 255))
          (%mem-set-at! a i 0)
          (self a o (+ i 1) n))
      0))))

(def %forms (list %row-form %add-form %out-form))

(def %pure (List map int-form-pure %forms))

(def %k-row ())
(def %k-add ())
(def %k-out ())

(def %install!
  (fn (_ ks)
    (set! %k-row (List ref 0 ks))
    (set! %k-add (List ref 1 ks))
    (set! %k-out (List ref 2 ks))))

(%install! %pure)

(def %addr (fn (_ r) (ptr->int (str->ptr r))))

; N zero bytes: one word cleared, then copied over the rest, doubling.
(def %zeroed
  (fn (_ n)
    (def r (str-make (int+ n %word-size)))
    (def p (str->ptr r))
    (ptr-set-word! p 0 0)
    ((fn (self k)
       (when (int< k n)
         (do (mem-copy (int->ptr (int+ (ptr->int p) k)) p (if (int< (int* 2 k) n) k (int- n k)))
             (self (int* 2 k)))))
     %word-size)
    r))
(def %max (fn (_ a b) (if (int< a b) b a)))
(def %min (fn (_ a b) (if (int< a b) a b)))

; The value an integer key has in a list of (KEY . VALUE), or nil.
(def %lookup
  (fn (_ k l) ((fn (_ hit) (if (null? hit) () (rest hit))) (List find (fn (_ e) (int= (first e) k)) l))))

; N bytes, every one a mix of its place, so no kernel matches by chance.
(def %check-bytes
  (fn (_ n)
    (def r (str-make n))
    (def p (str->ptr r))
    ((fn (self i) (when (int< i n) (do (ptr-set! p i (int& (int+ (int* i 37) (int>> i 3)) 255) 1) (self (int+ i 1))))) 0)
    r))

(def %same-bytes?
  (fn (self a b i n)
    (match ((int< i n) (if (int= (ptr-ref (int->ptr a) i 1) (ptr-ref (int->ptr b) i 1)) (self a b (int+ i 1) n) #f))
           (#t #t))))

; Each kernel run pure and by the candidate on copies of the same input,
; the outputs compared byte for byte.
(def %agrees?
  (fn (_ engine)
    (def src (%check-bytes 256))
    (def wa (%check-bytes 512))
    (def wb (%check-bytes 512))
    (def oa (%check-bytes 256))
    (def ob (%check-bytes 256))
    (def ra ((List ref 0 %pure) (%addr src) (%addr oa) 0 40 7000 98304))
    (def rb ((List ref 0 engine) (%addr src) (%addr ob) 0 40 7000 98304))
    (def row? (if (= ra rb) (%same-bytes? (%addr oa) (%addr ob) 0 256) #f))
    ((List ref 1 %pure) (%addr src) (%addr wa) 0 64)
    ((List ref 1 engine) (%addr src) (%addr wb) 0 64)
    (def add? (%same-bytes? (%addr wa) (%addr wb) 0 512))
    ((List ref 2 %pure) (%addr wa) (%addr oa) 0 64)
    ((List ref 2 engine) (%addr wb) (%addr ob) 0 64)
    (and row? add? (%same-bytes? (%addr oa) (%addr ob) 0 256) (%same-bytes? (%addr wa) (%addr wb) 0 512))))

(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit linux) %pure
          (fn (_)
            (import x/tool/int-form-jit)
            ((prim-ref (lit int-form) (lit jit-make)) %forms %agrees?))
          %install!)))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; --- The kernel's numbers ----------------------------------------------------
;
; An ioctl's request is its direction, the size of what it passes, its type
; letter and its number, packed as _IOC packs them.  Some sizes are counted
; in words, so the requests that pass them are reckoned at load.

(def %ioc (fn (_ dir size type nr) (+ (* dir 1073741824) (* size 65536) (* type 256) nr)))

(def %kd-setmode 19258)              ; KDSETMODE
(def %eviocgrab (%ioc 1 4 69 144))  ; EVIOCGRAB
(def %pcm-hw-params-size (if (= %word-size 8) 608 604))
(def %pcm-hw-params (%ioc 3 %pcm-hw-params-size 65 17))
(def %pcm-prepare (%ioc 0 0 65 64))
(def %pcm-drop (%ioc 0 0 65 67))
(def %pcm-delay (%ioc 2 %word-size 65 33))
(def %pcm-writei (%ioc 1 (* 3 %word-size) 65 80))

; struct input_event: a timeval of two words, then type, code and value.
(def %event-size (+ (* 2 %word-size) 8))

; Linux's key numbers and the SDL keycodes they are, for a US keyboard:
; printable keys as their unshifted character, the rest as SDL names them.
(def %keymap
  (lit ((1 . 27) (2 . 49) (3 . 50) (4 . 51) (5 . 52) (6 . 53) (7 . 54)
        (8 . 55) (9 . 56) (10 . 57) (11 . 48) (12 . 45) (13 . 61) (14 . 8)
        (15 . 9) (16 . 113) (17 . 119) (18 . 101) (19 . 114) (20 . 116)
        (21 . 121) (22 . 117) (23 . 105) (24 . 111) (25 . 112) (26 . 91)
        (27 . 93) (28 . 13) (29 . 1073742048) (30 . 97) (31 . 115) (32 . 100)
        (33 . 102) (34 . 103) (35 . 104) (36 . 106) (37 . 107) (38 . 108)
        (39 . 59) (40 . 39) (41 . 96) (42 . 1073742049) (43 . 92) (44 . 122)
        (45 . 120) (46 . 99) (47 . 118) (48 . 98) (49 . 110) (50 . 109)
        (51 . 44) (52 . 46) (53 . 47) (54 . 1073742053) (56 . 1073742050)
        (57 . 32) (58 . 1073741881) (59 . 1073741882) (60 . 1073741883)
        (61 . 1073741884) (62 . 1073741885) (63 . 1073741886) (64 . 1073741887)
        (65 . 1073741888) (66 . 1073741889) (67 . 1073741890) (68 . 1073741891)
        (87 . 1073741892) (88 . 1073741893) (96 . 13) (97 . 1073742052)
        (100 . 1073742054) (102 . 1073741898) (103 . 1073741906) (104 . 1073741899)
        (105 . 1073741904) (106 . 1073741903) (107 . 1073741901) (108 . 1073741905)
        (109 . 1073741902) (110 . 1073741897) (111 . 127))))

; The modifier keys and SDL's bits for them: shift, control, alt.
(def %modmap
  (lit ((42 . 1) (54 . 2) (29 . 64) (97 . 128) (56 . 256) (100 . 512))))

(def-class Linux ()
  (doc "A window on the Linux console: Sdl's messages answered by the framebuffer, the kernel's input devices and ALSA's playback device, through syscalls alone."
    (note "open uses /dev/fb0 and its geometry in /sys/class/graphics/fb0, every /dev/input/event*, /dev/snd/pcmC0D0p for sound and /dev/tty0 for the console, unless devices! names others.")
    (example "(Linux key (lit up))" "1073741906")
    (see open) (see show!) (see poll) (see devices!))
  (static
    (%window-cell (pair () ()))
    (%device-cell (pair (list "/dev/fb0" "/sys/class/graphics/fb0" "/dev/input" "/dev/snd/pcmC0D0p" "/dev/tty0") ()))
    (%sound-cell (pair () ()))

    (method devices! (self (param fb STRING "The framebuffer's device")
                           (param sysfs STRING "Its directory in /sys/class/graphics, which holds virtual_size, bits_per_pixel and stride")
                           (param input STRING "The directory whose event* devices are read for keys")
                           (param pcm STRING "ALSA's playback device")
                           (param console STRING "The console's terminal, put in graphics mode while a window is open"))
      (doc "Name the devices the next open and the first stream use."
        (returns STRING "The framebuffer's device")
        (example "(Linux devices! \"/dev/fb0\" \"/sys/class/graphics/fb0\" \"/dev/input\" \"/dev/snd/pcmC0D0p\" \"/dev/tty0\")" "\"/dev/fb0\""))
      (%set-first! (Linux %device-cell) (list fb sysfs input pcm console))
      fb)

    (method %device (self (param k INTEGER "0 the framebuffer, 1 its sysfs directory, 2 the input directory, 3 the playback device, 4 the console"))
      (doc "A device devices! named."
        (returns STRING "Its path")
        (sample "(Linux %device 0)" "\"/dev/fb0\""))
      (List ref k (first (Linux %device-cell))))

    (method available? (self)
      (doc "Whether a Linux window can be opened: the framebuffer is there."
        (returns BOOL "#t when it is")
        (sample "(Linux available?)" "#t on a Linux machine with a framebuffer"))
      (File exists? (Linux %device 0)))

    (method keys (self)
      (doc "Keycodes by name for keys that are not printable characters: Sdl's, as the window reports SDL's keycodes."
        (returns LIST "((name . keycode) ...)")
        (example "(first (Linux keys))" "('up . 1073741906)"))
      (Sdl keys))

    (method key (self (param name SYMBOL "A key name from (Linux keys)"))
      (doc "The keycode the window reports for a named key."
        (returns INTEGER "SDL's keycode")
        (example "(Linux key (lit escape))" "27"))
      (Sdl key name))

    (method buttons (self)
      (doc "Gamepad button names, as Sdl's; no gamepad is read."
        (returns LIST "Button names")
        (example "(first (Linux buttons))" "'south"))
      (Sdl buttons))

    (method axes (self)
      (doc "Gamepad axis names, as Sdl's; no gamepad is read."
        (returns LIST "Axis names")
        (example "(first (Linux axes))" "'left-x"))
      (Sdl axes))

    (method error (self)
      (doc "The last error message: always empty, as Linux raises its errors."
        (returns STRING "\"\"")
        (example "(Linux error)" "\"\""))
      "")

    (method jit! (self)
      (doc "Build and adopt the compiled loops (JIT; ARM64 and x86-64 backends) now, if they agree with the pure-x loops. Idempotent. Answers #t when they are in use: the pure-x loops draw the same frames and mix the same sound, but a frame takes seconds."
        (returns BOOL "#t when the compiled loops are in use")
        (sample "(Linux jit!)" "#t"))
      (%jit-try!))

    (method %ioctl (self (param fd INTEGER "Descriptor") (param request INTEGER "The request") (param arg ANY "An integer, or a buffer"))
      (doc "ioctl(2) as a syscall, sign-folded."
        (returns INTEGER "0 or more, or negative on error")
        (sample "(Linux %ioctl fd 19258 1)" "0"))
      (Sys %sign-fold (syscall (syscall-id (lit ioctl)) fd request arg)))

    (method %mode (self (param names LIST "Open flags by name"))
      (doc "The open flags named, OR'd."
        (returns INTEGER "The flags")
        (sample "(Linux %mode (list (lit rdonly) (lit nonblock)))" "2048"))
      (List fold (fn (_ acc n) (+ acc (first (Assoc get n file-modes)))) 0 names))

    ; --- The window: a vector of the framebuffer's descriptor, the screen's
    ; width, height and row stride in bytes, the picture's width and height,
    ; the title, the frame drawn last, the scaling, the screen's buffer and
    ; where the picture lies in it, the events waiting for poll, the input
    ; devices' descriptors, the console's descriptor and the modifiers held.
    (method %field (self (param field SYMBOL "A field name"))
      (doc "The slot that holds a field of the window."
        (returns INTEGER "The slot")
        (example "(Linux %field (lit frame))" "7"))
      (match
        ((eq? field (lit fb)) 0) ((eq? field (lit sw)) 1) ((eq? field (lit sh)) 2)
        ((eq? field (lit stride)) 3) ((eq? field (lit w)) 4) ((eq? field (lit h)) 5)
        ((eq? field (lit title)) 6) ((eq? field (lit frame)) 7) ((eq? field (lit scaling)) 8)
        ((eq? field (lit out)) 9) ((eq? field (lit place)) 10) ((eq? field (lit events)) 11)
        ((eq? field (lit inputs)) 12) ((eq? field (lit console)) 13) ((eq? field (lit mods)) 14)
        (#t (Err raise (lit value) "Linux: no such field" field))))

    (method %ref (self (param win VECTOR "A window from open") (param field SYMBOL "A field name"))
      (doc "A field of the window."
        (returns ANY "Its value")
        (sample "(Linux %ref win (lit sw))" "1280"))
      (Vector ref (Linux %field field) win))

    (method %set! (self (param win VECTOR "A window from open") (param field SYMBOL "A field name") (param v ANY "The new value"))
      (doc "Set a field of the window."
        (returns ANY "v")
        (sample "(Linux %set! win (lit events) ())" "nil"))
      (Vector set! (Linux %field field) v win)
      v)

    (method %window (self)
      (doc "The window open, or nil."
        (returns ANY "The window")
        (sample "(Linux %window)" "the window, or nil"))
      (first (Linux %window-cell)))

    (method %numbers (self (param path STRING "A sysfs file of numbers"))
      (doc "The numbers in a file, split at commas and white space."
        (returns LIST "The numbers")
        (sample "(Linux %numbers \"/sys/class/graphics/fb0/virtual_size\")" "(1280 800)"))
      (def text (File read-all path))
      (def n (Str8 length text))
      ((fn (self i from acc)
         (def end? (= i n))
         (def c (if end? 10 (char->int (Str8 ref i text))))
         (if (or (= c 44) (= c 10) (= c 32) (= c 9))
           (let ((acc2 (if (< from i) (pair (%str->number (Str8 sub from (- i from) text)) acc) acc)))
             (if end? (List reverse acc2) (self (+ i 1) (+ i 1) acc2)))
           (self (+ i 1) from acc)))
       0 0 ()))

    (method open (self (param title STRING "Kept for Sdl's sake: the console shows no title")
                       (param w INTEGER "Picture width in pixels")
                       (param h INTEGER "Picture height in pixels")
                       (param scale INTEGER "Taken for Sdl's sake: the picture is fitted to the screen"))
      (doc "Take the screen and the keyboard for a w x h RGBA picture, scaled to the screen by whole multiples with nearest-pixel sampling. The framebuffer must be 32 bits a pixel."
        (returns VECTOR "The window")
        (sample "(Linux open \"x\" 320 200 3)" "a window filling the screen"))
      (unless (null? (Linux %window))
        (Err raise (lit state) "Linux open: a window is open already" ()))
      (def sysfs (Linux %device 1))
      (def size (Linux %numbers (Str8 append sysfs "/virtual_size")))
      (def bpp (first (Linux %numbers (Str8 append sysfs "/bits_per_pixel"))))
      (unless (= bpp 32)
        (Err raise (lit value) "Linux open: the framebuffer is not 32 bits a pixel" bpp))
      (def fb (File open (Linux %device 0) (lit rdwr)))
      (when (< fb 0) (Err raise (lit io) "Linux open: cannot open the framebuffer" (Linux %device 0)))
      (%jit-try!)
      (def win (Vector make 15 ()))
      (Linux %set! win (lit fb) fb)
      (Linux %set! win (lit sw) (first size))
      (Linux %set! win (lit sh) (List ref 1 size))
      (Linux %set! win (lit stride) (first (Linux %numbers (Str8 append sysfs "/stride"))))
      (Linux %set! win (lit w) w)
      (Linux %set! win (lit h) h)
      (Linux %set! win (lit title) title)
      (Linux %set! win (lit scaling) (lit whole))
      (Linux %set! win (lit mods) 0)
      (Linux %set! win (lit inputs) (Linux %open-inputs))
      (Linux %set! win (lit console) (Linux %graphics!))
      (%set-first! (Linux %window-cell) win)
      (Linux %clear! win)
      win)

    (method %open-inputs (self)
      (doc "Every event device in the input directory, opened without blocking and grabbed from the console; those that will not open are left out."
        (returns LIST "Their descriptors")
        (sample "(Linux %open-inputs)" "(5 6)"))
      (def dir (Linux %device 2))
      (def names (guard (_ ()) (File list-dir dir)))
      (def events (List filter (fn (_ n) (Str8 starts? "event" n)) names))
      (def fds (List map (fn (_ n) (File open (Str8 append dir "/" n) (Linux %mode (list (lit rdonly) (lit nonblock))))) events))
      (def open (List filter (fn (_ fd) (<= 0 fd)) fds))
      (List for-each (fn (_ fd) (Linux %ioctl fd %eviocgrab 1)) open)
      open)

    (method %graphics! (self)
      (doc "The console put in graphics mode, so the kernel draws nothing on the screen."
        (returns INTEGER "The console's descriptor, or -1 when there is none")
        (sample "(Linux %graphics!)" "7"))
      (def fd (File open (Linux %device 4) (lit rdwr)))
      (when (<= 0 fd) (Linux %ioctl fd %kd-setmode 1))
      fd)

    ; --- The picture.
    (method scaling! (self (param win VECTOR "A window from open")
                           (param mode SYMBOL "whole: whole multiples only; fit: as large as the screen allows, its shape kept"))
      (doc "Set how the picture is scaled to the screen: by whole multiples, or as large as fits."
        (returns VECTOR "The window")
        (sample "(Linux scaling! win (lit fit))" "win"))
      (unless (or (eq? mode (lit whole)) (eq? mode (lit fit)))
        (Err raise (lit value) "Linux scaling!: the mode is whole or fit" mode))
      (Linux %set! win (lit scaling) mode)
      (Linux %set! win (lit out) ())
      (Linux %clear! win)
      win)

    (method place (self (param win VECTOR "A window from open"))
      (doc "Where the picture lies on the screen: its left and top, and its width and height there."
        (returns LIST "(X Y W H) in the screen's pixels")
        (sample "(Linux place win)" "(0 40 1280 720) for 640 x 360 on 1280 x 800"))
      (def sw (Linux %ref win (lit sw)))
      (def sh (Linux %ref win (lit sh)))
      (def w (Linux %ref win (lit w)))
      (def h (Linux %ref win (lit h)))
      (def size
        (if (eq? (Linux %ref win (lit scaling)) (lit whole))
          (let ((s (%max 1 (%min (int/ sw w) (int/ sh h)))))
            (list (* w s) (* h s)))
          (if (<= (* sw h) (* sh w))
            (list sw (int/ (* h sw) w))
            (list (int/ (* w sh) h) sh))))
      (def dw (%min sw (first size)))
      (def dh (%min sh (List ref 1 size)))
      (list (int/ (- sw dw) 2) (int/ (- sh dh) 2) dw dh))

    (method %clear! (self (param win VECTOR "A window from open"))
      (doc "The whole screen black, ready for the picture."
        (returns ANY "nil")
        (sample "(Linux %clear! win)" "nil"))
      (def fb (Linux %ref win (lit fb)))
      (def row (%zeroed (Linux %ref win (lit stride))))
      (File seek fb 0)
      ((fn (self y) (when (< y (Linux %ref win (lit sh))) (do (File write fb row (Linux %ref win (lit stride))) (self (+ y 1))))) 0)
      ())

    (method canvas (self (param win VECTOR "A window from open"))
      (doc "A zeroed RGBA buffer the size of the window's picture: transparent black."
        (returns STRING "A region of w*h*4 bytes")
        (sample "(Linux canvas win)" "a 256000-byte region for 320 x 200"))
      (%zeroed (* 4 (Linux %ref win (lit w)) (Linux %ref win (lit h)))))

    (method draw! (self (param win VECTOR "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Keep the buffer as the frame; nothing reaches the screen until present!."
        (returns VECTOR "The window")
        (sample "(Linux draw! win (Linux canvas win))" "win"))
      (Linux %set! win (lit frame) buf)
      win)

    (method present! (self (param win VECTOR "A window from open"))
      (doc "Write the frame drawn last to the screen, scaled into its place there: each of the picture's rows is converted once and copied for the screen rows it fills, and the whole screen, its black bars too, goes to the framebuffer in one write, so nothing the console drew outlives a frame."
        (returns VECTOR "The window")
        (sample "(Linux present! win)" "win"))
      (Linux %pump!)
      (def frame (Linux %ref win (lit frame)))
      (unless (null? frame)
        (do (def at (Linux place win))
            (def stride (Linux %ref win (lit stride)))
            (def w (Linux %ref win (lit w)))
            (def h (Linux %ref win (lit h)))
            (def dw (List ref 2 at))
            (def dh (List ref 3 at))
            (when (null? (Linux %ref win (lit out)))
              (Linux %set! win (lit out) (%zeroed (* stride (Linux %ref win (lit sh))))))
            (def out (Linux %ref win (lit out)))
            (def src (%addr frame))
            (def dst (+ (%addr out) (* stride (List ref 1 at)) (* 4 (first at))))
            (def step (int/ (int<< w 16) dw))
            ((fn (self y last)
               (when (< y dh)
                 (let ((sy (int/ (* y h) dh)))
                   (do (if (= sy last)
                         (mem-copy (int->ptr (+ dst (* y stride))) (int->ptr (+ dst (* (- y 1) stride))) (* 4 dw))
                         (%k-row (+ src (* sy w 4)) (+ dst (* y stride)) 0 dw 0 step))
                       (self (+ y 1) sy)))))
             0 -1)
            (def fb (Linux %ref win (lit fb)))
            (File seek fb 0)
            (File write fb out (* stride (Linux %ref win (lit sh))))))
      win)

    (method show! (self (param win VECTOR "A window from open")
                        (param buf STRING "An RGBA buffer the window's size"))
      (doc "Draw the buffer and write it to the screen."
        (returns VECTOR "The window")
        (sample "(Linux show! win buf)" "win"))
      (Linux draw! win buf)
      (Linux present! win))

    (method read-pixels (self (param win VECTOR "A window from open"))
      (doc "The frame drawn last, as an RGBA buffer; nil before any."
        (returns ANY "A region of w*h*4 bytes, or nil")
        (sample "(Linux read-pixels win)" "the drawn frame"))
      (Linux %ref win (lit frame)))

    (method fullscreen! (self (param win VECTOR "A window from open") (param on BOOL "#t for fullscreen, #f for a window"))
      (doc "Taken for Sdl's sake: the window has the whole screen either way."
        (returns VECTOR "The window")
        (sample "(Linux fullscreen! win #t)" "win"))
      win)

    ; --- Keys.
    (method %read-inputs! (self (param win VECTOR "A window from open"))
      (doc "Read what the input devices have, without waiting, and queue its keys as events."
        (returns ANY "nil")
        (sample "(Linux %read-inputs! win)" "nil"))
      (def buf (str-make (* 64 %event-size)))
      (def drain
        (fn (self fd)
          (def n (File read fd buf (* 64 %event-size)))
          (when (< 0 n)
            (do (Linux %events! win buf n)
                (when (= n (* 64 %event-size)) (self fd))))))
      (List for-each drain (Linux %ref win (lit inputs)))
      ())

    (method %events! (self (param win VECTOR "A window from open") (param buf STRING "Input events as the kernel writes them") (param n INTEGER "Bytes of them"))
      (doc "Queue the key events among the first n bytes of buf: a press as key-down, a repeat as key-down repeating, a release as key-up, with the modifiers held."
        (returns ANY "nil")
        (sample "(Linux %events! win buf 48)" "nil"))
      (def p (str->ptr buf))
      ((fn (self at)
         (when (<= (+ at %event-size) n)
           (do (when (= (ptr-ref p (+ at (* 2 %word-size)) 2) 1)
                 (Linux %key-event! win (ptr-ref p (+ at (* 2 %word-size) 2) 2) (ptr-ref p (+ at (* 2 %word-size) 4) 4)))
               (self (+ at %event-size)))))
       0)
      ())

    (method %key-event! (self (param win VECTOR "A window from open") (param code INTEGER "Linux's key number") (param value INTEGER "1 pressed, 2 repeating, 0 released"))
      (doc "Queue one key's event, its modifiers counted first; a key with no SDL keycode is not queued."
        (returns ANY "nil")
        (sample "(Linux %key-event! win 30 1)" "nil"))
      (def bit (%lookup code %modmap))
      (unless (null? bit)
        (Linux %set! win (lit mods)
          (if (= value 0)
            (int& (Linux %ref win (lit mods)) (- 65535 bit))
            (+ (int& (Linux %ref win (lit mods)) (- 65535 bit)) bit))))
      (def k (Linux %keycode code))
      (unless (null? k)
        (Linux %queue! win (list (if (= value 0) (lit key-up) (lit key-down)) k (Linux %ref win (lit mods)) (= value 2))))
      ())

    (method %keycode (self (param code INTEGER "Linux's key number"))
      (doc "The SDL keycode of a Linux key number, as a US keyboard has it."
        (returns INTEGER|NIL "The keycode, or nil for a key with none")
        (example "(Linux %keycode 103)" "1073741906"))
      (%lookup code %keymap))

    (method %queue! (self (param win VECTOR "A window from open") (param event LIST "An event"))
      (doc "Put an event at the end of the queue poll answers from."
        (returns ANY "nil")
        (sample "(Linux %queue! win (list (lit quit)))" "nil"))
      (Linux %set! win (lit events) (List append (Linux %ref win (lit events)) (list event)))
      ())

    (method poll (self)
      (doc "The next event from the keyboard, or nil; the same events as Sdl's poll answers."
        (returns ANY "An event list, or nil")
        (sample "(Linux poll)" "('key-down 97 0 #f)"))
      (Linux %pump!)
      (def win (Linux %window))
      (if (null? win) ()
        (do (Linux %read-inputs! win)
            (let ((events (Linux %ref win (lit events))))
              (if (null? events) ()
                (do (Linux %set! win (lit events) (rest events))
                    (first events)))))))

    (method post-key! (self (param code INTEGER "An SDL keycode"))
      (doc "Queue a key-down event, as a key pressed would be."
        (returns INTEGER "The code")
        (sample "(Linux post-key! 13)" "13"))
      (def win (Linux %window))
      (unless (null? win) (Linux %queue! win (list (lit key-down) code 0 #f)))
      code)

    (method close (self (param win VECTOR "A window from open"))
      (doc "Give the console back in text mode and the keyboard back to it, black the screen and close the devices."
        (returns ANY "nil")
        (sample "(Linux close win)" "nil"))
      (Linux %clear! win)
      (List for-each (fn (_ fd) (do (Linux %ioctl fd %eviocgrab 0) (File close fd))) (Linux %ref win (lit inputs)))
      (def con (Linux %ref win (lit console)))
      (when (<= 0 con) (do (Linux %ioctl con %kd-setmode 0) (File close con)))
      (File close (Linux %ref win (lit fb)))
      (%set-first! (Linux %window-cell) ())
      ())

    ; --- Sound: one device, set to the first stream's rate and channels,
    ; plays the mix of every stream open.  The sound is a vector of the
    ; device's descriptor, its rate, channels, bytes a frame and buffer in
    ; frames, the frames written to it, the streams, and the words the mix
    ; is summed in.  A stream is a vector of its sound, its chunks of bytes
    ; waiting (each (BYTES FROM LEN): its bytes from FROM to LEN), the bytes waiting, and the frame
    ; written to the device after its last.
    (method %sound (self)
      (doc "The sound device open, or nil."
        (returns ANY "The sound")
        (sample "(Linux %sound)" "the sound, or nil"))
      (first (Linux %sound-cell)))

    (method %hw-params (self (param rate INTEGER "Frames a second") (param chans INTEGER "Channels"))
      (doc "A snd_pcm_hw_params asking for interleaved signed 16-bit little-endian frames at the rate and channels, a buffer of a tenth to a quarter of a second, and any period the device likes."
        (returns STRING "The struct, for SNDRV_PCM_IOCTL_HW_PARAMS")
        (sample "(Linux %hw-params 44100 2)" "608 bytes"))
      (def b (%zeroed %pcm-hw-params-size))
      (def p (str->ptr b))
      (def mask! (fn (_ k bit) (ptr-set! p (+ 4 (* k 32) (* 4 (int>> bit 5))) (int<< 1 (int& bit 31)) 4)))
      (def interval! (fn (_ k lo hi) (do (ptr-set! p (+ 260 (* (- k 8) 12)) lo 4) (ptr-set! p (+ 264 (* (- k 8) 12)) hi 4))))
      (mask! 0 3)
      (mask! 1 2)
      (mask! 2 0)
      ((fn (self k) (when (< k 20) (do (interval! k 0 4294967295) (self (+ k 1))))) 8)
      (interval! 8 16 16)
      (interval! 9 (* 16 chans) (* 16 chans))
      (interval! 10 chans chans)
      (interval! 11 rate rate)
      (interval! 17 (int/ rate 10) (int/ rate 4))
      (ptr-set! p 512 4294967295 4)
      (ptr-set! p 520 4294967295 4)
      b)

    (method %open-sound (self (param rate INTEGER "Frames a second") (param chans INTEGER "Channels"))
      (doc "The playback device opened without blocking, set to the rate and channels and prepared."
        (returns VECTOR "The sound")
        (sample "(Linux %open-sound 44100 2)" "the sound"))
      (%jit-try!)
      (def fd (File open (Linux %device 3) (Linux %mode (list (lit rdwr) (lit nonblock)))))
      (when (< fd 0) (Err raise (lit io) "Linux audio-open: cannot open the playback device" (Linux %device 3)))
      (def hw (Linux %hw-params rate chans))
      (when (< (Linux %ioctl fd %pcm-hw-params hw) 0)
        (do (File close fd)
            (Err raise (lit io) "Linux audio-open: the device takes no signed 16-bit frames at that rate" (list rate chans))))
      (Linux %ioctl fd %pcm-prepare 0)
      (def frames (ptr-ref (str->ptr hw) (+ 260 (* 9 12)) 4))
      (def snd (Vector make 8 ()))
      (Vector set! 0 fd snd)
      (Vector set! 1 rate snd)
      (Vector set! 2 chans snd)
      (Vector set! 3 (* 2 chans) snd)
      (Vector set! 4 frames snd)
      (Vector set! 5 0 snd)
      (Vector set! 6 () snd)
      (Vector set! 7 (%zeroed (* frames chans %word-size)) snd)
      (%set-first! (Linux %sound-cell) snd)
      snd)

    (method %delay (self (param snd VECTOR "The sound"))
      (doc "The frames written to the device and not yet played; a device that ran dry is prepared again, with nothing in it."
        (returns INTEGER "Frames")
        (sample "(Linux %delay snd)" "4410"))
      (def d (%zeroed %word-size))
      (def r (Linux %ioctl (Vector ref 0 snd) %pcm-delay d))
      (if (< r 0)
        (do (Linux %ioctl (Vector ref 0 snd) %pcm-prepare 0) 0)
        (%max 0 (ptr-ref-word (str->ptr d) 0))))

    (method %pump! (self)
      (doc "Mix what the streams have waiting into the room the device has, and write it."
        (returns ANY "nil")
        (sample "(Linux %pump!)" "nil"))
      (def snd (Linux %sound))
      (unless (null? snd)
        (do (def bpf (Vector ref 3 snd))
            (def want (List fold (fn (_ m s) (%max m (int/ (Vector ref 2 s) bpf))) 0 (Vector ref 6 snd)))
            (def k (%min want (- (Vector ref 4 snd) (Linux %delay snd))))
            (when (< 0 k)
              (do (def acc (Vector ref 7 snd))
                  (def samples (* k (Vector ref 2 snd)))
                  (List for-each (fn (_ s) (Linux %take! s (%addr acc) (* k bpf) (+ (Vector ref 5 snd) k))) (Vector ref 6 snd))
                  (def out (str-make (* k bpf)))
                  (%k-out (%addr acc) (%addr out) 0 samples)
                  (def x (%zeroed (* 3 %word-size)))
                  (ptr-set-word! (str->ptr x) %word-size (%addr out))
                  (ptr-set-word! (str->ptr x) (* 2 %word-size) k)
                  (when (< (Linux %ioctl (Vector ref 0 snd) %pcm-writei x) 0)
                    (do (Linux %ioctl (Vector ref 0 snd) %pcm-prepare 0)
                        (Linux %ioctl (Vector ref 0 snd) %pcm-writei x)))
                  (Vector set! 5 (+ (Vector ref 5 snd) k) snd)))))
      ())

    (method %take! (self (param s VECTOR "A stream") (param acc INTEGER "The mix's words") (param n INTEGER "Bytes wanted") (param until INTEGER "The frame written after these"))
      (doc "Add up to n of the stream's bytes waiting into the mix, and drop them from it."
        (returns ANY "nil")
        (sample "(Linux %take! s acc 1764 4410)" "nil"))
      ((fn (self done)
         (def chunks (Vector ref 1 s))
         (when (if (< done n) (not (null? chunks)) #f)
           (let ((bytes (first (first chunks))) (from (List ref 1 (first chunks))) (len (List ref 2 (first chunks))))
             (let ((m (%min (- n done) (- len from))))
               (do (%k-add (+ (%addr bytes) from) (+ acc (* (int/ done 2) %word-size)) 0 (int/ m 2))
                   (Vector set! 2 (- (Vector ref 2 s) m) s)
                   (Vector set! 3 until s)
                   (Vector set! 1 (if (= (+ from m) len) (rest chunks) (pair (list bytes (+ from m) len) (rest chunks))) s)
                   (self (+ done m)))))))
       0)
      ())

    (method audio-open (self (param rate INTEGER "Frames a second, such as 44100")
                             (param chans INTEGER "Channels: 1 or 2"))
      (doc "Open a stream of signed 16-bit frames. The first opens the playback device at its rate and channels; every stream after must have the same."
        (returns VECTOR "The stream")
        (sample "(Linux audio-open 44100 2)" "a stream"))
      (def snd (if (null? (Linux %sound)) (Linux %open-sound rate chans) (Linux %sound)))
      (unless (if (= rate (Vector ref 1 snd)) (= chans (Vector ref 2 snd)) #f)
        (Err raise (lit value) "Linux audio-open: every stream has the first stream's rate and channels" (list rate chans)))
      (def s (Vector make 4 ()))
      (Vector set! 0 snd s)
      (Vector set! 2 0 s)
      (Vector set! 3 0 s)
      (Vector set! 6 (List append (Vector ref 6 snd) (list s)) snd)
      s)

    (method audio-put! (self (param s VECTOR "A stream from audio-open")
                             (param buf STRING "Signed 16-bit frames")
                             (param n INTEGER "Bytes of buf to play"))
      (doc "Queue n bytes of buf to play after what the stream has queued; they are copied, so buf may be used again."
        (returns BOOL "#t")
        (sample "(Linux audio-put! s buf 4096)" "#t"))
      (when (< 0 n)
        (do (def copy (str-make n))
            (mem-copy (str->ptr copy) (str->ptr buf) n)
            (Vector set! 1 (List append (Vector ref 1 s) (list (list copy 0 n))) s)
            (Vector set! 2 (+ (Vector ref 2 s) n) s)))
      (Linux %pump!)
      #t)

    (method audio-queued (self (param s VECTOR "A stream from audio-open"))
      (doc "Bytes the stream has queued and not yet played: those waiting to be mixed, and those mixed and still in the device."
        (returns INTEGER "Bytes")
        (sample "(Linux audio-queued s)" "17640"))
      (Linux %pump!)
      (def snd (Vector ref 0 s))
      (def played (- (Vector ref 5 snd) (Linux %delay snd)))
      (+ (Vector ref 2 s) (* (Vector ref 3 snd) (%max 0 (- (Vector ref 3 s) played)))))

    (method audio-clear! (self (param s VECTOR "A stream from audio-open"))
      (doc "Drop what the stream has waiting to be mixed; what is in the device plays out."
        (returns BOOL "#t")
        (sample "(Linux audio-clear! s)" "#t"))
      (Vector set! 1 () s)
      (Vector set! 2 0 s)
      #t)

    (method audio-close (self (param s VECTOR "A stream from audio-open"))
      (doc "Release the stream. When the last is gone the device is stopped and closed."
        (returns ANY "nil")
        (sample "(Linux audio-close s)" "nil"))
      (def snd (Vector ref 0 s))
      (Vector set! 6 (List filter (fn (_ t) (not (eq? t s))) (Vector ref 6 snd)) snd)
      (when (null? (Vector ref 6 snd))
        (do (Linux %ioctl (Vector ref 0 snd) %pcm-drop 0)
            (File close (Vector ref 0 snd))
            (%set-first! (Linux %sound-cell) ())))
      ())))

(doc (provide x/sys/linux Linux)
  "A window on the Linux console that answers Sdl's messages: the picture on the framebuffer, keys from the kernel's input devices, sound through ALSA's playback device, all by syscalls."
  (example "(Linux key (lit escape))" "27"))
