#!/bin/sh
# seam.sh -- the platform still provides what a lang is promised.
#
# tools/contract/seam.x declares the names a lang may rely on.  This holds the
# running platform to them, in every dialect, and holds the documented table to
# the declaration so the two cannot drift.
#
# THE FAILURE IT EXISTS FOR is invisible from inside this repository: a lang
# lives in its own repo, so a rename here that drops %repl-prompt or
# import-path! breaks it silently and this tree stays green.  That is one of
# the three ways the last generation of langs rotted, and it is the one no
# amount of testing over there can catch in time.
#
# EVERY DIALECT, because a lang declares which one it loads on and any of the
# three is a legal answer.  ~8s for all three (he 1s, xe 4s, rn 3s -- the
# tower's runtime cc compilations dominate), which buys a place in the fast
# gates rather than the deep tier.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SEAM=tools/contract/seam.x
DOC=docs/lang-contract.md
[ -f "$SEAM" ] || { echo "seam: no declaration at $SEAM" >&2; exit 2; }

# --- the closed vocabulary ------------------------------------------------
# An unknown form is an error, the ruling every other manifest here follows: a
# declaration that silently ignores what it does not understand cannot be
# extended without wondering which readers obeyed which half of it.
bad=$(sed -n 's/^(\([a-z-]*\)[ )].*/\1/p' "$SEAM" | sort -u | grep -vx 'seam' || true)
[ -z "$bad" ] || { echo "seam: unknown form(s) in $SEAM: $bad" >&2; exit 2; }
badclass=$(sed -n 's/^(seam \([a-z-]*\) .*/\1/p' "$SEAM" | sort -u \
	| grep -vxE 'always|installed|bundle' || true)
[ -z "$badclass" ] || { echo "seam: unknown class(es) in $SEAM: $badclass" >&2; exit 2; }

ALWAYS=$(sed -n 's/^(seam always \([^ ]*\) .*/\1/p' "$SEAM")
INSTALLED=$(sed -n 's/^(seam installed \([^ ]*\) .*/\1/p' "$SEAM")
BUNDLE=$(sed -n 's/^(seam bundle \([^ ]*\) .*/\1/p' "$SEAM")
[ -n "$ALWAYS" ] || { echo "seam: $SEAM declares no always-rows" >&2; exit 2; }

# --- the probe -------------------------------------------------------------
# Evaluating an unbound symbol raises, so a guard turns "is this name here?"
# into a value.  The name is only READ -- `repl` is not called, %banner is not
# run -- so the probe cannot hang on a session it accidentally started.
W="${TMPDIR:-/tmp}/seam.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT
PROBE="$W/probe.x"
: > "$PROBE"
for n in $ALWAYS $INSTALLED $BUNDLE; do
	printf '(display "%s=" (guard (_ "missing") (do %s "ok")) "\\n")\n' "$n" "$n" >> "$PROBE"
done

fail=0
for d in he xe rn; do
	out="$W/$d.out"
	if ! sh x.sh --no-pin -q -l "$d" -f "$PROBE" > "$out" 2>"$W/$d.err"; then
		echo "seam: $d failed to boot the probe" >&2
		sed 's/^/  /' "$W/$d.err" | head -5 >&2
		fail=1
		continue
	fi
	for n in $ALWAYS; do
		if ! grep -qx "$n=ok" "$out"; then
			echo "seam: $d does not provide '$n' -- declared 'always' in $SEAM" >&2
			fail=1
		fi
	done
	# A checkout has no %install-root.  If one of these ever answers `ok` here,
	# the row is no longer conditional and every lang's guard has become
	# superstition -- say so rather than let the guidance rot into a habit.
	for n in $INSTALLED; do
		if grep -qx "$n=ok" "$out"; then
			echo "seam: $d provides '$n' in a CHECKOUT, but $SEAM declares it 'installed'" >&2
			echo "  either the row is wrong or the guard the contract asks langs to write is" >&2
			fail=1
		fi
	done
	# A bare dialect is not a bundle, so the bundle-class names must be absent
	# here.  Same reasoning as the installed rows above: a name that quietly
	# became unconditional turns the class into a fiction, and the bundle half
	# of this gate would then be proving nothing.
	for n in $BUNDLE; do
		if grep -qx "$n=ok" "$out"; then
			echo "seam: $d provides '$n' with NO bundle loaded, but $SEAM declares it 'bundle'" >&2
			fail=1
		fi
	done
done

# --- the bundle class, with a bundle actually loaded -----------------------
# The other half.  X_LANG_DIR points -l at the fixture's parent (see
# tools/contract/bundles/seamprobe/lang.xon); the entry defines nothing, so
# everything the probe finds came from the wrapper's bundle_form.
#
# ONE DIALECT IS ENOUGH, and the asymmetry with the loop above is deliberate:
# what varies across he/xe/rn is the LIBRARY, and %lang-root is emitted by the
# wrapper ahead of any of it.  Running the fixture three times would cost the
# tower's boot twice to re-prove a shell function's output.
if [ -n "$BUNDLE" ]; then
	out="$W/bundle.out"
	if ! X_LANG_DIR=tools/contract/bundles/ \
			sh x.sh --no-pin -q -l seamprobe -f "$PROBE" > "$out" 2>"$W/bundle.err"; then
		echo "seam: the seamprobe fixture failed to load" >&2
		sed 's/^/  /' "$W/bundle.err" | head -5 >&2
		fail=1
	else
		for n in $BUNDLE; do
			if ! grep -qx "$n=ok" "$out"; then
				echo "seam: a loaded bundle does not get '$n' -- declared 'bundle' in $SEAM" >&2
				echo "  x.sh's bundle_form is what emits it" >&2
				fail=1
			fi
		done
	fi
fi

# --- the documented table must be the declared one -------------------------
# The contract's table is what a lang author reads; this file is what the gate
# enforces.  Two lists for one fact is how they drift, and a documented seam
# nothing holds is exactly the state this gate was added to end.
if [ -f "$DOC" ]; then
	doc_names=$(awk '/^## The seam/{s=1;next} /^## /{if(s)exit} s' "$DOC" \
		| sed -n 's/^| `\([^`]*\)` |.*/\1/p' | sort -u)
	decl_names=$(printf '%s\n%s\n%s\n' "$ALWAYS" "$INSTALLED" "$BUNDLE" | sed '/^$/d' | sort -u)
	if [ "$doc_names" != "$decl_names" ]; then
		# Temp files, not <(...): process substitution is a bashism and CI's
		# Linux leg runs dash, where it is a syntax error -- a gate that only
		# parses on the author's machine is worse than no gate.
		printf '%s\n' "$doc_names" > "$W/doc.txt"
		printf '%s\n' "$decl_names" > "$W/decl.txt"
		echo "seam: $DOC's table and $SEAM disagree" >&2
		echo "  only in the doc:  $(comm -23 "$W/doc.txt" "$W/decl.txt" | tr '\n' ' ')" >&2
		echo "  only in seam.x:   $(comm -13 "$W/doc.txt" "$W/decl.txt" | tr '\n' ' ')" >&2
		fail=1
	fi
fi

[ "$fail" = 0 ] || { echo "seam: FAIL" >&2; exit 1; }
echo "seam: ok ($(printf '%s\n' $ALWAYS | wc -l | tr -d ' ') always, $(printf '%s\n' $INSTALLED | wc -l | tr -d ' ') installed, $(printf '%s\n' $BUNDLE | wc -l | tr -d ' ') bundle, he/xe/rn)"
