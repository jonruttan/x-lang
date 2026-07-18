# GC stack roots: from conservative scanning to precise tracking

Design/findings report, and the record of the completed migration:
the conservative C-stack scan is **gone** — `x_heap_callstack_mark` /
`x_heap_vector_mark`, the `stack-base` field and its plumbing are
deleted, and the mark phase runs on the root chain (§6) alone. Collect
at the 50M-object load: 50.1 s → **0.659 s**. The inverted-scan stopgap
(§5) was prototyped and measured during exploration, then withdrawn; its
algorithm is retained here as the design for a *reporting* checker
should a rooting bug ever need diagnosis — re-arming a conservative scan
is not a fallback, because it masks missing roots rather than finding
them (the "-O2 hides the bug" era in mechanism form).

Baseline measurements (full `lib/x-base.x` load: 50.59M live objects,
2.0 GB RSS):

| operation | cost |
|---|---|
| one heap-chain walk | 0.786 s |
| one top-level `(Heap collect)`, before | 50.1 s (~64 stack words, most non-matching → near-full walks each) |
| one top-level `(Heap collect)`, with §5 stopgap | **1.905 s** (measured; ≈ one scan walk + base-tree mark + sweep walk, the O(heap) floor) |

The collect cost is `O(W × H)` — stack words at collect time × heap chain
length — so it scales with C-stack *depth* as well as heap size. A collect
issued at eval depth (thousands of stack words) would take hours at this
heap size.


## 1. Root cause: off-chain means unenumerable, not unswept

The owner's hypothesis — "statically allocated objects aren't attached to
the GC chain when they're created; maybe that's at the root of this" — is
correct, with one refinement about *which* attachment is missing.

Objects come into existence two ways:

- `x_obj_alloc` (`ext/x-expr/src/x-obj.c:152-154`) — links every heap
  allocation into the intrusive sweep chain: header slot 0
  (`X_OBJ_META_HEAP`), LIFO, head at `x_obj_heap(p_base)`.
- `x_obj_set` (`ext/x-expr/include/x-obj.h:319`) — in-place brace
  initialization for stack and file-scope `x_satom_t`/`x_spair_t` storage.
  Never linked anywhere.

Staying **off the sweep chain is correct and must stay**: the chain is the
free list of the sweep phase; linking stack or static storage into it would
have `x_heap_sweep` call `x_obj_free` on non-heap memory. The actual gap is
that off-chain objects are on **no enumerable structure at all**, so the
collector cannot ask "what stack objects are live right now?" — it
compensates by scanning raw stack memory and testing every word for
identity against every chain node (`x_heap_vector_mark`). The scan is the
brute-force substitute for a missing *registration* link, not a missing
*sweep* link.

The decisive layout fact: under `X_HEAP`, **every** object — including
stack and static ones — already reserves header slot 0, and `x_obj_set`
initializes it to NULL (`x-obj.h:319`). Off-chain objects carry a dormant
link field today. A registration chain threaded through that slot costs
zero additional memory and zero layout change.

Audit of true file-scope statics (they are *not* the problem):

| static | holds | heap refs? |
|---|---|---|
| `x_type_atom_obj`, `x_type_pair_obj`, units/length atoms, `x_true_obj`, `x_false_obj` (`ext/x-expr/src/x-obj.c:31-38`) | strings / ints | never |
| six hook atoms (`src/x-eval.c:414-425`), per-type mark/units atoms (`src/x-type/{procedure,operative}.c`) | C fn pointers | never |
| `x_tco_op_tag` (`src/x-eval.c:91`) | NULL datum; identity sentinel | never, but **heap records point at it** (`x-eval.c:170`) |

None can reference heap objects, so none need GC visibility. The cost and
the hazard both live in the **stack** population: ~38 `x_satom_t`/
`x_spair_t` locals and roughly 60–70 functions holding bare `x_obj_t*`
locals across allocating calls (inventory, §4).

