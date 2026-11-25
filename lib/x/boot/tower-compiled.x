; boot/tower-compiled.x -- the numeric tower with compiled tokenizer analysers
;
; What xenon and radon add to neon's compiler (boot/compiler.x), and what
; x-base.x loads over the core: each tower type's library and its literal,
; with the literal's analyser compiled as soon as it is loaded, so the rest
; of the tower, user source and tests are tokenized through native code.
;
; Each state's fvars are passed as an argument to its own compile, so no
; analyser captures a previous type's free variables.
;
; Loads via raw `include` from the dialect bodies -- registered in the
; pre-seed below (with the tower modules) per the pre-seed invariant that
; make check-boot-order enforces.  Its own includes are ../-relative,
; so it loads from any directory: an installed tree's importer runs anywhere.

; The compiler and the compile ladder.  An import, so it is a no-op wherever
; the name is already registered: under a body that included the file, and
; in a base that imported it by name before this one.
(import x/boot/compiler)

; Fetch the type-system helpers from the catalogue (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-of (prim-ref (lit type) (lit of)))

; (%tower-state ENV NAME): a module's binding of one of its states, as it
; stands -- the interpreted twin before its compile, the compiled one after.
(def %tower-state (fn (_ env name) (eval name env)))

; Pre-register the heavy module NAMES so the tower's internal imports are
; no-ops and the curated load order below stays authoritative.
(%set-first! %module-loaded-cell
  (pair (lit x/boot/tower-compiled)
  (pair (lit x/num/bigint)
  (pair (lit x/num/bigint/literal)
  (pair (lit x/type/regex)
  (pair (lit x/type/regex/literal)
  (pair (lit x/num/float)
  (pair (lit x/num/float/literal)
  (pair (lit x/num/rational)
  (pair (lit x/num/rational/literal)
  (pair (lit x/num/complex)
  (pair (lit x/num/complex/literal)
  (pair (lit x/num/decimal)
  (pair (lit x/num/decimal/literal)
    (first %module-loaded-cell)))))))))))))))


; --- Load numeric tower with immediate analyser compilation ---

; 1. Bigint + int-capped
; Each tower type is a library and, in a module of its own, the literal that
; writes it; the states compiled below are the literal module's, float's
; apart, whose states the library keeps to read text by.
(include "../num/bigint.x")
(include "../num/bigint/literal.x")
(import x/num/bigint/literal big-digits big-sign-state int-capped-base int-capped-digits int-capped-sign)
; These two PUSH a new analyser rather than swapping one, so there is no
; interpreted twin already installed to fall back to -- the twin is written
; here.  The bodies must agree with the compiled forms below; they can, because
; unlike quote and quasiquote, these use byte codes on both sides and so are
; textually identical.
(def %big-analyse-interp
  (fn (_ buffer score chr)
    (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) big-sign-state ())
      (if (< chr 58) big-digits ()))))
(def %int-analyse-interp
  (fn (_ buffer score chr)
    (if (< chr #\0)
      (if (or (= chr #\-) (= chr #\+)) int-capped-sign ())
      (if (= chr #\0) int-capped-base
        (if (<= chr #\9) int-capped-digits ())))))
; --- The per-character digit LOOPS ---
; Each of these is entered once per token and then runs once per CHARACTER
; until the token ends, which is where a number's reading cost actually goes.
; They loop by returning their self param (`me`), so the whole run of digits
; stays in native code instead of re-entering the interpreter per character.
; The states they hand off to at the END of a run are left interpreted: those
; fire once per token, and an interpreted state resolves its successor by
; global name at call time, so it picks up whichever of these is installed.
; big-digits and int-capped-digits are NOT compiled, and the attempt is not
; made.  Both close their run by measuring the token -- (%buffer-len buffer),
; against %int-max-digits -- and the lane has no door for it, so the compile
; raises.  A raise here is not free the way a miss is: the compiler emits most
; of the body before it reaches the form it cannot lower, nothing is cached
; because nothing was produced, and the attempt drags in asm-compile.x (2.5M
; evals) on a boot that would otherwise never load it.  Measured, the two
; attempts alone cost ~14M evals of a 65M boot -- more than every successful
; state put together.
;
; So they stay interpreted, declared here rather than discovered each boot.
; The other five types' states still compile, and they run on the same
; characters, which is why an integer literal still reads 58% cheaper.
; Compiling these two wants a buffer-length door on the lane.

(%tower-jit-push! big-analyse (%type-by-atom (%type-of (Num expt 2 64)))
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) big-sign-state ())
        (if (< chr 58) big-digits ()))))
    (list (pair (lit big-sign-state) big-sign-state)
          (pair (lit big-digits) big-digits))
    %big-analyse-interp)
(%tower-jit-push! int-analyse (%type-by-atom (%type-of 0))
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) int-capped-sign ())
        (if (= chr 48) int-capped-base
          (if (<= chr 57) int-capped-digits ())))))
    (list (pair (lit int-capped-sign) int-capped-sign)
          (pair (lit int-capped-base) int-capped-base)
          (pair (lit int-capped-digits) int-capped-digits))
    %int-analyse-interp)

; 2. Regex, and its #/pattern/ literal (no compile: its states run inside a
; literal only)
(include "../type/regex.x")
(include "../type/regex/literal.x")

