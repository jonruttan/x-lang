; boot/tower-compiled.x -- the numeric tower with compiled tokenizer analysers
;
; The shared heart of every full-stack dialect body (x-base.x and
; boot/{xenon,radon}.x): load the compiler, compile the quote-family analysers and swap
; them into the symbol type's analyse list, then load each tower type and
; immediately compile its analyser.  Analysers run on every char while
; tokenizing, so compiling them makes every SUBSEQUENT file parse through
; native code instead of interpreted closures (~20x faster tokenizing of the
; rest of the tower, user source, and tests).
;
; This file was extracted from three near-identical copies in the dialect
; entries; the copies had already diverged (the experimental entry grew per-type fvar names
; that were never reset).  One copy, one idiom: %compile-fvars is set before
; each compile and cleared after, so no analyser accidentally captures a
; previous type's free variables.
;
; Loads via raw `include` from the dialect entries -- registered in the
; pre-seed below (with the tower modules) per the pre-seed invariant that
; make check-boot-order enforces.

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-of (prim-ref 'type 'of))
(def %type-analyse-cell (prim-ref 'type 'analyse-cell))
(def %type-push-analyse (prim-ref 'type 'push-analyse))

; Pre-register the heavy module NAMES so the tower's internal imports are
; no-ops and the curated load order below stays authoritative.
(%set-first! %module-loaded-cell
  (pair (lit x/boot/tower-compiled)
  (pair (lit x/type/hash)
  (pair (lit x/tool/compile)
  (pair (lit x/num/bigint)
  (pair (lit x/type/regex)
  (pair (lit x/num/float)
  (pair (lit x/num/rational)
  (pair (lit x/num/complex)
  (pair (lit x/num/decimal)
    (first %module-loaded-cell)))))))))))

; Load compiler infrastructure FIRST (before numeric tower)
; (posix.x already loaded by x-core.x)
(include "lib/x/type/hash.x")
(include "lib/x/tool/compile.x")

; --- Compile the quote-family analysers and swap them into the symbol
;     type's analyse list.  x-core.x (lit-reader.x) installed interpreted
;     versions; these run on every char while tokenizing, so compiling them
;     keeps subsequent files parsing fast. ---
;
; The character constants below are BYTE CODES, not the #\c literals their
; interpreted twins in lit-reader.x/quasi-reader.x use: `compile` emits a
; constant verbatim into the generated C, so #\` reaches cc as #\` and the
; build dies with "expected expression".  ' = 39, $ = 36, ` = 96, , = 44.

