; state.x -- Turtle state and movement primitives
(import x/num/float)

; ============================================================
; State
; ============================================================

(def %turtle-x (exact->inexact 0))
(def %turtle-y (exact->inexact 0))
(def %turtle-heading (exact->inexact 0))
(def %turtle-pen #t)
(def %turtle-segments ())

(def %deg->rad
  (fn (_ deg)
    (f/ (f* (if (float? deg) deg (exact->inexact deg)) %pi)
        (exact->inexact 180))))

(def %as-float
  (fn (_ n) (if (float? n) n (exact->inexact n))))

(def %as-int
  (fn (_ n) (if (float? n) (inexact->exact n) n)))

; ============================================================
; Segment emission
; ============================================================

; Hook called after each entry — set by server
(def %turtle-on-segment ())

; Segment format: (x y h d p)
;   x,y = position BEFORE this step
;   h   = heading BEFORE this step
;   d   = distance moved (0 for pure turns)
;   p   = pen state (#t/#f)
(def %turtle-emit
  (fn (_ dist)
    (def seg (list %turtle-x %turtle-y %turtle-heading dist %turtle-pen))
    (set! %turtle-segments (pair seg %turtle-segments))
    (if (null? %turtle-on-segment) () (%turtle-on-segment seg))))

; ============================================================
; Movement
; ============================================================

(def turtle-forward
  (fn (_ n)
    (def dist (%as-float n))
    (%turtle-emit dist)
    (def rad (%deg->rad %turtle-heading))
    (set! %turtle-x (f+ %turtle-x (f* dist (fsin rad))))
    (set! %turtle-y (f- %turtle-y (f* dist (fcos rad))))))

(def turtle-back
  (fn (_ n) (turtle-forward (- n))))

(def turtle-right
  (fn (_ n)
    (%turtle-emit (exact->inexact 0))
    (set! %turtle-heading (f+ %turtle-heading (%as-float n)))))

(def turtle-left
  (fn (_ n)
    (%turtle-emit (exact->inexact 0))
    (set! %turtle-heading (f- %turtle-heading (%as-float n)))))

(def turtle-penup   (fn () (set! %turtle-pen #f)))
(def turtle-pendown (fn () (set! %turtle-pen #t)))

(def %turtle-on-clear ())

(def turtle-clearscreen
  (fn ()
    (set! %turtle-x (exact->inexact 0))
    (set! %turtle-y (exact->inexact 0))
    (set! %turtle-heading (exact->inexact 0))
    (set! %turtle-pen #t)
    (set! %turtle-segments ())
    (if (null? %turtle-on-clear) () (%turtle-on-clear))))

(provide x/logo/state
  %turtle-x %turtle-y %turtle-heading %turtle-pen %turtle-segments
  %as-float %as-int
  turtle-forward turtle-back turtle-right turtle-left
  turtle-penup turtle-pendown turtle-clearscreen
  %turtle-on-segment %turtle-on-clear)
