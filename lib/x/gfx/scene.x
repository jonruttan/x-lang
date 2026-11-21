; scene.x -- Scene: figures and animations drawn as frames, and played.
;
; A frame is a canvas, black behind, with each figure drawn on it in order
; and then each animation's figure at one progress.  The frame is 8 units
; high whatever the canvas (x/gfx/figure).
;
; A stage is where frames are shown: (FRONT WINDOW WIDTH HEIGHT RATE
; STOPPED).  FRONT is a class that answers Sdl's messages (x/sys/sdl,
; x/sys/web, x/sys/linux); open, show!, poll and close are the four sent.
; RATE is the most frames shown a second.  STOPPED is a cell, #t once the
; window was closed: playing and waiting on a stopped stage show nothing
; and answer at once, so a script of scenes runs out.
;
; Playing goes by the clock.  Each frame is drawn at the share of the time
; gone, eased, so animations last what they were given however long a frame
; takes, and the last frame is the animations' end.  The figures that do
; not change are drawn once a play, and each frame is a copy of that with
; the animations' figures drawn on.  The heap is collected after every
; frame.
(module x/gfx/scene)

(import x/gfx/canvas)
(import x/gfx/shape)
(import x/gfx/figure)
(import x/sys/posix)
(import x/num/float Float float-of f-div f-mul f-sub)

(import x/core/doors int* int+ int- int/ int<)

(def %one (float-of 1))
(def %two (float-of 2))
(def %three (float-of 3))
(def %million (float-of 1000000))

(def %smooth (fn (_ p) (f-mul (f-mul p p) (f-sub %three (f-mul %two p)))))

(def %frame
  (fn (_ figures animations progress width height)
    ((fn (_ c)
       (do (List for-each (fn (_ f) (Figure draw! c f)) figures)
           (List for-each (fn (_ a) (Figure draw! c (a progress))) animations)
           c))
     (Canvas fill! (Canvas make width height) 0 0 width height (list 0 0 0)))))

(def %after
  (fn (_ figures animations)
    (List append figures (List map (fn (_ a) (a 1)) animations))))

; --- A stage's parts -------------------------------------------------------

(def %front (fn (_ s) (first s)))
(def %window (fn (_ s) (first (rest s))))
(def %width (fn (_ s) (first (rest (rest s)))))
(def %height (fn (_ s) (first (rest (rest (rest s))))))
(def %rate (fn (_ s) (first (rest (rest (rest (rest s)))))))
(def %stopped (fn (_ s) (first (rest (rest (rest (rest (rest s))))))))

(def %stopped? (fn (_ s) (first (%stopped s))))

; --- Playing ---------------------------------------------------------------

; Microseconds since T0, a (Sys time-of-day).
(def %since
  (fn (_ t0)
    ((fn (_ t1) (int+ (int* (int- (first t1) (first t0)) 1000000) (int- (rest t1) (rest t0))))
     (Sys time-of-day))))

(def %micros (fn (_ seconds) (Float ->int (f-mul (float-of seconds) %million))))