(set! %compile-fvars
  (list (pair '%quasi-accept %quasi-accept)))
(def %c-quasi-analyse
  (match
    (%compile-hosted?
      (compile
      (lit (fn (_ buffer score chr)
        (if (= chr 96) %quasi-accept ())))
      %compile-fvars))
    ; No C headers in this engine: keep the interpreted twin, so the
    ; identity swap below replaces this handler with itself.
    (#t %quasi-analyse)))

(set! %compile-fvars
  (list (pair '%unquote-after-comma %unquote-after-comma)))
(def %c-unquote-analyse
  (match
    (%compile-hosted?
      (compile
      (lit (fn (_ buffer score chr)
        (if (= chr 44) %unquote-after-comma ())))
      %compile-fvars))
    ; No C headers in this engine: keep the interpreted twin, so the
    ; identity swap below replaces this handler with itself.
    (#t %unquote-analyse)))

(set! %compile-fvars
  (list (pair '%lit-accept %lit-accept)))
(def %c-lit-analyse
  (match
    (%compile-hosted?
      (compile
      (lit (fn (_ buffer score chr)
        (if (= chr 39) %lit-accept ())))
      %compile-fvars))
    ; No C headers in this engine: keep the interpreted twin, so the
    ; identity swap below replaces this handler with itself.
    (#t %lit-analyse)))

; Only the entry test compiles: it is the piece that runs on every character.
; The states behind it (%interp-after-dollar's machine) run inside a literal
; only, so they stay interpreted -- and they are closures over a `let`, with no
; global names for %compile-fvars to bind anyway.
(set! %compile-fvars
  (list (pair '%interp-after-dollar %interp-after-dollar)))
(def %c-interp-analyse
  (match
    (%compile-hosted?
      (compile
      (lit (fn (_ buffer score chr)
        (if (= chr 36) %interp-after-dollar ())))
      %compile-fvars))
    ; No C headers in this engine: keep the interpreted twin, so the
    ; identity swap below replaces this handler with itself.
    (#t %interp-analyse)))
(set! %compile-fvars ())

; Swap the compiled analysers in for the interpreted handlers BY IDENTITY,
; never by seat.  A positional swap breaks silently the day lit-reader.x
; grows a handler: when $"..." interpolation joined the list at seat 0,
; the old three-seat overwrite destroyed the $ analyser (every $-string
; then read as one SYMBOL in every tower dialect) while ' ` , kept
; working -- each char still had SOME handler, so nothing failed loudly.
; Matching each interpreted handler follows the contract instead of the
; layout; handlers this file does not know (and the C catch-all tail)
; pass through untouched.
; Identity MUST be (obj same?) -- pointer identity.  eq? compares value
; words, and two DIFFERENT interpreted closures answer eq? #t (their
; first data words coincide), so an eq?-keyed draft of this walk stamped
; the first compiled handler over every seat and killed the quote family.
(def %tower-same? (prim-ref 'obj 'same?))
(def %sym-analyse-list
  (first (first (%type-analyse-cell (%type-by-atom (%type-of "x"))))))
(def %tower-swap-one!
  (fn (_ cell)
    (match
      ((%tower-same? (first cell) %interp-analyse) (%set-first! cell %c-interp-analyse))
      ((%tower-same? (first cell) %lit-analyse) (%set-first! cell %c-lit-analyse))
      ((%tower-same? (first cell) %quasi-analyse) (%set-first! cell %c-quasi-analyse))
      ((%tower-same? (first cell) %unquote-analyse) (%set-first! cell %c-unquote-analyse))
      (#t ()))))
(def %tower-swap-analysers!
  (fn (self cell)
    (match
      ((null? cell) ())
      (#t (do (%tower-swap-one! cell) (self (rest cell)))))))
(%tower-swap-analysers! %sym-analyse-list)

; --- Load numeric tower with immediate analyser compilation ---

; 1. Bigint + int-capped
(include "lib/x/num/bigint.x")
(set! %compile-fvars
  (list (pair '%big-sign-state %big-sign-state)
        (pair '%big-digits %big-digits)
        (pair '%int-capped-digits %int-capped-digits)
        (pair '%int-capped-sign %int-capped-sign)
        (pair '%int-capped-base %int-capped-base)))
; These two PUSH a new analyser rather than swapping one, so there is no
; interpreted twin already installed to fall back to -- the twin is written
; here.  The bodies must agree with the compiled forms below; they can, because
; unlike the quote family these use byte codes on both sides and so are
; textually identical.
(def %big-analyse-interp
  (fn (_ buffer score chr)
    (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) %big-sign-state ())
      (if (< chr 58) %big-digits ()))))
(def %int-analyse-interp
  (fn (_ buffer score chr)
    (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) %int-capped-sign ())
      (if (= chr 48) %int-capped-base
        (if (< chr 58) %int-capped-digits ())))))
(%type-push-analyse (%type-by-atom (%type-of (Num expt 2 64)))
  (match
    (%compile-hosted?
      (compile
        (lit (fn (_ buffer score chr)
          (if (< chr 48)
            (if (or (= chr 45) (= chr 43)) %big-sign-state ())
            (if (< chr 58) %big-digits ()))))
        %compile-fvars))
    (#t %big-analyse-interp)))
(%type-push-analyse (%type-by-atom (%type-of 0))
  (match
    (%compile-hosted?
      (compile
        (lit (fn (_ buffer score chr)
          (if (< chr 48)
            (if (or (= chr 45) (= chr 43)) %int-capped-sign ())
            (if (= chr 48) %int-capped-base
              (if (< chr 58) %int-capped-digits ())))))
        %compile-fvars))
    (#t %int-analyse-interp)))
(set! %compile-fvars ())

; 2. Regex (C analyser, no compile needed)
(include "lib/x/type/regex.x")

; 3. Float
(include "lib/x/num/float.x")
(set! %compile-fvars
  (list (pair '%float-int-digits %float-int-digits)
        (pair '%float-neg-int %float-neg-int)))
; The interpreted twin, for an engine with no C headers.  Must agree with
; the compiled form below.
(def %float-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %float-neg-int ())
      (if (< chr 58) %float-int-digits ()))))
(%type-push-analyse (%type-by-atom (%type-of 1.0))
  (match
    (%compile-hosted?
      (compile
        ; Sign branch mirrors the interpreted analyser -- without it, -7.5
        ; only parses via the stacked interpreted fallback (#45 R4).
        (lit (fn (_ buffer score chr)
      (if (< chr 48)
            (if (= chr 45) %float-neg-int ())
            (if (< chr 58) %float-int-digits ()))))
        %compile-fvars))
    (#t %float-analyse-interp)))
(set! %compile-fvars ())

; 4. Rational
(include "lib/x/num/rational.x")
(set! %compile-fvars
  ; %rat-sign is rational.x's module-level def, like every other stage's sign
  ; state. It used to be an anonymous closure built right here, which the
  ; compiled analyser captured and nothing rooted once %compile-fvars was
  ; cleared below -- a later collect freed it, and the next leading '+'/'-'
  ; jumped into freed memory (#49).
  (list (pair '%rat-numer %rat-numer)
        (pair '%rat-sign %rat-sign)))
; The interpreted twin, for an engine with no C headers.  Must agree with
; the compiled form below.
(def %rat-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
      (if (< chr 58) %rat-numer ()))))
(%type-push-analyse (%type-by-atom (%type-of 1/2))
  (match
    (%compile-hosted?
      (compile
        (lit (fn (_ buffer score chr)
      (if (< chr 48)
            (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
            (if (< chr 58) %rat-numer ()))))
        %compile-fvars))
    (#t %rat-analyse-interp)))
(set! %compile-fvars ())

; 5. Complex
(include "lib/x/num/complex.x")
(set! %compile-fvars
  (list (pair '%cx-real-int %cx-real-int)
        (pair '%cx-neg %cx-neg)))
; The interpreted twin, for an engine with no C headers.  Must agree with
; the compiled form below.
(def %cx-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %cx-neg ())
      (if (< chr 58) %cx-real-int ()))))
(%type-push-analyse (%type-by-atom (%type-of 1+1i))
  (match
    (%compile-hosted?
      (compile
        ; Sign branch: -1+2i analyses as complex (#45 R4).
        (lit (fn (_ buffer score chr)
      (if (< chr 48)
            (if (= chr 45) %cx-neg ())
            (if (< chr 58) %cx-real-int ()))))
        %compile-fvars))
    (#t %cx-analyse-interp)))
(set! %compile-fvars ())

; 6. Decimal
;
; Last, and the order is load-bearing twice over.  Its from-alist declares
; float and (through the pact) rational and complex, so those handles must
; already exist; and its analyser only scores a run that ENDS in `d`, which
; is a longer claim than float's on the same digits -- 1.5d beats 1.5 by the
; suffix, and a token without one is never contested.
(include "lib/x/num/decimal.x")
(set! %compile-fvars
  (list (pair '%dec-int %dec-int)
        (pair '%dec-sign %dec-sign)))
; The interpreted twin, for an engine with no C headers.  Must agree with
; the compiled form below.
(def %dec-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) %dec-sign ())
      (if (< chr 58) %dec-int ()))))
(%type-push-analyse (%type-by-atom (%type-of 1.5d))
  (match
    (%compile-hosted?
      (compile
        ; Sign branch mirrors the interpreted analyser: -0.001d is one
        ; token, not a `-` applied to a decimal (#45 R4's lesson).
        (lit (fn (_ buffer score chr)
      (if (< chr 48)
            (if (or (= chr 45) (= chr 43)) %dec-sign ())
            (if (< chr 58) %dec-int ()))))
        %compile-fvars))
    (#t %dec-analyse-interp)))
(set! %compile-fvars ())

; --- Reclaim the load burst: NOT HERE ---------------------------------------
;
; The collect that reclaims this block's output lives in the dialect BODIES
; (boot/xenon.x, boot/radon.x, x-base.x), not in this file, and the reason is
; worth recording because this file is the obvious place for it.
;
; THIS FILE IS IMPORTABLE.  tools/check/doctest.sh walks every module under
; lib/x and imports it, from a HELIUM base where this path is not pre-seeded --
; so `(import x/boot/tower-compiled)` really loads it, and a collect on the last
; line runs inside the walking tool, at a moment that tool did not choose.  It
; freed state doctest was holding and truncated its output; the run failed with
; "an import is eating stdin".  A module cannot know what its importer is
; holding, so a module must not collect.
;
; That is also the sharper lesson: the engine has no auto-GC, so objects that
; are live-but-unrooted are invisible until something collects.  The first
; collect anyone adds is the one that finds them.  Boot is the safe moment --
; nothing else is in flight -- and the dialect bodies are the files that are
; never imported.
