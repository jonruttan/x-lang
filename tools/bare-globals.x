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
  ; --- module system: ruled bare 2026-07-22 (user: "I want to keep them") ---
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
  ; --- name-kept io verbs + x-lib-version: ruled bare 2026-07-22 ---
  (display)
  (newline)
  (write)
  (list)
  (x-lib-version)
  ; ============ SCOPE EXTENSION (2026-07-22): the runtime library ============
  ; The scan now covers all of lib/x/ except the dialect toolboxes and
  ; lib/x/tool/ (additive DSLs, see the scanner header).  Groups below are
  ; SANCTIONED-AS-FOUND: each awaits its own ruling round; sweep candidates
  ; are marked.  Shrinking is the point.
  ; --- class-system vocabulary (the homing mechanism itself) ---
  (class-members)
  (class-methods)
  (class-name)
  (class-of)
  (class-parent)
  (class-static-members)
  (class-static-methods)
  (class?)
  (def-class)
  (instance-of?)
  (method-ref)
  (new)
  (new-from)
  (object?)
  (super)
  ; --- predicates, scope-extension additions (join the ruled family) ---
  (complex?)
  (real?)
  ; --- doc/help REPL verbs ---
  (apropos)
  (doc)
  (help)
  (modules)
  (note)
  ; --- reader intrinsics (tokenizer-callback vocabulary; score-set and
  ;     buffer-unread are ALSO symbol-keyed in the compiler emitter table) ---
  (buffer-len)
  (buffer-unread)
  (current-line)
  (peek-char)
  (score-set)
  ; --- repl verbs ---
  (quit)
  (repl)
  ; --- iteration / laziness (form-like) ---
  (delay)
  (iter)
  ; --- platform lookups + syscall tables (opt-in modules) ---
  (darwin-syscall-numbers)
  (i386-syscall-names)
  (os-darwin?)
  (os-linux?)
  (protocol-format-id)
  (sock-id)
  (socketcall-id)
  (syscall-id)
  (x86_64-syscall-names)
  ; --- spec-harness vocabulary (tests/x/lib loads these) ---
  (raised)
  (throws?)
)))
