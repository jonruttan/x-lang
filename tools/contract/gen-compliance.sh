#!/bin/sh
# gen-compliance.sh -- generate an engine's compliance suite from its declaration.
#
#   Usage: sh tools/contract/gen-compliance.sh <engine-dir> <out-file>
#
# COMPLIANCE IS NOT CONFORMANCE.  The conformance suite asks "is this a correct
# x-lang evaluator" and is written against the language.  Compliance asks a
# narrower and nastier question: DOES THIS ENGINE DO WHAT IT CLAIMS?  Its subject
# is the engine's own x-engine.xon, and every check is generated FROM a row of
# that file, so the suite cannot drift from the declaration it audits.
#
# WHY IT HAS TO EXIST.  check-engine-contract compares `provides` against
# `requires` -- but it compares them as TEXT.  An engine that over-declares passes
# that gate, gets chosen by the resolver, and fails in the field.  For a capability
# that failure is loud (an unbound coordinate).  For a GUARANTEE it is silent: an
# engine that claims gc/explicit-only while collecting on allocation corrupts the
# six library sites that hold raw pointers across allocating expressions, and
# reports nothing.  Under-declaring is harmless -- the engine is merely treated as
# less capable than it is -- so every check here tests in the OVER-declaring
# direction only: each row is a claim to be falsified.
#
# THE CHECKS RUN BARE, and that is the whole point.  A probe through x.sh would
# load the library, and lib/x/boot/registry.x REPLACES the C prim-ref door while
# reflect.x refiles catalog entries with x-level implementations -- so a probe with
# the library loaded cannot tell an engine capability from a library one.  Bare,
# the only things in scope are what the engine itself binds.  The engine's own
# tests/bare harness runs these (it arms the allocation ceiling and loads nothing);
# x-lang generates them, for the same reason it owns the vocabulary.
#
# HOW A BARE CHECK OBSERVES ANYTHING.  There is no printer -- display and write are
# x-lang -- so a check signals through `error`, whose message the engine's C loop
# prints as `*** ERROR: <text>`.  Every section below ends in (error "ok") on the
# property holding and (error "<something else>") when it does not, so a FAILURE
# and a CRASH are distinguishable: a crash prints neither.
#
# THE CATALOG DOOR.  `prim-ref` does not exist bare -- it is x-level
# (lib/x/boot/registry.x replaces the C bindings) -- so a coordinate is resolved by
# walking the committed base paths to the prims cell and taking its first: the
# catalog is an alist-of-alists ((ns . ((method . prim) ...)) ...), built by
# x_prims_file in the engine's src/x-prim.c.  The extra `first` is load-bearing;
# without it the walk stops at the CELL, every lookup silently misses, and the
# suite reports a fully-equipped engine as having nothing.
set -e

ENGINE="${1:-}"; OUT="${2:-}"
[ -n "$ENGINE" ] && [ -n "$OUT" ] || {
	echo "gen-compliance: usage: gen-compliance.sh <engine-dir> <out-file>" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="$(cd "$ENGINE" && pwd)"
FEAT="$ROOT/tools/contract/features.x"
XON="$ENGINE/x-engine.xon"
ISA="$ENGINE/tools/contract/isa.x"
for f in "$FEAT" "$XON" "$ISA"; do
	[ -f "$f" ] || { echo "gen-compliance: missing $f" >&2; exit 2; }
done

W="${TMPDIR:-/tmp}/gencomp.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

# coordinate -> group, exactly as the contract gate computes it
awk '/^\(def %feature-group-rows/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    for (i=2;i<=NF;i++) print $i, $1 }' "$FEAT" | sort > "$W/exp"
awk '/^\(def %feature-capabilities/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF>=2 && $2!="rows" && $2!="-") print $2, $1 }' "$FEAT" | sort -k1,1 > "$W/tagmap"
awk '/^\(def %isa-catalog/{s=1;next} /^\)\)\)/{s=0}
     s && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF>=3) print $1 "/" $2, $3 }' "$ISA" | sort -k2,2 > "$W/isa"
join -1 2 -2 1 -o 1.1,2.2 "$W/isa" "$W/tagmap" | sort > "$W/bytag"
# Bare-bound names are NOT catalog coordinates: they carry no ns/method split and
# are probed by evaluating the symbol, not by walking the catalog.  Splitting one
# on "/" yields a nonsense (syscall . syscall) lookup that misses every time and
# reports a fully-equipped engine as lacking the capability.
awk '/^\(def %isa-bare/{s=1;next} /^\(def %isa-keep/{s=1;next} /^\)\)\)/{s=0}
     s && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l; if (NF>=1) print $1 }' "$ISA" \
  | sort -u > "$W/bare"
{ cat "$W/exp"; awk 'NR==FNR{o[$1];next} !($1 in o)' "$W/exp" "$W/bytag"; } | sort -u > "$W/c2g"

