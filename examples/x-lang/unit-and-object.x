; unit-and-object.x -- What every value is made of: the unit, and the object
; as a row of units, a header and then data (x/gfx/figure, x/gfx/scene)
;
; Usage:
;   sh x.sh -f examples/x-lang/unit-and-object.x
;       draws the last frame and prints how many figures it holds and one
;       pixel of it
;
;   SCENES=web sh x.sh -f examples/x-lang/unit-and-object.x
;       plays it in a browser; the page's address is printed on stderr
;
;   SCENES=sdl sh x.sh -f examples/x-lang/unit-and-object.x
;       plays it in a window, on a host with SDL3
;
; What it shows is x-expr's include/x-obj.h: the datum union, the object
; layout and the metadata accessors.

(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/num/float)
(import x/num/float/literal)
(import x/sys/posix)

; --- Figures ---------------------------------------------------------------

(def uo-blue (list 88 196 221))
(def uo-gold (list 240 190 80))
(def uo-pink (list 209 71 189))
(def uo-grey (list 150 150 150))
(def uo-dark (list 20 40 60))

; A cell SIDE across about X Y, outlined in COLOUR.
(def uo-cell
  (fn (_ x y side colour)
    (Figure shift (Figure fill (Figure stroke (Figure square side) colour 0.05) uo-dark) x y)))

; TEXT, a capital HEIGHT high, about X Y.
(def uo-text (fn (_ text x y height) (Figure shift (Figure label text height) x y)))

(def uo-arrow (fn (_ x0 y0 x1 y1 colour) (Figure stroke (Figure arrow x0 y0 x1 y1) colour 0.05)))

; A figure with nothing of it showing: what a figure fades in from.
(def uo-clear (fn (_ fig) ((Figure fade-out fig) 1)))

; --- The stage -------------------------------------------------------------
;
; A state is the named figures on the stage, in the order they are drawn:
; ((NAME . FIGURE) ...).  An action is a function of a state that answers
; (NAMES ANIMATIONS STATE): the names it animates, their animations, and the
; state once they are done.  A beat runs its actions together.