; 3. Float
(include "../num/float.x")
(include "../num/float/literal.x")
; bigint's states above are imported: the tower reads them and never rebinds
; them, so the root's copies stay exact.  The float states are rebound by the
; compiles below, in the module's own frame, and a copy would keep the
; interpreted twin -- so the tower reads the module's binding, as it stands.
(def %float-env (module x/num/float))
; --- The STATES, not just the entry test (x-lang#596's parked half) ---
;
; The entry analyser runs once per token; the states run once per CHARACTER,
; and until now every one of them was interpreted -- which is why a number
; costs so much more than an identifier to read.  Measured on this tree, 2000
; literals each, over the cost of the same count of symbols: a float literal
; +60,036 evals, an int +21,793.
;
; This could not be written until a compiled analyser could return ITSELF
; (#583) and call itself (#596): a looping state continues a token by handing
; the same handler back, and the function's own pointer does not exist until
; its compile finishes, so no fvar can carry it.  The self param does -- it is
; slot 0 of the callee's own argument list.  `me` names it below.
;
; It was also not worth doing until compiling was cheap.  Each of these is
; another compile-asm call on every boot; with the byte cache (#590) they are
; a load rather than a compile from the second process onward.
;
; ORDER IS LOAD-BEARING, twice.  A state that hands off to another takes it as
; an fvar, which bakes the value that name holds AT COMPILE TIME -- so the
; innermost state compiles first, or the compiled one hands back an
; interpreted successor and the loop drops out of native code on its first
; transition.  And all of them compile before the ENTRY analyser below, which
; names two of them the same way.
(%tower-jit-global! float-exp-digits #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        me
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
    ()
    (%tower-state %float-env (lit float-exp-digits))
    %float-env)
(%tower-jit-global! float-exp-first #t
    (lit (fn (_ buffer score chr)
      (if (and (>= chr 48) (<= chr 57)) float-exp-digits ())))
    (list (pair (lit float-exp-digits) (%tower-state %float-env (lit float-exp-digits))))
    (%tower-state %float-env (lit float-exp-first))
    %float-env)
(%tower-jit-global! float-exp-sign #t
    (lit (fn (_ buffer score chr)
      (if (or (= chr 43) (= chr 45))
        float-exp-first
        (if (and (>= chr 48) (<= chr 57)) float-exp-digits ()))))
    (list (pair (lit float-exp-first) (%tower-state %float-env (lit float-exp-first)))
          (pair (lit float-exp-digits) (%tower-state %float-env (lit float-exp-digits))))
    (%tower-state %float-env (lit float-exp-sign))
    %float-env)
(%tower-jit-global! float-frac #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        me
        (if (or (= chr 101) (= chr 69))
          float-exp-sign
          (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))
    (list (pair (lit float-exp-sign) (%tower-state %float-env (lit float-exp-sign))))
    (%tower-state %float-env (lit float-frac))
    %float-env)
(%tower-jit-global! float-first-frac #t
    (lit (fn (_ buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        (%seq (%score-set score 1 buffer) float-frac)
        ())))
    (list (pair (lit float-frac) (%tower-state %float-env (lit float-frac))))
    (%tower-state %float-env (lit float-first-frac))
    %float-env)
(%tower-jit-global! float-int-digits #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        me
        (if (= chr 46) float-first-frac ()))))
    (list (pair (lit float-first-frac) (%tower-state %float-env (lit float-first-frac))))
    (%tower-state %float-env (lit float-int-digits))
    %float-env)