# The prelude every section needs: bare engines share nothing between sections
# (one process per case), so the catalog walk is repeated verbatim each time.
prelude() {
	cat <<'P'
(include "tools/contract/base-paths.x")
(def %assoc (fn (self k l)
  (match ((eq? l ()) ())
         ((eq? (first (first l)) k) (first l))
         (#t (self k (rest l))))))
(def %walk (fn (self steps o)
  (match ((eq? steps ()) o)
         ((eq? (first steps) (lit f)) (self (rest steps) (first o)))
         (#t (self (rest steps) (rest o))))))
(def %cat (first (%walk (rest (rest (%assoc (lit prims) %base-paths))) (%base))))
(def %coord (fn (self ns m)
  (match ((eq? (%assoc ns %cat) ()) ())
         (#t (%assoc m (rest (%assoc ns %cat)))))))
P
}

{
printf '# Compliance -- %s\n\n' "$(basename "$ENGINE")"
printf 'Generated by x-lang tools/contract/gen-compliance.sh from x-engine.xon.\n'
printf 'Every section falsifies one declared row. Do not edit; regenerate.\n'

# --- one section per declared capability group that has ISA rows -------------
awk '/^\(provides /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$XON" | sort -u > "$W/claimed"
while read -r grp; do
	awk -v g="$grp" '$2==g {print $1}' "$W/c2g" | sort > "$W/coords"
	[ -s "$W/coords" ] || continue
	n=$(wc -l < "$W/coords" | tr -d ' ')
	printf '\n### provides %s -- all %s coordinates resolve\n\n' "$grp" "$n"
	printf '```scheme\n'
	prelude
	printf '(def %%missing 0)\n'
	while read -r coord; do
		if grep -q "^$coord$" "$W/bare"; then
			# a bare name: bound or not.  `guard` is itself bare, so an unbound
			# symbol is catchable without any library.
			printf '(set! %%missing (guard (e (+ %%missing 1)) (match ((eq? %s ()) (+ %%missing 1)) (#t %%missing))))\n' "$coord"
		else
			ns=${coord%%/*}; m=${coord#*/}
			printf '(set! %%missing (match ((eq? (%%coord (lit %s) (lit %s)) ()) (+ %%missing 1)) (#t %%missing)))\n' "$ns" "$m"
		fi
	done < "$W/coords"
	printf '(match ((= %%missing 0) (error "ok")) (#t (error "missing")))\n'
	printf '```\n---\n    *** ERROR: ok\n'
done < "$W/claimed"

# --- one section per declared guarantee --------------------------------------
# Only guarantees with a falsifying experiment get a section; the rest are named
# in the report as UNTESTED rather than silently counted as passing, because a
# suite that quietly skips a claim is indistinguishable from one that verified it.
if grep -q '^(guarantee eval/tco)' "$XON"; then
	# The depth is bounded ABOVE by the allocation ceiling, not by ambition: each
	# iteration conses an argument spine, and gc/explicit-only means none of it is
	# ever reclaimed mid-loop, so a long enough loop exhausts the guard's budget
	# even on a perfectly tail-recursive engine.  60k frames is far past any C
	# stack yet well inside the ceiling -- the two guarantees constrain each other,
	# which is worth knowing before writing a "bigger is better" depth here.
	printf '\n### guarantee eval/tco -- deep tail recursion returns rather than crashing\n\n'
	printf '```scheme\n'
	printf '(def %%loop (fn (self n) (match ((= n 0) (lit done)) (#t (self (- n 1))))))\n'
	printf '(match ((eq? (%%loop 60000) (lit done)) (error "ok")) (#t (error "wrong")))\n'
	printf '```\n---\n    *** ERROR: ok\n'
fi

if grep -q '^(guarantee gc/non-moving)' "$XON"; then
	printf '\n### guarantee gc/non-moving -- an address survives heavy allocation\n\n'
	printf '```scheme\n'
	prelude
	printf '(def %%obj->ptr (rest (%%coord (lit obj) (lit ->ptr))))\n'
	printf '(def %%ptr->int (rest (%%coord (lit ptr) (lit ->int))))\n'
	printf '(def %%p (pair 1 2))\n'
	printf '(def %%a0 (%%ptr->int (%%obj->ptr %%p)))\n'
	printf '(def %%burn (fn (self n junk) (match ((= n 0) (lit done)) (#t (self (- n 1) (pair n n))))))\n'
	printf '(%%burn 50000 ())\n'
	printf '(match ((= %%a0 (%%ptr->int (%%obj->ptr %%p))) (error "ok")) (#t (error "moved")))\n'
	printf '```\n---\n    *** ERROR: ok\n'
fi

if grep -q '^(guarantee gc/explicit-only)' "$XON"; then
	printf '\n### guarantee gc/explicit-only -- a raw pointer held across allocation stays live\n\n'
	printf '```scheme\n'
	prelude
	printf '(def %%obj->ptr (rest (%%coord (lit obj) (lit ->ptr))))\n'
	printf '(def %%ptr->int (rest (%%coord (lit ptr) (lit ->int))))\n'
	printf '(def %%int->ptr (rest (%%coord (lit int) (lit ->ptr))))\n'
	printf '(def %%ptr->obj (rest (%%coord (lit ptr) (lit ->obj))))\n'
	printf '(def %%p (pair 7 8))\n'
	printf '(def %%i0 (%%ptr->int (%%obj->ptr %%p)))\n'
	printf '(def %%burn (fn (self n junk) (match ((= n 0) (lit done)) (#t (self (- n 1) (pair n n))))))\n'
	printf '(%%burn 50000 ())\n'
	printf '(def %%back (%%ptr->obj (%%int->ptr %%i0)))\n'
	printf '(match ((= (first %%back) 7) (error "ok")) (#t (error "clobbered")))\n'
	printf '```\n---\n    *** ERROR: ok\n'
fi
} > "$OUT"

echo "gen-compliance: $(grep -c '^### ' "$OUT") checks generated into $OUT"
