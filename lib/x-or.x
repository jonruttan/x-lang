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
; Pre-register all heavy module paths
(set-first! %include-list-cell
  (pair "lib/x/posix.x"
  (pair "lib/x/hash.x"
  (pair "lib/x/compile.x"
  (pair "lib/x/bignum.x"
  (pair "lib/x/regex.x"
  (pair "lib/x/float.x"
  (pair "lib/x/rational.x"
  (pair "lib/x/complex.x"
  (pair "lib/x/or.x"
    (first %include-list-cell)))))))))))
; Load compiler infrastructure FIRST (before numeric tower)
(include "lib/x/posix.x")
(include "lib/x/hash.x")
(include "lib/x/compile.x")

; --- Load numeric tower with immediate analyser compilation ---
; Each type's analyser is compiled right after loading, so subsequent
; type source files are parsed through compiled (fast) analysers.

; 1. Bignum — also provides int-capped analyser
(include "lib/x/bignum.x")
(set! %compile-fvars
  (list (pair (lit %big-sign-state) %big-sign-state)
        (pair (lit %big-digits) %big-digits)
        (pair (lit %int-capped-digits) %int-capped-digits)
        (pair (lit %int-capped-sign) %int-capped-sign)))
(type-push-analyse (type-by-atom (type-of (expt 2 64)))
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

; 2. Regex (has C analyser, no compile needed)
(include "lib/x/regex.x")

; 3. Float
(include "lib/x/float.x")
(set! %compile-fvars
  (list (pair (lit %float-int-digits) %float-int-digits)))
(type-push-analyse (type-by-atom (type-of 1.0))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %float-int-digits ()))))
    %compile-fvars))
(set! %compile-fvars ())

; 4. Rational
(include "lib/x/rational.x")
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
(include "lib/x/complex.x")
(set! %compile-fvars
  (list (pair (lit %cx-real-int) %cx-real-int)))
(type-push-analyse (type-by-atom (type-of 1+1i))
  (compile
    (lit (fn (_ buffer score chr)
      (if (< chr 48) () (if (< chr 58) %cx-real-int ()))))
    %compile-fvars))
(set! %compile-fvars ())

; Load x-or extensions (parsed through all compiled analysers)
(include "lib/x/or.x")
(set! %lang-name "x-or")
(set! %lang-version x-lib-version)
(%banner)
(repl)
