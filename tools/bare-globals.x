; tools/bare-globals.x -- the sanctioned bare top level of boot/core (#108).
;
; THE TOP LEVEL IS SACRED: lib/x-core.x + lib/x/boot + lib/x/core may bind
; only these bare names.  tools/bare-globals-scan.sh (make check-bare-globals)
; diffs the live def surface against this file in BOTH directions, so the
; list can only shrink deliberately: sweep a name to %-private (public face
; on a class) and delete its row in the same commit.  C-bound bare names
; live in tools/isa.x's %isa-bare section, not here.
;
; FORMAT (rigid, one entry per line -- the awk parses the same bytes):
;   (name)
;
; RULED TO STAY (2026-07-21): the ? predicates, the syntax forms, and the
; keep-list survivors.  Everything under "SWEEP" is a future #108 round.
(def %bare-globals (lit (
  ; --- predicates: ruled bare 2026-07-21 ---
  (atom?)
  (boolean?)
  (char?)
  (equal?)
  (not)
  (null?)
  (number?)
  (operative?)
  (pair?)
  (procedure?)
  (str=?)
  (str?)
  (symbol?)
  ; --- syntax forms (keep-list) ---
  (and)
  (begin)
  (case)
  (cond)
  (do)
  (if)
  (let)
  (let-opts)
  (letrec)
  (or)
  (quasi)
  (unless)
  (when)
  ; --- module system (forms in practice) ---
  (import)
  (import-path!)
  (include-once)
  (provide)
  (require-once)
  ; --- registry protocol (keep-list) ---
  (prim-domain)
  (prim-ref)
  (prim-reg!)
  (prims)
  ; --- name-kept io verbs + misc keep ---
  (display)
  (newline)
  (write)
  (list)
  (time)
  (x-lib-version)
  ; --- convenience aliases: pending ruling (#108 census) ---
  (else)
  (str-copy)
)))
