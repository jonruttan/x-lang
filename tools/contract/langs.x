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
; r5rs was 37 until x-engine-c v0.1.3.  Every token beginning with `.` reached
; the reader as the pair-dot sentinel, so a syntax-rules pattern read as an
; improper list -- and R5RS's macro layer is written entirely in ellipsis
; patterns, so the fix moved 28 specs at once.
(lang "r5rs"  "x-r5rs"  667  9)
; r7rs did NOT move, and the difference is worth recording.  v0.1.3's
; `(base def-global)` is quoted as taking this bundle from 579 to 595, but that
; is the ENGINE gaining the capability: x-r7rs's `guard` still works around its
; absence, and until the bundle adopts it the number here does not change.  The
; budget is measured, never transcribed from a commit message.
(lang "r7rs"  "x-r7rs"  637 58)
