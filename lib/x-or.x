; # Computational Expressions in C
;
; ## x-or.x -- x/or Standard Library
;
; @description x/or: Experimental/Hacking dialect
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
; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-analyse-cell (prim-ref (lit type) (lit analyse-cell)))
(def %type-push-analyse (prim-ref (lit type) (lit push-analyse)))

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
  (pair "lib/x/or.x"
    (first %include-list-cell))))))))))))
; Load compiler infrastructure (needed for analyser compilation + caching)
; (posix.x already loaded by x-core.x)
(include "lib/x/core/hash.x")
(include "lib/x/tool/compile.x")

; --- Compile the quote-family analysers and swap them into the symbol
;     type's analyse list.  They run on every char during tokenizing;
;     keeping them as interpreted fn closures makes every subsequent file
;     parse ~20% slower, so compile and install them. ---

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
  (first (first (%type-analyse-cell (%type-by-atom (type-of "x"))))))
(set-first! %sym-analyse-list %c-lit-analyse)
(set-first! (rest %sym-analyse-list) %c-quasi-analyse)
(set-first! (rest (rest %sym-analyse-list)) %c-unquote-analyse)

; --- Load numeric tower with immediate analyser compilation ---
; Each type's analyser is compiled right after loading, so subsequent
; type source files are parsed through compiled (fast) analysers.

; 1. Bignum — also provides int-capped analyser
(include "lib/x/num/bignum.x")
(def %big-fvars
  (list (pair (lit %big-sign-state) %big-sign-state)
        (pair (lit %big-digits) %big-digits)
        (pair (lit %int-capped-digits) %int-capped-digits)
        (pair (lit %int-capped-sign) %int-capped-sign)))
(%type-push-analyse (%type-by-atom (type-of (Num expt 2 64)))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    %big-fvars))
(%type-push-analyse (%type-by-atom (type-of 0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %int-capped-sign ())
        (if (< chr 58) %int-capped-digits ()))))
    %big-fvars))

; 2. Regex (has C analyser, no compile needed)
(include "lib/x/type/regex.x")

; 3. Float
(include "lib/x/num/float.x")
(def %float-fvars
  (list (pair (lit %float-int-digits) %float-int-digits)))
(%type-push-analyse (%type-by-atom (type-of 1.0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    %float-fvars))

; 4. Rational
(include "lib/x/num/rational.x")
(def %rat-fvars
  (list (pair (lit %rat-numer) %rat-numer)
        (pair (lit %rat-sign)
          (fn (_ buffer score chr)
            (if (< chr 48) () (if (< chr 58) %rat-numer ()))))))
(%type-push-analyse (%type-by-atom (type-of 1/2))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
        (if (< chr 58) %rat-numer ()))))
    %rat-fvars))

; 5. Complex
(include "lib/x/num/complex.x")
(def %cx-fvars
  (list (pair (lit %cx-real-int) %cx-real-int)))
(%type-push-analyse (%type-by-atom (type-of 1+1i))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    %cx-fvars))

; Load x-or extensions (parsed through all compiled analysers)
(include "lib/x/or.x")

; ANSI color support (terminal detection + REPL highlighting)
(include "lib/x/sys/ansi.x")

(set! %lang-name "x-or")
(set! %lang-version x-lib-version)
(%banner)
(repl)
