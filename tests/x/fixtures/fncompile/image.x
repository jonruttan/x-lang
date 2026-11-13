; image.x -- a library a state image is written of, by
; tests/x/specs/ext/fn-compile.spec.md: closures compiled with compile-fn!,
; each of which has passed a Ptr to a string's bytes through a call site's
; template.  One call returns, one is a tail call, one raises out of its
; callee; str=? hands %mem-cmp two Ptrs, and %member-str? calls str=?.  The
; writer names every word of the image, or refuses it.
(include "lib/x-core.x")
(import x/tool/fn-compile compile-fn!)
(import x/core/doors int+)
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %fci-take (fn (_ p n) n))
(def %fci-boom (fn (_ p) (error "boom")))
(def %fci-call (fn (_ s) (int+ (%fci-take (%str->ptr s) 1) 0)))
(def %fci-tail (fn (_ s) (%fci-take (%str->ptr s) 2)))
(def %fci-raise (fn (_ s) (int+ (%fci-boom (%str->ptr s)) 0)))
(def %fci-states
  (List map (fn (_ n) ((compile-fn! n (eval n)) state))
    (lit (%fci-call %fci-tail %fci-raise str=? %member-str?))))
(write
  (list %fci-states (%fci-call "abc") (%fci-tail "abc")
    (guard (e (lit caught)) (%fci-raise "abc"))
    (str=? "abc" "abc") (%member-str? "b" (list "a" "b"))))
(newline)
