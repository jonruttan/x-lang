; state.x -- Turtle state and movement primitives
(import x/num/float)

; ============================================================
; State
; ============================================================

(def %turtle-x (Float exact->inexact 0))
(def %turtle-y (Float exact->inexact 0))
(def %turtle-heading (Float exact->inexact 0))
(def %turtle-pen #t)
(def %turtle-pen-color "#222")
(def %turtle-pen-width (Float exact->inexact 1))
(def %turtle-bc ())    ; bytecode list (reversed, newest first)

(def %deg->rad
  (fn (_ deg)
    (Float / (Float * (if (Float float? deg) deg (Float exact->inexact deg)) %pi)
        (Float exact->inexact 180))))

(def %as-float
  (fn (_ n) (if (Float float? n) n (Float exact->inexact n))))

(def %as-int
  (fn (_ n) (if (Float float? n) (Float inexact->exact n) n)))

; ============================================================
; Bytecode emission
; ============================================================

; Hook called after each bytecode entry — set by server
(def %turtle-on-bc ())

; Emit opcode with no args
(def %bc-emit-0
  (fn (_ op)
    (set! %turtle-bc (pair op %turtle-bc))
    (unless (null? %turtle-on-bc) (%turtle-on-bc op))))

; Emit opcode with one float arg
(def %bc-emit-1
  (fn (_ op val)
    (set! %turtle-bc (pair val (pair op %turtle-bc)))
    (unless (null? %turtle-on-bc) (%turtle-on-bc op val))))

; Emit opcode with two float args
(def %bc-emit-2
  (fn (_ op a b)
    (set! %turtle-bc (pair b (pair a (pair op %turtle-bc))))
    (unless (null? %turtle-on-bc) (%turtle-on-bc op a b))))

; ============================================================
; Movement
; ============================================================

(def turtle-forward
  (fn (_ n)
    (def dist (%as-float n))
    (%bc-emit-1 "F" dist)
    (def rad (%deg->rad %turtle-heading))
    (set! %turtle-x (Float + %turtle-x (Float * dist (Float sin rad))))
    (set! %turtle-y (Float - %turtle-y (Float * dist (Float cos rad))))))

(def turtle-back
  (fn (_ n) (turtle-forward (- n))))

(def turtle-right
  (fn (_ n)
    (def deg (%as-float n))
    (set! %turtle-heading (Float + %turtle-heading deg))
    (%bc-emit-1 "R" deg)))

(def turtle-left
  (fn (_ n)
    (def deg (%as-float n))
    (set! %turtle-heading (Float - %turtle-heading deg))
    (%bc-emit-1 "L" deg)))

(def turtle-penup   (fn () (set! %turtle-pen #f) (%bc-emit-0 "U")))
(def turtle-pendown (fn () (set! %turtle-pen #t) (%bc-emit-0 "D")))

(def turtle-pencolor
  (fn (_ color)
    (set! %turtle-pen-color color)
    (%bc-emit-1 "K" color)))

(def turtle-penwidth
  (fn (_ width)
    (set! %turtle-pen-width (%as-float width))
    (%bc-emit-1 "W" (%as-float width))))

(def %turtle-on-clear ())

(def turtle-clearscreen
  (fn ()
    (set! %turtle-x (Float exact->inexact 0))
    (set! %turtle-y (Float exact->inexact 0))
    (set! %turtle-heading (Float exact->inexact 0))
    (set! %turtle-pen #t)
    (set! %turtle-pen-color "#222")
    (set! %turtle-pen-width (Float exact->inexact 1))
    (set! %turtle-bc ())
    (unless (null? %turtle-on-clear) (%turtle-on-clear))))


(provide x/logo/state
  %turtle-x %turtle-y %turtle-heading %turtle-pen %turtle-bc
  %as-float %as-int
  turtle-forward turtle-back turtle-right turtle-left
  turtle-penup turtle-pendown turtle-pencolor turtle-penwidth
  turtle-clearscreen
  %turtle-on-bc %turtle-on-clear
  %bc-emit-0 %bc-emit-1 %bc-emit-2)
