; prelude.x -- the bare-engine harness preamble, shared by every suite that runs
; against an engine with NO LIBRARY LOADED (conformance, and the generated
; compliance run).
;
; This is a REAL x-lang file on purpose.  It used to be a heredoc inside the
; runner and a stack of printf lines inside the compliance generator, which meant
; the only x-lang in the project that could not be read, linted, highlighted or
; run on its own was the x-lang that tests the engine.  Anything a suite needs to
; SAY belongs in a .x or .spec.md file; a shell script may compute DATA for it,
; and nothing else.
;
; Everything here stays inside the bare-callable set -- fn, match, def, error,
; first, rest, eq?, +, include -- because a preamble written in anything richer
; would be testing itself rather than the engine.

; --- the assertion ----------------------------------------------------------
; A bare engine has no printer: display and write are x-lang, and it does not
; echo results either (a plain `(+ 1 2)` prints nothing at all).  The only
; observation channel is `error`, whose text the read-eval loop prints as
; `*** ERROR: <text>`.  So an assertion is an error either way, and the suites
; compare which one.  A CRASH prints neither, which is how a dead engine stays
; distinguishable from a wrong answer.
(def %ok (fn (self c) (match (c (error "ok")) (#t (error "no")))))

; --- the catalog door -------------------------------------------------------
; `prim-ref` DOES NOT EXIST bare: it is x-level (lib/x/boot/registry.x replaces
; the C bindings).  A coordinate is reached by walking the engine's own committed
; base paths to the prims cell -- and then taking ONE MORE first, because the path
; ends at the CELL whose car is the catalog.  Without that step every lookup
; misses in silence and a fully equipped engine reports as having nothing.
;
; The catalog is an alist-of-alists, ((ns . ((method . prim) ...)) ...), built by
; x_prims_file.  Namespace and method symbols are interned, so these comparisons
; are pointer comparisons.
(include "tools/contract/base-paths.x")

(def %assoc
  (fn (self k l)
    (match ((eq? l ()) ())
           ((eq? (first (first l)) k) (first l))
           (#t (self k (rest l))))))

(def %walk
  (fn (self steps o)
    (match ((eq? steps ()) o)
           ((eq? (first steps) (lit f)) (self (rest steps) (first o)))
           (#t (self (rest steps) (rest o))))))

(def %cat
  (first (%walk (rest (rest (%assoc (lit prims) %base-paths))) (%base))))

; (%coord 'ns 'method) -> the primitive filed there, or () when absent.
(def %coord
  (fn (self ns m)
    (match ((eq? (%assoc ns %cat) ()) ())
           (#t (rest (%assoc m (rest (%assoc ns %cat))))))))

; (%count-missing '((ns method) ...)) -> how many of those coordinates are absent.
; The compliance suite's provides check is a fold over generated DATA rather than
; generated code: the shell computes the list, this walks it.
(def %count-missing
  (fn (self pairs n)
    (match ((eq? pairs ()) n)
           (#t (self (rest pairs)
                     (match ((eq? (%coord (first (first pairs))
                                          (first (rest (first pairs)))) ())
                             (+ n 1))
                            (#t n)))))))

; The allocation churn used by the GC experiments: conses `n` pairs and returns a
; symbol, so a caller can burn heap without holding any of it.
(def %burn
  (fn (self n junk)
    (match ((= n 0) (lit done))
           (#t (self (- n 1) (pair n n))))))

; (%count-missing-bare '(name ...)) -> how many of those BARE names are unbound.
; Bare-bound primitives carry no ns/method split, so they cannot be looked up in
; the catalog; `eval!` resolves a symbol held in a variable, which is what lets
; this be data-driven too -- the alternative was a shell script printf-ing one
; line of x-lang per name, which is how this file came to exist.
(def %count-missing-bare
  (fn (self names n)
    (match ((eq? names ()) n)
           (#t (self (rest names)
                     (guard (e (+ n 1))
                       (match ((eq? (eval! (first names)) ()) (+ n 1))
                              (#t n))))))))