; float-neg-int -- the SIGN state -- is deliberately NOT compiled.
;
; #49 was "a compiled analyser captured something nothing rooted, a later
; collect freed it, and the next leading '+'/'-' jumped into freed memory",
; and the sign states are where it lived: every other tower stage keeps its
; sign state a module-level def for exactly that reason.  Two of the radon
; smoke cases that fail on CI with the states installed are #49's own
; regressions, and this is the only sign state among them.
;
; It is also the cheapest one to give up: a sign runs ONCE per token, not once
; per character, so leaving it interpreted costs almost nothing of the win
; while removing the one pattern with a history of exactly this failure.

; The interpreted twin, for an engine with no JIT.  Must agree with
; the compiled form below.  It is built in the module's frame so that its
; successors resolve there at call time, to whichever state is installed.
(def %float-analyse-interp
  (eval (lit (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) float-neg-int ())
      (if (< chr 58) float-int-digits ()))))
    %float-env))
(%tower-jit-push! float-analyse (%type-by-atom (%type-of 1.0))
    ; Sign branch mirrors the interpreted analyser -- without it, -7.5
    ; only parses via the stacked interpreted fallback (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) float-neg-int ())
        (if (< chr 58) float-int-digits ()))))
    (list (pair (lit float-neg-int) (%tower-state %float-env (lit float-neg-int)))
          (pair (lit float-int-digits) (%tower-state %float-env (lit float-int-digits))))
    %float-analyse-interp)

; 4. Rational
(include "../num/rational.x")
(include "../num/rational/literal.x")
; %rat-sign is rational.x's module-level def, like every other stage's sign
; state. It used to be an anonymous closure built right here, which the
; compiled analyser captured and nothing rooted once the fvar list was
; cleared -- a later collect freed it, and the next leading '+'/'-'
; jumped into freed memory (#49).
; The states are the module's own, read and set through its frame as float's
; are above.
(def %rat-env (module x/num/rational/literal))
(%tower-jit-global! rat-denom #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        (%seq (%score-set score 1 buffer) me)
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
    ()
    (%tower-state %rat-env (lit rat-denom))
    %rat-env)
(%tower-jit-global! rat-numer #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        me
        (if (= chr 47) rat-first-denom ()))))
    (list (pair (lit rat-first-denom) (%tower-state %rat-env (lit rat-first-denom))))
    (%tower-state %rat-env (lit rat-numer))
    %rat-env)
; The interpreted twin, for an engine with no JIT.  Must agree with the
; compiled form below; built in the module's frame, see float's.
(def %rat-analyse-interp
  (eval (lit (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) rat-sign (if (= chr 43) rat-sign ()))
      (if (< chr 58) rat-numer ()))))
    %rat-env))
(%tower-jit-push! rat-analyse (%type-by-atom (%type-of 1/2))
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) rat-sign (if (= chr 43) rat-sign ()))
        (if (< chr 58) rat-numer ()))))
    (list (pair (lit rat-sign) (%tower-state %rat-env (lit rat-sign)))
          (pair (lit rat-numer) (%tower-state %rat-env (lit rat-numer))))
    %rat-analyse-interp)

; 5. Complex
(include "../num/complex.x")
(include "../num/complex/literal.x")
(def %cx-env (module x/num/complex/literal))
(%tower-jit-global! cx-imag-frac #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57))
        me
        (if (= chr 105) (%score-set score 1 buffer) ()))))
    ()
    (%tower-state %cx-env (lit cx-imag-frac))
    %cx-env)
