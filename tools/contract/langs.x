; langs.x -- the lang bundles this platform is checked against.
;
; (langs-dir "PATH")             where bundles live, relative to the repo root.
;                                X_LANGS_DIR overrides it.
; (lang "NAME" "DIR" TESTS FAILED)   NAME as `-l` spells it, DIR under langs-dir,
;                                and the suite's counts as of the last edit.
;
; FAILED may only shrink (tools/check/langs.sh), the rule percent-globals.x
; runs on.  A number here is not a target; it is the debt this platform is
; known to be carrying, recorded so it cannot quietly grow.
;
; check-seam catches a rename in eight seconds and catches nothing else.  A
; behaviour change, an arity change, a reader that scores a tie differently:
; the platform stays green, every bundle's CI runs on its own schedule against
; a release rather than the working tree, and the break surfaces weeks later
; somewhere else.  The platform moving under the bundles is invisible here
; unless something runs them.
;
; A bundle lives in its own repository, so this gate is advisory about presence
; and strict about regression.  Bundles absent from the disk are skipped loudly
; and the gate still passes -- x-lang must build for someone who cloned nothing
; else.  Bundles that are present must not get worse.
;
; The counts are against whatever revision of each bundle is checked out, which
; is a real limitation and the reason TESTS is recorded beside FAILED: a suite
; that shrank is a different suite, and the gate says so rather than silently
; comparing a smaller run to an older number.

(langs-dir "../languages")

