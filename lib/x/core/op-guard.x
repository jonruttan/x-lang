; op-guard.x -- non-numeric types refuse arithmetic (#52, ruled)
;
; (+ 1 "abc") returned the string's POINTER as an integer -- silent wrong
; answer plus an address disclosure -- because the arithmetic prims' int
; fallthrough runs x_intval on whatever op_try declined. The refusal lives
; where the dispatch information lives: each non-numeric TYPE registers
; arithmetic op handlers that RAISE, so C's op_try -- which already consults
; the registry on every arithmetic call -- routes a bad operand to a clean
; err:type instead of the int fallthrough. THE REGISTRY THAT OWNS DISPATCH
; OWNS THE REFUSAL.
;
; Costs nothing on the int fast path: op_try fast-declines when NEITHER
; type carries ops, and INT keeps none. The tower is untouched by
; construction -- float/rational/bigint handlers sit on their own types and
; win their own dispatches. Two residual holes, both recorded on #52:
;   - nil-typed operands: op_try cannot consult a type that is not there.
;     The booleans left this class when BOOL claimed them (type/bool.x,
;     #101); (+ 1 ()) is caught by the C prims' nil guards.
;   - mixed tower/non-numeric ((+ 1.5 "a")): both sides own the op and
;     neither type absorbs the other, so op_try declines ("unrelated
;     types: not ours to decide") -- pre-existing tower-side behaviour.
;
; `=` is deliberately NOT registered: it is value-word compare in the
; fallthrough, and interned symbols answer it correctly by pointer -- an
; error op would break working (= 'a 'a) code for no reported crash.
;
; Loads in x-core after err.x (Err raise) and vector.x (the #() handle).
;
; The refusal itself is (Type refuse-arithmetic!), in x/type/type.x, so
; x/type/bool.x installs BOOL's through the same door; this file holds the
; policy, which types refuse.

; CHAR is deliberately ABSENT: characters ARE their code points
; arithmetically, and that pun is load-bearing contract, not an accident --
; the printer's escaper orders chars with `<`, the regex engine's count
; parser reads {3} via (- ch #\0) INSIDE the tokenizer (where a raise
; kills the reader), and utf8 decode masks CHAR-typed bytes with `&`
; (str-byte-ref returns CHAR). Both discovered by registering refusals and
; watching the suite burn.
(Type refuse-arithmetic! (Type by-atom (Type of "")) "STRING")
(Type refuse-arithmetic! (Type by-atom (Type of (lit (0)))) "LIST")
(Type refuse-arithmetic! (Type by-atom (Type of (pair () ()))) "PAIR")
(Type refuse-arithmetic! (Type by-atom (Type of #(0))) "VECTOR")

; SYMBOL is deliberately absent: a symbol's type slot is the interning
; tree, not a registered type, so op_try never consults a type for them -- a registration here lands somewhere dispatch cannot see.
; Symbol operands are the one documented residual on #52 -- the boolean
; half closed when bool.x claimed the singletons (#101).

(doc (provide x/core/op-guard)
  "Non-numeric types (string, list, pair, vector) refuse the arithmetic operators with err:type instead of falling through to pointer arithmetic; symbols cannot (their type slot is the interning tree, not a registered type) and remain the documented residual; booleans refuse via type/bool.x.")
