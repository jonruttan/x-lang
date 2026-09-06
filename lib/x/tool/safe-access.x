; safe-access.x -- turn the (first ()) / (rest ()) crash into a clean error.
;
; docs/spec.md rules (first ()) UNDEFINED, and the C prims are unchecked by
; design (the core is a CPU: the layer that ACCEPTS the program does the
; checking).  In practice that means an ordinary typo dereferences nil and
; takes the process down with no diagnostic.  Importing this module shadows
; both globals with guarded closures over the captured prims, so the same typo
; raises instead.
;
; OPT-IN, AND IT HAS TO BE.  The library's own internals resolve first and rest
; through these same globals, so the guard is not free:
;
;     first/rest-saturated walk    6.03s -> 8.48s   (1.41x)
;     mixed list/sort/dict/string  4.15s -> 7.16s   (1.73x)
;
; Import it while debugging; leave it out of anything that has to be fast.  The
; zero-cost fix is a nil branch inside the engine's first/rest prims, which is
; an engine change, not a library one.
;
; THE BODY MAY USE C PRIMITIVES ONLY -- match, eq?, error.  `if` and `do` are
; x-lang OPERATIVES (lib/x/boot/operatives.x) that walk their own body forms
; with first/rest.  Writing the guard with either one makes it call itself
; through the operative, unbounded, and the process dies exactly the way it did
; before -- during boot, with nothing on stdout.  That is not a style rule; it
; is the whole reason this file reads the way it does.

; The prims are captured by a `let`, not by top-level defs: the guards need
; them, and the top level stays clean (tools/check/percent-globals.sh).  The
; globals are then rebound with set!, which reaches the existing bindings the
; whole library resolves through -- a `def` here would bind in the let frame
; and shadow nothing.
(let ((prim-first first) (prim-rest rest))
  (set! first
    (fn (_ p)
      (match
        ((eq? p ()) (error "first: () has no first"))
        (#t (prim-first p)))))
  (set! rest
    (fn (_ p)
      (match
        ((eq? p ()) (error "rest: () has no rest"))
        (#t (prim-rest p))))))

(doc (provide x/tool/safe-access)
  (note "Costs 1.4x-1.7x: the library walks its own lists through these globals.")
  (note "Guard bodies use C primitives only -- if/do are operatives that call")
  (note "first/rest themselves, which makes the guard recurse into itself.")
  "Development aid: (first ()) and (rest ()) raise instead of crashing.")