(def uo-get
  (fn (self state name)
    (match ((null? state) ())
           ((str=? (first (first state)) name) (rest (first state)))
           (#t (self (rest state) name)))))

(def uo-del
  (fn (self state name)
    (match ((null? state) ())
           ((str=? (first (first state)) name) (rest state))
           (#t (pair (first state) (self (rest state) name))))))

; NAME's figure becomes FIG where it stands in the order, or is added last.
(def uo-set
  (fn (self state name fig)
    (match ((null? state) (list (pair name fig)))
           ((str=? (first (first state)) name) (pair (pair name fig) (rest state)))
           (#t (pair (first state) (self (rest state) name fig))))))

(def uo-has?
  (fn (self names name)
    (match ((null? names) #f)
           ((str=? (first names) name) #t)
           (#t (self (rest names) name)))))

; FIG fades in as NAME.
(def uo-in
  (fn (_ name fig)
    (fn (_ state) (list (list name) (list (Figure morph (uo-clear fig) fig)) (uo-set state name fig)))))

; FIG slides in as NAME from DX to its right, fading in on the way.
(def uo-from
  (fn (_ name fig dx)
    (fn (_ state)
      (list (list name) (list (Figure morph (Figure shift (uo-clear fig) dx 0) fig)) (uo-set state name fig)))))

; FIG is drawn in as NAME, from its first point on.
(def uo-draw
  (fn (_ name fig)
    (fn (_ state) (list (list name) (list (Figure create fig)) (uo-set state name fig)))))

; NAME fades out and is gone; no NAME, nothing happens.
(def uo-out
  (fn (_ name)
    (fn (_ state)
      ((fn (_ old)
         (if (null? old)
           (list () () state)
           (list (list name) (list (Figure fade-out old)) (uo-del state name))))
       (uo-get state name)))))

; NAME becomes FIG by a morph; no NAME, FIG fades in.
(def uo-to
  (fn (_ name fig)
    (fn (_ state)
      ((fn (_ old)
         (if (null? old)
           ((uo-in name fig) state)
           (list (list name) (list (Figure morph old fig)) (uo-set state name fig))))
       (uo-get state name)))))

; NAME's figure fades out as FIG fades in under the same name: how text
; changes.
(def uo-swap
  (fn (_ name fig)
    (fn (_ state)
      ((fn (_ old)
         (if (null? old)
           ((uo-in name fig) state)
           (list (list name)
                 (list (Figure fade-out old) (Figure morph (uo-clear fig) fig))
                 (uo-set state name fig))))
       (uo-get state name)))))

; The line of words under the stage becomes TEXT.
(def uo-say (fn (_ text) (uo-swap "caption" (uo-text text 0 -3.5 0.26))))

; The actions run together over SECONDS; with none, the stage is held.
(def uo-beat
  (fn (_ seconds . actions)
    (fn (_ state play wait)
      ((fn (_ done)
         ((fn (_ names animations next)
            (do (if (null? animations)
                  (wait (List map rest state) seconds)
                  (play (List map rest
                          (List fold
                            (fn (_ kept entry) (if (uo-has? names (first entry)) kept (List append kept (list entry))))
                            () state))
                        animations seconds))
                next))
          (first done) (first (rest done)) (first (rest (rest done)))))
       (List fold
         (fn (_ acc action)
           ((fn (_ did)
              (list (List append (first acc) (first did))
                    (List append (first (rest acc)) (first (rest did)))
                    (first (rest (rest did)))))
            (action (first (rest (rest acc))))))
         (list () () state)
         actions)))))

; --- The beats -------------------------------------------------------------
;
; The row's units stand at x = -3, -1.8, -0.6 and 0.6, each 1.2 across.

(def uo-reading
  (fn (_ value tag)
    (uo-beat 0.5 (uo-swap "content" (uo-text value 0 0.5 0.36)) (uo-swap "tag" (uo-text tag 0 -1.2 0.2)))))

(def uo-part1
  (list
    ; 1: one kind of cell.
    (uo-beat 1.5)
    (uo-beat 1.2 (uo-draw "u0" (uo-cell 0 0.5 1.2 uo-blue)))
    (uo-beat 0.5 (uo-in "name" (uo-text "unit" 0 -0.55 0.24)) (uo-say "one kind of cell"))
    (uo-beat 1.2)

    ))
(Heap collect)

(def uo-part2
  (list
    ; 2: six ways to read it.
    (uo-beat 0.5 (uo-say "six ways to read it"))
    (uo-reading "42" "i  integer")
    (uo-beat 1.3)
    (uo-reading "'a'" "c  character")
    (uo-beat 1.3)
    (uo-beat 0.5 (uo-out "content") (uo-swap "tag" (uo-text "s  string" 0 -1.2 0.2))
             (uo-draw "reach" (uo-arrow 0 0.5 2.3 0.5 uo-grey))
             (uo-in "target" (uo-text "\"hello\"" 3.2 0.5 0.24)))
    (uo-beat 1.3)
    (uo-beat 0.5 (uo-swap "tag" (uo-text "p  object" 0 -1.2 0.2))
             (uo-swap "target" (uo-cell 2.9 0.5 0.8 uo-blue)))
    (uo-beat 1.3)
    (uo-beat 0.5 (uo-swap "tag" (uo-text "fn  function" 0 -1.2 0.2))
             (uo-swap "target" (uo-text "code" 3.0 0.5 0.24)))
    (uo-beat 1.3)
    (uo-beat 0.5 (uo-swap "tag" (uo-text "v  opaque pointer" 0 -1.2 0.2)) (uo-out "target"))
    (uo-beat 1.3)

    ))
(Heap collect)

(def uo-part3
  (list
    ; 3: unit, the cell counted; datum, the cell read.
    (uo-beat 0.5 (uo-out "reach") (uo-out "tag") (uo-in "content" (uo-text "42" 0 0.5 0.36))
             (uo-say "datum: the cell read"))
    (uo-beat 0.4 (uo-swap "name" (uo-text "datum" 0 -0.55 0.24)))
    (uo-beat 1.2)
    (uo-beat 0.4 (uo-swap "name" (uo-text "unit" 0 -0.55 0.24)) (uo-say "unit: the cell counted"))
    (uo-beat 1.2)
    (uo-beat 0.5 (uo-say "nothing in the cell says which reading"))
    (uo-beat 1.6)

    ))
(Heap collect)

(def uo-part4
  (list
    ; 4: an object is a row of units.
    (uo-beat 0.5 (uo-out "content") (uo-out "name") (uo-say "an object: a row of units"))
    (uo-beat 0.8 (uo-to "u0" (uo-cell -3 0.5 1.2 uo-blue)))
    (uo-beat 0.5 (uo-from "u1" (uo-cell -1.8 0.5 1.2 uo-blue) 4))
    (uo-beat 0.5 (uo-from "u2" (uo-cell -0.6 0.5 1.2 uo-blue) 4))
    (uo-beat 0.5 (uo-from "u3" (uo-cell 0.6 0.5 1.2 uo-blue) 4))
    (uo-beat 1)

    ))
(Heap collect)

(def uo-part5
  (list
    ; 5: a header, then data.
    (uo-beat 0.8 (uo-say "a header, then data")
             (uo-to "u0" (uo-cell -3 0.5 1.2 uo-gold))
             (uo-to "u1" (uo-cell -1.8 0.5 1.2 uo-gold))
             (uo-to "u2" (uo-cell -0.6 0.5 1.2 uo-gold)))
    (uo-beat 0.5 (uo-in "heap" (uo-text "heap" -3 1.45 0.2)))
    (uo-beat 0.5 (uo-in "type" (uo-text "type" -1.8 1.45 0.2)))
    (uo-beat 0.5 (uo-in "flags" (uo-text "flags" -0.6 1.45 0.2)))
    (uo-beat 0.5 (uo-in "data" (uo-text "data" 0.6 1.45 0.2)))
    (uo-beat 1)

    ))
(Heap collect)

(def uo-part6
  (list
    ; 6: the pointer lands on the header; data starts at 3.
    (uo-beat 0.8 (uo-say "the pointer lands on the header")
             (uo-draw "pointer" (uo-arrow -3 -1.7 -3 -0.25 uo-pink))
             (uo-in "pointer-name" (uo-text "object pointer" -3 -2.05 0.2)))
    (uo-beat 0.8)
    (uo-beat 0.4 (uo-in "at0" (uo-text "0" -3 2 0.2)))
    (uo-beat 0.4 (uo-in "at1" (uo-text "1" -1.8 2 0.2)))
    (uo-beat 0.4 (uo-in "at2" (uo-text "2" -0.6 2 0.2)))
    (uo-beat 0.5 (uo-in "at3" (uo-text "3" 0.6 2 0.2))
             (uo-in "starts" (uo-text "data starts here" 3 2 0.2))
             (uo-draw "edge" (Figure stroke (Figure line 0 1.3 0 -0.3) uo-pink 0.06)))
    (uo-beat 1.4)

    ))
(Heap collect)

(def uo-part7
  (list
    ; 7: the header is made of the same cell.
    (uo-beat 0.6 (uo-say "the header is made of the same cell") (uo-out "starts")
             (uo-draw "probe" (uo-cell -3 3.1 0.6 uo-blue)))
    (uo-beat 0.6 (uo-to "probe" (Figure stroke (Figure shift (Figure square 1.2) -3 0.5) uo-blue 0.08))
             (uo-in "as0" (uo-text "p" -3 0.5 0.3)))
    (uo-beat 0.6)
    (uo-beat 0.6 (uo-to "probe" (Figure stroke (Figure shift (Figure square 1.2) -1.8 0.5) uo-blue 0.08))
             (uo-in "as1" (uo-text "p" -1.8 0.5 0.3)))
    (uo-beat 0.6)
    (uo-beat 0.6 (uo-to "probe" (Figure stroke (Figure shift (Figure square 1.2) -0.6 0.5) uo-blue 0.08))
             (uo-in "as2" (uo-text "i" -0.6 0.5 0.3)))
    (uo-beat 0.6)
    (uo-beat 0.5 (uo-out "probe"))
    (uo-beat 0.8)

    ))
(Heap collect)

(def uo-part8
  (list
    ; 8: the header is fixed; the data is any length.
    (uo-beat 0.6 (uo-say "the header is fixed, the data any length")
             (uo-out "pointer") (uo-out "pointer-name")
             (uo-out "at0") (uo-out "at1") (uo-out "at2") (uo-out "at3"))
    (uo-beat 0.5 (uo-from "d1" (uo-cell 1.8 0.5 1.2 uo-blue) 3))
    (uo-beat 0.5 (uo-from "d2" (uo-cell 3 0.5 1.2 uo-blue) 3))
    (uo-beat 0.5 (uo-to "d3" (uo-cell 4.2 0.5 1.2 uo-blue)) (uo-in "more" (uo-text "..." 5.3 0.5 0.3))
             (uo-in "dn" (uo-cell 6.4 0.5 1.2 uo-blue)) (uo-in "n" (uo-text "N" 6.4 0.5 0.3)))
    (uo-beat 1.6)

    ))
(Heap collect)

(def uo-part9
  (list
    ; 9: the two smallest lengths.
    (uo-beat 0.6 (uo-out "d1") (uo-out "d2") (uo-out "d3") (uo-out "more") (uo-out "dn") (uo-out "n")
             (uo-say "one unit of data, or two"))
    (uo-beat 0.8
             (uo-to "v0" (uo-cell -3 -1.6 1.2 uo-gold)) (uo-to "v1" (uo-cell -1.8 -1.6 1.2 uo-gold))
             (uo-to "v2" (uo-cell -0.6 -1.6 1.2 uo-gold)) (uo-to "v3" (uo-cell 0.6 -1.6 1.2 uo-blue))
             (uo-to "v4" (uo-cell 1.8 -1.6 1.2 uo-blue)))
    (uo-beat 0.5 (uo-in "next" (uo-text "next" 4.4 -0.55 0.24)))
    (uo-beat 3)))
(Heap collect)

; A part is made, then the heap collected, so that making the figures of the
; whole script never holds more than one part of garbage.
(def uo-steps
  (List append uo-part1 uo-part2 uo-part3 uo-part4 uo-part5 uo-part6 uo-part7 uo-part8 uo-part9))

; Every step in turn, from an empty stage: the figures at the end.
(def uo-run
  (fn (_ play wait)
    (List map rest (List fold (fn (_ state step) (step state play wait)) () uo-steps))))

; --- Running ---------------------------------------------------------------

; With no window the steps go straight to their ends and the last frame is
; drawn, 160 by 90: how many figures it holds, and a pixel inside the first
; header unit.
(def uo-still
  (fn (_)
    ((fn (_ figures)
       (do (display "figures ")
           (write (List length figures))
           (newline)
           (display "header ")
           (write (Canvas pixel (Scene frame figures () 1 160 90) 42 35))
           (newline)))
     (uo-run (fn (_ figures animations seconds) figures) (fn (_ figures seconds) figures)))))

(def uo-live
  (fn (_ front)
    (def stage (Scene open front "unit and object" 1280 720 15))
    ; An empty stage first, long enough to open the page or the window.
    (Scene wait stage () 4)
    (uo-run (fn (_ figures animations seconds) (Scene play stage figures animations seconds))
            (fn (_ figures seconds) (Scene wait stage figures seconds)))
    (Scene close stage)))

((fn (_ how)
   (match
     ((null? how) (uo-still))
     ((str=? how "web") (do (import x/sys/web) (uo-live Web)))
     ((str=? how "sdl") (do (import x/sys/sdl) (uo-live Sdl)))
     (#t (uo-still))))
 (Sys getenv "SCENES"))
