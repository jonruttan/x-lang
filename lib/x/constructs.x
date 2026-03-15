; constructs.x -- x-lang construct declarations (XEON)
;
; Pure data format -- no code, just s-expressions read by tools.
; Each entry: (name (key . value) ...)
;
;   fmt    - Formatter layout:
;            head-1  = 1 arg on head line, rest as body (def, if, let)
;            head-kw = keyword-width arg on head line, rest as body (fn, op)
;            body    = no args on head line, all as body (do, match)
;            call    = default function call layout
;
;   scope  - Linter scope behavior:
;            bind    = first arg is a binding name (def)
;            bind-set = first arg is a symbol being set (set)
;            params  = first arg is parameter list (fn)
;            params-env = first + second args are params + env (op)
;            let     = first arg is binding pairs list (let)
;            guard   = first arg is (var handler) clause (guard)
;            quasi   = body is quasiquoted (quasi)
;            none    = no scope effect (if, do, match)
;            skip    = skip entirely, don't walk body (lit, include)
;
;   branch - Coverage branch behavior:
;            cond    = then/else branches (if)
;            clauses = each subform is a clause (match, cond)
;            short   = short-circuit, each arg is a branch (and, or)
;            guard   = normal + error paths (guard)
;            none    = no branches

(
  (def     (fmt . head-1)  (scope . bind)       (branch . none))
  (set     (fmt . head-1)  (scope . bind-set)    (branch . none))
  (fn      (fmt . head-kw) (scope . params)      (branch . none))
  (op      (fmt . head-kw) (scope . params-env)  (branch . none))
  (if      (fmt . head-1)  (scope . none)        (branch . cond))
  (do      (fmt . body)    (scope . none)        (branch . none))
  (begin   (fmt . body)    (scope . none)        (branch . none))
  (let     (fmt . head-1)  (scope . let)         (branch . none))
  (match   (fmt . body)    (scope . none)        (branch . clauses))
  (cond    (fmt . body)    (scope . none)        (branch . clauses))
  (guard   (fmt . head-1)  (scope . guard)       (branch . guard))
  (and     (fmt . call)    (scope . none)        (branch . short))
  (or      (fmt . call)    (scope . none)        (branch . short))
  (lit     (fmt . call)    (scope . skip)        (branch . none))
  (quasi   (fmt . call)    (scope . quasi)       (branch . none))
  (include (fmt . call)    (scope . skip)        (branch . none))
  (time    (fmt . call)    (scope . none)        (branch . none))
  (when    (fmt . head-1)  (scope . none)        (branch . cond))
  (unless  (fmt . head-1)  (scope . none)        (branch . cond))
)
