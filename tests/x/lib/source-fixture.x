; source-fixture.x -- forms on FIXED lines for the Source specs
; (tests/x/specs/lib/source.spec.md).  The quoted form sits on line 7, the
; closure's body form on line 10 and the position capture on line 12; the
; spec asserts those numbers, so a change to the leading lines must update
; the spec with it.

(def source-fixture-form (lit (alpha beta)))
(def source-fixture-fn
  (fn (_ n)
    (* n n)))

(def source-fixture-here (Source here))
