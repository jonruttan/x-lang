; error-loc-fixture.x -- deliberate unbound reference for the source-location
; error-reporting specs (tests/x/specs/meta/error-location.spec.md).
;
; `%not-a-real-binding` sits on a FIXED line so the spec can assert that
; (io error-line) reports it and (io error-file) names this file -- even
; though error-loc-boom runs at CALL time, long after this include popped.
; If the leading lines change, update the expected line in the spec.
(def error-loc-boom
  (fn (_)
    %not-a-real-binding))
