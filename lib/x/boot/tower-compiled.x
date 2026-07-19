; boot/tower-compiled.x -- the numeric tower with compiled tokenizer analysers
;
; The shared heart of every full-stack dialect entry (x-base.x, x-and.x,
; x-or.x): load the compiler, compile the quote-family analysers and swap
; them into the symbol type's analyse list, then load each tower type and
; immediately compile its analyser.  Analysers run on every char while
; tokenizing, so compiling them makes every SUBSEQUENT file parse through
; native code instead of interpreted closures (~20x faster tokenizing of the
; rest of the tower, user source, and tests).
;
; This file was extracted from three near-identical copies in the dialect
; entries; the copies had already diverged (x-or grew per-type fvar names
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

; Pre-register the heavy module paths so the tower's internal imports are
; no-ops and the curated load order below stays authoritative.
(set-first! %include-list-cell
  (pair "lib/x/boot/tower-compiled.x"
  (pair "lib/x/type/hash.x"
  (pair "lib/x/tool/compile.x"
  (pair "lib/x/num/bignum.x"
  (pair "lib/x/type/regex.x"
  (pair "lib/x/num/float.x"
  (pair "lib/x/num/rational.x"
  (pair "lib/x/num/complex.x"
    (first %include-list-cell))))))))))

; Load compiler infrastructure FIRST (before numeric tower)
; (posix.x already loaded by x-core.x)
(include "lib/x/type/hash.x")
(include "lib/x/tool/compile.x")

; --- Compile the quote-family analysers and swap them into the symbol
;     type's analyse list.  x-core.x (lit-reader.x) installed interpreted
;     versions; these run on every char while tokenizing, so compiling them
;     keeps subsequent files parsing fast. ---

(set! %compile-fvars
  (list (pair '%quasi-accept %quasi-accept)))
(def %c-quasi-analyse
  (compile
    (lit (fn (_ buffer score chr)
      (if (= chr 96) %quasi-accept ())))
    %compile-fvars))

(set! %compile-fvars
  (list (pair '%unquote-after-comma %unquote-after-comma)))
(def %c-unquote-analyse
  (compile
    (lit (fn (_ buffer score chr)
      (if (= chr 44) %unquote-after-comma ())))
    %compile-fvars))

(set! %compile-fvars
  (list (pair '%lit-accept %lit-accept)))
(def %c-lit-analyse
  (compile
    (lit (fn (_ buffer score chr)
      (if (= chr 39) %lit-accept ())))
    %compile-fvars))
(set! %compile-fvars ())

; Swap the compiled analysers in for the interpreted handlers.  The symbol
; type's analyse list (from lit-reader.x) is (lit quasi unquote <C symbol
; analyse>); the C catch-all tail stays as is.
(def %sym-analyse-list
  (first (first (%type-analyse-cell (%type-by-atom (%type-of "x"))))))
(set-first! %sym-analyse-list %c-lit-analyse)
(set-first! (rest %sym-analyse-list) %c-quasi-analyse)
(set-first! (rest (rest %sym-analyse-list)) %c-unquote-analyse)

; --- Load numeric tower with immediate analyser compilation ---

; 1. Bignum + int-capped
(include "lib/x/num/bignum.x")
(set! %compile-fvars
  (list (pair '%big-sign-state %big-sign-state)
        (pair '%big-digits %big-digits)
        (pair '%int-capped-digits %int-capped-digits)
        (pair '%int-capped-sign %int-capped-sign)))
(%type-push-analyse (%type-by-atom (%type-of (Num expt 2 64)))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    %compile-fvars))
(%type-push-analyse (%type-by-atom (%type-of 0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %int-capped-sign ())
        (if (< chr 58) %int-capped-digits ()))))
    %compile-fvars))
(set! %compile-fvars ())

; 2. Regex (C analyser, no compile needed)
(include "lib/x/type/regex.x")

; 3. Float
(include "lib/x/num/float.x")
(set! %compile-fvars
  (list (pair '%float-int-digits %float-int-digits)
        (pair '%float-neg-int %float-neg-int)))
(%type-push-analyse (%type-by-atom (%type-of 1.0))
  (compile
    ; Sign branch mirrors the interpreted analyser -- without it, -7.5
    ; only parses via the stacked interpreted fallback (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %float-neg-int ())
        (if (< chr 58) %float-int-digits ()))))
    %compile-fvars))
(set! %compile-fvars ())

; 4. Rational
(include "lib/x/num/rational.x")
(set! %compile-fvars
  (list (pair '%rat-numer %rat-numer)
        (pair '%rat-sign
          (fn (_ buffer score chr)
            (if (< chr 48) () (if (< chr 58) %rat-numer ()))))))
(%type-push-analyse (%type-by-atom (%type-of 1/2))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
        (if (< chr 58) %rat-numer ()))))
    %compile-fvars))
(set! %compile-fvars ())

; 5. Complex
(include "lib/x/num/complex.x")
(set! %compile-fvars
  (list (pair '%cx-real-int %cx-real-int)
        (pair '%cx-neg %cx-neg)))
(%type-push-analyse (%type-by-atom (%type-of 1+1i))
  (compile
    ; Sign branch: -1+2i analyses as complex (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %cx-neg ())
        (if (< chr 58) %cx-real-int ()))))
    %compile-fvars))
(set! %compile-fvars ())