(%tower-jit-global! cx-imag-int #t
    (lit (fn (me buffer score chr)
      (match
        ((and (>= chr 48) (<= chr 57)) me)
        ((= chr 46) cx-imag-dot)
        ((= chr 105) (%score-set score 1 buffer))
        (#t ()))))
    (list (pair (lit cx-imag-dot) (%tower-state %cx-env (lit cx-imag-dot))))
    (%tower-state %cx-env (lit cx-imag-int))
    %cx-env)
(%tower-jit-global! cx-real-frac #t
    (lit (fn (me buffer score chr)
      (match
        ((and (>= chr 48) (<= chr 57)) me)
        ((= chr 43) cx-sign)
        ((= chr 45) cx-sign)
        ((= chr 105) (%score-set score 1 buffer))
        (#t ()))))
    (list (pair (lit cx-sign) (%tower-state %cx-env (lit cx-sign))))
    (%tower-state %cx-env (lit cx-real-frac))
    %cx-env)
(%tower-jit-global! cx-real-int #t
    (lit (fn (me buffer score chr)
      (match
        ((and (>= chr 48) (<= chr 57)) me)
        ((= chr 46) cx-real-dot)
        ((= chr 43) cx-sign)
        ((= chr 45) cx-sign)
        ((= chr 105) (%score-set score 1 buffer))
        (#t ()))))
    (list (pair (lit cx-real-dot) (%tower-state %cx-env (lit cx-real-dot)))
          (pair (lit cx-sign) (%tower-state %cx-env (lit cx-sign))))
    (%tower-state %cx-env (lit cx-real-int))
    %cx-env)
; The interpreted twin, for an engine with no JIT.  Must agree with the
; compiled form below; built in the module's frame, see float's.
(def %cx-analyse-interp
  (eval (lit (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) cx-neg ())
      (if (< chr 58) cx-real-int ()))))
    %cx-env))
(%tower-jit-push! cx-analyse (%type-by-atom (%type-of 1+1i))
    ; Sign branch: -1+2i analyses as complex (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) cx-neg ())
        (if (< chr 58) cx-real-int ()))))
    (list (pair (lit cx-neg) (%tower-state %cx-env (lit cx-neg)))
          (pair (lit cx-real-int) (%tower-state %cx-env (lit cx-real-int))))
    %cx-analyse-interp)

; 6. Decimal
;
; Last, and the order is load-bearing twice over.  Its from-alist declares
; float and (through the pact) rational and complex, so those handles must
; already exist; and its analyser only scores a run that ENDS in `d`, which
; is a longer claim than float's on the same digits -- 1.5d beats 1.5 by the
; suffix, and a token without one is never contested.
(include "../num/decimal.x")
; The 1.5d literal is a module of its own; the states compiled below are its.
(include "../num/decimal/literal.x")
(def %dec-env (module x/num/decimal/literal))
(%tower-jit-global! dec-exp-digits #t
    (lit (fn (me buffer score chr)
      (if (and (>= chr 48) (<= chr 57)) me
        (if (= chr 100) (%score-set score 1 buffer) ()))))
    ()
    (%tower-state %dec-env (lit dec-exp-digits))
    %dec-env)
(%tower-jit-global! dec-frac #t
    (lit (fn (me buffer score chr)
      (match
        ((and (>= chr 48) (<= chr 57)) me)
        ((= chr 100) (%score-set score 1 buffer))
        ((or (= chr 101) (= chr 69)) dec-exp-sign)
        (#t ()))))
    (list (pair (lit dec-exp-sign) (%tower-state %dec-env (lit dec-exp-sign))))
    (%tower-state %dec-env (lit dec-frac))
    %dec-env)
(%tower-jit-global! dec-int #t
    (lit (fn (me buffer score chr)
      (match
        ((and (>= chr 48) (<= chr 57)) me)
        ((= chr 100) (%score-set score 1 buffer))
        ((= chr 46) dec-first-frac)
        ((or (= chr 101) (= chr 69)) dec-exp-sign)
        (#t ()))))
    (list (pair (lit dec-first-frac) (%tower-state %dec-env (lit dec-first-frac)))
          (pair (lit dec-exp-sign) (%tower-state %dec-env (lit dec-exp-sign))))
    (%tower-state %dec-env (lit dec-int))
    %dec-env)
; The interpreted twin, for an engine with no JIT.  Must agree with the
; compiled form below; built in the module's frame, see float's.
(def %dec-analyse-interp
  (eval (lit (fn (_ buffer score chr)
      (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) dec-sign ())
      (if (< chr 58) dec-int ()))))
    %dec-env))
(%tower-jit-push! dec-analyse (%type-by-atom (%type-of 1.5d))
    ; Sign branch mirrors the interpreted analyser: -0.001d is one
    ; token, not a `-` applied to a decimal (#45 R4's lesson).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) dec-sign ())
        (if (< chr 58) dec-int ()))))
    (list (pair (lit dec-sign) (%tower-state %dec-env (lit dec-sign)))
          (pair (lit dec-int) (%tower-state %dec-env (lit dec-int))))
    %dec-analyse-interp)

; --- The library's compiled loops --------------------------------------------
; Loading the function compiler compiles the library's own hot loops (Hash
; fnv-1a's, lib/x/tool/fn-compile.x), each on Compiled's list, so an image
; holds them interpreted and the loader compiles them again.
(import x/tool/fn-compile)

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
