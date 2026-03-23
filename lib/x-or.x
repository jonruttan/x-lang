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
  (pair "lib/x/sys/posix.x"
  (pair "lib/x/sys/hash.x"
  (pair "lib/x/tool/compile.x"
  (pair "lib/x/num/bignum.x"
  (pair "lib/x/sys/regex.x"
  (pair "lib/x/num/float.x"
  (pair "lib/x/num/rational.x"
  (pair "lib/x/num/complex.x"
  (pair "lib/x/or.x"
    (first %include-list-cell)))))))))))
; Load compiler infrastructure FIRST (before numeric tower)
(include "lib/x/sys/posix.x")
(include "lib/x/sys/hash.x")
(include "lib/x/tool/compile.x")

; --- Load numeric tower with immediate analyser compilation ---
; Each type's analyser is compiled right after loading, so subsequent
; type source files are parsed through compiled (fast) analysers.

; 1. Bignum — also provides int-capped analyser
(include "lib/x/num/bignum.x")
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
(include "lib/x/sys/regex.x")

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

; Load x-or extensions (parsed through all compiled analysers)
(include "lib/x/or.x")
(set! %lang-name "x-or")
(set! %lang-version x-lib-version)
(%banner)
(repl)
