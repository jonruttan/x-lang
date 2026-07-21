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
; construction -- float/rational/bignum handlers sit on their own types and
; win their own dispatches. Two residual holes, both recorded on #52:
;   - nil-typed operands: op_try cannot consult a type that is not there.
;     The booleans left this class when BOOL claimed them (type/bool.x,
;     #101); (+ 1 ()) is caught by the C prims' nil guards.
;   - mixed tower/non-numeric ((+ 1.5 "a")): both sides own the op and
;     neither type absorbs the other, so op_try declines ("unrelated
;     types: not ours to decide") -- pre-existing tower-side behavior.
;
; `=` is deliberately NOT registered: it is value-word compare in the
; fallthrough, and interned symbols answer it correctly by pointer -- an
; error op would break working (= 'a 'a) code for no reported crash.
;
; Loads in x-core after err.x (Err raise) and vector.x (the #() handle).

(def %og-push (prim-ref (lit type) (lit push-op)))
(def %og-by-atom (prim-ref (lit type) (lit by-atom)))
(def %og-type-of (prim-ref (lit type) (lit of)))

; One raising handler per (op, type-name) pair, so the message names both.
(def %og-refuse
  (fn (_ opname tname)
    (fn (_ a b)
      (Err raise (lit type)
        (%str-append "no " (%str-append opname (%str-append " for " tname)))
        ()))))

(def %og-install
  (fn (_ handle tname ops)
    (let ((ts (%og-by-atom handle)))
      (List for-each
        (fn (_ op) (%og-push ts op (%og-refuse (symbol->str op) tname)))
        ops))))

(def %og-all   (list (lit +) (lit -) (lit *) (lit /) (lit %) (lit <)))

; CHAR is deliberately ABSENT: characters ARE their code points
; arithmetically, and that pun is load-bearing contract, not an accident --
; the printer's escaper orders chars with `<`, the regex engine's count
; parser reads {3} via (- ch #\0) INSIDE the tokenizer (where a raise
; kills the reader), and utf8 decode masks CHAR-typed bytes with `&`
; (str-byte-ref returns CHAR). Both discovered by registering refusals and
; watching the suite burn.
(%og-install (%og-type-of "") "STRING" %og-all)
(%og-install (%og-type-of (lit (0))) "LIST" %og-all)
(%og-install (%og-type-of (pair () ())) "PAIR" %og-all)
(%og-install (%og-type-of #(0)) "VECTOR" %og-all)

; SYMBOL is deliberately absent: symbols are TREE-typed (their type slot is
; the interning tree, not a type struct), so op_try never consults a struct
; for them -- a registration here lands somewhere dispatch cannot see.
; Symbol operands are the one documented residual on #52 -- the boolean
; half closed when bool.x claimed the singletons (#101).

(doc (provide x/core/op-guard)
  "Non-numeric types (string, list, pair, vector) refuse the arithmetic operators with err:type instead of falling through to pointer arithmetic; symbols cannot (tree-typed) and remain the documented residual; booleans refuse via type/bool.x.")
