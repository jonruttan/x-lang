; tstate.x -- Extended turtle state commands
(import x/logo/state)
(import x/logo/types)
(import x/logo/expr)
(import x/num/float)

; ============================================================
; Turtle visibility and scale
; ============================================================

(def %turtle-visible #t)
(def %turtle-scale (exact->inexact 1))

; ============================================================
; Register extended turtle commands
; ============================================================

; SETXY: move to absolute position (draws if pen down)
(def turtle-setxy
  (fn (_ x y)
    (def nx (%as-float x))
    (def ny (%as-float y))
    (def seg (list %turtle-x %turtle-y nx ny %turtle-pen %turtle-heading))
    (set! %turtle-segments (pair seg %turtle-segments))
    (set! %turtle-x nx)
    (set! %turtle-y ny)
    (if (null? %turtle-on-segment) () (%turtle-on-segment seg))))

; HOME: return to origin, heading 0
(def turtle-home
  (fn ()
    (turtle-setxy 0 0)
    (set! %turtle-heading (exact->inexact 0))))

; DISTANCE: distance from turtle to a point (x, y)
(def turtle-distance
  (fn (_ px py)
    (def dx (f- (%as-float px) %turtle-x))
    (def dy (f- (%as-float py) %turtle-y))
    (fsqrt (f+ (f* dx dx) (f* dy dy)))))

; TOWARDS: heading from turtle toward point (x, y), in degrees
(def turtle-towards
  (fn (_ px py)
    (def dx (f- (%as-float px) %turtle-x))
    (def dy (f- %turtle-y (%as-float py)))
    (def rad (fatan2 dx dy))
    (f/ (f* rad (exact->inexact 180)) %pi)))

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
  (pair (list "SETX"        1 (fn (_ x) (turtle-setxy x %turtle-y)))
  (pair (list "SETY"        1 (fn (_ y) (turtle-setxy %turtle-x y)))
  %logo-commands)))))))))

; Register state query functions (0-arg, return values)
(set! %logo-functions
  (pair (list "DISTANCE"      2 (fn (_ x y) (turtle-distance x y)))
  (pair (list "TOWARDS"       2 (fn (_ x y) (turtle-towards x y)))
  (pair (list "TURTLE.STATE"  turtle-state)
  %logo-functions))))

; SETTURTLE takes a list — register as command
(set! %logo-commands
  (pair (list "SETTURTLE" 1 (fn (_ state) (turtle-setturtle state)))
  (pair (list "FACE"      2 (fn (_ x y)
          (def bearing (turtle-towards x y))
          (def turn (f- bearing %turtle-heading))
          (turtle-left turn)))
  %logo-commands)))

; MEMBER function (list membership test)
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
          (set! %turtle-scale (f* %turtle-scale (%as-float factor)))))
  (pair (list "S.FORWARD" 1 (fn (_ dist)
          (turtle-forward (f* (%as-float dist) %turtle-scale))))
  (pair (list "S.FD"      1 (fn (_ dist)
          (turtle-forward (f* (%as-float dist) %turtle-scale))))
  %logo-commands))))

(provide x/logo/tstate
  turtle-setxy turtle-home turtle-distance turtle-towards
  turtle-state turtle-setturtle %turtle-visible)
