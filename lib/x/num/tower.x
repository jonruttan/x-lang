; numeric.x -- Numeric tower promotion utilities
(import x/core/list)

; Build a variadic fold operator that promotes to a new numeric type.
; pred?:   type predicate (float?, bignum?, etc.)
; type-op: binary op for the new type (f+, big+, etc.)
; coerce:  promote to the new type (%ensure-float, %ensure-big, etc.)
; prev-op: fallback for non-matching types (the previous layer's operator)
; identity: identity element (0 for +, 1 for *)
(doc (def %make-fold-op
  (fn (_ (param pred? CALLABLE "Type predicate")
       (param type-op CALLABLE "Binary type-specific operation")
       (param coerce CALLABLE "Coercion to this type")
       (param prev-op CALLABLE "Fallback operator for other types")
       (param identity NUMBER "Identity element (0 for +, 1 for *)"))
    (fn (_ . args)
      (if (null? args) identity
        (fold
          (fn (_ acc x)
            (if (pred? acc) (type-op acc (coerce x))
              (if (pred? x) (type-op (coerce acc) x)
                (prev-op acc x))))
          (first args) (rest args))))))
  (returns CALLABLE "Variadic operator with type promotion")
  "Create a variadic arithmetic operator that promotes operands to a numeric type.")

; Build a binary comparison operator with type promotion.
; pred?:   type predicate
; type-cmp: binary comparison for the new type (f<, big<, etc.)
; coerce:  promote to the new type
; prev-op: fallback comparison
(doc (def %make-cmp-op
  (fn (_ (param pred? CALLABLE "Type predicate")
       (param type-cmp CALLABLE "Binary type-specific comparison")
       (param coerce CALLABLE "Coercion to this type")
       (param prev-op CALLABLE "Fallback comparison for other types"))
    (fn (_ a b)
      (if (pred? a) (type-cmp a (coerce b))
        (if (pred? b) (type-cmp (coerce a) b)
          (prev-op a b))))))
  (returns CALLABLE "Binary comparison with type promotion")
  "Create a binary comparison operator that promotes operands to a numeric type.")

(doc (provide x/num/tower %make-fold-op %make-cmp-op)
  "Numeric tower helpers for building type-promoting operators.")
