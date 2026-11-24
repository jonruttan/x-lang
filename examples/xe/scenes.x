; scenes.x -- Seven short animated scenes: figures made, placed, morphed
; and played (x/gfx/figure, x/gfx/scene)
;
; Usage:
;   sh x.sh -l xe -f examples/xe/scenes.x
;       draws each scene's last frame and prints the pixel at its centre
;
;   SCENES=web sh x.sh -l xe -f examples/xe/scenes.x
;       plays them in a browser; the page's address is printed on stderr
;
;   SCENES=sdl sh x.sh -l xe -f examples/xe/scenes.x
;       plays them in a window, on a host with SDL3
;
; The scenes follow the Manim Community quickstart tutorial, one for one.

(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/num/float)
(import x/num/float/literal)
(import x/sys/posix)

(def pink (list 209 71 189 128))
(def sky (list 88 196 221 178))
(def leaf (list 131 193 103 178))
(def coral (list 252 98 85))

(def quarter-turn (Float / (Float pi) 4))

; A figure is a value: each of these answers a new one.
(def ring (Figure stroke (Figure circle 1) coral 0.04))
(def pink-ring (Figure fill ring pink))
(def plain-square (Figure square 2))
(def tilted (Figure rotate plain-square quarter-turn))

; A scene is a function of PLAY and WAIT.  (play figures animations seconds)
; shows the figures while the animations run and answers the figures
; afterwards; (wait figures seconds) holds them.

; A circle drawn.
(def create-circle
  (fn (_ play wait)
    (play () (list (Figure create pink-ring)) 1)))

; A square drawn, morphed into a circle, and faded out.
(def square-to-circle
  (fn (_ play wait)
    (def drawn (play () (list (Figure create tilted)) 1))
    (def rounded (play () (list (Figure morph (first drawn) pink-ring)) 1))
    (play () (list (Figure fade-out (first rounded))) 1)))

; Two figures side by side, drawn together.
(def square-and-circle
  (fn (_ play wait)
    (def beside (Figure next-to (Figure fill plain-square sky) pink-ring 'right 0.5))
    (play () (list (Figure create pink-ring) (Figure create beside)) 1)))

; A change animated is a morph from a figure to its changed copy.
(def animated-square-to-circle
  (fn (_ play wait)
    (def drawn (play () (list (Figure create plain-square)) 1))
    (def turned (play () (list (Figure morph (first drawn) tilted)) 1))
    (def rounded (play () (list (Figure morph (first turned) ring)) 1))
    (play () (list (Figure morph (first rounded) pink-ring)) 1)))

; A morph to a half-turned square shrinks through its middle; a turn keeps
; its size all the way.
(def different-rotations
  (fn (_ play wait)
    (def left (Figure shift (Figure fill (Figure stroke plain-square sky 0.04) sky) -2 0))
    (def right (Figure shift (Figure fill (Figure stroke plain-square leaf 0.04) leaf) 2 0))
    (wait (play () (list (Figure morph left (Figure rotate left (Float pi)))
                         (Figure turn right (Float pi)))
                2)
          1)))

; One figure morphed twice, then faded.
(def two-transforms
  (fn (_ play wait)
    (def squared (play () (list (Figure morph ring plain-square)) 1))
    (def cornered (play () (list (Figure morph (first squared) (Figure triangle 1))) 1))
    (wait (play () (list (Figure fade-out (first cornered))) 1) 0.5)))

; A figure shown, held, and morphed through two others.
(def transform-cycle
  (fn (_ play wait)
    (def shown (wait (list ring) 1))
    (def squared (play () (list (Figure morph (first shown) plain-square)) 1))
    (play () (list (Figure morph (first squared) (Figure triangle 1))) 1)))

(def all-scenes
  (list (pair "create-circle" create-circle)
        (pair "square-to-circle" square-to-circle)
        (pair "square-and-circle" square-and-circle)
        (pair "animated-square-to-circle" animated-square-to-circle)
        (pair "different-rotations" different-rotations)
        (pair "two-transforms" two-transforms)
        (pair "transform-cycle" transform-cycle)))

; With no window, a scene's animations go straight to their end and its
; last frame is drawn: 160 by 90, the pixel at the centre printed.
(def draw-stills
  (fn (_)
    (List for-each
      (fn (_ s)
        ((fn (_ figures)
           (do (display (first s))
               (display " ")
               (write (Canvas pixel (Scene frame figures () 1 160 90) 80 45))
               (newline)))
         ((rest s) (fn (_ figures animations seconds) (Scene after figures animations))
                   (fn (_ figures seconds) figures))))
      all-scenes)))

; On a stage, each scene plays and its end is held a moment.
(def play-live
  (fn (_ front)
    (def stage (Scene open front "scenes" 854 480 15))
    (List for-each
      (fn (_ s)
        (Scene wait stage
          ((rest s) (fn (_ figures animations seconds) (Scene play stage figures animations seconds))
                    (fn (_ figures seconds) (Scene wait stage figures seconds)))
          0.5))
      all-scenes)
    (Scene close stage)))

((fn (_ how)
   (match
     ((null? how) (draw-stills))
     ((str=? how "web") (do (import x/sys/web) (play-live Web)))
     ((str=? how "sdl") (do (import x/sys/sdl) (play-live Sdl)))
     (#t (draw-stills))))
 (Sys getenv "SCENES"))
