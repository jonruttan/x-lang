; test/assert.x -- error-path assertions for tests (importable by user code).
;
; The spec-harness personality (tests/x/lib/assert.x) layers these over
; x-core for the .x suite; shipping them under lib/ means user programs can
; (import x/test/assert) and get the same error-path coverage idiom.
;
; Why these exist: "this expression must raise" is otherwise hand-rolled as
; (guard (e <sentinel>) expr) at every site -- and the SILENT-FAILURE class
; (a form that should raise but returns nil, reading as a pass under a naive
; value check) stays invisible. throws? reports it (#f), raised exposes the
; error's content for assertion.
;
; Thunks follow the self-passing convention: pass (fn (_) EXPR); the helper
; calls it as (thunk) -- arg 0 binds to the thunk itself and EXPR ignores it.

(doc (def throws?
  (fn (_ (param thunk CALLABLE "Nullary thunk to run"))
    (guard (e #t)
      (do (thunk) #f))))
  (returns BOOL "#t if the thunk raised, #f if it returned (a nil return included)")
  (example "(throws? (fn (_) (error \"boom\")))" "#t")
  "Test whether running a thunk raises an error.")

(doc (def raised
  (fn (_ (param thunk CALLABLE "Nullary thunk to run"))
    (guard (e e)
      (do (thunk) (lit %none)))))
  (returns ANY "The raised value, or the symbol %none when the thunk returned normally")
  (note "%none is a SYMBOL (not nil), so a raised nil and a non-raising thunk stay distinct under (eq? (raised ...) (lit %none)).")
  (example "(raised (fn (_) (error \"boom\")))" "\"boom\"")
  "The value a thunk raised, or %none when it did not raise.")

(doc (provide x/test/assert throws? raised)
  (example "(throws? (fn (_) (first ())))" "#t or #f, depending on the form under test")
  "Test-support assertions: error-path coverage for user test code.")
