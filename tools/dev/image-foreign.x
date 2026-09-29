; image-foreign.x -- which foreign units a state image can name, and how many
; it still cannot.
;
;   sh x.sh -q -f tools/dev/image-foreign.x
;
; Every foreign unit in the heap holds a raw address, and no address survives
; into another process.  Each one has to be reacquired by name, and this counts
; how far the naming sources reach.  Run it beside tools/dev/image-write.x,
; whose foreign table this measures the inputs to.
;
; The key is the C function pointer, not the object address: a foreign unit is
; the function pointer a primitive holds in unit 0, so a naming map keyed on
; the primitive object's own address matches nothing.  Keying on the function
; merges nothing it should not -- the catalog's `+` and the bare `+` are two
; distinct objects sharing one C function, and they stay two records in the
; image, so identity survives.  docs/state-images.md's warning is about naming
; an object by a path that yields an equal value, which is a different thing.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import x/tool/image/walk image-walk image-walk-all image-over-units image-trace-flag image-collect image-mark! image-clear! image-int+)
(import x/tool/image/name image-name-map image-name-map-get image-dl-round-trips? image-foreign-catalog image-foreign-typecall)

; --- census: classify every foreign unit in the heap -----------------------
; acc = (catalog-named bare-named . unnamed)
(def %census
  (fn (_ k w acc)
    (if (eq? k 3) (%tally (image-name-map-get %MAP w) acc w) acc)))
(def %tally
  (fn (_ tag acc w)
    (if (null? tag) (%tally-miss acc w)
      (if (eq? (first tag) image-foreign-catalog) (pair (image-int+ (first acc) 1) (rest acc))
        (if (eq? (first tag) image-foreign-typecall) (%bump2 acc)
          (pair (first acc) (pair (image-int+ (first (rest acc)) 1) (rest (rest acc)))))))))
(def %bump2
  (fn (_ acc)
    (pair (first acc)
      (pair (first (rest acc))
        (pair (image-int+ (first (rest (rest acc))) 1) (rest (rest (rest acc))))))))
(def %tally-miss
  (fn (_ acc w)
    (pair (first acc)
      (pair (first (rest acc))
        (pair (first (rest (rest acc)))
          (if (image-dl-round-trips? w)
            (pair (image-int+ (first (rest (rest (rest acc)))) 1) (rest (rest (rest (rest acc)))))
            (pair (first (rest (rest (rest acc)))) (image-int+ (rest (rest (rest (rest acc)))) 1))))))))
(def %f-walk (fn (_ p acc) (image-over-units p %census acc)))

(image-collect)
(image-mark! (%base) image-trace-flag)
(def %CPSCAN (first (image-walk-all (pair 1 2) %cp-scan (pair () ()))))
(def %CALLS (%cp-entries (first %CPSCAN) (rest %CPSCAN) ()))
(def %MAP (%append %CALLS (image-name-map (Base wrap (%base)))))
(display "naming table:  ") (write (%mlen %MAP 0)) (display " entries") (newline)
((fn (_ r)
   (do (display "foreign units named by catalog: ") (write (first (first r))) (newline)
       (display "               by bare binding: ") (write (first (rest (first r)))) (newline)
       (display "        by its type (type-call): ") (write (first (rest (rest (first r))))) (newline)
       (display "            by dladdr round-trip: ") (write (first (rest (rest (rest (first r)))))) (newline)
       (display "                       UNNAMED: ") (write (rest (rest (rest (rest (first r)))))) (newline)
       (display "                       visited: ") (write (rest r)) (newline)))
 (image-walk (pair 1 2) %f-walk (pair 0 (pair 0 (pair 0 (pair 0 0))))))
(image-clear! image-trace-flag)
