; tool/jit-group.x -- a compiled engine's functions, built once a machine.
;
; A codec's engine is a few compiled functions and a proof: the maker
; generates each function's expression, compiles it, wires a driver and
; checks the driver against the pure-x reference before it is adopted.
; The compile cache keeps the machine code, so a second process compiles
; nothing -- but it still generates every expression, prints each to its
; key text to find the entry (a 20KB expression prints in half a second),
; and runs the proof again.  Six engines in front of a TLS connection paid
; fourteen seconds that way, every process.
;
; The Lexer's answer (x/reader/lexer) is a cache group: its compiles run
; under one key, the group file holds every entry, and a plan in the
; group's extra names each entry's key text, so a later process pours the
; entries by name with no form made, printed or checked.  This is that
; answer for the engines, as one function:
;
;   (jit-group KEY GEN USE) -> what USE answers
;
; KEY names the engine and its parameters; the cache folds the machine,
; the release and the library version in, so an upgrade never replays.
; GEN is (fn (_) -> expressions), one (fn ...) a function, called only
; when the group holds no plan.  USE is (fn (_ fns replayed?) -> result):
; fns the compiled functions in GEN's order, replayed? #t when they were
; poured from the group, in which case the maker's proof has already
; passed on these very bytes, in the process that stored them, and USE
; skips it.  A raise from USE (a proof that fails) leaves no plan behind:
; the group closes on the raise before anything is stored.
;
; Where no group can be used -- the cache stands aside, the held-entry
; machinery is absent, or a group is already open (groups do not nest,
; and a nested group would read the outer one's plan) -- the functions are
; compiled as they always were and USE runs with replayed? #f.
(module x/tool/jit-group)

(import x/tool/asm-cache asm-cache-group asm-cache-group-held asm-cache-group-extra! asm-cache-held-pour asm-cache-last-text)

; The compile through the cache, as x/tool/compile's compile-asm reaches
; it: the catalogue entry asm-cache registers.  Not x/tool/compile itself,
; whose load -- the C pipeline with it -- is a third of a second a process,
; where a replay pours and never compiles.
(def %jg-compile-asm (prim-ref (lit compile) (lit asm-cached)))

; The plan: the key texts, one a line.  An expression's text has no
; newline in it (write-to-str prints a form on one line), and a plan whose
; text had one is not recorded.
(def %jg-sep "\n")

(def %jg-map
  (fn (self f l) (if (null? l) () (pair (f (first l)) (self f (rest l))))))

(def %jg-all?
  (fn (self ok? l) (if (null? l) #t (if (ok? (first l)) (self ok? (rest l)) #f))))

; The plan's functions poured from the group, or () when there is no plan
; or any entry of it is not held.
(def %jg-replay
  (fn (_)
    (def held (asm-cache-group-held))
    (def extra (if (null? held) () (rest held)))
    (if (not (str? extra)) ()
      (do (def texts (Str8 split %jg-sep extra))
          (def fns (%jg-map (fn (_ t) (asm-cache-held-pour t ())) texts))
          (if (%jg-all? (fn (_ f) (not (null? f))) fns) fns ())))))

; Compile each expression, noting its key text after each: ((fn . text) ...).
(def %jg-compile-all
  (fn (_ exprs)
    (%jg-map (fn (_ e) (do (def f (%jg-compile-asm e)) (pair f (asm-cache-last-text)))) exprs)))

(def %jg-plan-text
  (fn (_ made)
    (def texts (%jg-map rest made))
    (if (%jg-all? (fn (_ t) (if (str? t) (not (Str8 includes? %jg-sep t)) #f)) texts)
      (Str8 join %jg-sep texts)
      ())))

(def jit-group
  (fn (_ key gen use)
    (if (not (null? (asm-cache-group-held)))
      ; a group is open already: compile plainly, outside it
      (use (%jg-map %jg-compile-asm (gen)) #f)
      (asm-cache-group key
        (fn (_)
          (def poured (%jg-replay))
          (if (not (null? poured))
            (use poured #t)
            (do (def made (%jg-compile-all (gen)))
                (def out (use (%jg-map first made) #f))
                (def plan (%jg-plan-text made))
                (unless (null? plan) (asm-cache-group-extra! plan))
                out)))))))

(doc (provide x/tool/jit-group jit-group)
  "A compiled engine's functions as one cache group: (jit-group KEY GEN USE) compiles GEN's expressions and records a plan the next process pours them by, with nothing generated, printed or proven again; USE gets the functions and whether they were replayed.")