; Every event waiting is read; a quit or a close stops the stage.
(def %events!
  (fn (self s)
    ((fn (_ e)
       (unless (null? e)
         (do (when (if (eq? (first e) (lit quit)) #t (eq? (first e) (lit close)))
               (%set-first! (%stopped s) #t))
             (self s))))
     ((%front s) poll))))

(def %show!
  (fn (_ s figures animations progress)
    ((%front s) show! (%window s)
      (first (rest (rest (%frame figures animations progress (%width s) (%height s))))))))

; A frame from BACK, the frame of the figures that do not change: a copy
; of it with the animations' figures drawn on.
(def %show-over!
  (fn (_ s back animations progress)
    ((fn (_ c)
       (do (List for-each (fn (_ a) (Figure draw! c (a progress))) animations)
           ((%front s) show! (%window s) (first (rest (rest c))))))
     (Canvas copy! (Canvas make (%width s) (%height s)) 0 0 back 0 0 (%width s) (%height s)))))

; Sleep what is left of a frame's time, STARTED microseconds after T0.
(def %pace!
  (fn (_ s t0 started)
    ((fn (_ left) (when (int< 0 left) (Sys usleep left)))
     (int- (int/ 1000000 (%rate s)) (int- (%since t0) started)))))

(def %play
  (fn (_ s figures animations seconds)
    (def total (%micros seconds))
    (unless (%stopped? s)
      ((fn (_ t0 back)
         ((fn (self)
            ((fn (_ gone)
               (do (%show-over! s back animations
                     (if (int< gone total) (%smooth (f-div (float-of gone) (float-of total))) %one))
                   (%events! s)
                   (Heap collect)
                   (when (if (int< gone total) (if (%stopped? s) #f #t) #f)
                     (do (%pace! s t0 gone)
                         (self)))))
             (%since t0)))))
       (Sys time-of-day)
       (%frame figures () %one (%width s) (%height s))))
    (%after figures animations)))

(def %wait
  (fn (_ s figures seconds)
    (def total (%micros seconds))
    (unless (%stopped? s)
      ((fn (_ t0)
         (do (%show! s figures () %one)
             (Heap collect)
             ((fn (self)
                ((fn (_ gone)
                   (do (%events! s)
                       (when (if (int< gone total) (if (%stopped? s) #f #t) #f)
                         (do (%pace! s t0 gone)
                             (self)))))
                 (%since t0))))))
       (Sys time-of-day)))
    figures))

(def-class Scene ()
  (doc "Figures and animations drawn as frames, and played on a stage. A frame is a canvas, black behind, each figure on it in order and then each animation's figure at one progress. A stage shows frames through a front end, a class that answers Sdl's messages; play runs animations by the clock and answers the figures as they stand afterwards."
    (example "(do (import x/gfx/canvas) (import x/gfx/figure) (Canvas pixel (Scene frame (list (Figure fill (Figure square 4) (list 9 8 7))) () 0 8 8) 4 4))" "(9 8 7 255)")
    (see frame) (see play))
  (static
    (method smooth (self (param progress NUMBER "0 to 1"))
      (doc "Progress eased: slow away from 0 and slow into 1, 3p^2 - 2p^3."
        (returns FLOAT "0 to 1")
        (example "(Scene smooth 0.5)" "0.5")
        (example "(Scene smooth 0.25)" "0.15625"))
      (%smooth (float-of progress)))

    (method frame (self (param figures LIST "Figures, drawn first to last")
                        (param animations LIST "Animations, each drawn at PROGRESS after the figures")
                        (param progress NUMBER "0 to 1")
                        (param width INTEGER "The canvas's width in pixels")
                        (param height INTEGER "The canvas's height in pixels"))
      (doc "The frame: an opaque black canvas with the figures and the animations' figures drawn on it."
        (returns LIST "A canvas")
        (example "(do (import x/gfx/canvas) (import x/gfx/figure) (Canvas pixel (Scene frame () (list (Figure fade-out (Figure fill (Figure square 4) (list 200 100 50)))) 1 8 8) 4 4))" "(0 0 0 255)"))
      (%frame figures animations progress width height))

    (method after (self (param figures LIST "Figures")
                        (param animations LIST "Animations"))
      (doc "The figures as they stand once the animations are done: FIGURES, then each animation's figure at progress 1. It is what play answers."
        (returns LIST "Figures")
        (example "(do (import x/gfx/figure) (Figure bounds (first (Scene after () (list (Figure morph (Figure square 2) (Figure square 4)))))))" "(-2.0 -2.0 2.0 2.0)"))
      (%after figures animations))

    (method open (self (param front ANY "A front end's class: Sdl, Web or Linux")
                       (param title STRING "The window's title")
                       (param width INTEGER "The frame's width in pixels")
                       (param height INTEGER "The frame's height in pixels")
                       (param rate INTEGER "The most frames shown a second, 1 or more"))
      (doc "A stage: a window of FRONT's showing WIDTH x HEIGHT frames. Builds Shape's and Canvas's compiled loops first, where there is a JIT."
        (returns LIST "(FRONT WINDOW WIDTH HEIGHT RATE STOPPED)")
        (sample "(do (import x/sys/web) (Scene open Web \"scene\" 854 480 15))" "a stage, its page's address on stderr"))
      (do (Shape jit!)
          (Canvas jit!)
          (list front (front open title width height 1) width height rate (pair #f ()))))

    (method play (self (param stage LIST "A stage, from open")
                       (param figures LIST "Figures shown throughout")
                       (param animations LIST "Animations run together")
                       (param seconds NUMBER "How long they run"))
      (doc "Show frames of the figures and the animations for SECONDS, each frame at the share of the time gone, eased by smooth; the last frame is the animations' end. A window closed on the way stops the stage. On a stopped stage nothing is shown."
        (returns LIST "The figures afterwards, as after answers them")
        (sample "(Scene play stage () (list (Figure create (Figure circle 1))) 1)" "the circle, once it has been drawn over a second"))
      (%play stage figures animations seconds))

    (method wait (self (param stage LIST "A stage, from open")
                       (param figures LIST "Figures shown")
                       (param seconds NUMBER "How long to hold them"))
      (doc "Show the figures and hold them for SECONDS, reading the window's events meanwhile."
        (returns LIST "FIGURES")
        (sample "(Scene wait stage figures 0.5)" "figures, half a second on"))
      (%wait stage figures seconds))

    (method stopped? (self (param stage LIST "A stage, from open"))
      (doc "Whether the stage's window was closed while playing or waiting."
        (returns BOOL "#t once it was")
        (sample "(Scene stopped? stage)" "#f"))
      (%stopped? stage))

    (method close (self (param stage LIST "A stage, from open"))
      (doc "Close the stage's window."
        (returns ANY "nil")
        (sample "(Scene close stage)" "nil"))
      (do ((%front stage) close (%window stage))
          ()))))

(doc (provide x/gfx/scene Scene)
  "A scene's frames and its stage: (Scene frame figures animations progress width height) draws one frame; (Scene open front title width height rate) makes a stage on Sdl, Web or Linux, and play, wait and close run it."
  (example "(Scene smooth 0.5)" "0.5"))
