; doc-annotations.x -- the annotation names no platform holds
;
; Pure data -- no code, just s-expressions.  Each entry: (NAME "what it is").
;
; An annotation is the T of a (param NAME T ...) or (returns T ...) doc form,
; and it names a type (docs/glossary.md, "annotation").  The check,
; tools/check/doc-annotations.sh, asks the platform it runs on for its runtime
; types and reads the classes from the source's def-class forms.  The names
; here are the ones neither of those holds.

(
  (ANY      "Every value.")
  (NUMBER   "A union: every numeric runtime type.")
  (CALLABLE "A union: every value that can be called.")
  (ALIST    "An alist: a list of assocs.")
  (TYPE     "A runtime type's handle.")
  (NIL      "The value nil.  x-expr reports this name for an object with no type label.")
)
