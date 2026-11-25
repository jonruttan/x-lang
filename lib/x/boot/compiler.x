; boot/compiler.x -- the compiler, and the core's reader hooks compiled by it
;
; The first half of every dialect above helium (boot/neon.x, and through it
; boot/xenon.x and boot/radon.x; boot/tower-compiled.x for a base that loads
; the tower alone): load the compiler and the assembler, then compile the
; analysers the core installed and swap them into the symbol type's analyse
; list.  Analysers run on every character while tokenizing, so every file
; read after this one is tokenized through native code.
;
; The helpers the tower's literal compiles use (%tower-asm, %tower-jit-global!
; and the rest) are defined here, since they are the compile ladder itself.
;
; The neon body includes it and boot/tower-compiled.x imports it.  It
; registers its own name below, per the pre-seed invariant that make
; check-boot-order enforces, so whichever comes second is a no-op.  Its
; includes are ../-relative, so it loads from any directory.

; Fetch the type-system helpers from the catalogue (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-of (prim-ref 'type 'of))
(def %type-analyse-cell (prim-ref 'type 'analyse-cell))
(def %type-push-analyse (prim-ref 'type 'push-analyse))

; Pre-register the module NAMES loaded here by raw include, so a later import
; of one is a no-op.
(%set-first! %module-loaded-cell
  (pair (lit x/boot/compiler)
  (pair (lit x/type/hash)
  (pair (lit x/tool/compile)
    (first %module-loaded-cell)))))

