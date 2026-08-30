; langs.x -- the lang bundles this platform is checked against.
;
; (langs-dir "PATH")             where bundles live, relative to the repo root.
;                                X_LANGS_DIR overrides it.
; (lang "NAME" "DIR" TESTS FAILED)   NAME as `-l` spells it, DIR under langs-dir,
;                                and the suite's counts as of the last edit.
;
; FAILED MAY ONLY SHRINK (tools/check/langs.sh), the rule percent-globals.x
; runs on.  A number here is not a target and not an excuse; it is the debt this
; platform is known to be carrying, recorded so it cannot quietly grow.
;
; WHY THIS FILE EXISTS.  check-seam catches a RENAME in eight seconds -- one of
; the three ways the last generation of langs rotted, and its header is right
; that no amount of testing "over there" catches it in time.  It cannot catch
; anything else.  A behaviour change, an arity change, a reader that now scores
; a tie differently: the platform stays green, every bundle's CI is on its own
; schedule against a RELEASE rather than your working tree, and the break
; surfaces weeks later as somebody else's mystery.
;
; The measurement that prompted this: with x-lang green at 2590/0, the six
; bundles carried 175 failures between them and nothing in this tree said so.
; Pinning x-engine-c v0.1.3 took that to 69 without a line changing in any
; bundle -- which is the same point from the other side: the platform moving
; under them is invisible here unless something runs them.
;
; A BUNDLE LIVES IN ITS OWN REPOSITORY, so this gate is advisory about
; PRESENCE and strict about REGRESSION.  Bundles absent from the disk are
; skipped loudly and the gate still passes -- x-lang must build for someone who
; cloned nothing else.  Bundles that ARE present must not get worse.
;
; The counts are against whatever revision of each bundle is checked out, which
; is a real limitation and the reason TESTS is recorded beside FAILED: a suite
; that shrank is a different suite, and the gate says so rather than silently
; comparing a smaller run to an older number.

(langs-dir "../languages")

; Green, and expected to stay that way.
(lang "krn"   "x-krn"    74  0)
(lang "sweet" "x-sweet"  32  0)
(lang "python" "x-python"  4  0)

; DEBT, each with a reason, none of them an invitation.
;
; ash's two are the single- and double-quoted string readers, which accumulate
; the value in a module-level global during analyse and lose it -- a bundle bug,
; documented in its own README.  It was 80 until x-engine-c v0.1.3: the stock
; v0.1.2 segfaulted the isolated tokenizer base on the first character, so
; nearly the whole suite was red for a reason that was never ash's.
(lang "ash"   "x-ash"    82  2)
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
(lang "r5rs"  "x-r5rs"  667  0)
; r7rs did NOT move on the pin, and the reason is simpler than it looked: the
; engine did not gain anything it uses.  `(base def-global)` -- the capability
; that would retire this bundle's `guard` shadow -- is NOT in v0.1.3 either; it
; is proposed and unmerged.  So neither side of that trade has happened yet.
;
; 43, not 58, and the correction is about measurement.  58 is what this suite
; reports when something else is running: an orphaned engine holding a core has
; made it say 49, 58 and 247 for one unchanged tree, with batches dying
; mid-run.  check-langs runs six suites in sequence, which is precisely that
; condition.  Measured twice on a quiet machine it is 43, on both engines.
(lang "r7rs"  "x-r7rs"  637 43)
