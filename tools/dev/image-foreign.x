; image-foreign.x -- which foreign units a state image can name, and how many
; it still cannot.
;
;   sh x.sh -q -f tools/dev/image-foreign.x
;
; Every foreign unit in the heap holds a raw address, and no address survives
; into another process.  Each one has to be reacquired by name, and this counts
; how far the naming sources reach.  It counts the heap of the base it runs
; in, the writer's own names included; tools/dev/image-write.x images a child
; and names its words by the same sources, in the same order.
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

(import x/tool/image/walk image-walk image-over-units image-trace-flag image-collect image-mark! image-clear! image-int+)
(import x/tool/image/walk image-word-at image-obj->ptr image-ptr->obj image-int->ptr image-ref-word image-type-off image-type-label image-type-heap)
(import x/tool/image/name image-name-map image-name-map-add image-name-map-get image-dl-round-trips? image-dl-handle)
(import x/tool/image/name image-foreign-catalog image-foreign-bare image-foreign-typecall image-foreign-dlopen)

; --- census: classify every foreign unit in the heap -----------------------
; The tally is a list of six counts, in the order the report prints them:
; catalog, bare binding, type-call, dlopen handle, dladdr round trip, unnamed.
(def %bump
  (fn (self acc i)
    (if (eq? i 0) (pair (image-int+ (first acc) 1) (rest acc))
      (pair (first acc) (self (rest acc) (- i 1))))))
; The word a type's own call handler holds, or 0: the writer's test for a
; call pointer a whole type shares (tools/dev/image-write.x).
(def %type-call-steps
  ((fn (self rows)
     (if (null? rows) ()
       (if (eq? (first (first rows)) (lit type-call)) (rest (rest (first rows)))
         (self (rest rows)))))
   %base-paths))
(def %call-word-of
  (fn (_ tw)
    (guard (_ 0)
      ((fn (_ h) (if (null? h) 0 (image-word-at (image-obj->ptr h) 0)))
       ((fn (self v steps)
          (if (null? steps) v
            (self (if (eq? (first steps) (lit f)) (first v) (rest v)) (rest steps))))
        (image-ptr->obj (image-int->ptr tw)) %type-call-steps)))))
(def %type-call?
  (fn (_ w p)
    ((fn (_ tw)
       (if (eq? (image-type-label tw) image-type-heap) (eq? w (%call-word-of tw)) #f))
     (image-ref-word p image-type-off))))
; The writer's order: the type-call test, then the map, then the linker.
(def %tally
  (fn (_ tag acc w)
    (if (null? tag) (%bump acc (if (image-dl-round-trips? w) 4 5))
      (if (eq? (first tag) image-foreign-catalog) (%bump acc 0)
        (if (eq? (first tag) image-foreign-dlopen) (%bump acc 3)
          (%bump acc 1))))))
(def %f-walk
  (fn (_ p acc)
    (image-over-units p
      (fn (_ k w a)
        (if (eq? k 3)
            (if (%type-call? w p) (%bump a 2) (%tally (image-name-map-get %MAP w) a w))
            a))
      acc)))

; The map is the base's catalog and bare primitives, and this process's
; dlopen handle, as the writer builds it.  Built before the mark, so its defs
; are made before any walk.
(def %MAP
  (image-name-map-add (image-name-map (Base wrap (%base)))
    (Ptr ->int image-dl-handle) image-foreign-dlopen ""))
(display "naming table:  ") (write (List length %MAP)) (display " entries") (newline)
(image-collect)
(image-mark! (%base) image-trace-flag)
((fn (_ r)
   ((fn (_ t)
      (do (display "foreign units named by catalog: ") (write (t 0)) (newline)
          (display "               by bare binding: ") (write (t 1)) (newline)
          (display "       by its type (type-call): ") (write (t 2)) (newline)
          (display "           as the dlopen handle: ") (write (t 3)) (newline)
          (display "          by dladdr round trip: ") (write (t 4)) (newline)
          (display "                       unnamed: ") (write (t 5)) (newline)
          (display "               objects visited: ") (write (rest r)) (newline)))
    (first r)))
 (image-walk (pair 1 2) %f-walk (list 0 0 0 0 0 0)))
(image-clear! image-trace-flag)
