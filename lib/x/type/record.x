; record.x -- def-record: lightweight named-field data types.
;
; A record IS a class (instances are plain objects): no new runtime type,
; because make-type registrations prepend to the reader-priority type alist
; -- a per-record tokenization tax -- and a parallel instance kind would
; fork every downstream facility (write, iter, equal?, help) that already
; understands objects. def-record is sugar over def-class plus the two
; methods a data carrier wants:
;
;   (def-record Span start len (colour ()))
;   (def s (new Span 3 5))            ; the ordinary positional/keyword ctor
;   (s start)                          ; field access, the ordinary door
;   (s with 'len 9)                    ; functional update -> a NEW record
;   (s =? (new Span 3 5))              ; structural equality, field by field
;
; `with` keys are QUOTED: with is an ordinary method, so its arguments
; evaluate -- a bare name would be looked up, not taken literally (new's
; bare keys work because new is an operative).
;
; Records are leaves: extending one is spelled def-class. Structural
; equality is a METHOD -- eq?/same? keep identity semantics, by ruling.
(import x/type/class)

; Functional update: copy the record with the named fields replaced.
; new-from takes the store as data, and an unknown key fails loudly
; through the ordinary %check-init-keys door. The overrides plist rides
; in front of the current fields alist, so its entries win the walk.
(def %record-with
  (fn (_ self overrides)
    (new-from (class-of self)
      (%append2 overrides (%obj-fields self)))))

; Structural equality: the same class (identity -- a record equals no
; other type), then equal? over the field alists, which sit in
; construction order on both sides.
(def %record=?
  (fn (_ self other)
    (if (not (object? other)) #f
      (if (not (same? (class-of self) (class-of other))) #f
        (equal? (%obj-fields self) (%obj-fields other))))))

(def %record-methods
  (lit ((method with (self . overrides) (%record-with self overrides))
        (method =? (self other) (%record=? self other)))))

(doc (def def-record
  (op (name . fields) e
    ; Expand to def-class with the two record methods appended, then
    ; tail-eval so the (def NAME ...) persists in the caller's env (the
    ; def-class placement rule).
    (tail-eval
      (pair (lit def-class)
        (pair name (pair () (%append2 fields %record-methods))))
      e)))
  (note "Fields: NAME | (NAME default), exactly as def-class members.")
  (note "Construction, access, and update ride the ordinary class doors:")
  (note "  (new R v1 v2 ...) positional/keyword; (r field) reads; (r field v) writes in place;")
  (note "  (r with 'field v ...) copies with replacements (keys quoted -- with is a")
  (note "  method, so its args evaluate); (r =? other) is structural, field by field.")
  (note "Records are leaves -- to extend one, write the def-class out.")
  (example "(do (def-record Pt x y) (def p (new Pt 1 2)) (list (p x) ((p with 'y 9) y) (p =? (new Pt 1 2))))" "(1 9 #t)")
  (see def-class)
  "Define a lightweight named-field record type (a class with with/=? built in).")

(doc (provide x/type/record def-record)
  (example "(do (def-record Pt x y) ((new Pt 1 2) y))" "2")
  "Lightweight named-field records over the class system.")
