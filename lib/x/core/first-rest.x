; first-rest.x -- first and rest guarded against nil, compiled
;
; The engine's first and rest are unchecked by design: (first ()) reads
; through a NULL pointer and takes the process down, with nothing a guard
; can catch.  The check is the library's, and it has to cost nothing the
; raw prims do not: the library walks every list through these two
; globals, and an interpreted guard measures 3.3x on a first/rest walk.
; So each guard is compiled -- an object function in the assembler lane,
; a nil test and a trampoline read -- and the globals are set! to the
; compiled prims once the lane is there.  A raise reads `first: () has no
; first`.
;
; Native code is per-process: the image writer gets the raw prims back
; (a transient thunk), and the recache hook compiles again after a load,
; from the byte cache the image carries.  Where the lane refuses -- an
; engine without the JIT's symbols, a platform without a backend -- the
; prims stay raw, and (first ()) is what the spec says it is.
(module x/core/first-rest)
(import x/tool/asm-cache)

(def %fr-compile (prim-ref (lit compile) (lit asm-cached)))
(def %fr-raw-first first)
(def %fr-raw-rest rest)
(def %fr-first-text "first: () has no first")
(def %fr-rest-text "rest: () has no rest")

; One shape for both: p arrives evaluated and stays a pointer, 0 is nil.
(def %fr-guard
  (fn (_ source text)
    (%fr-compile source (list (pair (lit error) error) (pair (lit m) text)) (lit object))))

(def %fr-arm!
  (fn (_)
    (guard (_ ())
      (do
        (set! first (%fr-guard (lit (fn (_ p) (if (= p 0) (error m) (first p)))) %fr-first-text))
        (set! rest (%fr-guard (lit (fn (_ p) (if (= p 0) (error m) (rest p)))) %fr-rest-text))))))

(def %fr-disarm!
  (fn (_)
    (set! first %fr-raw-first)
    (set! rest %fr-raw-rest)))

(%fr-arm!)
(set! %image-transients (pair %fr-disarm! %image-transients))
((prim-ref (lit image) (lit recache-hook!)) %fr-arm!)

(doc (provide x/core/first-rest)
  (note "Raises `first: () has no first` / `rest: () has no rest`; the guard is a compiled object function, so a list walk costs what it did on the raw prims.")
  "first and rest guarded against nil, as compiled prims the boot sets the globals to.")
