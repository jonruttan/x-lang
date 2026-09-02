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
; that were never reset).  One copy, one idiom: each state's fvars are passed
; as an argument to its own compile, so no analyser accidentally captures a
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

; --- THE BURST USES THE ENGINE'S OWN JIT, NEVER A SYSTEM TOOLCHAIN -----------
;
; These compiles used to go through the cc lane: write a .c file, spawn the
; host's C compiler, dlopen the object.  A language runtime cannot assume a C
; compiler exists on the machine that runs it -- CPython does not -- and a
; boot that shells out to a toolchain is not hosting a JIT.  compile-asm is
; the engine's own lane: machine code assembled in process, no toolchain, the
; same lane the lang bundles adopt for their tokenizers.  One catchable probe
; decides for the whole burst -- an engine without native/jit, or a platform
; predating fvar forwarding, answers by RAISING -- and every state then keeps
; its interpreted twin, the same honest fallback the missing-C-headers branch
; used to be.  The cc lane (lib/x/tool/compile.x) remains a TOOL a user may
; import and call; the boot never touches it again.
(def %tower-jit?
  (guard (_ #f)
    (do (compile-asm (lit (fn (_ x) (+ x k))) (list (pair (lit k) 1))) #t)))

; One site shape for the ten states, a LADDER of three rungs:
;
;   1. compile-asm -- the engine's own JIT, no toolchain, first choice.
;   2. the cc lane -- ONLY as a fallback, and only where the engine ships
;      its C headers (%compile-hosted?): an engine without native/jit but
;      with a hosted toolchain still gets compiled analysers, and the cc
;      lane's content-keyed /tmp cache means each expression compiles once
;      per machine, not once per boot.
;   3. the interpreted twin -- always correct, never raises.
;
; Any refusal at a rung drops one rung, never dies.  Fvars are passed as
; arguments and every value is a module-level def, which is what roots them
; after the burst (#49's lesson, kept).
(def %tower-asm
  (fn (_ src fvars interp)
    (if %tower-jit?
      (guard (_ interp) (compile-asm src fvars))
      (if %compile-hosted?
        (guard (_ interp) (compile src fvars))
        interp))))

; --- Compile the quote-family analysers and swap them into the symbol
;     type's analyse list.  x-core.x (lit-reader.x) installed interpreted
;     versions; these run on every char while tokenizing, so compiling them
;     keeps subsequent files parsing fast. ---
;

(def %c-quasi-analyse
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (= chr 96) %quasi-accept ())))
    (list (pair (lit %quasi-accept) %quasi-accept))
    ; No JIT in this engine: keep the interpreted twin, so the identity
    ; swap below replaces this handler with itself.
    %quasi-analyse))

(def %c-unquote-analyse
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (= chr 44) %unquote-after-comma ())))
    (list (pair (lit %unquote-after-comma) %unquote-after-comma))
    %unquote-analyse))

(def %c-lit-analyse
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (= chr 39) %lit-accept ())))
    (list (pair (lit %lit-accept) %lit-accept))
    %lit-analyse))

; Only the entry test compiles: it is the piece that runs on every character.
; The states behind it (%interp-after-dollar's machine) run inside a literal
; only, so they stay interpreted -- and they are closures over a `let`, with no
; global names for an fvar list to bind anyway.
(def %c-interp-analyse
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (= chr 36) %interp-after-dollar ())))
    (list (pair (lit %interp-after-dollar) %interp-after-dollar))
    %interp-analyse))

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

