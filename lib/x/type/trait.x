; trait.x -- traits: named bundles of methods (and requirements) mixed into
; classes at definition time. Composition for shared BEHAVIOUR; first-class
; delegation (the `delegates` def-class form, in class.x) covers shared
; STORAGE -- a wrapper forwarding to a field is a relationship, not a mixin.
;
;   (import x/type/trait)
;   (def-trait Comparable
;     (require cmp)                          ; the host chain must provide these
;     (method <? (self other) (< (self cmp other) 0))
;     (method =? (self other) (= (self cmp other) 0))
;     (static (method max-of (self a b) (if (< (a cmp b) 0) b a))))
;
;   (def-class Version ()
;     (with Comparable)                      ; a def-class body form
;     parts
;     (method cmp (self other) ...))
;
; A trait stores its method FORMS plus its defining env: at class-close the
; host builds them with the ordinary method builder, so `super` resolves
; against the HOST's chain and member access works, while the body's free
; names resolve where the trait was written. Conflict rules are explicit,
; no linearization: the class's own method beats a trait's; a trait's beats
; an inherited one; two traits supplying one selector with no own override
; refuse at definition time, naming both. Trait-supplied methods count as
; definitions for interface contracts.
(import x/type/class)

; A trait value: (%trait-tag name reqs iforms sforms env). The tag is the
; unforgeable-pair trick; traits are data, not callables.
(def %trait-tag (list (lit %trait)))
(def %trait-name   (fn (_ t) (first (rest t))))
(def %trait-reqs   (fn (_ t) (first (rest (rest t)))))
(def %trait-iforms (fn (_ t) (first (rest (rest (rest t))))))
(def %trait-sforms (fn (_ t) (first (rest (rest (rest (rest t)))))))
(def %trait-env    (fn (_ t) (first (rest (rest (rest (rest (rest t))))))))

(doc (def trait?
  (fn (_ (param x ANY "Value to test"))
    (if (pair? x) (eq? (first x) %trait-tag) #f)))
  (returns BOOL "#t for a trait value")
  (see def-trait)
  "Test whether a value is a trait.")

(doc (def def-trait
  (op (name . body) e
    (let ((reqs (%find-form body (lit require)))
          (sblock (%find-form body (lit static))))
      (def %methods-of
        (fn (loop fs)
          (unless (null? fs)
            (if (if (pair? (first fs)) (eq? (first (first fs)) (lit method)) #f)
              (pair (first fs) (loop (rest fs)))
              (loop (rest fs))))))
      (tail-eval
        (list (lit def) name
          (list (lit lit)
            (list %trait-tag (%selector name) reqs
              (%methods-of body) (%methods-of sblock) e)))
        e))))
  (note "(def-trait NAME (require SEL...) (method ...)... (static (method ...)...))")
  (note "Body: (require SEL...) names the host chain must provide (checked at the")
  (note "host's def-class); (method ...) forms mix into instance methods; a")
  (note "(static ...) block's methods mix into statics. Bodies close over THIS")
  (note "definition site; super inside them resolves against the HOST's chain.")
  (note "Mix in with (with NAME...) in a def-class body.")
  (example "(do (def-trait T (method hi (self) 'hi)) (def-class C () (with T)) ((new C) hi))" "'hi")
  (see def-class)
  "Define a trait: a named method bundle classes mix in with (with ...).")

(doc (provide x/type/trait def-trait trait?)
  (note "Traits are composition for shared behaviour; `delegates` (a def-class")
  (note "body form) is the storage-forwarding counterpart; `interface` remains")
  (note "the abstract contract on an extends-chain -- three distinct tools.")
  (example "(do (def-trait T (method hi (self) 'hi)) (def-class C () (with T)) ((new C) hi))" "'hi")
  "Trait definition and predicate; the mixing happens in def-class.")
