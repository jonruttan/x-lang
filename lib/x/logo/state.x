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
; Movement
; ============================================================

; Hook called after each new segment — set by server
(def %turtle-on-segment ())

(def turtle-forward
  (fn (_ n)
    (def dist (%as-float n))
    (def rad (%deg->rad %turtle-heading))
    (def nx (f+ %turtle-x (f* dist (fsin rad))))
    (def ny (f- %turtle-y (f* dist (fcos rad))))
    (def seg (list %turtle-x %turtle-y nx ny %turtle-pen %turtle-heading))
    (set! %turtle-segments (pair seg %turtle-segments))
    (set! %turtle-x nx)
    (set! %turtle-y ny)
    (if (null? %turtle-on-segment) () (%turtle-on-segment seg))))

(def turtle-back
  (fn (_ n) (turtle-forward (- n))))

; Notify the browser of heading changes without adding to segment list
(def %emit-heading-update
  (fn ()
    (if (null? %turtle-on-segment) ()
      (%turtle-on-segment
        (list %turtle-x %turtle-y %turtle-x %turtle-y #f %turtle-heading)))))

(def turtle-right
  (fn (_ n)
    (set! %turtle-heading (f+ %turtle-heading (%as-float n)))
    (%emit-heading-update)))

(def turtle-left
  (fn (_ n)
    (set! %turtle-heading (f- %turtle-heading (%as-float n)))
    (%emit-heading-update)))

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
