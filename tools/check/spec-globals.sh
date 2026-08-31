#!/bin/sh
# spec-globals.sh -- a spec may not rebind a name the shared vocabulary owns.
#
# The harness evaluates a snippet's top-level forms with `eval!`, so a
# top-level (def NAME ...) inside a spec binds in the GLOBAL env and outlives
# the snippet.  Within one file that is the point: sections build on each
# other.  Across files it is a leak, because glob mode buckets up to
# SPEC_BATCH files into ONE interpreter -- so a spec that defines `op` as a
# throwaway name clobbers the operative former for every later file in its
# bucket.
#
# THAT IS WHAT THIS GATE EXISTS FOR, and the reason it is a gate rather than a
# convention is that the damage is invisible from the file that causes it.  The
# spec that breaks is someone else's, in a different directory, and it breaks
# only at a particular batch size:
#
#     args mode, one job per file    2831/0
#     glob mode, SPEC_BATCH=1        2695/0
#     glob mode, SPEC_BATCH=8        2695, 2 failed
#
# The failure it produced read as a missing binding in a NEW C primitive --
# convincingly enough to be diagnosed as an engine defect and nearly answered
# with an engine release.  It was `(do (def op '+) ...)` in a quasiquote spec,
# eight files earlier in the same process.
#
# THE PROTECTED SET is the shared vocabulary, from the two manifests that
# already define it: the engine's bare and keep names
# (engine/tools/contract/isa.x) and the runtime library's sanctioned top level
# (tools/contract/bare-globals.x).  It follows those files automatically, which
# is the point of deriving rather than listing -- a name that becomes global
# tomorrow is protected tomorrow.
#
# NOT PROTECTED, deliberately: everything else a spec defines.  Helper names
# (`x`, `xs`, `f`) are the normal way to write a spec and collide with nothing.
# The rule is only "do not take a name the vocabulary owns".
#
# WHAT COUNTS AS TOP LEVEL is the binding position, not the column: depth 0 of
# a fence, or nested only inside sequencing forms (`do`, `%seq`, `begin`,
# `doc`), which open no frame.  A def inside a `fn` or `op` body binds in that
# frame and is nobody else's business.  Quoted data (`'`, a backquote, `lit`,
# `quasi`) is skipped -- a spec ABOUT quasiquote is full of unevaluated `def`
# forms, and flagging those would make the gate useless in exactly the file
# that motivated it.
#
# Scope is x-lang's own specs.  The bundles run the same harness with the same
# hazard; their kit could carry this check, and does not yet.
set -e
cd "$(dirname "$0")/../.."

SPECS=$(find tests/x/specs -name '*.spec.md' | sort)
[ -n "$SPECS" ] || { echo "spec-globals: no specs found" >&2; exit 2; }

ISA=engine/tools/contract/isa.x
BARE=tools/contract/bare-globals.x
for f in "$ISA" "$BARE"; do
	[ -f "$f" ] || { echo "spec-globals: missing manifest $f" >&2; exit 2; }
done

W="${TMPDIR:-/tmp}/spec-globals.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

{
	sed -n '/^(def %isa-bare/,/^)))/p;/^(def %isa-keep/,/^)))/p' "$ISA" |
		awk '/^  \(/ { gsub(/[()]/, " "); print $1 }'
	awk '/^\(def %bare-globals/ { next }
	     /^ *\(/            { gsub(/[()]/, ""); print $1 }' "$BARE"
} | grep -v '^$' | sort -u > "$W/protected"

# Every (def NAME ...) a snippet evaluates at global binding position.
awk '
function tok(t, ln) {
	if (t == "(") {
		sp++; head[sp] = ""; want_head = 1
		if (prevq && data_from < 0) data_from = sp
		prevq = 0
		return
	}
	if (t == ")") {
		if (data_from >= 0 && sp <= data_from) data_from = -1
		if (sp > 0) sp--
		want_head = 0; want_name = 0
		return
	}
	if (want_head) {
		head[sp] = t; want_head = 0
		if (data_from < 0 && (t == "lit" || t == "quasi")) data_from = sp
		if (data_from < 0 && t == "def" && seqonly()) want_name = 1
		return
	}
	if (want_name) { print FILENAME "\t" ln "\t" t; want_name = 0 }
}
function seqonly(   i) {
	for (i = 1; i < sp; i++)
		if (head[i] != "do" && head[i] != "%seq" && head[i] != "begin" && head[i] != "doc")
			return 0
	return 1
}
/^```/ {
	infence = ! infence
	if (infence) { sp = 0; data_from = -1; want_head = 0; want_name = 0; prevq = 0 }
	next
}
! infence { next }
{
	line = $0; n = length(line)
	for (i = 1; i <= n; i++) {
		c = substr(line, i, 1)
		if (c == ";") break
		if (c == "\"") {
			i++
			while (i <= n) {
				d = substr(line, i, 1)
				if (d == "\\") i++
				else if (d == "\"") break
				i++
			}
			prevq = 0; continue
		}
		if (c == "#" && substr(line, i + 1, 1) == "\\") { i += 2; prevq = 0; continue }
		if (c == "\047" || c == "`") { prevq = 1; continue }
		if (c == "(" || c == ")") { tok(c, FNR); continue }
		if (c == " " || c == "\t") { prevq = 0; continue }
		j = i
		while (j <= n && index(" \t()\";\047`", substr(line, j, 1)) == 0) j++
		tok(substr(line, i, j - i), FNR)
		i = j - 1; prevq = 0
	}
}' $SPECS > "$W/defs"

hits=$(awk -F'\t' '
	NR == FNR { prot[$1]; next }
	($3 in prot) { print $1 ":" $2 "\t" $3 }
' "$W/protected" "$W/defs")

if [ -n "$hits" ]; then
	echo "spec-globals: a spec rebinds a name the shared vocabulary owns." >&2
	echo "  These bind GLOBALLY and outlive the file, so every later spec in the" >&2
	echo "  same SPEC_BATCH bucket sees the replacement.  Rename the local to" >&2
	echo "  something the vocabulary does not own (a %-prefixed name is the" >&2
	echo "  convention), or move the def inside the frame that needs it." >&2
	echo >&2
	printf '%s\n' "$hits" | sed 's/^/    /' >&2
	exit 1
fi

echo "spec-globals: no spec rebinds a shared global ($(grep -c . "$W/protected") names protected)."