; Load compiler infrastructure FIRST (before numeric tower)
; (posix.x already loaded by x-core.x)
; hash.x is not included here: x-core.x ends by loading x/core/first-rest,
; whose cache door imports x/type/hash, so it is already in.
(include "../tool/compile.x")
(import x/tool/compile compile compile-asm compile-hosted?)
; The assembler, loaded here rather than on the first compile-asm.  The
; tower's analyser compiles below load it at run time through asm-cache, and
; num/float.x imports it for its stubs.  A run-time import is invisible to
; tools/release/amalgamate.sh, which inlines float's top-level import instead:
; asm.x then loaded twice in an amalgam, and the second load left %arch
; empty, so the first stub float emitted crashed the boot.  Imported here, at
; top level and ahead of both, it is inlined once and both imports find it.
(import x/tool/asm)
; The quote and quasiquote readers' entry tests and states, to compile and to
; swap by identity.
(import x/reader/lit-reader lit-accept lit-analyse macro-delimit interp-analyse interp-after-hash)
(import x/reader/quasi-reader quasi-accept quasi-analyse unquote-after-comma unquote-analyse)
; Every compile below is on Compiled's list: it is switched to interpreted
; before a state image is written and compiled again after one is loaded.
(import x/tool/compiled)

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
;
; The probe is one state in the form the states below take -- analyser mode,
; a loop through the self param, a handoff through an fvar -- so it refuses
; where they would and nowhere else.  Its result is never called.
;
; It is asked again once a state image has loaded, since the loading engine
; is not the writing one.  Its hook is added after its first run and before
; the first entry's: whatever the first compile loaded has its own hooks in
; by then, and every entry compiles under this process's answer.
(def %tower-jit? #f)
(def %tower-probe!
  (fn (_)
    (set! %tower-jit?
      (guard (_ #f)
        (do (compile-asm (lit (fn (me buffer score chr) (if (= chr 32) me k)))
                         (list (pair (lit k) 1)) #t)
            #t)))))
(%tower-probe!)
((prim-ref (lit image) (lit recache-hook!)) %tower-probe!)

; One pattern for the ten states, a LADDER of three rungs:
;
;   1. compile-asm -- the engine's own JIT, no toolchain, first choice.
;   2. the cc lane -- ONLY as a fallback, and only where the engine ships
;      its C headers (compile-hosted?): an engine without native/jit but
;      with a hosted toolchain still gets compiled analysers, and the cc
;      lane's content-keyed /tmp cache means each expression compiles once
;      per machine, not once per boot.
;   3. the interpreted twin -- always correct, never raises.
;
; A closed rung answers the interpreted twin, and the entry's state is
; `interpreted`.  A compile that raises is not caught here: the raise reaches
; the entry, which installs the twin and keeps the raise's text, so
; (Compiled report) names every state whose compile failed and why.  Fvars are passed as arguments and every value is a
; module-level def, which is what roots them after the burst (#49's lesson,
; kept).
(def %tower-asm
  (fn (_ src fvars interp)
    (if %tower-jit?
      (compile-asm src fvars #t)
      (if compile-hosted?
        (compile src fvars)
        interp))))

; The ladder's MIDDLE RUNG is for bodies EITHER compiler can lower, and none of
; the analyser STATES below is one.  They speak the tokenizer protocol -- they
; loop by returning their self param, and they call %score-set and
; %buffer-unread -- and every part of that is the ASSEMBLER lane's:
; the self param resolves to firstobj of p_args with no eval and no unbox
; (#583), and the trampolines are its own.  Grep the cc lane for analyser mode,
; object params or a self param and there is nothing; it is simply the wrong
; compiler for these bodies, whatever it does with one.
;
; The ENTRY analysers above are different and keep the full ladder: they only
; test a character and hand back a state, which the cc lane has lowered
; correctly for as long as it has existed.
;
; So every state takes the asm lane or stays interpreted, nothing in between.
; The point is not only to avoid a bad compile -- it is that on a host WITHOUT
; native/jit this whole section must be a strict NO-OP, leaving exactly the
; interpreted states that were there before it was written.  CI's ubuntu engine
; is that host, and it is where the ladder's middle rung was found reaching
; these bodies at all.
(def %tower-asm-only
  (fn (_ src fvars interp)
    (if %tower-jit? (compile-asm src fvars #t) interp)))

; --- Every compile is on the list ---------------------------------------------
; A compiled analyser is native code in a page this process mapped, and no
; state image can carry it.  So every compile below makes an entry of
; Compiled's (lib/x/tool/compiled.x): the interpreted twin, the function that
; compiles it, and the function that installs either.  The image writer
; switches every entry to interpreted before its walk, so an image holds the
; interpreted tower, and the loader compiles each again in the order it was
; made here.  A compile evaluates its fvars form each time it runs: a
; state's free names are the states compiled before it, and after a load
; those are new objects.
;
; The tower installs into one of two places: a name's binding, which may
; be in a module's own environment as the float states' are, and one cell
; of a type's handler list.

; An entry whose compile is one of the two ladders over SRC and the fvars
; FVARSF answers.
(def %tower-compiled!
  (fn (_ name asm src fvarsf interp install)
    (Compiled make name interp (fn (_) (asm src (fvarsf) interp)) install)))
; (%tower-jit-global! NAME ONLY? SRC FVARS INTERP [ENV]): NAME is set! to the
; compile of SRC over FVARS, or to INTERP when the lane refuses; ONLY? picks
; %tower-asm-only over %tower-asm.  An operative, so FVARS stays a form.  ENV
; is the environment NAME is bound in: a module's frame for a state the
; module owns, the caller's own when left out.
(def %tower-jit-global!
  (op (name only? src fvars interp . env) e
    (%tower-compiled! name
      (if (eval only? e) %tower-asm-only %tower-asm)
      (eval src e) (fn (_) (eval fvars e)) (eval interp e)
      (Compiled into-name name (if (null? env) e (eval (first env) e))))))
; (%tower-jit-push! NAME TYPE SRC FVARS INTERP): INTERP is pushed onto TYPE's
; analyse stack, where %type-push-analyse puts it, and the entry NAME
; installs into the cell it landed in.
(def %tower-jit-push!
  (op (name ts src fvars interp) e
    (%tower-jit-push-run! name (eval ts e) (eval src e) (fn (_) (eval fvars e)) (eval interp e))))
(def %tower-jit-push-run!
  (fn (_ name ts src fvarsf interp)
    (%type-push-analyse ts interp)
    (%tower-compiled! name %tower-asm src fvarsf interp
      (Compiled into-cell (first (%type-analyse-cell ts))))))
; (%tower-swap! NAME CELL INTERP COMPILE): CELL's first, INTERP, becomes
; (COMPILE).
(def %tower-swap!
  (fn (_ name cell interp compile)
    (Compiled make name interp compile (Compiled into-cell cell))))

; --- Compile the quote and quasiquote analysers and swap them into the symbol
;     type's analyse list.  x-core.x (lit-reader.x) installed interpreted
;     versions; these run on every char while tokenizing, so compiling them
;     keeps subsequent files parsing fast. ---
;

(def %c-quasi-analyse ())
(%tower-jit-global! %c-quasi-analyse #f
    (lit (fn (_ buffer score chr)
      (if (= chr 96) quasi-accept ())))
    (list (pair (lit quasi-accept) quasi-accept))
    ; No JIT in this engine: keep the interpreted twin, so the identity
    ; swap below replaces this handler with itself.
    quasi-analyse)

(def %c-unquote-analyse ())
(%tower-jit-global! %c-unquote-analyse #f
    (lit (fn (_ buffer score chr)
      (if (= chr 44) unquote-after-comma ())))
    (list (pair (lit unquote-after-comma) unquote-after-comma))
    unquote-analyse)

(def %c-lit-analyse ())
(%tower-jit-global! %c-lit-analyse #f
    (lit (fn (_ buffer score chr)
      (if (= chr 39) lit-accept ())))
    (list (pair (lit lit-accept) lit-accept))
    lit-analyse)

; Only the entry test compiles: it is the piece that runs on every character.
; The states behind it (interp-after-hash's machine) run inside a literal
; only, so they stay interpreted -- and they are closures over a `let`, with no
; global names for an fvar list to bind anyway.
(def %c-interp-analyse ())
(%tower-jit-global! %c-interp-analyse #f
    (lit (fn (_ buffer score chr)
      (if (= chr 35) interp-after-hash ())))
    (list (pair (lit interp-after-hash) interp-after-hash))
    interp-analyse)

; Compiled the compiled analysers in for the interpreted handlers BY IDENTITY,
; never by seat.  A positional swap breaks silently the day lit-reader.x
; grows a handler: when #"..." interpolation joined the list at seat 0,
; the old three-seat overwrite destroyed its analyser (every interpolated
; literal then read as one SYMBOL in every tower dialect) while ' ` , kept
; working -- each char still had SOME handler, so nothing failed loudly.
; Matching each interpreted handler follows the contract instead of the
; layout; handlers this file does not know (and the C catch-all tail)
; pass through untouched.
; Identity MUST be (obj same?) -- pointer identity.  eq? compares value
; words, and two DIFFERENT interpreted closures answer eq? #t (their
; first data words coincide), so an eq?-keyed draft of this walk stamped
; the first compiled handler over every seat and killed quote and quasiquote alike.
(def %tower-same? (prim-ref 'obj 'same?))
(def %sym-analyse-list
  (first (first (%type-analyse-cell (%type-by-atom (%type-of "x"))))))
(def %tower-swap-one!
  (fn (_ cell)
    (match
      ((%tower-same? (first cell) interp-analyse) (%tower-swap! (lit interp-analyse) cell interp-analyse (fn (_) %c-interp-analyse)))
      ((%tower-same? (first cell) lit-analyse) (%tower-swap! (lit lit-analyse) cell lit-analyse (fn (_) %c-lit-analyse)))
      ((%tower-same? (first cell) quasi-analyse) (%tower-swap! (lit quasi-analyse) cell quasi-analyse (fn (_) %c-quasi-analyse)))
      ((%tower-same? (first cell) unquote-analyse) (%tower-swap! (lit unquote-analyse) cell unquote-analyse (fn (_) %c-unquote-analyse)))
      (#t ()))))
(def %tower-swap-analysers!
  (fn (self cell)
    (match
      ((null? cell) ())
      (#t (do (%tower-swap-one! cell) (self (rest cell)))))))
(%tower-swap-analysers! %sym-analyse-list)

; --- Compile the symbol type's delimiter hook -------------------------------
;
; macro-delimit (lit-reader.x) runs on EVERY character of every symbol
; token: the C symbol analyser calls it per char to ask whether ' ` , ends the
; token (so foo'bar reads as foo then 'bar).  Interpreted, it is the single
; largest per-character reader cost.  It has the same pattern as the numeric
; analysers, so it JITs through the same lane, and like them it speeds every
; read AFTER it -- the rest of the tower, xe.x, and (the bulk of the win) all
; source read once the platform is up: bundles, user files, specs.  A tower
; boot itself drops ~13% (x-core is read before the compiler exists, so it,
; like the numeric literals, stays interpreted); the
; one op it needs that they do not, reading the last consumed character, is the
; jit_buffer_last_char trampoline (%buffer-last-char below).  It compiles
; through %tower-asm-only, as the states do: %buffer-last-char and
; %buffer-unread are the asm lane's trampolines, and the cc rung compiles the
; hook without refusing into one that misreads the source read after it.  So
; where the asm lane is closed the symbol type keeps the interpreted
; macro-delimit, and an engine without the JIT (or the trampoline) is
; unchanged.  The body has no free variable, so its fvar table is empty and
; the analyser mode is declared.
(def %type-delimit-cell (prim-ref 'type 'delimit-cell))
; Compile only when the engine exports jit_buffer_last_char, asked of the
; process with dlsym, the way the lane resolves its trampolines.  asm-compile.x
; binds the address as well, but only once a cache miss has loaded the compiler,
; and a boot whose compiles all hit the byte cache never loads it.  Decide up
; front rather than attempting the compile and catching the failure: a compile
; aborted against a missing trampoline is not worth the risk (an x86-64 backend
; left bad state and the next boot crashed), when the answer -- keep the
; interpreted macro-delimit -- is known here.
(def %c-macro-delimit macro-delimit)
(if (null? ((prim-ref 'ffi 'dlsym) ((prim-ref 'ffi 'dlopen) () 1) "jit_buffer_last_char")) ()
  (%tower-jit-global! %c-macro-delimit #t
    (lit (fn (_ buffer)
      ; ' ` (39 96) each end an adjacent token; the comma (44) does not, as
      ; in the interpreted macro-delimit this twins.  %buffer-unread rewinds
      ; the delimiter char AND returns the buffer, which is the value the C
      ; delimit protocol tests for a match -- so no %seq is needed (and the
      ; asm lane does not compile %seq with a call in discard position).
      (if (or (= (%buffer-last-char buffer) 39)
              (or (= (%buffer-last-char buffer) 96)
                  (= (%buffer-last-char buffer) 96)))
        (%buffer-unread buffer)
        ())))
    ()
    macro-delimit))
(def %sym-delimit-list
  (first (%type-delimit-cell (%type-by-atom (%type-of "x")))))
(def %tower-swap-delimit!
  (fn (self cell)
    (match
      ((null? cell) ())
      ((%tower-same? (first cell) macro-delimit) (%tower-swap! (lit macro-delimit) cell macro-delimit (fn (_) %c-macro-delimit)))
      (#t (self (rest cell))))))
(%tower-swap-delimit! %sym-delimit-list)
