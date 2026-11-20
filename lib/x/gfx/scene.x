; scene.x -- Scene: figures and animations drawn as a frame.
;
; A frame is a canvas, black behind, with each figure drawn on it in order
; and then each animation's figure at one progress.  The frame is 8 units
; high whatever the canvas (x/gfx/figure).
(module x/gfx/scene)

(import x/gfx/canvas)
(import x/gfx/figure)
(import x/num/float float-of f-mul f-sub)

(def %two (float-of 2))
(def %three (float-of 3))

(def-class Scene ()
  (doc "Figures and animations drawn as a frame: a canvas, black behind, each figure on it in order and then each animation's figure at one progress."
    (example "(do (import x/gfx/canvas) (import x/gfx/figure) (Canvas pixel (Scene frame (list (Figure fill (Figure square 4) (list 9 8 7))) () 0 8 8) 4 4))" "(9 8 7 255)")
    (see frame))
  (static
    (method smooth (self (param progress NUMBER "0 to 1"))
      (doc "Progress eased: slow away from 0 and slow into 1, 3p^2 - 2p^3."
        (returns FLOAT "0 to 1")
        (example "(Scene smooth 0.5)" "0.5")
        (example "(Scene smooth 0.25)" "0.15625"))
      ((fn (_ p) (f-mul (f-mul p p) (f-sub %three (f-mul %two p)))) (float-of progress)))

    (method frame (self (param figures LIST "Figures, drawn first to last")
                        (param animations LIST "Animations, each drawn at PROGRESS after the figures")
                        (param progress NUMBER "0 to 1")
                        (param width INTEGER "The canvas's width in pixels")
                        (param height INTEGER "The canvas's height in pixels"))
      (doc "The frame: an opaque black canvas with the figures and the animations' figures drawn on it."
        (returns LIST "A canvas")
        (example "(do (import x/gfx/canvas) (import x/gfx/figure) (Canvas pixel (Scene frame () (list (Figure fade-out (Figure fill (Figure square 4) (list 200 100 50)))) 1 8 8) 4 4))" "(0 0 0 255)"))
      ((fn (_ c)
         (do (List for-each (fn (_ f) (Figure draw! c f)) figures)
             (List for-each (fn (_ a) (Figure draw! c (a progress))) animations)
             c))
       (Canvas fill! (Canvas make width height) 0 0 width height (list 0 0 0))))))

(doc (provide x/gfx/scene Scene)
  "A scene's frame: (Scene frame figures animations progress width height) draws figures and animations at one progress on a black canvas; (Scene smooth p) eases a progress."
  (example "(Scene smooth 0.5)" "0.5"))
