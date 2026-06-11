; tstate.x -- Extended turtle state commands
(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/num/float)

; ============================================================
; Turtle visibility and scale
; ============================================================

(def %turtle-visible #t)
(def %turtle-scale (Float exact->inexact 1))

; ============================================================
; Extended movement commands (emit bytecodes)
; ============================================================

; SETXY: move to absolute position
(def turtle-setxy
  (fn (_ x y)
    (def nx (%as-float x))
    (def ny (%as-float y))
    (%bc-emit-2 "M" nx ny)
    (set! %turtle-x nx)
    (set! %turtle-y ny)))

; HOME: return to origin, heading 0
(def turtle-home
  (fn ()
    (%bc-emit-0 "O")
    (set! %turtle-x (Float exact->inexact 0))
    (set! %turtle-y (Float exact->inexact 0))
    (set! %turtle-heading (Float exact->inexact 0))))

; DISTANCE: distance from turtle to a point (x, y)
(def turtle-distance
  (fn (_ px py)
    (def dx (Float - (%as-float px) %turtle-x))
    (def dy (Float - (%as-float py) %turtle-y))
    (Float sqrt (Float + (Float * dx dx) (Float * dy dy)))))

; TOWARDS: heading from turtle toward point (x, y), in degrees
(def turtle-towards
  (fn (_ px py)
    (def dx (Float - (%as-float px) %turtle-x))
    (def dy (Float - %turtle-y (%as-float py)))
    (def rad (Float atan2 dx dy))
    (Float / (Float * rad (Float exact->inexact 180)) %pi)))

; TURTLE.STATE: return current state as list
(def turtle-state
  (fn ()
    (list %turtle-x %turtle-y %turtle-heading %turtle-pen)))

; SETTURTLE: restore state from list
(def turtle-setturtle
  (fn (_ state)
    (set! %turtle-x (first state))
    (set! %turtle-y (first (rest state)))
    (set! %turtle-heading (first (rest (rest state))))
    (set! %turtle-pen (first (rest (rest (rest state)))))))

; ============================================================
; Register commands in the command table
; ============================================================

(set! %logo-commands
  (pair (list "SETXY"       2 (fn (_ x y) (turtle-setxy x y)))
  (pair (list "HOME"        0 turtle-home)
  (pair (list "HIDETURTLE"  0 (fn () (set! %turtle-visible #f)))
  (pair (list "HT"          0 (fn () (set! %turtle-visible #f)))
  (pair (list "SHOWTURTLE"  0 (fn () (set! %turtle-visible #t)))
  (pair (list "ST"          0 (fn () (set! %turtle-visible #t)))
  (pair (list "PENCOLOR"    1 (fn (_ c) (turtle-pencolor c)))
  (pair (list "PC"          1 (fn (_ c) (turtle-pencolor c)))
  (pair (list "PENWIDTH"    1 (fn (_ w) (turtle-penwidth w)))
  (pair (list "PW"          1 (fn (_ w) (turtle-penwidth w)))
  (pair (list "SETX"        1 (fn (_ x) (turtle-setxy x %turtle-y)))
  (pair (list "SETY"        1 (fn (_ y) (turtle-setxy %turtle-x y)))
  (pair (list "SETHEADING"  1 (fn (_ n)
          (set! %turtle-heading (%as-float n))
          (%bc-emit-1 "H" (%as-float n))))
  (pair (list "SETH"        1 (fn (_ n)
          (set! %turtle-heading (%as-float n))
          (%bc-emit-1 "H" (%as-float n))))
  %logo-commands)))))))))))))))

; Register state query functions
(set! %logo-functions
  (pair (list "DISTANCE"      2 (fn (_ x y) (turtle-distance x y)))
  (pair (list "TOWARDS"       2 (fn (_ x y) (turtle-towards x y)))
  (pair (list "TURTLE.STATE"  turtle-state)
  %logo-functions))))

(set! %logo-commands
  (pair (list "SETTURTLE" 1 (fn (_ state) (turtle-setturtle state)))
  (pair (list "FACE"      2 (fn (_ x y)
          (def bearing (turtle-towards x y))
          (def turn (Float - bearing %turtle-heading))
          (turtle-left turn)))
  %logo-commands)))

; MEMBER function
(set! %logo-functions
  (pair (list "MEMBER" 2
    (fn (_ item lst)
      (def %search
        (fn (self l)
          (match
            ((null? l) #f)
            ((if (number? item) (= (first l) item) (eq? (first l) item)) #t)
            (#t (self (rest l))))))
      (%search (%block-contents lst))))
  %logo-functions))

; GROW and S.FORWARD
(set! %logo-commands
  (pair (list "GROW"      1 (fn (_ factor)
          (set! %turtle-scale (Float * %turtle-scale (%as-float factor)))))
  (pair (list "S.FORWARD" 1 (fn (_ dist)
          (turtle-forward (Float * (%as-float dist) %turtle-scale))))
  (pair (list "S.FD"      1 (fn (_ dist)
          (turtle-forward (Float * (%as-float dist) %turtle-scale))))
  %logo-commands))))

(provide x/logo/tstate
  turtle-setxy turtle-home turtle-distance turtle-towards
  turtle-state turtle-setturtle %turtle-visible)
