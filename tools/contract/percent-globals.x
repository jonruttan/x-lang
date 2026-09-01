; percent-globals.x -- the %-global budget, per file: (file "PATH" COUNT)
; May only SHRINK (tools/check/percent-globals.sh).  A file absent here
; has budget 0.  The composed alternative: home helpers as %-statics on
; the module's class (classes ARE namespaces; pin.x is the worked
; example -- 100 globals homed to 1).
;
; Scope is lib/ + apps/ + tools/ (#304): a tool script co-loads with the
; library, so its globals share the env.  Counting is form-accurate
; (tools/check/defs.awk), which sees two shapes the old line grep did
; not -- (doc (def %name ...)), so DOCUMENTED helpers stopped hiding, and
; defs directly inside a top-level (do ...), which is how tool scripts
; are written.  Rows that grew when the blind spots closed record
; globals that were always there, not new pollution.
;
; Hot-path rows stand on MEASURED de-dispatch grounds (8-30x class
; call overhead): sha256*, asm*, compile*, boot/*, and (#334: 15x on
; the fnv byte loop, 2x on dict ops, benchmarked) type/dict + type/hash,
; and (#335: cached int %// on the random draw loop, port math, and the
; per-expression gc tick) num/random + sys/socket + tool/asm-compile,
; and (#307: the sugar-fold cell reads per PRINTED NODE) tool/fmt, and
; tool/highlight, whose whole body is a per-BYTE scan: routing it through
; the class doors (Str8 ref / Char =?) and the numeric tower cost ~10x the
; resident memory of the cached byte prims -- 4KB of source wanted ~2.5GB
; and a 13KB module OOM-killed the machine; on byte-ref it peaks ~290MB
; above boot.  Grew by one for %hl-depth, the per-line paren scan that tells
; a transcript's continuation lines from its results -- same inner loop, same
; grounds.
; The type/class.x row GROWS during the object-model v2 arc (plan
; approved 2026-08-20): the dispatch engine's own helpers are the
; measured hot path (8-30x, #332) the exception above exists for --
; each growth step is one warm-path helper, named per commit.
; doc-gen grew by one for %doc-vis-note, shared by the method and member
; emitters when an entry comes out of a (private ...) or (protected ...)
; block: inlining it instead would duplicate the tier wording at both call
; sites, which is how the two drift.
; platform/syscall.x grew by two for %declared-os and %declared-arch: the engine's
; BUILD now declares its os and arch, and the triple parse became the fallback for
; an engine that could not establish them.  Boot-constrained like the rest of that
; file -- it loads mid-x-core, before the class machinery that would home them.
; LOGO'S THIRTEEN ROWS LEFT WITH LOGO (x-logo), and the last thing they
; recorded is worth keeping even though the files are gone.  run.x's single
; row was %logo-app-root, and it BOUGHT a deletion: the app root had been
; re-derived in main.x and guessed a third way in serve.x, as a cwd-relative
; literal that resolved only from the repo root -- so the viewer was broken in
; every INSTALLED tree.  One name in the ENTRY was the fix.
;
; The bundle needs even that one no longer: x.sh defines %lang-root for it
; (tools/contract/seam.x), so the fact is stated once by the only thing that
; knows it rather than derived once by the file most likely to be moved.  A
; budget row is a ratchet on a repo's own inventory; a lang in its own
; repository ratchets its own.
; Everything else is unhomed inventory awaiting the pin.x treatment.
; lib/x/reader/indent.x arrives at 6, and every one is the reader-context
; exception rather than convenience: four (advance/scan/measure/classify) are
; the catalog-registered functions themselves -- ns `indent`, fetched raw by
; per-character callers exactly as ns `token`'s terminators are -- and two are
; cached int/char prims those functions call once per CHARACTER of every leading
; whitespace run.  The stack arithmetic, which runs once per LINE, is homed on
; the class as (Indent %pop) / (Indent %feed) and costs nothing here.  #520.
; boot/tower-compiled.x grew from 17 to 18 for %dec-analyse-interp, the sixth
; tower stage's interpreted analyser twin -- one per stage is what this file
; IS, and the twin is not optional: the decimal analyser is PUSHED rather than
; swapped, so an engine with no C headers has nothing to fall back to unless
; the fallback is written here beside the compiled form it must agree with.
; num/decimal.x arrives at 72, ABOVE float's 60, and the difference between
; the two files is where the mathematics lives.  Float's twenty math methods
; are each one dlsym: libm computes in doubles, so the module is a door.
; There is no libm for a 34-digit decimal, so decimal.x carries the
; arithmetic itself -- the series for ln/exp/log10, their shared atanh, the
; ln 10 they ride on and its cache, the fixed-point scaling the series run
; in, and the working-precision plumbing that keeps guard digits out of the
; caller's answer.  Those are the rows float does not have to pay for, and
; four of them (bite, bite-div, drop, to-fx) are the measured 75x: they are
; what makes a power-of-ten division take bigint's single-limb fast path.  The rest stands on the same measured grounds
; bigint's 60 does: significand arithmetic and eleven analyser states are the
; reader's and the tower's hot paths, and class dispatch costs 8-30x there
; (the three hex states -- base, xfirst, xdigits -- joined for #507).
; Rows 61-63 are the #584 guard: %big-mixed-check raises the lattice's
; teaching error where the C arbitration would fall through to
; payload-word reads (an undeclared typed pair with handlers on both
; sides), and %type-from-cell/%type-ops-cell are its cached catalog
; accessors, per the file's own fetch-and-cache convention.
; What is NOT here is the point -- the text scanners (find, find-exp,
; parse-exp, digits) and the printer's zero/scientific helpers are LOCAL defs
; inside the two functions that use them, because a parse-local helper has no
; business in a flat global namespace.  #550.

(file "lib/x/boot/data.x" 14)
(file "lib/x/boot/engine.x" 2)
(file "lib/x/boot/module.x" 50)
(file "lib/x/boot/operatives.x" 6)
(file "lib/x/boot/printer.x" 76)
(file "lib/x/boot/reflect.x" 29)
(file "lib/x/boot/registry.x" 8)
(file "lib/x/boot/string.x" 25)
(file "lib/x/boot/tower-compiled.x" 18)
(file "lib/x/codec/json.x" 30)
(file "lib/x/codec/sha256-jit.x" 34)
(file "lib/x/codec/sha256.x" 33)
(file "lib/x/codec/utf8.x" 6)
(file "lib/x/core/alist.x" 12)
(file "lib/x/core/arithmetic.x" 17)
(file "lib/x/core/boolean.x" 3)
(file "lib/x/core/control.x" 2)
(file "lib/x/core/list.x" 19)
(file "lib/x/core/logic.x" 1)
(file "lib/x/core/math.x" 5)
(file "lib/x/core/op-guard.x" 6)
(file "lib/x/core/predicates.x" 12)
(file "lib/x/core/quasi.x" 1)
(file "lib/x/core/syntax.x" 5)
(file "lib/x/doc/doc-gen.x" 32)
(file "lib/x/doc/doc.x" 73)
(file "lib/x/num/bigint.x" 63)
(file "lib/x/num/complex.x" 41)
(file "lib/x/num/decimal.x" 72)
(file "lib/x/num/float.x" 60)
(file "lib/x/num/random.x" 6)
(file "lib/x/num/tower.x" 10)
(file "lib/x/num/rational.x" 39)
(file "lib/x/platform/socket.x" 1)
(file "lib/x/platform/syscall.x" 7)
(file "lib/x/protocol/seq.x" 1)
(file "lib/x/protocol/str/str8.x" 14)
(file "lib/x/protocol/str/utf8.x" 5)
(file "lib/x/reader/intrinsics.x" 5)
(file "lib/x/reader/lit-reader.x" 21)
(file "lib/x/reader/quasi-reader.x" 9)
(file "lib/x/reader/analyser.x" 14)
(file "lib/x/reader/indent.x" 6)
(file "lib/x/repl/ansi.x" 26)
(file "lib/x/repl/banner.x" 4)
(file "lib/x/repl/loop.x" 12)
(file "lib/x/rn.x" 1)
(file "lib/x/sys/date.x" 6)
(file "lib/x/sys/file.x" 7)
(file "lib/x/sys/pact.x" 12)
(file "lib/x/sys/posix.x" 32)
(file "lib/x/sys/socket.x" 31)
(file "lib/x/sys/stream.x" 5)
(file "lib/x/tool/asm-compile.x" 63)
(file "lib/x/tool/asm.x" 37)
(file "lib/x/tool/asm/arm64.x" 8)
(file "lib/x/tool/asm/x86_64.x" 23)
(file "lib/x/tool/compile.x" 25)
; emit.x rose 54 to 57 for the CHARACTER write handler: the type handle,
; the char->int door, and the writer itself -- one emitter family, the
; same standing the int and symbol writers have.
(file "lib/x/tool/compile/emit.x" 57)
(file "lib/x/tool/compile/pipeline.x" 10)
(file "lib/x/tool/contract.x" 4)
(file "lib/x/tool/cov.x" 8)
(file "lib/x/tool/fmt.x" 23)
(file "lib/x/tool/highlight.x" 39)
(file "lib/x/tool/lint.x" 69)
(file "lib/x/tool/pin.x" 1)
(file "lib/x/tool/profile.x" 4)
(file "lib/x/type/array.x" 2)
(file "lib/x/type/assoc.x" 1)
(file "lib/x/type/bool.x" 5)
(file "lib/x/type/char-io.x" 11)
(file "lib/x/type/char.x" 5)
(file "lib/x/type/record.x" 3)
(file "lib/x/type/trait.x" 6)
(file "lib/x/type/class.x" 89)
(file "lib/x/type/convert.x" 20)
(file "lib/x/type/dict.x" 19)
(file "lib/x/type/err.x" 6)
(file "lib/x/type/gen.x" 1)
(file "lib/x/type/generic.x" 19)
(file "lib/x/type/hash.x" 7)
(file "lib/x/type/iter.x" 19)
(file "lib/x/type/list.x" 5)
(file "lib/x/type/path.x" 2)
(file "lib/x/type/promise.x" 6)
(file "lib/x/type/ptr.x" 3)
(file "lib/x/type/regex.x" 41)
(file "lib/x/type/str-utf8.x" 14)
(file "lib/x/type/struct.x" 48)
(file "lib/x/type/vector.x" 17)
(file "tools/check/boot-order.x" 33)
(file "tools/check/dialect-cover.x" 9)
(file "tools/check/doc-forms.x" 5)
(file "tools/check/doctest.x" 11)
(file "tools/contract/bare-globals.x" 1)
(file "tools/contract/conformance-covered.x" 1)
(file "tools/contract/constraints.x" 1)
(file "tools/contract/features.x" 5)
(file "tools/contract/requires.x" 1)
(file "tools/dev/bench-sha256.x" 75)
(file "tools/dev/cov-report.x" 5)
(file "tools/dev/cov.x" 32)
(file "tools/dev/doc-index.x" 10)
(file "tools/dev/doc.x" 4)
(file "tools/dev/fmt.x" 13)
(file "tools/dev/highlight.x" 8)
(file "tools/dev/lint.x" 22)
(file "tools/fuzz/diff-gen.x" 18)
