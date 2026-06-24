; assert.x -- Test-support assertions for the .x spec suite.
;
; Loaded by a spec via `# @lib ../tests/x/lib/assert.x`; like the other test
; libs (token.x, fmt.x) it stands in for the default lib, so it includes
; x-core first and layers the helpers on top.
;
; Why this exists: the spec harness compares only the LAST output line and
; discards stderr (see tests/spec-runner.awk), so "this expression must raise"
; was previously hand-rolled as (guard (e <sentinel>) expr) in every spec that
; needed it. Naming the pattern makes error-path coverage cheap and uniform --
; and catches the SILENT-FAILURE class: a form that should raise but instead
; returns nil reads as a pass under a naive value check, but `throws?` reports
; it (returns #f), so the gap is visible.
;
; Multi-line / ordered-output capture is a HARNESS concern (the opt-in
; full-output mode in the runner), not a library one, so it is deliberately
; not provided here.
;
; Thunks follow the self-passing convention: pass (fn (_) EXPR); the helper
; calls it as (thunk) -- arg 0 binds to the thunk itself and EXPR ignores it.
(include "lib/x-core.x")

; #t if running THUNK raises an error, #f if it returns normally (including a
; normal nil return -- so this distinguishes "raised" from "returned nil").
(def throws?
  (fn (_ thunk)
    (guard (e #t)
      (do (thunk) #f))))

; The value THUNK raised (whatever was handed to `error`), or the symbol
; `%none` when THUNK returns without raising -- so a spec can assert on the
; error's content: (raised (fn (_) (error "boom"))) -> "boom". The %none
; sentinel is a symbol (not nil) so a raised nil and a non-raising thunk stay
; distinct under (eq? (raised ...) (lit %none)).
(def raised
  (fn (_ thunk)
    (guard (e e)
      (do (thunk) (lit %none)))))
