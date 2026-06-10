; # Computational Expressions in C
;
; ## x-and.x -- x/and Standard Library
;
; @description x/and: Stable/Hardened dialect
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Pre-register all heavy module paths
(set-first! %include-list-cell
  (pair "lib/x/sys/posix.x"
  (pair "lib/x/core/hash.x"
  (pair "lib/x/tool/compile.x"
  (pair "lib/x/num/bignum.x"
  (pair "lib/x/type/regex.x"
  (pair "lib/x/num/float.x"
  (pair "lib/x/num/rational.x"
  (pair "lib/x/num/complex.x"
  (pair "lib/x/sys/ansi.x"
  (pair "lib/x/and.x"
    (first %include-list-cell))))))))))))
; Load compiler infrastructure FIRST (before numeric tower)
; (posix.x already loaded by x-core.x)
(include "lib/x/core/hash.x")
(include "lib/x/tool/compile.x")

; --- Compile the quote-family analysers and swap them into the symbol
;     type's analyse list.  x-core.x (lit-reader.x) installed interpreted
;     versions; these run on every char while tokenizing, so compiling them
;     keeps subsequent files parsing fast. ---

(set! %compile-fvars
  (list (pair (lit %quasi-accept) %quasi-accept)))
(def %c-quasi-analyse
  (compile
    (lit (fn (_ buffer score chr)
      (if (= chr 96) %quasi-accept ())))
    %compile-fvars))

(set! %compile-fvars
  (list (pair (lit %unquote-after-comma) %unquote-after-comma)))
(def %c-unquote-analyse
  (compile
    (lit (fn (_ buffer score chr)
      (if (= chr 44) %unquote-after-comma ())))
    %compile-fvars))

(set! %compile-fvars
  (list (pair (lit %lit-accept) %lit-accept)))
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
  (first (first (type-analyse-cell (type-by-atom (type-of "x"))))))
(set-first! %sym-analyse-list %c-lit-analyse)
(set-first! (rest %sym-analyse-list) %c-quasi-analyse)
(set-first! (rest (rest %sym-analyse-list)) %c-unquote-analyse)

; --- Load numeric tower with immediate analyser compilation ---

; 1. Bignum + int-capped
(include "lib/x/num/bignum.x")
(set! %compile-fvars
  (list (pair (lit %big-sign-state) %big-sign-state)
        (pair (lit %big-digits) %big-digits)
        (pair (lit %int-capped-digits) %int-capped-digits)
        (pair (lit %int-capped-sign) %int-capped-sign)))
(type-push-analyse (type-by-atom (type-of (Num expt 2 64)))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    %compile-fvars))
(type-push-analyse (type-by-atom (type-of 0))
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
  (list (pair (lit %float-int-digits) %float-int-digits)))
(type-push-analyse (type-by-atom (type-of 1.0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    %compile-fvars))
(set! %compile-fvars ())

; 4. Rational
(include "lib/x/num/rational.x")
(set! %compile-fvars
  (list (pair (lit %rat-numer) %rat-numer)
        (pair (lit %rat-sign)
          (fn (_ buffer score chr)
            (if (< chr 48) () (if (< chr 58) %rat-numer ()))))))
(type-push-analyse (type-by-atom (type-of 1/2))
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
  (list (pair (lit %cx-real-int) %cx-real-int)))
(type-push-analyse (type-by-atom (type-of 1+1i))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    %compile-fvars))
(set! %compile-fvars ())

; Load x-and module (parsed through all compiled analysers)
(include "lib/x/and.x")

; ANSI color support (terminal detection + REPL highlighting)
(include "lib/x/sys/ansi.x")

(set! %lang-name "x-and")
(set! %lang-version x-lib-version)
(%banner)
(repl)