`x_tco_op_tag` proves a fragile invariant worth writing down: heap→static
edges exist, `x_heap_tree_mark` sets the mark flag on whatever it visits
(`x-heap.c:42`), and `x_heap_sweep` clears flags **only for chain
objects** (`x-heap.c:175`). So an off-chain object that is ever marked
keeps its bit forever, and a later collect will *skip* it ("already
marked") without re-walking its children. Harmless for childless atoms
like the tag; **a heap-reachable off-chain pair would silently lose its
children on the second collect**. Today this never fires only because no
off-chain pair is heap-reachable, by convention. The precise design must
not inherit this trap (§6, two-pass walk).


## 2. What the conservative scan actually covers — and doesn't

Covers (everything in `[current frame, stack_base)`):

- named `x_obj_t*` locals, including ones the source never rooted;
- compiler temporaries spilled to the stack;
- the *interiors* of stack pairs/atoms — their field words are scanned as
  raw words, which is why the pervasive nil-typed stack arg pairs
  (e.g. `x_obj_type_name`, `ext/x-expr/src/x-obj.c:319`) work even though
  `x_heap_tree_mark` would not traverse a nil-typed pair.

Does **not** cover:

- **Registers.** `x_heap_callstack_mark` has no register-spill step (no
  setjmp trick). A reference held only in a callee-saved register at
  collect time is invisible. This is exactly the historical
  "`-O2` can hide the bug" class: the current scheme is *incomplete*
  conservatism, not a guarantee.
- **call/cc's dormant stack copies.** `x_prim_callcc` snapshots the C
  stack into a malloc'd buffer (`src/x-prim/callcc.c:192`) that the scan
  never sees. Captured frames survive only through the GC-visible state
  list (env, save-stack, error-handler, **eval-list**) saved into the
  continuation closure (`callcc.c:198-210`) and restored on invoke
  (`callcc.c:179-186`). The system already runs on the contract "explicit
  root structures are the truth; the C stack is re-derivable" wherever
  continuations are involved. Precise tracking generalizes that contract;
  it does not introduce it.
- Collection is **explicit-only** (`x_prim_heap_collect`,
  `src/x-prim/io.c:431`; no allocation-threshold trigger), which bounds
  when any of this can fire: only inside calls that can reach
  `(Heap collect)`.


## 3. Existing rooting machinery (prior art to generalize)

- **eval-list rooting**: `x_obj_push_field`/`x_obj_pop_field` on
  `x_eval_field_eval_list`, ~24 push/pop pairs across `src/`. LIFO and
  balanced on normal return paths (the reported imbalance in
  `x_eval_op_body` is a false alarm — the early returns at
  `x-eval.c:180-188` are outside the push window at `191-194`). Each push
  **allocates a heap pair** (`x-obj.c:509`), which is why it cannot be the
  universal per-frame discipline: it would tax exactly the hot paths the
  stack-pair design exists to keep allocation-free.
- **Unwind handling exists but is asymmetric** (the LIFO-unwind problem
  precise tracking must solve is already present): `guard` snapshots and
  restores `save_stack` on the error path (`src/x-syntax/control.c:126,151`)
  and call/cc restores the **eval-list** on invoke (`callcc.c:184`), but
  `guard` does **not** restore the eval-list. Consequence: any
  `x_obj_push_field` window containing an eval that errors (e.g.
  `x_eval_op_body` `x-eval.c:191-194`, `%seq` `control.c:231-237`) leaks
  its rooted entry permanently when the longjmp skips the pop —
  over-retention, growing with each caught error. One-line fix in the
  same style as `save_stack`: snapshot `x_firstobj(eval_list)` at guard
  entry, restore on the error branch. (Found during this exploration;
  not applied — flagged separately.)
- **Heap-group lists**: `mark-roots` / `mark-hooks` / `free-hooks`
  (`ext/x-expr/src/x-heap.c:224-266`), walked by the parent's
  `x_heap_mark_phase`/`x_heap_sweep_phase` (`src/x-prim/io.c:234-302`) —
  x-expr stores, the embedder dispatches. The precise root walk slots into
  this same split.


## 4. The migration surface (inventory)

Approximate, by grep + reading (details in the per-file counts below):

- Stack-object declarations: 38+ (`x-eval.c` 16, `x-token.c` 14,
  `x-type.c` 5, `x-prim.c` 2, `x-prim/core.c` 1) — plus arg-pair arrays in
  `x-prim/io.c` and `callcc.c`.
- Functions holding a GC-visible local (stack object or bare `x_obj_t*`)
  across an allocating call: **~60–70**, of which ~25 are hot
  (eval trampoline, procedure dispatch, arithmetic, tokenizer
  analyse/read loop: `x_token_analyse` holds `p_winner`/`p_entry`/
  `p_analyse` across `x_callable_apply`, `src/x-token.c:187-233`).
- Nonlocal exits to integrate: `guard` (`control.c:121-170`),
  `x_eval_error` (`x-eval.c`, longjmp to handler), call/cc
  capture/invoke (`callcc.c`).

This is the honest size of "the scan disappears entirely": **every one**
of those sites must either adopt registration or be proven to never span a
collect. The conservative scan currently papers over all of them at once,
including compiler temporaries no inventory can list — which is why the
migration needs the hybrid checker (§6.4), not faith.

**The window rule (narrows the surface considerably).** Collection is
explicit-only (§2), so pure allocators (`x_mk*`, `x_obj_alloc`) can
*never* collect — a hold across a pure allocation is safe. The
registration window is precisely: *a sole reference held across a call
that can evaluate x-lang code* (`x_eval*`, `x_callable_apply`,
`x_obj_prim_call`, type-hook dispatch). Three standing exemptions, each
proven once and reusable:

- buffers — always base-rooted: every active buffer is pushed onto the
  base's buffer field stack (`src/x-cli.c:132,207`, `src/x-eval.c:768`);
- values read out of base fields or the type alist — rooted by the
  base-tree mark for as long as the field/alist still holds them;
- the collect path's own `hook_args` wrappers — their referents live on
  the base's hook lists.

Should the trigger policy ever change (allocation-threshold collects),
the window widens back to every allocating call and this section must be
revisited — worth a loud comment wherever that policy would be touched.


## 5. Stopgap (measured, then withdrawn): invert the scan's loops

Prototyped during exploration: `x_heap_vector_mark` gathers the region's
words into a chunk (1024), insertion-sorts it (no libc, no allocation
mid-collect), and walks the chain **once per chunk**, binary-searching
each node's address among the words. Same set intersection, identical
marking semantics, `O(H log W)` instead of `O(W × H)`. Measured on the
50M-object repro before being reverted: **50.1 s → 1.905 s** (26×; full
spec suite and the x-expr heap specs passed against it). The residual ≈
one scan chain-walk (0.786 s) + base-tree mark + sweep chain-walk — the
O(heap) floor any collect pays at this heap size.

Withdrawn per owner direction: the destination is precise tracking, not a
faster scan. The algorithm stays in this report because it is the
**validation oracle** for the migration — in a checker build it runs
*after* the precise mark and reports any chain object it would have
marked that the root chain missed (§6.4). ~40 lines in
`x_heap_vector_mark` whenever validation begins.


## 6. Destination (mechanism landed): the root chain

The user-stated construction, implemented: *an object chain with a
different root — one that gets marked, but doesn't get swept.* Off-chain
objects link LIFO through the **same header slot 0** the allocation chain
uses, from a **different head**, so any object is on exactly one chain:
the allocation chain is swept, the root chain is marked. The slot is
dormant (NULL-initialized by `x_obj_set`) in every off-chain object, so
registration costs no memory and no allocation.

### 6.1 Mechanism (`ext/x-expr`, landed)

- Head field: `x_base_field_heap_root_chain` — eighth heap-group leaf
  (`x-base.c`, `x-base.h`). Interior to `(todo heap)` in
  `tools/base-layout.x`, so no descriptor bump / `gen-layout` was needed
  (verified: the generated `x-eval-layout.h` has zero heap coupling).
- `x_heap_root_push(p_cell, node)` — two stores;
  `x_heap_root_pop(p_cell)` — one store; `x_heap_root_slot(p_base)` —
  head-slot address, hoisted once per frame so the base-tree field chase
  is per-frame, not per-push (`x-heap.h`). Cheaper than one
  `x_obj_push_field` (a heap allocation) on every call.
- `x_heap_root_chain_mark(p_base, flags)` — **two-pass** walk
  (`x-heap.c`): pass 1 clears every registered node's mark flag (sweep
  clears flags on the allocation chain only — without the pre-clear, a
  node still registered at the next collect is skipped as already-marked
  and its referents die: the §1 sticky-bit trap, now retired). Pass 2
  tree-marks each node. The pre-clear also makes the walk
  order-independent for stack-built argument lists (one registered
  pair's payload linking another) and for nodes the base-tree mark
  already visited through the head field itself.
- Wired as mark pass 2 in `x_heap_mark_phase` (`src/x-prim/io.c`),
  after the base-tree mark. (During the migration the conservative scan
  ran alongside it as belt-and-braces; with the migration complete the
  scan was deleted outright.)
- Unit specs: `ext/x-expr/tests/src/5.1.x-heap.root-chain.spec.c` —
  push/pop LIFO, survive-sweep, reclaim-after-pop, the two-cycle
  stale-mark regression (fails on any one-pass walk), and the
  stack→stack payload chain.

Registration contract (documented on the macros):

- Off-chain objects only — pushing a heap object would overwrite its
  allocation-chain link and truncate the sweep chain.
- Registered pairs carry `x_type_pair_obj` (`x_heap_tree_mark` descends
  only spair-typed pairs; the historical nil-typed arg pairs must be
  retyped as they migrate). Bare `x_obj_t*` locals convert to a
  registered `x_spair_t` cell whose payload holds the value(s).
- Pop on every exit path; push each node at most once (no cycle guard).

### 6.2 Nonlocal exits (landed)

- **guard** (`src/x-syntax/control.c`): snapshots the head beside
  `p_saved_save_stack`, restores it on the error branch — the longjmp'd
  frames' pops never ran, and their nodes are dead stack memory the next
  mark must not walk. Same pattern as the save-stack restore.
- **call/cc** (`src/x-prim/callcc.c`): the head rides the saved
  interpreter-state list **as an opaque ptr atom** — its nodes are stack
  memory, dead while the continuation is dormant, so tree-marking the
  state list must not traverse them — and is restored on invoke right
  after the segment memcpy brings those bytes back (all chain nodes lie
  inside the captured segment, which spans from call/cc's frame to the
  stack base). Dormant copies stay non-roots: unchanged contract (§2).
- **Lazy-pop by address is unsound** and must not be attempted: a node
  in a dead sibling frame can sit in the "live" address range at collect
  time. Pops are eager; the checker build catches misses.

### 6.3 Exemplar site (landed): `%seq`

`x_prim_seq` (`control.c`) now roots its argument list in a registered
stack cell instead of an eval-list push — the same LIFO protection with
zero allocation per call, and (unlike the eval-list idiom, §3) leak-free
across caught errors, because guard restores the chain head. This is the
conversion template for the ~60–70 sites in §4.

### 6.4 Migration path: hybrid, zone by zone

The root-chain walk now runs unconditionally as mark pass 3 — it is
additive, and an empty chain is a no-op, so it needs no flag. The flag
enters at the *end* of the migration: an `X_HEAP_PRECISE_CHECK` build
replaces the conservative scan with the §5 inverted scan in report-only
mode — any chain object the scan would mark that the root chain missed
is a root the discipline missed, printed with the stack-word address so
the offending frame is findable. The default build keeps the scan as
belt-and-braces until the checker is silent.

Zone order (each zone: convert, run x-expr suite + spec runner under
CHECK, soak):

1. collect path itself + `x-prim/io.c` arg pairs (smallest, self-hosting);
2. tokenizer frames (`x-token.c`, `x-token/sexp/*`) — the historically
   GC-fragile area; registration finally protects reader re-entry frames
   *by construction*;
3. prims by family (`core`, `arith`, `string`, `pred`, `type`, syntax);
4. eval core (`x-eval.c`, `x-prim.c` trampoline) last, with the eval-list
   idiom retired or kept only where values must survive call/cc capture.

**Status: migration complete; the scan is deleted.** No flag, no
fallback path: `x_heap_callstack_mark` and `x_heap_vector_mark` are
removed from x-expr along with the heap-group `stack-base` field, the
`x_base_t.p_stack_base` member, the CLI's stack-base capture, and the
`X_NO_OPTIMIZE` attribute machinery that existed for the scan's anchor.
(call/cc's own `g_stack_base` is unrelated — segment capture — and
stays.) History lives in git; the checker design lives in §5.

Converted (every eval-list rooting site plus the latent scan-only
holds):

- io.c: `write` / `display` / `to_string` / `atomic` / `repl`;
- tokenizer: `x_token_analyse` (replace-analyser hold),
  `x-token/sexp/list.c` reader (list under construction);
- central helpers: `x_eargs` (earlier results parked in registered
  slots while later args evaluate — previously bare caller out-params),
  `x_eval_list` (args + the fresh result across the recursion —
  the result hold was never covered by the eval-list idiom),
  `x_eval_body` / `x_eval_body_tco` (one cell per walk instead of a
  cons per element), `x_eval_op_body` (+ the restore record, held bare
  across the whole body previously), `x_eval` (the kept TCO restore
  records — popped off the save-stack and held only in C locals across
  every trampoline iteration: the deepest scan-only hold in the system);
- application path: `x_prim_apply` (callee rooted *before* operand
  evaluation — see below), `x_type_list_eval` (expression + the
  resolved operator, which is fresh when the operator position is a
  combination), `x_prim_atomic` (core.c), `%seq`, `guard`/call-cc head
  integration;
- registration/binding: `x_value_bind`, `x_prims_file`, `x_prims_add`,
  `prim-reg!`, `use` (vestigial under the window rule but converted —
  cheaper than the eval-list conses they paid, and policy-proof).

Audited and exempt under the window rule: `x_token_read` (fresh result
crosses only a pure memcpy), `x_token_delimit` / `read_expr` /
`read_char` (base-rooted holds only), the mark/sweep phases'
`hook_args`.

**The one miss the gates caught** — and why the empirical gate is the
real validator: with the scan off, the full suite passed but the
`lib/x-base.x` load + collect segfaulted. `x_prim_apply` held its
callee bare across `x_eval_list` of the operands (the rooting started
only afterwards, where the old eval-list push sat); a fresh callee — a
lambda built by the caller's body — died when the operands' evaluation
collected. The suite never builds that shape; the library load does.
Lesson recorded: rooting must begin where the *hold* begins, not where
the old idiom happened to push, and suite-green under precise is
necessary but not sufficient — the library-load soak is part of the
gate.

Verification of the final state: full suite 1474/0 with the scan on,
1474/0 with the scan off, x-expr's own suite green, `lib/x-base.x` load
clean, and the 50M-object collect measured at **0.659 s** (baseline
50.1 s, ~76×) with the scan off entirely.

Flip the scan off (`X_HEAP_PRECISE` without CHECK) only after the checker
runs clean across the full suite and a library-load soak. Registers stop
being a threat at that point not because they're scanned but because the
discipline guarantees every live reference also lives in a registered
slot — the same reason eval-list rooting works under `-O2` today.

### 6.5 Residual risks

- Completeness is a *process* guarantee (checker + zones), never a static
  one — C compilers may cache a registered slot's value in a register, but
  that's safe: the slot itself stays live and scanned/marked.
- The discipline must be documented as a hard house rule (like
  declarations-at-top): "a heap reference crossing an allocating call
  lives in a registered slot, period."
- 32-bit (Pi): nothing here is word-size-sensitive; the existing
  pointer-compare idiom is already in use (`x-heap.c:130`).


## 7. Comparison and recommendation

| | inverted scan (measured, withdrawn) | root chain (mechanism landed) |
|---|---|---|
| collect stack-root cost at 50M objects | 0.79 s (one walk; total collect measured 1.905 s) | ~0 once migrated (registry-sized; total collect → mark+sweep floor ≈ 1.1 s) |
| deep-stack collect | O(H·W/1024) | O(registry) |
| code touched | 1 function | mechanism done; ~60–70 site conversions remain (§4) |
| new bug surface | none | missed push/pop (checker-caught), unwind integration (done for guard/call-cc) |
| false retention | keeps it | eliminated at migrated sites |
| register blindness | keeps it | eliminated by the discipline (§6.4) |
| future moving/compacting GC | blocked | enabled once the scan retires |

Outcome (measured, scan deleted): **50.1 s → 0.659 s** per collect at
the 50M-object load — better than the projected floor because the
scan's chain walk is gone and a fully-marked heap sweeps fast.
Registration proved cheaper per call than the eval-list idiom it
replaced (two stores vs a heap allocation; the body/args walkers now
use one cell per walk instead of a cons per element, a net allocation
*reduction* on the hot path). Residual risk, stated honestly: precision
is a per-site property and the gates exercised the suite plus the full
library load — an embedder path outside both could still hide a miss.
The remedy for a suspected miss is diagnosis, not regression: build the
§5 inverted scan as a *reporting* checker (it names the stack word the
chain missed), fix the site, and keep the discipline — never a
conservative re-mark, which only re-hides the bug.


## 8. Defects found during exploration (not fixed here)

1. **guard leaks eval-list roots on error** (§3) — restore omitted on the
   longjmp path; callcc has the analogous restore. Over-retention, grows
   per caught error crossing a push window.
2. **Sticky mark bits on off-chain objects** (§1) — latent trap, benign
   today by convention; the precise walk's pass 1 retires it.
3. **Register blindness of the current scan** (§2) — pre-existing,
   explains the historical `-O2` rooting incidents; unchanged by the
   stopgap, retired by precise mode.
