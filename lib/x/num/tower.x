; tower.x -- the numeric tower's MIXED-TYPE policy, on generic functions.
;
; Each numeric module stays self-sufficient: its own same-type operator
; handlers load with it, so (import x/num/float) alone keeps working.
; Mixed-type pairs only exist when two modules coexist -- and their policy
; lives HERE, once, visibly, instead of as N^2 hand-written coercions:
;
;   (import x/num/tower)                     ; pulls the whole tower
;   (+ 1/2 3.5)                              ; -> promoted via the cvt lattice
;   (num+ a b)                               ; the generics, callable directly
;
; Seven generics -- num+ num- num* num/ num% num< num= -- carry one method
; per type (the module's own worker) plus a shared miss handler: when the
; operand types differ, the cvt from-lattice (the same relation the C
; operator arbitration reads -- one promotion authority everywhere) names
; the absorbing side, the other operand converts, and the call re-enters
; once. A pair the lattice does not relate is a TEACHING ERROR naming both
; types -- previously the bigint x rational mix fell through to raw C
; SILENTLY (the recorded hole); now it says what is missing.
;
; The ops-cell shims this file pushes shadow each module's own handlers
; (prepend wins). Same-type pairs branch straight to the module's worker
; -- tower arithmetic is hot and the generic walk is the COLD path by
; design -- so only genuinely mixed pairs pay generic dispatch. Complex
; registers no ordering (unordered) and keeps its own loud % refusal.
(import x/num/bigint)
(import x/num/float)
(import x/num/rational)
(import x/num/complex)
(import x/type/generic)

(def %tw-str-append (prim-ref (lit str) (lit append)))
(def %tw-type-of (prim-ref (lit type) (lit of)))
(def %tw-type-name (prim-ref (lit type) (lit name)))
(def %tw-push-op (prim-ref (lit type) (lit push-op)))

; A type struct's HANDLE: the name-stack's current atom (field 0 of the
; struct tree, (current . saved) stacked) -- the same atom (Type of v)
; returns and type? pointer-compares. The modules export their STRUCTS
; (%rational-ts et al., what push-op wants); the generics key on handles.
(def %tw-handle (fn (_ ts) (first (first ts))))

(def-generic num+ "Tower addition: one method per numeric type; a mixed pair promotes via the cvt lattice, and an unrelated pair errors naming both types.")
(def-generic num- "Tower subtraction; see num+.")
(def-generic num* "Tower multiplication; see num+.")
(def-generic num/ "Tower division; see num+.")
(def-generic num% "Tower modulo; see num+. Complex registers none (its own handler refuses).")
(def-generic num< "Tower ordering; see num+. Complex is unordered and registers none.")
(def-generic num= "Tower numeric equality; see num+.")

; Per-generic miss handler. The cvt from-lattice names the ABSORBING side
; (the same relation the C operator arbitration reads); promotion is the
; absorber module's OWN formula -- (worker (ensure a) (ensure b)) -- run
; directly, never re-entered through the generic. That is forced, not
; stylistic: the tower's constructors NORMALIZE (a whole rational reduces
; to the int it equals, so %ensure-rat is int-transparent and the workers
; are int-tolerant) -- a promoted pair is not guaranteed to look same-type
; to the dispatcher, and re-entering on it looped forever, the hard way.
; A handle absorbs only when it is a tower member carrying an ensure (INT
; declares conversions for index coercion but sits UNDER the tower --
; absorbed, never absorbing). An unrelated pair is the teaching error.
(def %tw-ensure-of ())                      ; ((handle . ensure) ...), filled below
(def %tw-absorb?
  (fn (_ h other)
    (if (null? (%assoc-get h %tw-ensure-of)) #f (%g-absorbs? h other))))
(def %tw-promote-for
  (fn (_ wtab)                              ; wtab: ((handle . worker) ...) for ONE generic
    (fn (_ g args)
      (let ((a (first args)) (b (first (rest args))))
        (let ((ha (%tw-type-of a)) (hb (%tw-type-of b)))
          (def %run
            (fn (_ h x y)
              (let ((w (%assoc-get h wtab)) (en (%assoc-get h %tw-ensure-of)))
                (if (null? w)
                  (error (%tw-str-append "tower: " (%tw-str-append (%tw-type-name h)
                    " sits this operator out")))
                  (w (en x) (en y))))))
          (match
            ((%tw-absorb? ha hb) (%run ha a b))
            ((%tw-absorb? hb ha) (%run hb a b))
            (#t
              (error (%tw-str-append "tower: no method and no declared promotion ("
                (%tw-str-append (%tw-type-name ha)
                  (%tw-str-append " x " (%tw-str-append (%tw-type-name hb)
                    ") -- declare the cvt relation or write the (on ...) method"))))))))))))

; Wire one operator across the four types: an exact-pair method per type
; with a worker (nil = the type sits this operator out), the shared miss
; handler, and the ops-cell shim that shadows the module's own handler --
; same-type branches straight to the worker (hot), mixed falls into the
; generic (cold, promoted).
(def %tw-op!
  (fn (_ g opsym structs workers)
    (def %wtab
      (fn (loop ts ws acc)
        (if (null? ts) acc
          (loop (rest ts) (rest ws)
            (if (null? (first ws)) acc
              (pair (pair (%tw-handle (first ts)) (first ws)) acc))))))
    (def %wire
      (fn (loop ts ws)
        (unless (null? ts)
          (do
            (unless (null? (first ws))
              (let ((h (%tw-handle (first ts))) (w (first ws)))
                (Generic add! g (list h h) (fn (_ a b) (w a b)))
                (%tw-push-op (first ts) opsym
                  (fn (_ a b)
                    (if (eq? (%tw-type-of a) (%tw-type-of b))
                      (w a b)
                      (g a b))))))
            (loop (rest ts) (rest ws))))))
    (Generic miss! g (%tw-promote-for (%wtab structs workers ())))
    (%wire structs workers)))

; struct order: bigint, float, rational, complex
(def %tw-structs (list %bigint-ts %float-ts %rational-ts %complex-ts))
(set! %tw-ensure-of
  (list (pair (%tw-handle %bigint-ts) %ensure-big)
        (pair (%tw-handle %float-ts) %ensure-float)
        (pair (%tw-handle %rational-ts) %ensure-rat)
        (pair (%tw-handle %complex-ts) %ensure-complex)))
(%tw-op! num+ (lit +) %tw-structs (list %big-add %f-add %rat-add %cx-add))
(%tw-op! num- (lit -) %tw-structs (list %big-sub %f-sub %rat-sub %cx-sub))
(%tw-op! num* (lit *) %tw-structs (list %big-mul %f-mul %rat-mul %cx-mul))
(%tw-op! num/ (lit /) %tw-structs (list %big-div %f-div %rat-div %cx-div))
(%tw-op! num% (lit %) %tw-structs (list %big-mod %f-mod %rat-mod ()))
(%tw-op! num< (lit <) %tw-structs (list %big-lt %f-lt %rat-lt ()))
(%tw-op! num= (lit =) %tw-structs (list %big-eq %f-eq %rat-eq %cx-eq))

(doc (provide x/num/tower num+ num- num* num/ num% num< num=)
  (note "The mixed-type policy layer: import it whenever two numeric modules meet.")
  (note "Same-type arithmetic stays on each module's fast worker; a mixed pair")
  (note "promotes through the cvt from-lattice (one authority, shared with the C")
  (note "operator arbitration) or errors naming both types. The generics are")
  (note "callable values; (Generic methods-of num+) shows the method table.")
  (example "(do (import x/num/tower) (num= 1/2 1/2))" "#t")
  "The numeric tower's mixed-type arithmetic, homed on seven generics.")
