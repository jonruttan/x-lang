#!/bin/sh
# prim-doc.sh -- every entry in the C primitive reference names a real
# primitive, and calls it the way it can actually be called.
#
# THE CONTRACT: for each ### entry in docs/primitives.md,
#   1. the heading names a binding site the C source actually registers, and
#   2. the signature line calls it in the form that resolves -- by name when
#      the name is bound, through prim-ref when it is not.
#
# WHY BOTH HALVES. The doc-example gate runs fenced examples; nothing reads
# signature lines, which sit outside the fence. So `(str append a b)` shipped
# as the signature of a real primitive while the example below it used
# prim-ref and passed. It was wrong twice over: `str append` is not the
# primitive's NAME -- that is `str-append`, FILED at catalog coordinate
# `(str append)` -- and `(str append ...)` is not a form that evaluates,
# because `str` is not a binding.
#
# Whether a name is bound is not a judgement call. x_prims_bind_table binds it
# unless its namespace is de-registered and it is not on the keep-list, and
# both lists live in the C source. This gate reads the same bytes the engine
# does rather than forming a second opinion about them.
#
# The scanner is tools/lib/isa-scan.awk, shared with check/isa.sh so that one
# parser covers the six registration shapes. This gate asks it for the entry
# NAMES that isa.sh's manifest diff does not carry (-v names=1).
#
# NOT CHECKED: prose. That an entry names a real primitive and calls it
# correctly says nothing about whether the sentence describing it is true.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Report mode exists because this gate found 22 pre-existing entries on its
# first run -- x-lang definitions in lib/ documented as C primitives (#456) --
# and a gate that lands red rots. Same promotion rule as the doc-example tier:
# the way to gate is to fix the doc, and the count prints on every run so the
# decision keeps coming up.
REPORT=""
case "${1:-}" in --report) REPORT=1; shift ;; esac

DOC="${1:-docs/primitives.md}"
SCAN="${TMPDIR:-/tmp}/prim-doc-scan.$$"
trap 'rm -f "$SCAN"' EXIT INT TERM

[ -f "$DOC" ] || { echo "prim-doc: no such doc: $DOC" >&2; exit 1; }

awk -v names=1 -f tools/lib/isa-scan.awk \
	src/*.c src/x-prim/*.c src/x-syntax/*.c opt/x-prim/*.c > "$SCAN"

awk -v docname="$DOC" -v sq="'" -v report="${REPORT:-}" '
# ---- the C source view, from the shared scanner
NR == FNR {
	if ($1 == "bare" || $1 == "value") bound[$2] = 1
	else if ($1 == "keep")    kept[$2] = 1
	else if ($1 == "dereg")   dereg[$2] = 1
	else if ($1 == "catalog") { cns[$4] = $2; cmeth[$4] = $3 }
	next
}

# ---- the document. A backticked ### heading names an entry; a bare one
#      (### Strings) is a group heading and has no signature to check.
/^### `/ {
	name = $0
	sub(/^### `/, "", name)
	sub(/`.*$/, "", name)
	pending = name
	pline = FNR
	next
}

# The signature is the first line after the heading that opens with a paren.
pending != "" && /^`\(/ {
	sig = $0

	if (!((pending in bound) || (pending in cns))) {
		printf "%s:%d  %s -- no primitive of that name is registered\n",
			docname, pline, pending
		bad++
		pending = ""
		next
	}

	# It binds unless its namespace is de-registered and it is not kept.
	if (pending in bound)                              binds = 1
	else if ((cns[pending] in dereg) && !(pending in kept)) binds = 0
	else                                               binds = 1

	if (binds) {
		if (index(sig, "`(" pending " ") != 1 && index(sig, "`(" pending ")") != 1) {
			printf "%s:%d  %s binds by name -- signature should be (%s ...), got: %s\n",
				docname, pline, pending, pending, sig
			bad++
		}
	} else {
		want = "`((prim-ref " sq cns[pending] " " sq cmeth[pending] ")"
		if (index(sig, want) != 1) {
			printf "%s:%d  %s does not bind (namespace %s de-registered) -- signature should be ((prim-ref %s%s %s%s) ...), got: %s\n",
				docname, pline, pending, cns[pending],
				sq, cns[pending], sq, cmeth[pending], sig
			bad++
		}
	}
	pending = ""
	next
}

END {
	if (bad && report != "") {
		printf "prim-doc: %d entry/entries disagree with the C surface (report-only, not gated).\n", bad
		exit 0
	}
	if (bad) {
		printf "prim-doc: FAIL -- %d entry/entries disagree with the C surface.\n", bad
		exit 1
	}
	printf "prim-doc: ok (%d entries in %s agree with the C binding surface).\n", checked, docname
}
{ if (pending != "" && $0 ~ /^### /) pending = "" }
' "$SCAN" "$DOC"