; --- Compile the symbol type's delimiter hook -------------------------------
;
; %macro-delimit (lit-reader.x) runs on EVERY character of every symbol-shaped
; token: the C symbol analyser calls it per char to ask whether ' ` , ends the
; token (so foo'bar reads as foo then 'bar).  Interpreted, it is the single
; largest per-character reader cost.  It is the same shape as the numeric
; analysers, so it JITs through the same lane, and like them it speeds every
; read AFTER it -- the rest of the tower, xe.x, and (the bulk of the win) all
; source read once the platform is up: bundles, user files, specs.  A tower
; boot itself drops ~13% (x-core is read before the compiler exists, so it,
; like the numeric literals, stays interpreted); the
; one op it needs that they do not, reading the last consumed character, is the
; jit_buffer_last_char trampoline (%buffer-last-char below).  The %tower-asm
; ladder keeps the interpreted %macro-delimit as the fallback, so an engine
; without the JIT (or the trampoline) is unchanged.  A lone (pair (lit _u) 1)
; fvar forces analyser mode for a body that has no real free variable.
(def %type-delimit-cell (prim-ref 'type 'delimit-cell))
; Compile only when the engine actually exports jit_buffer_last_char.
; asm-compile resolved it to a non-zero address; an engine that predates it
; (the released engine CI builds against, until the next engine release) left
; it 0.  Decide up front rather than attempting the compile and catching the
; failure: a compile aborted against a missing trampoline is not worth the
; risk (an x86-64 backend left bad state and the next boot crashed), when the
; answer -- keep the interpreted %macro-delimit -- is known here.  The guard
; covers the (import-order) case where the name is not yet bound at all.
(def %c-macro-delimit
  (if (guard (_ #t) (= %jit-buffer-last-char 0))
    %macro-delimit
  (%tower-asm
    (lit (fn (_ buffer)
      ; ' ` , (39 96 44) each end an adjacent token.  %buffer-unread rewinds
      ; the delimiter char AND returns the buffer, which is the value the C
      ; delimit protocol tests for a match -- so no %seq is needed (and the
      ; asm lane does not compile %seq with a call in discard position).
      (if (or (= (%buffer-last-char buffer) 39)
              (or (= (%buffer-last-char buffer) 96)
                  (= (%buffer-last-char buffer) 44)))
        (%buffer-unread buffer)
        ())))
    (list (pair (lit _u) 1))
    %macro-delimit)))
(def %sym-delimit-list
  (first (%type-delimit-cell (%type-by-atom (%type-of "x")))))
(def %tower-swap-delimit!
  (fn (self cell)
    (match
      ((null? cell) ())
      ((%tower-same? (first cell) %macro-delimit) (%set-first! cell %c-macro-delimit))
      (#t (self (rest cell))))))
(%tower-swap-delimit! %sym-delimit-list)

; --- Load numeric tower with immediate analyser compilation ---

; 1. Bigint + int-capped
(include "lib/x/num/bigint.x")
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
    (if (< chr #\0)
      (if (or (= chr #\-) (= chr #\+)) %int-capped-sign ())
      (if (= chr #\0) %int-capped-base
        (if (<= chr #\9) %int-capped-digits ())))))
(%type-push-analyse (%type-by-atom (%type-of (Num expt 2 64)))
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %big-sign-state ())
        (if (< chr 58) %big-digits ()))))
    (list (pair (lit %big-sign-state) %big-sign-state)
          (pair (lit %big-digits) %big-digits))
    %big-analyse-interp))
(%type-push-analyse (%type-by-atom (%type-of 0))
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %int-capped-sign ())
        (if (= chr 48) %int-capped-base
          (if (<= chr 57) %int-capped-digits ())))))
    (list (pair (lit %int-capped-sign) %int-capped-sign)
          (pair (lit %int-capped-base) %int-capped-base)
          (pair (lit %int-capped-digits) %int-capped-digits))
    %int-analyse-interp))

; 2. Regex (C analyser, no compile needed)
(include "lib/x/type/regex.x")

; 3. Float
(include "lib/x/num/float.x")
; The interpreted twin, for an engine with no JIT.  Must agree with
; the compiled form below.
(def %float-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %float-neg-int ())
      (if (< chr 58) %float-int-digits ()))))
(%type-push-analyse (%type-by-atom (%type-of 1.0))
  (%tower-asm
    ; Sign branch mirrors the interpreted analyser -- without it, -7.5
    ; only parses via the stacked interpreted fallback (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %float-neg-int ())
        (if (< chr 58) %float-int-digits ()))))
    (list (pair (lit %float-neg-int) %float-neg-int)
          (pair (lit %float-int-digits) %float-int-digits))
    %float-analyse-interp))

; 4. Rational
(include "lib/x/num/rational.x")
; %rat-sign is rational.x's module-level def, like every other stage's sign
; state. It used to be an anonymous closure built right here, which the
; compiled analyser captured and nothing rooted once the fvar list was
; cleared -- a later collect freed it, and the next leading '+'/'-'
; jumped into freed memory (#49).
; The interpreted twin, for an engine with no JIT.  Must agree with
; the compiled form below.
(def %rat-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
      (if (< chr 58) %rat-numer ()))))
(%type-push-analyse (%type-by-atom (%type-of 1/2))
  (%tower-asm
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %rat-sign (if (= chr 43) %rat-sign ()))
        (if (< chr 58) %rat-numer ()))))
    (list (pair (lit %rat-sign) %rat-sign)
          (pair (lit %rat-numer) %rat-numer))
    %rat-analyse-interp))

; 5. Complex
(include "lib/x/num/complex.x")
; The interpreted twin, for an engine with no JIT.  Must agree with
; the compiled form below.
(def %cx-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (= chr 45) %cx-neg ())
      (if (< chr 58) %cx-real-int ()))))
(%type-push-analyse (%type-by-atom (%type-of 1+1i))
  (%tower-asm
    ; Sign branch: -1+2i analyses as complex (#45 R4).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (= chr 45) %cx-neg ())
        (if (< chr 58) %cx-real-int ()))))
    (list (pair (lit %cx-neg) %cx-neg)
          (pair (lit %cx-real-int) %cx-real-int))
    %cx-analyse-interp))

; 6. Decimal
;
; Last, and the order is load-bearing twice over.  Its from-alist declares
; float and (through the pact) rational and complex, so those handles must
; already exist; and its analyser only scores a run that ENDS in `d`, which
; is a longer claim than float's on the same digits -- 1.5d beats 1.5 by the
; suffix, and a token without one is never contested.
(include "lib/x/num/decimal.x")
; The interpreted twin, for an engine with no JIT.  Must agree with
; the compiled form below.
(def %dec-analyse-interp
  (fn (_ buffer score chr)
      (if (< chr 48)
      (if (or (= chr 45) (= chr 43)) %dec-sign ())
      (if (< chr 58) %dec-int ()))))
(%type-push-analyse (%type-by-atom (%type-of 1.5d))
  (%tower-asm
    ; Sign branch mirrors the interpreted analyser: -0.001d is one
    ; token, not a `-` applied to a decimal (#45 R4's lesson).
    (lit (fn (_ buffer score chr)
      (if (< chr 48)
        (if (or (= chr 45) (= chr 43)) %dec-sign ())
        (if (< chr 58) %dec-int ()))))
    (list (pair (lit %dec-sign) %dec-sign)
          (pair (lit %dec-int) %dec-int))
    %dec-analyse-interp))

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
