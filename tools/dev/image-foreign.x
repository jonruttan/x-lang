; image-foreign.x -- which foreign units a state image can name, and how many
; it still cannot.
;
;   sh x.sh -q -f tools/dev/image-foreign.x
;
; Every foreign unit in the heap holds a raw address, and no address survives
; into another process.  So each one has to be REACQUIRED by name, and this
; counts how far the naming sources actually reach.  Run it beside
; tools/dev/image-write.x, whose foreign table this measures the inputs to.
;
; THE KEY IS THE C FUNCTION POINTER, NOT THE OBJECT ADDRESS.  A foreign unit
; IS the function pointer a primitive holds in unit 0; keying a naming map on
; the primitive object's own address matches nothing, which is what the first
; version of this did (0 of 146).  Nor does keying on the function merge
; anything it should not: the catalog's `+` and the bare `+` are two distinct
; objects sharing one C function, and they stay two records in the image, so
; identity survives.  docs/state-images.md's warning is about naming an OBJECT
; by a path that yields an equal value, which is a different thing.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(include "tools/dev/image-name.x")

; --- census: classify every foreign unit in the heap -----------------------
; acc = (catalog-named bare-named . unnamed)
(def %census
  (fn (_ k w acc)
    (if (eq? k 3) (%tally (%map-get %MAP w) acc w) acc)))
(def %tally
  (fn (_ tag acc w)
    (if (null? tag) (%tally-miss acc w)
      (if (eq? (first tag) %F-CATALOG) (pair (%int+ (first acc) 1) (rest acc))
        (if (eq? (first tag) %F-TYPECALL) (%bump2 acc)
          (pair (first acc) (pair (%int+ (first (rest acc)) 1) (rest (rest acc)))))))))
(def %bump2
  (fn (_ acc)
    (pair (first acc)
      (pair (first (rest acc))
        (pair (%int+ (first (rest (rest acc))) 1) (rest (rest (rest acc))))))))
(def %tally-miss
  (fn (_ acc w)
    (pair (first acc)
      (pair (first (rest acc))
        (pair (first (rest (rest acc)))
          (if (%dl-round-trips? w)
            (pair (%int+ (first (rest (rest (rest acc)))) 1) (rest (rest (rest (rest acc)))))
            (pair (first (rest (rest (rest acc)))) (%int+ (rest (rest (rest (rest acc)))) 1))))))))
(def %f-walk (fn (_ p acc) (%over-units p %census acc)))

(%collect)
(%mark! (%base) %TRACE)
(def %CPSCAN (first (%walk-all (pair 1 2) %cp-scan (pair () ()))))
(def %CALLS (%cp-entries (first %CPSCAN) (rest %CPSCAN) ()))
(def %MAP (%append %CALLS (%make-map (Base wrap (%base)))))
(display "naming table:  ") (write (%mlen %MAP 0)) (display " entries") (newline)
((fn (_ r)
   (do (display "foreign units named by catalog: ") (write (first (first r))) (newline)
       (display "               by bare binding: ") (write (first (rest (first r)))) (newline)
       (display "        by its type (type-call): ") (write (first (rest (rest (first r))))) (newline)
       (display "            by dladdr round-trip: ") (write (first (rest (rest (rest (first r)))))) (newline)
       (display "                       UNNAMED: ") (write (rest (rest (rest (rest (first r)))))) (newline)
       (display "                       visited: ") (write (rest r)) (newline)))
 (%walk (pair 1 2) %f-walk (pair 0 (pair 0 (pair 0 (pair 0 0))))))
(%clear! %TRACE)