; Green, and expected to stay that way.
(lang "krn"   "x-krn"    74  0)
(lang "sweet" "x-sweet"  32  0)
; python's one failure was `what a class body accepts: only defs and pass`,
; which the bundle accepted instead of raising -- x-python's own bug, in
; x-python's own repository, measured identically on x-lang 41bca38f +
; x-engine-c v0.1.6 and on the ERR branch + v0.2.2, so nothing this platform
; did moved it.  The bundle has since fixed it: 1005 specs, 0 failed, measured
; at x-python b8f652a against this tree.  Ratcheted 1 -> 0.
;
; 592 is a FLOOR, not a census: the bundle is under active development and
; reported 601 minutes after the run that first recorded it.  The lower
; measured number is the safe one to record -- the column exists to catch a
; suite that SHRANK, and a floor set to a moving high-water mark cries wolf.
; It stays at 592 for that reason, not because the suite is that size.
(lang "python" "x-python" 592  0)
; awk is the self-hosting arc's first tool bundle: the build closure's
; heaviest external after the regex trio (docs/bootstrap-closure.md).
; 167 = feature-complete: the language, the CLI (`x -l awk -- ...` with
; -F/-v/-f, files/stdin, FILENAME/FNR/ARGV, redirection, exit status),
; and both pipe forms with SIGPIPE held off.  The six pending are
; recorded divergences only (04-divergences).  First performance pass
; done: byte-door scans, if-chain dispatchers, no defs at depth -- the
; record loop is 2.8x its first measure; the next step is the compile
; lanes.
(lang "awk"   "x-awk"   167  0)
; grep is the arc's second tool, and the closure's MOST-invoked external
; (4,186 calls).  BRE by escape-swap translation onto the regex engine,
; -E native, -F bytes; -i compiled into the pattern; the full POSIX flag
; set minus back-references and [:named:] classes, which refuse loudly.
(lang "grep"  "x-grep"   29  0)
; sed is the arc's third tool and its first CROSS-BUNDLE build: it
; requires-lang grep and rides its BRE translator and byte doors.
; s/// with backrefs on the regex engine's capture groups, addresses
; and ranges, the cycle; hold space and multiline are recorded pending.
(lang "sed"   "x-sed"    21  0)
; make completes the arc's core set (awk, grep, sed, make), and is
; deliberately self-contained -- the bootstrap's root requires no other
; lang.  The measured GNU subset: the functions, conditionals, pattern
; rules and automatics x-lang's own Makefiles use; it dry-runs x-awk's
; real Makefile.
(lang "make"  "x-make"   23  0)
; coreutils is the arc's second tier: NINETY-TWO applets in one bundle
; (busybox shape) -- parity with busybox's coreutils set.  The measured
; core (sort/tr/cut/join/comm), every digest byte-identical with the
; system tool (md5sum sha1sum sha256sum sha512sum cksum sum), expr with
; its own anchored matcher, od, the scripting set, and the nineteen
; applets that ride v0.11.0's doors (chmod ln readlink realpath df
; uname id ...).  Absent for want of a door: who stty hostid mknod.
(lang "coreutils" "x-coreutils" 103 0)
; cc is the arc's final tier: the full C front end, a cell-machine
; evaluator (`run` -- every spec an oracle row against /usr/bin/cc),
; and `build` -- eligible integer functions lower through the engine's
; compile-asm lane to NATIVE code, no external toolchain.  The build
; slice covers LOOPS (for/while transformed to tail self-recursion --
; params and accumulators alike ride the self-call; body locals
; substitute away; if/else merges as a ternary; return/break/continue
; are guarded exits, pre-loop guards wrap when loop-invariant; inits
; over the params pad as lane functions applied at the call boundary;
; nested loops two deep run as a state machine over the one self-call;
; and pointers -- the program's memory is one raw buffer the interpreter
; and the native twins address alike, so arrays cross the boundary and a
; native bubble sort sorts main's array), so gcd, isprime, a
; countdown-from-n, a triangular pair count and the sort all compile:
; a 2M-iteration loop, 79s interpreted vs 9.5s built.  Twin agreement
; is the spec.
; Structs: fields as cell offsets, -> and ., arrays of structs, scaled
; pointer steps, typedef, copy -- oracle-identical.  switch
; (fallthrough, break, continue through to the loop) and function-like
; macros (argument text, boundary substitution, rescan).
; #ifdef/#ifndef/#else/#endif/#undef/#if-defined and initializer lists;
; the heap zero-fills (str make is space-filled).
(lang "cc"    "x-cc"    119  0)
; logo's 83/0 here is the same 83 tests that ran as lib/logo.spec.md in this
; tree, against the same turtle kernel, through the bundle's own harness
; instead of tests/x/lib.
;
; It is the one row to run alone.  The turtle kernel's resident heap is 5-7GB
; (its @weight 7 travelled with it), and check-langs runs these suites in
; sequence on whatever machine invoked it -- the condition the r7rs note below
; describes.  Measured beside another heavy suite, the numbers here do not
; mean anything.
;
; Its two other suites are not counted here and cannot be: the examples gate
; and the pty contract live in the bundle's CI, and one of them needs a
; terminal this gate cannot provide.
(lang "logo"  "x-logo"   83  0)

; The recorded debt, each row with its reason.
;
; ash's two were the single- and double-quoted string readers, which
; accumulated the value in a module-level global during analyse and lost it --
; a bundle bug, documented in its own README.  It was 80 until x-engine-c
; v0.1.3: the stock v0.1.2 segfaulted the isolated tokenizer base on the first
; character, so nearly the whole suite was red for a reason that was never
; ash's.  The bundle has since fixed both: 974 specs, 0 failed, measured at
; x-ash b975506 against this tree.  Ratcheted 2 -> 0.  The 82 floor stays, for
; the reason the python row states.
(lang "ash"   "x-ash"    82  0)
; r5rs is GREEN, and it took both halves.  37 -> 9 came from the bundle: R5RS
; 6.6 ports rewritten against File (21), and exactness under 6.2.5 (7).  The
; last nine were the ELLIPSIS group, and they were the engine's: every token
; beginning with `.` reached the reader as the pair-dot sentinel, so `...` was
; unreadable and syntax-rules patterns could not be written at all.
;
; x-engine-c v0.1.4 stopped the dot being a token kind -- nothing claims the
; character now, and the list reader recognises the one-character symbol "."
; where it already decides pair-versus-list.  R5RS's macro layer is written
; entirely in ellipsis patterns, so one reader fix moved all nine at once.
;
; A zero here is a claim, not a hope: the row is what makes a tenth failure
; loud.
;
; IT IS LOUD NOW, and the zero stays.  The suite reports 667/3 against this
; tree, all three the pitfall 3.2 cases that assert a macro-introduced
; definition does not escape its `let`:
;
;   macro-defined variable does not leak (pitfall 3.2)              got 1
;   define-syntax: the definition stays inside the expansion        got 777
;   let-syntax: the definition stays inside the expansion           got 888
;
; Not the bundle's debt and not a stale checkout: measured at x-r5rs dd3ba79,
; whose only commits since its last macro work are prose rewrites.  x-r5rs
; fixed exactly these in 0514d99 and 2c45ab0 (2026-09-08).
;
; WALKED, one build and one suite run per row, x-r5rs held at dd3ba79 and each
; x-lang commit built against the engine its own pin names:
;
;   x-lang       pin       result   what it is
;   v0.14.0      v0.2.8    667/0    the last green pairing
;   18f0b530^    v0.2.8    667/667  source already migrated, pin behind
;   18f0b530     v0.2.10   667/3    the pin that takes the new env model
;   edaabc2a     v0.2.11   667/3
;   d6fdd68d     v0.2.12   667/3
;   ef0cc505     v0.2.13   667/3    where this tree sits
;
; The three arrive with "an environment is a value" -- x-engine-c#49, released
; in v0.2.10 and carried here by #720, which bumps the pin twice.  A `def`
; binds in the current environment, an `eval` with an environment makes it
; current with the binding staying put, and the frame marks, shadow list and
; local boundary those two bundle fixes were written against were retired with
; it.  Nothing since has moved the number in either direction.
;
; THE ENGINE AND OUR ADAPTATION TO IT CANNOT BE SEPARATED BY PINNING, and the
; two 667/667 rows are why: v0.14.0's source does not run on v0.2.10, and the
; migrated source does not run on v0.2.8.  The transition is atomic, so this
; names a release, not yet a line.
;
; So the debt is this platform's, on an unreleased change, and the row is left
; red deliberately -- a budget raised to 3 would be recording our own
; regression as the bundle's.
(lang "r5rs"  "x-r5rs"  667  0)
; r7rs moved 43 -> 27 on x-engine-c v0.1.5, and the sixteen are all of `error`,
; `error objects` and `guard`.  (base def-global) lets an operative define for
; its caller, which is what this bundle's `guard` needed: R7RS guard and x's
; guard are different forms sharing a name, so providing one means shadowing
; the other, and shadowing interposes exactly the frame that broke the eval!
; workaround.  The bundle changed nothing -- it already preferred the primitive
; and fell back when it was absent.
;
; 43, not 58, and the correction is about measurement.  58 is what this suite
; reports when something else is running: an orphaned engine holding a core has
; made it say 49, 58 and 247 for one unchanged tree, with batches dying
; mid-run.  check-langs runs six suites in sequence, which is precisely that
; condition.  Measured twice on a quiet machine it is 43, on both engines.
; 27 -> 30, and the three are NOT this platform's doing.  Measured on x-lang
; 41bca38f + x-engine-c v0.1.6 -- a tree with none of the ERR work and the old
; pin -- the suite reports 30, the same as it does on the branch that carries
; both.  Two runs, one loaded and one quiet, agreed; the noise this file warns
; about above shows up as WILD numbers (49, 58, 247), not a steady +3.
;
; Raising a budget is against this file's own rule, and it is done here rather
; than quietly because the alternative is worse: leaving the gate red on main
; means the next real regression in any bundle lands on a check that is already
; failing and says nothing new.  The debt is x-r7rs's to pay in its own repo.
;
; 30 -> 33 against this tree, measured at x-r7rs c80a88c.  The three are not
; recorded, for the reason the r5rs row above gives at length: that bundle
; gained the same +3 in the same window, its three are the same pitfall 3.2
; assertions, and both bundles' macro layers were repaired against the engine
; model v0.2.10 replaced.  One cause, two bundles; it is read as ours until
; the r5rs three are answered.
(lang "r7rs"  "x-r7rs"  637 30)
