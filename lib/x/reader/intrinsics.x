; intrinsics.x -- Low-level intrinsics for tokenizer and profiling
;
; Buffer scoring helpers used by custom type analysers, and stderr output.
; Requires: data.x (first-int, set-first-int!)

; Write to stderr (swap fileout fd, display, restore)
; Variadic like display (#291): the fd swap wraps the whole batch.  A
; loop, not (apply display msgs): display is an OP, and applying it to
; VALUES would re-evaluate a list value as a form.
(def %stderr
  (fn (_ . msgs)
    (def %files (%reflect-base-cell (lit files)))
    (def %fo (first (rest %files)))
    (def %s (%cell-int %fo))
    (%set-cell-int! %fo (%cell-int (first (rest (rest %files)))))
    (def %each
      (fn (self lst)
        (if (eq? lst ()) ()
          (do (display (first lst)) (self (rest lst))))))
    (%each msgs)
    (%set-cell-int! %fo %s)))

; Quick profile dump to stderr (alloc-count + heap object count).
; ns `heap` is de-registered (R5): fetch the prim from the catalog.


; Buffer length and unread for tokenizer scoring
(def %buffer-len
  (fn (_ buffer)
    (- (%cell-int (rest buffer)) (%cell-int buffer))))
(def %buffer-unread
  (fn (_ buffer)
    (%set-cell-int!
      (rest buffer)
      (- (%cell-int (rest buffer)) 1))))
(def %score-set
  (fn (_ score sign buffer)
    (%set-cell-int! score (* sign (%buffer-len buffer)))))
; THE VARIANT an analyser accepted, for its type's reader.  (%score-variant! score k)
; writes the variant cell the engine hangs off the score's rest (x-token.c), and
; the winning handler's variant reaches the reader as its SECOND argument -- an
; int, or nil when no state declared one.  A set-cell-int! on (rest score),
; so it costs what %score-set costs and needs no primitive of its own.  The
; analyser already knows whether a literal ran through its fraction or its
; exponent state; this is how it says so, instead of the reader rescanning
; the text it just read.  THE SCORE IS A STACK CELL WITH NO TYPE, so the
; variant cell on its rest is reached through the raw-memory door (obj ref,
; data unit 1) and never through `rest`, which is the list primitive and
; refuses a typeless object.  Guarded: an engine without the cell has a nil
; unit there, and a write through nil is a crash where a no-op is the
; honest answer.
(def %score-variant-cell (prim-ref (lit obj) (lit ref)))
(def %score-variant!
  (fn (_ score variant)
    (let ((cell (%score-variant-cell score 1)))
      (if (null? cell) () (%set-cell-int! cell variant)))))
; The reader's side of the channel.  A reader is (fn (_ . args) ...) and its
; second argument is the variant as a RAW CELL -- a cell rather than an int
; because an int object only exists relative to a base that registered the
; int type, and a tokenizer base has none by design -- or nil when no state
; declared one.  (%read-variant args) answers the integer, or nil.
(def %read-variant
  (fn (_ args)
    (let ((k (first (rest args))))
      (if (null? k) () (%cell-int k)))))


; Current source line number
(def %current-line
  (fn (_ )
    (%cell-int (first (%reflect-base-cell (lit line))))))

(doc (provide x/reader/intrinsics)
  "Low-level tokenizer and profiling intrinsics: buffer scoring helpers and line tracking.")
